'use strict';

// The payroll calculator (docs/expense-management/IMPLEMENTATION_PLAN.md, section 6, phase P2). PURE: it is
// given everything it needs (the structure's lines, the month's school days, attendance, approved leave,
// the employment window and the school's one policy) and returns the month's pay with a full explanation.
// No database, no clock, no randomness: the same input always gives the same payslip, so a run can be
// recomputed and a payslip explained line by line.
//
// THE RULES (every one is tested; the school sees them in the docs and on the payslip):
//  1. Only school days count (the branch calendar: weekly offs, holidays, special working days).
//  2. Each school day is worth 2 "halves". Each half is PAID or UNPAID:
//       - approved leave covers its halves: a PAID type pays them, an UNPAID type does not (a type with no
//         pay concept pays, with a warning). Leave wins over the attendance mark for the halves it covers.
//       - the rest of the day follows attendance: PRESENT and LATE pay; HALF_DAY pays one half; ABSENT does
//         not; NOT MARKED follows the school's policy (default PAID, always reported as a warning).
//       - a school day outside the employment window (before joining, after leaving) is unpaid.
//  3. factor = paid halves / school-day halves. When nobody is short of a day the structure is paid exactly.
//  4. Each EARNING is prorated: round half up of amount x paid / total (BigInt, exact). A percentage line is
//     recomputed from its prorated basis. A FIXED deduction is NOT prorated (an advance recovery is the same
//     whatever the attendance). A percentage deduction follows its basis.
//  5. Net = earnings - deductions and is never negative: if the deductions are more than the earnings, the
//     LAST deductions are reduced until they fit, and what could not be taken is reported as
//     `unrecoveredDeductionMinor` (the school decides what to do with it; nothing is silently dropped).
//  6. Late marks and overtime change nothing in v1.

const { percentOf } = require('./payroll_math');

const UNMARKED = Object.freeze(['PAID', 'UNPAID']);
const PRESENT_LIKE = new Set(['PRESENT', 'LATE']);

/** round-half-up of amount * num / den, exactly. */
function proportion(amount, num, den) {
  if (den === 0) return amount;
  return Number((BigInt(amount) * BigInt(num) * 2n + BigInt(den)) / (BigInt(den) * 2n));
}

/**
 * @param {object} i
 * @param {string[]} i.workingDates   the month's school days (`yyyy-mm-dd`), from payroll_calendar
 * @param {object[]} i.lines          the structure's lines: { componentId, name?, kind, calc, amountMinor, percentBp?, basisId? }
 * @param {Object<string,string>} [i.attendance]  dateKey -> PRESENT | LATE | HALF_DAY | ABSENT
 * @param {object[]} [i.leave]        approved leave: { dateKeys: string[], halfDay: 'NONE'|'FIRST'|'SECOND', payType: 'PAID'|'UNPAID'|'NA' }
 * @param {{from?: string|null, to?: string|null}} [i.employment]  first and last day of employment (inclusive)
 * @param {{unmarkedDays?: 'PAID'|'UNPAID'}} [i.settings]
 */
function calculateMonth(i) {
  const settings = { unmarkedDays: 'PAID', ...(i.settings || {}) };
  if (!UNMARKED.includes(settings.unmarkedDays)) throw new Error('unmarkedDays must be PAID or UNPAID');
  const attendance = i.attendance || {};
  const employment = i.employment || {};
  const dates = [...new Set(i.workingDates || [])].sort();

  // leave: dateKey -> [{ halves, payType }]
  const leaveBy = new Map();
  for (const l of i.leave || []) {
    const halves = l.halfDay && l.halfDay !== 'NONE' ? 1 : 2;
    for (const k of l.dateKeys || []) {
      if (!leaveBy.has(k)) leaveBy.set(k, []);
      leaveBy.get(k).push({ halves, payType: l.payType });
    }
  }

  const days = { present: 0, late: 0, halfDay: 0, absent: 0, unmarked: 0, paidLeave: 0, unpaidLeave: 0, notEmployed: 0 };
  const warnings = [];
  let paid = 0;
  let unpaid = 0;
  const dayRows = [];

  for (const k of dates) {
    let p = 0;
    let u = 0;
    let note = null;
    if ((employment.from && k < employment.from) || (employment.to && k > employment.to)) {
      u = 2;
      days.notEmployed++;
      note = 'NOT_EMPLOYED';
    } else {
      let covered = 0;
      for (const l of leaveBy.get(k) || []) {
        const h = Math.min(l.halves, 2 - covered);
        if (h <= 0) {
          warnings.push({ code: 'LEAVE_OVERLAP', date: k });
          continue;
        }
        covered += h;
        if (l.payType === 'UNPAID') {
          u += h;
          days.unpaidLeave += h / 2;
          note = 'UNPAID_LEAVE';
        } else {
          p += h;
          days.paidLeave += h / 2;
          note = 'PAID_LEAVE';
          if (l.payType !== 'PAID') warnings.push({ code: 'LEAVE_PAY_TYPE_UNKNOWN', date: k });
        }
      }
      const rest = 2 - covered;
      if (rest > 0) {
        const a = attendance[k];
        if (PRESENT_LIKE.has(a)) {
          p += rest;
          if (covered === 0) days[a === 'LATE' ? 'late' : 'present']++;
        } else if (a === 'HALF_DAY') {
          // a half day pays one half (if leave already took one half, the remaining half was worked)
          p += 1;
          u += rest - 1;
          if (covered === 0) days.halfDay++;
        } else if (a === 'ABSENT') {
          u += rest;
          if (covered === 0) days.absent++;
        } else {
          if (settings.unmarkedDays === 'PAID') p += rest;
          else u += rest;
          days.unmarked++;
          warnings.push({ code: 'NOT_MARKED', date: k });
        }
      } else if (PRESENT_LIKE.has(attendance[k]) && u > 0) {
        warnings.push({ code: 'LEAVE_AND_PRESENT', date: k });
      }
      if (covered === 0) note = a2note(attendance[k], settings);
    }
    paid += p;
    unpaid += u;
    dayRows.push({ date: k, paidHalves: p, unpaidHalves: u, note });
  }

  const total = dates.length * 2;
  if (total === 0) warnings.push({ code: 'NO_WORKING_DAYS' });
  const full = total === 0 || unpaid === 0;

  // ---- lines ----
  const byId = new Map();
  const out = (i.lines || []).map((l) => ({ ...l, plannedMinor: l.amountMinor, amountMinor: l.amountMinor }));
  for (const l of out) byId.set(l.componentId, l);
  // FIXED earnings first (the bases), then everything else.
  for (const l of out) {
    if (l.kind === 'EARNING' && l.calc === 'FIXED') l.amountMinor = full ? l.plannedMinor : proportion(l.plannedMinor, paid, total);
  }
  for (const l of out) {
    if (l.calc !== 'PERCENT') continue;
    const basis = byId.get(l.basisId);
    l.amountMinor = full || !basis ? l.plannedMinor : percentOf(basis.amountMinor, l.percentBp);
  }
  // fixed deductions are NOT prorated (already l.amountMinor === planned)

  const sum = (kind) => out.filter((l) => l.kind === kind).reduce((s, l) => s + l.amountMinor, 0);
  const grossMinor = sum('EARNING');
  let deductionsMinor = sum('DEDUCTION');
  let unrecoveredDeductionMinor = 0;
  if (deductionsMinor > grossMinor) {
    let excess = deductionsMinor - grossMinor;
    for (const l of [...out].reverse()) {
      if (l.kind !== 'DEDUCTION' || excess === 0) continue;
      const cut = Math.min(l.amountMinor, excess);
      l.amountMinor -= cut;
      excess -= cut;
      unrecoveredDeductionMinor += cut;
    }
    deductionsMinor = sum('DEDUCTION');
  }

  return {
    period: dates.length ? dates[0].slice(0, 7) : null,
    workingDays: dates.length,
    paidHalves: paid,
    unpaidHalves: unpaid,
    paidDays: paid / 2,
    unpaidDays: unpaid / 2,
    days,
    dayRows,
    warnings,
    lines: out.map((l) => ({ componentId: l.componentId, name: l.name, kind: l.kind, calc: l.calc, plannedMinor: l.plannedMinor, amountMinor: l.amountMinor })),
    grossMinor,
    deductionsMinor,
    netMinor: grossMinor - deductionsMinor,
    unrecoveredDeductionMinor,
  };
}

function a2note(a, settings) {
  if (PRESENT_LIKE.has(a)) return a;
  if (a === 'HALF_DAY' || a === 'ABSENT') return a;
  return settings.unmarkedDays === 'PAID' ? 'NOT_MARKED_PAID' : 'NOT_MARKED_UNPAID';
}

module.exports = { UNMARKED, calculateMonth, proportion };

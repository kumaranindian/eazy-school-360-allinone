'use strict';

// Payroll phase P5: the payroll register. What was actually PAID, month by month, and a CSV of one month's
// payslips (one row per person, one column per pay component). Only PAID runs appear: a register is a record of
// what was paid, not of what is being prepared. School admin (any branch, or the whole school) and finance (own
// branch). Pay figures are in the responses, so they are kept out of the audit trail (call_audit.js).

const { validId } = require('./ids');
const { authorize } = require('./payroll');
const { civilToday, wall } = require('./expenses');
const { plainAmount } = require('./expense_reports');
const { csvCell } = require('./audit');
const calendar = require('./payroll_calendar');

const MAX_MONTHS = 24;
const MAX_BRANCHES = 30;
const SLIP_CAP = 1500;

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);
const monthsBetween = (from, to) => (Number(to.slice(0, 4)) - Number(from.slice(0, 4))) * 12 + (Number(to.slice(5, 7)) - Number(from.slice(5, 7))) + 1;

function validateRange(data, thisMonth) {
  const errors = {};
  const d = data || {};
  for (const k of ['fromPeriod', 'toPeriod']) if (typeof d[k] !== 'string' || !calendar.PERIOD.test(d[k])) errors[k] = 'yyyy-mm';
  if (!Object.keys(errors).length) {
    if (d.fromPeriod > d.toPeriod) errors.fromPeriod = 'cannot be after toPeriod';
    else if (d.toPeriod > thisMonth) errors.toPeriod = 'a month that has not started has nothing paid';
    else if (monthsBetween(d.fromPeriod, d.toPeriod) > MAX_MONTHS) errors.toPeriod = `at most ${MAX_MONTHS} months`;
  }
  if (Object.keys(errors).length) return { errors };
  return { value: { fromPeriod: d.fromPeriod, toPeriod: d.toPeriod } };
}
const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');

/** The branches the caller may read: one (finance or school admin), or the whole school (school admin only). */
async function scope(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  if (data && data.branchId !== undefined && data.branchId !== null && data.branchId !== '') {
    if (!validId(data.branchId)) return { error: 'PERMISSION_DENIED' };
    if (!(await authorize(db, uid, token, schoolId, data.branchId, 'view'))) return { error: 'PERMISSION_DENIED' };
    const b = (await branchRef(db, schoolId, data.branchId).get()).data() || {};
    return { schoolId, branches: [{ id: data.branchId, name: b.name || data.branchId }], whole: false };
  }
  const caller = await authorize(db, uid, token, schoolId, null, 'view');
  if (!caller || caller.role !== 'SCHOOL_ADMIN') return { error: 'PERMISSION_DENIED' };
  const snap = await db.collection('schools').doc(schoolId).collection('branches').limit(MAX_BRANCHES + 1).get();
  if (snap.docs.length > MAX_BRANCHES) return { error: 'FAILED_PRECONDITION', reason: `ask for one branch at a time (more than ${MAX_BRANCHES} branches)` };
  return { schoolId, branches: snap.docs.map((d) => ({ id: d.id, name: (d.data() || {}).name || d.id })), whole: true };
}

async function today(ctx, schoolId) {
  const s = (await ctx.db.collection('schools').doc(schoolId).get()).data() || {};
  return { thisMonth: civilToday(wall(ctx), s.timezone || 'UTC').slice(0, 7), currency: s.currency || 'INR' };
}

/** One row per PAID run in the range, with totals. */
async function getPayrollRegister(ctx, uid, token, data) {
  const { db } = ctx;
  const sc = await scope(ctx, uid, token, data);
  if (sc.error) return sc;
  const facts = await today(ctx, sc.schoolId);
  const range = validateRange(data, facts.thisMonth);
  if (range.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(range.errors) };
  const { fromPeriod, toPeriod } = range.value;
  const rows = [];
  for (const b of sc.branches) {
    const snap = await branchRef(db, sc.schoolId, b.id).collection('payrollRuns').where('status', '==', 'PAID').limit(200).get();
    for (const d of snap.docs) {
      const r = d.data();
      const period = r.period || d.id;
      if (period < fromPeriod || period > toPeriod) continue;
      rows.push({
        branchId: b.id, branchName: b.name, period, payslipCount: r.payslipCount || 0,
        grossMinor: r.grossMinor || 0, deductionsMinor: r.deductionsMinor || 0, netMinor: r.netMinor || 0,
        unrecoveredDeductionMinor: r.unrecoveredDeductionMinor || 0,
        paidDate: r.paidDate || null, paymentMode: r.paymentMode || null, expenseNumber: r.expenseNumber || null,
      });
    }
  }
  rows.sort((a, b) => (a.period < b.period ? 1 : a.period > b.period ? -1 : a.branchName.localeCompare(b.branchName)));
  const sum = (k) => rows.reduce((s, r) => s + r[k], 0);
  return {
    result: {
      currency: facts.currency, fromPeriod, toPeriod, whole: sc.whole, rows,
      totals: { runs: rows.length, payslipCount: sum('payslipCount'), grossMinor: sum('grossMinor'), deductionsMinor: sum('deductionsMinor'), netMinor: sum('netMinor'), unrecoveredDeductionMinor: sum('unrecoveredDeductionMinor') },
    },
  };
}

// ---- CSV of one paid run -----------------------------------------------------------------------------------------

/** Builds the CSV: one row per person, one column per pay component (earnings first), one-off items summed, totals last. */
function toCsv(payslips, run, currency) {
  const earnCols = [];
  const dedCols = [];
  for (const p of payslips) {
    for (const l of p.lines || []) {
      const list = l.kind === 'EARNING' ? earnCols : dedCols;
      if (!list.includes(l.name)) list.push(l.name);
    }
  }
  const money = (v) => plainAmount(v, currency);
  const header = ['employee_code', 'name', 'working_days', 'paid_days', 'unpaid_days', ...earnCols, 'one_off_earnings', ...dedCols, 'one_off_deductions', 'total_earnings', 'total_deductions', 'net_pay', 'currency', 'payment_mode', 'paid_date'];
  const lines = [header.map(csvCell).join(',')];
  const totals = { earn: earnCols.map(() => 0), oneEarn: 0, ded: dedCols.map(() => 0), oneDed: 0, gross: 0, deductions: 0, net: 0 };
  const sorted = [...payslips].sort((a, b) => String(a.staffName).localeCompare(String(b.staffName)) || String(a.employeeCode).localeCompare(String(b.employeeCode)));
  for (const p of sorted) {
    const by = (kind, cols) => cols.map((c) => (p.lines || []).filter((l) => l.kind === kind && l.name === c).reduce((s, l) => s + l.amountMinor, 0));
    const earn = by('EARNING', earnCols);
    const ded = by('DEDUCTION', dedCols);
    const oneEarn = (p.adjustments || []).filter((a) => a.kind === 'EARNING').reduce((s, a) => s + a.amountMinor, 0);
    const oneDed = (p.adjustments || []).filter((a) => a.kind === 'DEDUCTION').reduce((s, a) => s + a.amountMinor, 0);
    earn.forEach((v, i) => { totals.earn[i] += v; });
    ded.forEach((v, i) => { totals.ded[i] += v; });
    totals.oneEarn += oneEarn;
    totals.oneDed += oneDed;
    totals.gross += p.grossMinor;
    totals.deductions += p.deductionsMinor;
    totals.net += p.netMinor;
    lines.push([
      p.employeeCode || '', p.staffName || '', p.workingDays, p.paidDays, p.unpaidDays,
      ...earn.map(money), money(oneEarn), ...ded.map(money), money(oneDed),
      money(p.grossMinor), money(p.deductionsMinor), money(p.netMinor), currency, run.paymentMode || '', run.paidDate || '',
    ].map(csvCell).join(','));
  }
  lines.push([
    'TOTAL', `${sorted.length} staff`, '', '', '',
    ...totals.earn.map(money), money(totals.oneEarn), ...totals.ded.map(money), money(totals.oneDed),
    money(totals.gross), money(totals.deductions), money(totals.net), currency, '', '',
  ].map(csvCell).join(','));
  return lines.join('\r\n');
}

/** The CSV of one PAID run of a branch. */
async function exportPayrollRegister(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !calendar.PERIOD.test(String(data.period))) return { error: 'PERMISSION_DENIED' };
  if (!(await authorize(db, uid, token, schoolId, branchId, 'view'))) return { error: 'PERMISSION_DENIED' };
  const runRef = branchRef(db, schoolId, branchId).collection('payrollRuns').doc(data.period);
  const run = (await runRef.get()).data();
  if (!run) return { error: 'NOT_FOUND', reason: 'that run does not exist' };
  if (run.status !== 'PAID') return { error: 'FAILED_PRECONDITION', reason: 'the register is for runs that have been paid' };
  const snap = await runRef.collection('payslips').limit(SLIP_CAP + 1).get();
  if (snap.docs.length > SLIP_CAP) return { error: 'FAILED_PRECONDITION', reason: 'too many payslips for one export' };
  const slips = snap.docs.map((d) => d.data());
  const currency = run.currency || (await today(ctx, schoolId)).currency;
  return { result: { csv: toCsv(slips, run, currency), rows: slips.length, currency, period: data.period } };
}

module.exports = { MAX_MONTHS, validateRange, toCsv, getPayrollRegister, exportPayrollRegister };

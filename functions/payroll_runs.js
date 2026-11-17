'use strict';

// Payroll runs (docs/expense-management/IMPLEMENTATION_PLAN.md section 6, phase P3): one run per branch and month.
//
//   schools/{s}/branches/{b}/payrollRuns/{yyyy-mm}                   the run: status, totals, who did what
//   schools/{s}/branches/{b}/payrollRuns/{yyyy-mm}/payslips/{staffId}  a frozen payslip per person
//   schools/{s}/branches/{b}/payrollRuns/{yyyy-mm}/history/{00001}     append-only: every step, who, why
//
//   DRAFT -> CALCULATED -> APPROVED -> PAID      (CANCELLED from DRAFT, CALCULATED or APPROVED)
//
// One transition table. Every change re-reads the run inside a transaction, checks the status it came from and
// the version the caller saw, and writes the new status and a history entry together. A run is recomputable
// while CALCULATED; once APPROVED nothing in it changes (a correction is an adjustment in the NEXT run). The
// payslips are computed by the SAME code as the preview (payroll_preview.branchCalculations), so a run pays
// exactly what the preview showed. Pay data: school admin and finance only; amounts never appear in the audit
// trail, in logs, or in the history.
//
// Separation of duties: nobody approves a run they prepared (created, recalculated or adjusted), unless the
// school has switched `allowSelfApproval` on (payrollSettings). Only a school admin approves.

const crypto = require('node:crypto');
const { validId } = require('./ids');
const { authorize, CAPS } = require('./payroll');
const { civilToday, wall, validDate, PAYMENT_MODES } = require('./expenses');
const calendar = require('./payroll_calendar');
const preview = require('./payroll_preview');

const SCHOOL_ADMIN = 'SCHOOL_ADMIN';
const REASON_MIN = 10;
const REASON_MAX = 300;
const MAX_ADJUSTMENTS = 10;
const BATCH = 400;

const TRANSITIONS = Object.freeze({
  calculate: { from: ['DRAFT', 'CALCULATED'], to: 'CALCULATED' },
  approve: { from: ['CALCULATED'], to: 'APPROVED' },
  pay: { from: ['APPROVED'], to: 'PAID' },
  cancel: { from: ['DRAFT', 'CALCULATED', 'APPROVED'], to: 'CANCELLED' },
});
const CAP = Object.freeze({ calculate: 'prepare', approve: 'approve', pay: 'pay', cancel: 'prepare', adjust: 'prepare' });
// what counts as "preparing" for the separation-of-duties check
const PREPARING = ['create', 'calculate', 'adjust', 'adjustRemove'];

const trim = (v) => (typeof v === 'string' ? v.trim() : '');
const toMs = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : t instanceof Date ? t.getTime() : typeof t === 'number' ? t : null);
const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');
const seqId = (n) => String(n).padStart(5, '0');

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);
const runs = (db, s, b) => branchRef(db, s, b).collection('payrollRuns');
const slips = (runRef) => runRef.collection('payslips');
const historyCol = (runRef) => runRef.collection('history');

// ---- views (no payslip lines in a list; amounts only for people allowed to see pay, which every caller here is) ----

const runView = (id, r) => ({
  id,
  period: r.period || id,
  status: r.status,
  version: Number.isInteger(r.version) ? r.version : 1,
  currency: r.currency || '',
  payslipCount: r.payslipCount || 0,
  skippedCount: r.skippedCount || 0,
  warningCount: r.warningCount || 0,
  adjustmentCount: r.adjustmentCount || 0,
  grossMinor: r.grossMinor || 0,
  deductionsMinor: r.deductionsMinor || 0,
  netMinor: r.netMinor || 0,
  unrecoveredDeductionMinor: r.unrecoveredDeductionMinor || 0,
  unmarkedDays: r.unmarkedDays || 'PAID',
  workingDays: r.workingDays || 0,
  calculatedAtMs: toMs(r.calculatedAt),
  approvedAtMs: toMs(r.approvedAt),
  approvedByName: r.approvedByName || null,
  paidAtMs: toMs(r.paidAt),
  paidDate: r.paidDate || null,
  paymentMode: r.paymentMode || null,
  paymentReference: r.paymentReference || null,
  cancelReason: r.cancelReason || null,
  createdAtMs: toMs(r.createdAt),
});

const slipSummary = (id, p) => ({
  staffId: id,
  name: p.staffName || '',
  employeeCode: p.employeeCode || '',
  paidDays: p.paidDays,
  unpaidDays: p.unpaidDays,
  workingDays: p.workingDays,
  grossMinor: p.grossMinor,
  deductionsMinor: p.deductionsMinor,
  netMinor: p.netMinor,
  warningCount: Array.isArray(p.warnings) ? p.warnings.length : 0,
  adjustmentCount: Array.isArray(p.adjustments) ? p.adjustments.length : 0,
  unrecoveredDeductionMinor: p.unrecoveredDeductionMinor || 0,
});

const slipView = (id, p) => ({
  ...slipSummary(id, p),
  period: p.period,
  currency: p.currency || '',
  structureSeq: p.structureSeq || null,
  lines: (p.lines || []).map((l) => ({ componentId: l.componentId, name: l.name || '', kind: l.kind, calc: l.calc, plannedMinor: l.plannedMinor, amountMinor: l.amountMinor })),
  days: p.days || {},
  warnings: p.warnings || [],
  adjustments: (p.adjustments || []).map((a) => ({ id: a.id, kind: a.kind, label: a.label, amountMinor: a.amountMinor, reason: a.reason, atMs: a.atMs || null })),
  baseGrossMinor: p.baseGrossMinor,
  baseDeductionsMinor: p.baseDeductionsMinor,
});

// ---- pure: totals of a payslip with its adjustments ------------------------------------------------------------

/** Gross, deductions and net of [slip] with its adjustments applied. Returns { errors } when the net would be negative. */
function slipTotals(slip) {
  let gross = slip.baseGrossMinor;
  let ded = slip.baseDeductionsMinor;
  for (const a of slip.adjustments || []) {
    if (a.kind === 'EARNING') gross += a.amountMinor;
    else ded += a.amountMinor;
  }
  if (!Number.isSafeInteger(gross) || !Number.isSafeInteger(ded)) return { errors: { amountMinor: 'the total is too large' } };
  if (ded > gross) return { errors: { amountMinor: 'the net pay would be negative' } };
  return { grossMinor: gross, deductionsMinor: ded, netMinor: gross - ded };
}

function validateAdjustment(input) {
  const errors = {};
  const i = input && typeof input === 'object' ? input : {};
  if (i.kind !== 'EARNING' && i.kind !== 'DEDUCTION') errors.kind = 'EARNING or DEDUCTION';
  const label = trim(i.label);
  if (label.length < 2 || label.length > 60) errors.label = '2-60 characters';
  if (!Number.isSafeInteger(i.amountMinor) || i.amountMinor < 1 || i.amountMinor > 1e12) errors.amountMinor = 'a whole amount in minor units, above 0';
  const reason = trim(i.reason);
  if (reason.length < REASON_MIN || reason.length > REASON_MAX) errors.reason = `${REASON_MIN}-${REASON_MAX} characters`;
  if (Object.keys(errors).length) return { errors };
  return { value: { kind: i.kind, label, amountMinor: i.amountMinor, reason } };
}

// ---- helpers -----------------------------------------------------------------------------------------------------

async function loadPayrollSettings(db, schoolId) {
  return preview.settingsView((await preview.settingsRef(db, schoolId).get()).data());
}

async function checkPeriod(ctx, schoolId, period) {
  if (typeof period !== 'string' || !calendar.PERIOD.test(period)) return { error: 'INVALID_ARGUMENT', reason: 'period: yyyy-mm' };
  const school = (await ctx.db.collection('schools').doc(schoolId).get()).data() || {};
  const today = civilToday(wall(ctx), school.timezone || 'UTC');
  if (period > today.slice(0, 7)) return { error: 'INVALID_ARGUMENT', reason: 'period: a month that has not started cannot be paid' };
  const earliest = `${String(Number(today.slice(0, 4)) - 2).padStart(4, '0')}-${today.slice(5, 7)}`;
  if (period < earliest) return { error: 'INVALID_ARGUMENT', reason: 'period: more than 2 years back' };
  return { school, today };
}

const actorOf = (caller) => ({ name: trim(caller.profile.displayName || caller.profile.name).slice(0, 120) || null, role: caller.role });

function historyEntry(uid, caller, seq, action, from, to, reason, ctx) {
  const a = actorOf(caller);
  return { seq, action, from, to, reason: reason || null, actorId: uid, actorRole: a.role, actorName: a.name, at: ctx.now, atMs: wall(ctx).getTime() };
}

// ---- create and (re)calculate ------------------------------------------------------------------------------------

/**
 * Computes every payslip of the month and stores them, keeping the adjustments already entered, then moves
 * the run to CALCULATED. Used by create and by recalculate. The payslips are written first, the run only
 * moves when they are all there: a failure part-way leaves the run as it was.
 */
async function calculateInto(ctx, uid, caller, schoolId, branchId, period, action) {
  const { db, now } = ctx;
  const runRef = runs(db, schoolId, branchId).doc(period);
  const before = (await runRef.get()).data();
  if (!before) return { error: 'NOT_FOUND', reason: 'that run does not exist' };
  if (!TRANSITIONS.calculate.from.includes(before.status)) return { error: 'FAILED_PRECONDITION', reason: `cannot calculate a run that is ${String(before.status).toLowerCase()}` };

  const settings = await loadPayrollSettings(db, schoolId);
  const loaded = await preview.loadFacts(db, schoolId, branchId, period);
  if (loaded.error) return loaded;
  const { facts } = loaded;
  const { rows } = await preview.branchCalculations(db, schoolId, branchId, period, settings, facts);
  const school = (await db.collection('schools').doc(schoolId).get()).data() || {};
  const currency = school.currency || 'INR';

  const existing = new Map((await slips(runRef).limit(1500).get()).docs.map((d) => [d.id, d.data()]));
  const eligible = rows.filter((r) => r.calc);
  const skipped = rows.filter((r) => !r.calc).map((r) => r.staff.id);
  const writes = [];
  const totals = { gross: 0, ded: 0, net: 0, unrecovered: 0, warnings: 0, adjustments: 0 };
  let droppedAdjustments = 0;
  for (const r of eligible) {
    const c = r.calc;
    const prev = existing.get(r.staff.id);
    let adjustments = prev && Array.isArray(prev.adjustments) ? prev.adjustments : [];
    const slip = {
      schoolId, branchId, period, staffId: r.staff.id,
      staffName: preview.staffName(r.staff.data), employeeCode: r.staff.data.employeeCode || '',
      structureId: r.inf.id, structureSeq: r.inf.data.seq, currency,
      lines: c.lines, days: c.days, workingDays: c.workingDays, paidDays: c.paidDays, unpaidDays: c.unpaidDays, warnings: c.warnings,
      baseGrossMinor: c.grossMinor, baseDeductionsMinor: c.deductionsMinor, unrecoveredDeductionMinor: c.unrecoveredDeductionMinor,
      adjustments,
    };
    let t = slipTotals(slip);
    if (t.errors) {
      // the new base cannot carry the old one-off items (the net would be negative): they are dropped, and counted
      droppedAdjustments += adjustments.length;
      slip.adjustments = [];
      t = slipTotals(slip);
    }
    Object.assign(slip, t, { createdAt: (prev && prev.createdAt) || now, createdBy: (prev && prev.createdBy) || uid, updatedAt: now, updatedBy: uid });
    totals.gross += t.grossMinor;
    totals.ded += t.deductionsMinor;
    totals.net += t.netMinor;
    totals.unrecovered += c.unrecoveredDeductionMinor;
    totals.warnings += c.warnings.length;
    totals.adjustments += slip.adjustments.length;
    writes.push({ ref: slips(runRef).doc(r.staff.id), data: slip });
  }
  const keep = new Set(eligible.map((r) => r.staff.id));
  const stale = [...existing.keys()].filter((id) => !keep.has(id));

  for (let i = 0; i < writes.length; i += BATCH) {
    const batch = db.batch();
    for (const w of writes.slice(i, i + BATCH)) batch.set(w.ref, w.data);
    await batch.commit();
  }
  for (let i = 0; i < stale.length; i += BATCH) {
    const batch = db.batch();
    for (const id of stale.slice(i, i + BATCH)) batch.delete(slips(runRef).doc(id));
    await batch.commit();
  }

  const out = await db.runTransaction(async (tx) => {
    const cur = (await tx.get(runRef)).data();
    if (!cur || cur.version !== before.version || cur.status !== before.status) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    let seq = Number.isInteger(cur.historyCount) ? cur.historyCount : 0;
    seq += 1;
    tx.set(historyCol(runRef).doc(seqId(seq)), historyEntry(uid, caller, seq, action, cur.status, 'CALCULATED', null, ctx));
    tx.update(runRef, {
      status: 'CALCULATED', version: cur.version + 1, historyCount: seq,
      currency, workingDays: facts.workingDates.length, unmarkedDays: settings.unmarkedDays,
      payslipCount: eligible.length, skippedCount: skipped.length, skippedStaffIds: skipped.slice(0, 100),
      warningCount: totals.warnings, adjustmentCount: totals.adjustments,
      grossMinor: totals.gross, deductionsMinor: totals.ded, netMinor: totals.net, unrecoveredDeductionMinor: totals.unrecovered,
      calculatedAt: now, calculatedBy: uid, updatedAt: now, updatedBy: uid,
    });
    return { result: { id: period, period, status: 'CALCULATED', version: cur.version + 1, payslipCount: eligible.length, skippedCount: skipped.length, droppedAdjustments, removedPayslips: stale.length } };
  }, { maxAttempts: 5 });
  return out;
}

/** Creates the run for a month (or starts a cancelled month over) and calculates it. One run per branch and month. */
async function createPayrollRun(ctx, uid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId)) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, CAP.calculate);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const checked = await checkPeriod(ctx, schoolId, data.period);
  if (checked.error) return checked;
  const period = data.period;
  const runRef = runs(db, schoolId, branchId).doc(period);
  const made = await db.runTransaction(async (tx) => {
    const cur = (await tx.get(runRef)).data();
    if (cur && cur.status !== 'CANCELLED') return { error: 'ALREADY_EXISTS', reason: `a payroll run for that month already exists (${String(cur.status).toLowerCase()})` };
    const seq = (cur && Number.isInteger(cur.historyCount) ? cur.historyCount : 0) + 1;
    tx.set(historyCol(runRef).doc(seqId(seq)), historyEntry(uid, caller, seq, 'create', cur ? 'CANCELLED' : null, 'DRAFT', null, ctx));
    tx.set(runRef, {
      schoolId, branchId, period, status: 'DRAFT', version: (cur ? cur.version : 0) + 1, historyCount: seq,
      createdAt: cur ? cur.createdAt : now, createdBy: cur ? cur.createdBy : uid, updatedAt: now, updatedBy: uid,
    });
    return { ok: true };
  });
  if (made.error) return made;
  return calculateInto(ctx, uid, caller, schoolId, branchId, period, 'create');
}

/** Recalculates a run that is still DRAFT or CALCULATED (keeps the one-off adjustments). */
async function calculatePayrollRun(ctx, uid, token, data) {
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !calendar.PERIOD.test(String(data.period))) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(ctx.db, uid, token, schoolId, branchId, CAP.calculate);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const cur = (await runs(ctx.db, schoolId, branchId).doc(data.period).get()).data();
  if (!cur) return { error: 'NOT_FOUND', reason: 'that run does not exist' };
  if (data.baseVersion !== undefined && data.baseVersion !== cur.version) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
  return calculateInto(ctx, uid, caller, schoolId, branchId, data.period, 'calculate');
}

// ---- adjustments -------------------------------------------------------------------------------------------------

/** Adds (adjustment) or removes (adjustmentId) a one-off item on a payslip while the run is CALCULATED. */
async function changeAdjustment(ctx, uid, token, data, remove) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !validId(data.staffId) || !calendar.PERIOD.test(String(data.period))) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, CAP.adjust);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  let parsed = null;
  if (!remove) {
    parsed = validateAdjustment(data.adjustment);
    if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
  } else if (!validId(data.adjustmentId)) {
    return { error: 'INVALID_ARGUMENT', reason: 'adjustmentId' };
  }
  const runRef = runs(db, schoolId, branchId).doc(data.period);
  const slipRef = slips(runRef).doc(data.staffId);
  return db.runTransaction(async (tx) => {
    const run = (await tx.get(runRef)).data();
    if (!run) return { error: 'NOT_FOUND', reason: 'that run does not exist' };
    if (run.status !== 'CALCULATED') return { error: 'FAILED_PRECONDITION', reason: 'a run can only be adjusted while it is calculated, before approval' };
    if (data.baseVersion !== undefined && data.baseVersion !== run.version) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    const slip = (await tx.get(slipRef)).data();
    if (!slip) return { error: 'NOT_FOUND', reason: 'that person has no payslip in this run' };
    const list = Array.isArray(slip.adjustments) ? slip.adjustments : [];
    let next;
    let label = null;
    if (remove) {
      const found = list.find((a) => a.id === data.adjustmentId);
      if (!found) return { error: 'NOT_FOUND', reason: 'that adjustment does not exist' };
      next = list.filter((a) => a.id !== data.adjustmentId);
      label = found.label;
    } else {
      if (list.length >= MAX_ADJUSTMENTS) return { error: 'FAILED_PRECONDITION', reason: `at most ${MAX_ADJUSTMENTS} adjustments per payslip` };
      next = [...list, { id: crypto.randomBytes(6).toString('hex'), ...parsed.value, atMs: wall(ctx).getTime() }];
      label = parsed.value.label;
    }
    const t = slipTotals({ ...slip, adjustments: next });
    if (t.errors) return { error: 'FAILED_PRECONDITION', reason: reasonOf(t.errors) };
    const seq = (Number.isInteger(run.historyCount) ? run.historyCount : 0) + 1;
    // the history names the person and the item, never the amount
    tx.set(historyCol(runRef).doc(seqId(seq)), { ...historyEntry(uid, caller, seq, remove ? 'adjustRemove' : 'adjust', 'CALCULATED', 'CALCULATED', remove ? `Removed: ${label}` : parsed.value.reason, ctx), staffId: data.staffId });
    tx.update(slipRef, { adjustments: next, ...t, updatedAt: now, updatedBy: uid });
    tx.update(runRef, {
      version: run.version + 1, historyCount: seq,
      grossMinor: run.grossMinor + (t.grossMinor - slip.grossMinor),
      deductionsMinor: run.deductionsMinor + (t.deductionsMinor - slip.deductionsMinor),
      netMinor: run.netMinor + (t.netMinor - slip.netMinor),
      adjustmentCount: Math.max(0, (run.adjustmentCount || 0) + (next.length - list.length)),
      calculatedBy: uid, updatedAt: now, updatedBy: uid,
    });
    return { result: { id: data.period, version: run.version + 1, adjustmentCount: next.length } };
  }, { maxAttempts: 10 });
}
const adjustPayslip = (ctx, uid, token, data) => changeAdjustment(ctx, uid, token, data, false);
const removePayslipAdjustment = (ctx, uid, token, data) => changeAdjustment(ctx, uid, token, data, true);

// ---- approve, pay, cancel ---------------------------------------------------------------------------------------

/** Whether [uid] prepared the run (created, recalculated or adjusted it), from its history. */
async function preparedBy(db, runRef, uid) {
  const snap = await historyCol(runRef).where('actorId', '==', uid).limit(100).get();
  return snap.docs.some((d) => PREPARING.includes(d.data().action));
}

async function transition(ctx, uid, token, data, action) {
  const { db, now } = ctx;
  const spec = Object.prototype.hasOwnProperty.call(TRANSITIONS, action) ? TRANSITIONS[action] : null;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!spec || !validId(branchId) || !calendar.PERIOD.test(String(data.period))) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, CAP[action]);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const reason = trim(data.reason);
  if (reason.length > REASON_MAX) return { error: 'INVALID_ARGUMENT', reason: `reason: up to ${REASON_MAX} characters` };
  const runRef = runs(db, schoolId, branchId).doc(data.period);

  let payment = null;
  if (action === 'pay') {
    const p = data.payment && typeof data.payment === 'object' ? data.payment : {};
    const errors = {};
    if (!PAYMENT_MODES.includes(p.paymentMode)) errors.paymentMode = `choose one of ${PAYMENT_MODES.join(', ')}`;
    const reference = trim(p.paymentReference);
    if (reference.length > 60) errors.paymentReference = 'up to 60 characters';
    const school = (await db.collection('schools').doc(schoolId).get()).data() || {};
    const today = civilToday(wall(ctx), school.timezone || 'UTC');
    const paidDate = p.paidDate === undefined || p.paidDate === null || p.paidDate === '' ? today : p.paidDate;
    if (!validDate(paidDate)) errors.paidDate = 'a date (yyyy-mm-dd)';
    else if (paidDate > today) errors.paidDate = 'cannot be in the future';
    else if (paidDate < `${data.period}-01`) errors.paidDate = 'cannot be before the month being paid';
    if (Object.keys(errors).length) return { error: 'INVALID_ARGUMENT', reason: reasonOf(errors) };
    payment = { paymentMode: p.paymentMode, paymentReference: reference, paidDate };
  }

  // approval: what the caller is signing off must be what is stored, and nobody signs off their own work
  let seen = null;
  if (action === 'approve') {
    const run = (await runRef.get()).data();
    if (!run) return { error: 'NOT_FOUND', reason: 'that run does not exist' };
    if (run.status === spec.to) return { result: { id: data.period, status: run.status, version: run.version, duplicate: true } };
    if (run.status !== 'CALCULATED') return { error: 'FAILED_PRECONDITION', reason: `cannot approve a run that is ${String(run.status).toLowerCase()}` };
    if (data.baseVersion !== undefined && data.baseVersion !== run.version) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    const settings = await loadPayrollSettings(db, schoolId);
    if (settings.allowSelfApproval !== true && (await preparedBy(db, runRef, uid))) return { error: 'PERMISSION_DENIED', reason: 'you prepared this run; another school administrator must approve it' };
    if (!run.payslipCount) return { error: 'FAILED_PRECONDITION', reason: 'there are no payslips in this run' };
    if ((run.warningCount > 0 || run.skippedCount > 0) && data.acknowledgeWarnings !== true) return { error: 'FAILED_PRECONDITION', reason: 'the run has things to check; review them and confirm (acknowledgeWarnings)' };
    const all = (await slips(runRef).limit(1500).get()).docs.map((d) => d.data());
    const sum = (k) => all.reduce((s, p) => s + p[k], 0);
    if (all.length !== run.payslipCount || sum('grossMinor') !== run.grossMinor || sum('deductionsMinor') !== run.deductionsMinor || sum('netMinor') !== run.netMinor) {
      return { error: 'FAILED_PRECONDITION', reason: 'the totals do not match the payslips; recalculate the run' };
    }
    seen = run.version;
  }

  return db.runTransaction(async (tx) => {
    const cur = (await tx.get(runRef)).data();
    if (!cur) return { error: 'NOT_FOUND', reason: 'that run does not exist' };
    if (cur.status === spec.to) return { result: { id: data.period, status: cur.status, version: cur.version, duplicate: true } };
    if (!spec.from.includes(cur.status)) return { error: 'FAILED_PRECONDITION', reason: `cannot ${action} a run that is ${String(cur.status).toLowerCase()}` };
    if (data.baseVersion !== undefined && data.baseVersion !== cur.version) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    if (seen !== null && cur.version !== seen) return { error: 'ABORTED', reason: 'changed while you were approving; reload and check again' };
    if (action === 'cancel') {
      if (reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: `reason: at least ${REASON_MIN} characters` };
      if (cur.status === 'APPROVED' && caller.role !== SCHOOL_ADMIN) return { error: 'PERMISSION_DENIED', reason: 'only a school administrator can cancel an approved run' };
    }
    const seq = (Number.isInteger(cur.historyCount) ? cur.historyCount : 0) + 1;
    tx.set(historyCol(runRef).doc(seqId(seq)), historyEntry(uid, caller, seq, action, cur.status, spec.to, reason, ctx));
    const patch = { status: spec.to, version: cur.version + 1, historyCount: seq, updatedAt: now, updatedBy: uid };
    if (action === 'approve') Object.assign(patch, { approvedAt: now, approvedBy: uid, approvedByName: actorOf(caller).name });
    if (action === 'pay') Object.assign(patch, { ...payment, paidAt: now, paidBy: uid });
    if (action === 'cancel') Object.assign(patch, { cancelledAt: now, cancelledBy: uid, cancelReason: reason });
    tx.update(runRef, patch);
    return { result: { id: data.period, status: spec.to, version: cur.version + 1 } };
  }, { maxAttempts: 10 });
}
const approvePayrollRun = (ctx, uid, token, data) => transition(ctx, uid, token, data, 'approve');
const payPayrollRun = (ctx, uid, token, data) => transition(ctx, uid, token, data, 'pay');
const cancelPayrollRun = (ctx, uid, token, data) => transition(ctx, uid, token, data, 'cancel');

// ---- reads (school admin and finance of the branch) -------------------------------------------------------------

async function listPayrollRuns(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId)) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, 'view');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const snap = await runs(db, schoolId, branchId).orderBy('period', 'desc').limit(36).get();
  return { result: { runs: snap.docs.map((d) => runView(d.id, d.data())), canApprove: CAPS.approve.includes(caller.role), canPrepare: CAPS.prepare.includes(caller.role), canPay: CAPS.pay.includes(caller.role) } };
}

async function getPayrollRun(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !calendar.PERIOD.test(String(data.period))) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, 'view');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const runRef = runs(db, schoolId, branchId).doc(data.period);
  const run = (await runRef.get()).data();
  if (!run) return { error: 'NOT_FOUND', reason: 'that run does not exist' };
  const rows = (await slips(runRef).limit(1500).get()).docs.map((d) => slipSummary(d.id, d.data())).sort((a, b) => a.name.localeCompare(b.name));
  const settings = await loadPayrollSettings(db, schoolId);
  return {
    result: {
      run: runView(data.period, run), payslips: rows, skippedStaffIds: Array.isArray(run.skippedStaffIds) ? run.skippedStaffIds : [],
      canApprove: CAPS.approve.includes(caller.role), canPrepare: CAPS.prepare.includes(caller.role), canPay: CAPS.pay.includes(caller.role),
      allowSelfApproval: settings.allowSelfApproval === true,
    },
  };
}

async function getPayslip(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !validId(data.staffId) || !calendar.PERIOD.test(String(data.period))) return { error: 'PERMISSION_DENIED' };
  if (!(await authorize(db, uid, token, schoolId, branchId, 'view'))) return { error: 'PERMISSION_DENIED' };
  const snap = await slips(runs(db, schoolId, branchId).doc(data.period)).doc(data.staffId).get();
  if (!snap.exists) return { error: 'NOT_FOUND', reason: 'that person has no payslip in this run' };
  return { result: { payslip: slipView(snap.id, snap.data()) } };
}

async function getPayrollRunHistory(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !calendar.PERIOD.test(String(data.period))) return { error: 'PERMISSION_DENIED' };
  if (!(await authorize(db, uid, token, schoolId, branchId, 'view'))) return { error: 'PERMISSION_DENIED' };
  const runRef = runs(db, schoolId, branchId).doc(data.period);
  if (!(await runRef.get()).exists) return { error: 'NOT_FOUND', reason: 'that run does not exist' };
  const snap = await historyCol(runRef).orderBy('seq', 'asc').limit(300).get();
  return {
    result: {
      history: snap.docs.map((d) => {
        const h = d.data();
        return { seq: h.seq, action: h.action, from: h.from || null, to: h.to || null, reason: h.reason || null, actorName: h.actorName || null, actorRole: h.actorRole || null, staffId: h.staffId || null, atMs: h.atMs || null };
      }),
    },
  };
}

module.exports = {
  TRANSITIONS, CAP, PREPARING, slipTotals, validateAdjustment,
  createPayrollRun, calculatePayrollRun, adjustPayslip, removePayslipAdjustment,
  approvePayrollRun, payPayrollRun, cancelPayrollRun,
  listPayrollRuns, getPayrollRun, getPayslip, getPayrollRunHistory,
};

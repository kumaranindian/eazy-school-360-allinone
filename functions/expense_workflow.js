'use strict';

// Expense workflow (docs/expense-management/, phase E4): submit, approve or reject, pay, cancel, reopen.
//
//   DRAFT -> SUBMITTED -> APPROVED | REJECTED ;  APPROVED -> PAID ;  REJECTED -> DRAFT (reopen)
//   DRAFT | SUBMITTED | APPROVED -> CANCELLED
//
// ONE transition table; every change runs in a transaction that re-reads the expense, checks the status it
// came from, who is asking, and writes the new status AND an append-only history entry together. Approval is
// a per-school setting: when it is off, submitting approves at once (both steps are recorded, the second as
// automatic). Nobody approves their own expense unless the school allows it. Nothing here edits the amount
// or other details: an expense is only editable as a draft (expenses.js).
//
//   schools/{s}/branches/{b}/expenses/{id}/history/{00001}     { seq, action, from, to, actor..., reason }

const { authorize, settingsRef, settingsView, DEFAULT_SETTINGS, expenseCollection, expenseView, validDate, civilToday, wall, PAYMENT_MODES } = require('./expenses');
const { validId } = require('./ids');
const { createOnce } = require('./notify_events');

const ADMINS = ['SCHOOL_ADMIN', 'BRANCH_ADMIN'];
const REASON_MIN = 10;
const REASON_MAX = 300;

// action -> { from: statuses it may start from, to }
const TRANSITIONS = Object.freeze({
  submit: { from: ['DRAFT'], to: 'SUBMITTED' },
  approve: { from: ['SUBMITTED'], to: 'APPROVED' },
  reject: { from: ['SUBMITTED'], to: 'REJECTED' },
  pay: { from: ['APPROVED'], to: 'PAID' },
  cancel: { from: ['DRAFT', 'SUBMITTED', 'APPROVED'], to: 'CANCELLED' },
  reopen: { from: ['REJECTED'], to: 'DRAFT' },
});
// The capability an action needs (expenses.js CAPS); finer rules are in [mayAct].
const CAP = Object.freeze({ submit: 'create', approve: 'approve', reject: 'approve', pay: 'pay', cancel: 'create', reopen: 'create' });

const trim = (v) => (typeof v === 'string' ? v.trim() : '');
const text = (v, max) => trim(v).slice(0, max);
const historyCol = (ref) => ref.collection('history');
const seqId = (n) => String(n).padStart(5, '0');
const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');

/**
 * Pure: whether [role] ([uid]) may do [action] to [expense] under [settings]. Returns null when allowed, or
 * { error, reason }. Status is checked by the caller; this is only WHO.
 */
function mayAct(action, { role, uid, expense, settings }) {
  const own = expense.createdBy === uid;
  const denied = (reason) => ({ error: 'PERMISSION_DENIED', reason });
  switch (action) {
    case 'submit':
    case 'reopen':
      return own || ADMINS.includes(role) ? null : denied('only the person who recorded it, or an administrator');
    case 'approve':
    case 'reject': {
      const approvers = Array.isArray(settings.approverRoles) ? settings.approverRoles : DEFAULT_SETTINGS.approverRoles;
      // Only an administrator can ever approve, whatever the stored setting says (defence in depth).
      if (!(role === 'SCHOOL_ADMIN' || (role === 'BRANCH_ADMIN' && approvers.includes(role)))) return denied('your role may not decide expenses in this school');
      const mine = own || expense.submittedBy === uid;
      if (mine && settings.allowSelfApproval !== true) return denied('you cannot decide an expense you recorded');
      return null;
    }
    case 'pay':
      return role === 'SCHOOL_ADMIN' || role === 'FINANCE' ? null : denied('only a school administrator or finance can pay');
    case 'cancel':
      if (ADMINS.includes(role)) return null;
      return own && ['DRAFT', 'SUBMITTED'].includes(expense.status) ? null : denied('only the person who recorded it (before approval), or an administrator');
    default:
      return denied('unknown action');
  }
}

const needsReason = (action, status) => action === 'reject' || (action === 'cancel' && status !== 'DRAFT');

async function loadSettings(db, schoolId) {
  return settingsView({ ...DEFAULT_SETTINGS, ...((await settingsRef(db, schoolId).get()).data() || {}) });
}

// ---- notifications (best effort, after the change; one id per event and person) -----------------------

async function activeUsers(db, schoolId, role) {
  const q = await db.collection('users').where('schoolId', '==', schoolId).where('role', '==', role).where('status', '==', 'ACTIVE').get();
  return q.docs.map((d) => ({ id: d.id, ...d.data() }));
}

/** Who to tell: [kind] 'approvers' (school admins, plus branch admins when allowed), 'finance' of the branch, or a user id. */
async function recipientsFor(db, schoolId, branchId, kind, settings) {
  if (kind === 'approvers') {
    const owners = (await activeUsers(db, schoolId, 'SCHOOL_ADMIN')).map((u) => u.id);
    if (!settings.approverRoles.includes('BRANCH_ADMIN')) return owners;
    const branch = (await activeUsers(db, schoolId, 'BRANCH_ADMIN')).filter((u) => u.branchId === branchId).map((u) => u.id);
    return [...new Set([...owners, ...branch])];
  }
  if (kind === 'finance') return (await activeUsers(db, schoolId, 'FINANCE')).filter((u) => u.branchId === branchId).map((u) => u.id);
  return [kind];
}

/** The text names the expense NUMBER and what happened: never the amount, payee or a reason (it shows on a lock screen). */
async function notify(ctx, { schoolId, branchId, expenseId, number, version, type, to, title, body, skip, settings }) {
  const col = ctx.db.collection('schools').doc(schoolId).collection('branches').doc(branchId).collection('notifications');
  let created = 0;
  for (const uid of [...new Set(await recipientsFor(ctx.db, schoolId, branchId, to, settings))]) {
    if (!uid || uid === skip) continue;
    const ok = await createOnce(col.doc(`${type}__${expenseId}__${version}__${uid}`), {
      schoolId, branchId, audience: 'USER', recipientUserId: uid, type, title, body: body.replace('{number}', number),
      refType: 'EXPENSE', refId: expenseId, createdBy: 'system', createdAt: ctx.now, readAt: null,
    });
    if (ok) created++;
  }
  return created;
}

const MESSAGES = {
  submitted: { type: 'EXPENSE_SUBMITTED', to: 'approvers', title: 'Expense awaiting approval', body: 'Expense {number} needs your decision.' },
  approvedMaker: { type: 'EXPENSE_APPROVED', title: 'Expense approved', body: 'Expense {number} was approved.' },
  readyToPay: { type: 'EXPENSE_READY_TO_PAY', to: 'finance', title: 'Expense ready to pay', body: 'Expense {number} is approved and ready to pay.' },
  rejected: { type: 'EXPENSE_REJECTED', title: 'Expense rejected', body: 'Expense {number} was rejected. Open it to see why.' },
  paid: { type: 'EXPENSE_PAID', title: 'Expense paid', body: 'Expense {number} was paid.' },
};

async function notifyAfter(ctx, info) {
  const base = { schoolId: info.schoolId, branchId: info.branchId, expenseId: info.expenseId, number: info.number, version: info.version, skip: info.actor, settings: info.settings };
  const maker = info.createdBy;
  if (info.to === 'SUBMITTED') await notify(ctx, { ...base, ...MESSAGES.submitted });
  if (info.to === 'APPROVED') {
    if (info.action === 'approve') await notify(ctx, { ...base, ...MESSAGES.approvedMaker, to: maker });
    await notify(ctx, { ...base, ...MESSAGES.readyToPay });
  }
  if (info.to === 'REJECTED') await notify(ctx, { ...base, ...MESSAGES.rejected, to: maker });
  if (info.to === 'PAID') await notify(ctx, { ...base, ...MESSAGES.paid, to: maker });
}

// ---- the transition -----------------------------------------------------------------------------------

/**
 * Runs [action] on an expense. [data]: schoolId, branchId, expenseId, optional baseVersion, and per action:
 * reason (reject: required; cancel: required once submitted), payment { paymentMode, paymentReference, paidDate } (pay).
 */
async function transition(ctx, uid, token, data, action) {
  const { db, now } = ctx;
  const spec = Object.prototype.hasOwnProperty.call(TRANSITIONS, action) ? TRANSITIONS[action] : null;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!spec || !validId(branchId) || !validId(data.expenseId)) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, CAP[action]);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const reason = text(data.reason, REASON_MAX + 1);
  if (reason.length > REASON_MAX) return { error: 'INVALID_ARGUMENT', reason: `reason: up to ${REASON_MAX} characters` };
  const at = wall(ctx);
  let payment = null;
  if (action === 'pay') {
    const p = data.payment && typeof data.payment === 'object' ? data.payment : {};
    const errors = {};
    if (!PAYMENT_MODES.includes(p.paymentMode)) errors.paymentMode = `choose one of ${PAYMENT_MODES.join(', ')}`;
    const reference = text(p.paymentReference, 61);
    if (reference.length > 60) errors.paymentReference = 'up to 60 characters';
    const today = civilToday(at, (await db.collection('schools').doc(schoolId).get()).data().timezone || 'UTC');
    const paidDate = p.paidDate === undefined || p.paidDate === null || p.paidDate === '' ? today : p.paidDate;
    if (!validDate(paidDate)) errors.paidDate = 'a date (yyyy-mm-dd)';
    else if (paidDate > today) errors.paidDate = 'cannot be in the future';
    if (Object.keys(errors).length) return { error: 'INVALID_ARGUMENT', reason: reasonOf(errors) };
    payment = { paymentMode: p.paymentMode, paymentReference: reference, paidDate };
  }
  const settings = await loadSettings(db, schoolId);
  const ref = expenseCollection(db, schoolId, branchId).doc(data.expenseId);
  const actorName = text(caller.profile.displayName || caller.profile.name, 120) || null;
  let info = null;
  const out = await db.runTransaction(async (tx) => {
    info = null;
    const cur = (await tx.get(ref)).data();
    if (!cur) return { error: 'NOT_FOUND', reason: 'that expense does not exist' };
    if (cur.status === spec.to && action !== 'reopen') return { result: { id: ref.id, status: cur.status, version: cur.version, duplicate: true } };
    if (!spec.from.includes(cur.status)) return { error: 'FAILED_PRECONDITION', reason: `cannot ${action} an expense that is ${cur.status.toLowerCase()}` };
    if (data.baseVersion !== undefined && data.baseVersion !== cur.version) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    const who = mayAct(action, { role: caller.role, uid, expense: cur, settings });
    if (who) return who;
    if (needsReason(action, cur.status) && reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: `reason: at least ${REASON_MIN} characters` };
    if (action === 'submit') {
      const limit = settings.receiptRequiredOverMinor;
      if (limit !== null && cur.amountMinor > limit && !(Number.isInteger(cur.receiptCount) && cur.receiptCount >= 1)) {
        return { error: 'FAILED_PRECONDITION', reason: 'a receipt is required for this amount; attach one before submitting' };
      }
    }
    // the steps this call takes: submitting with approval switched off also approves, automatically
    const steps = [{ action, from: cur.status, to: spec.to, reason: reason || null, auto: false }];
    if (action === 'submit' && settings.approvalRequired === false) steps.push({ action: 'approve', from: 'SUBMITTED', to: 'APPROVED', reason: 'approval is not required in this school', auto: true });
    const final = steps[steps.length - 1].to;
    let seq = Number.isInteger(cur.historyCount) ? cur.historyCount : 0;
    for (const st of steps) {
      seq += 1;
      tx.set(historyCol(ref).doc(seqId(seq)), {
        seq, action: st.action, from: st.from, to: st.to, reason: st.reason, auto: st.auto,
        actorId: st.auto ? null : uid, actorRole: st.auto ? 'SYSTEM' : caller.role, actorName: st.auto ? null : actorName,
        at: now, atMs: at.getTime(),
      });
    }
    const patch = { status: final, version: cur.version + 1, historyCount: seq, updatedAt: now, updatedBy: uid };
    if (action === 'submit') Object.assign(patch, { submittedAt: now, submittedBy: uid, decidedAt: null, decidedBy: null, decidedByName: null, decisionReason: null });
    if (action === 'approve' || action === 'reject') Object.assign(patch, { decidedAt: now, decidedBy: uid, decidedByName: actorName, decisionReason: reason || null });
    if (final === 'APPROVED' && action === 'submit') Object.assign(patch, { decidedAt: now, decidedBy: null, decidedByName: null, decisionReason: 'approval is not required in this school' });
    if (action === 'pay') Object.assign(patch, { ...payment, paidAt: now, paidBy: uid });
    if (action === 'cancel') Object.assign(patch, { cancelledAt: now, cancelledBy: uid, cancelReason: reason || null });
    if (action === 'reopen') Object.assign(patch, { decidedAt: null, decidedBy: null, decidedByName: null, decisionReason: null });
    tx.update(ref, patch);
    info = { schoolId, branchId, expenseId: ref.id, number: cur.number, version: cur.version + 1, to: final, action, actor: uid, createdBy: cur.createdBy, settings };
    return { result: { id: ref.id, status: final, version: cur.version + 1 } };
  }, { maxAttempts: 10 });
  if (info) {
    try {
      await notifyAfter(ctx, info);
    } catch (e) {
      // The change is done; a notice that could not be written is not a reason to fail it.
      if (ctx.log) ctx.log('expense notification failed', { category: String((e && e.code) || 'error') });
    }
  }
  return out;
}

const submitExpense = (ctx, uid, token, data) => transition(ctx, uid, token, data, 'submit');
const payExpense = (ctx, uid, token, data) => transition(ctx, uid, token, data, 'pay');
const cancelExpense = (ctx, uid, token, data) => transition(ctx, uid, token, data, 'cancel');
const reopenExpense = (ctx, uid, token, data) => transition(ctx, uid, token, data, 'reopen');
/** [data.decision]: APPROVE or REJECT. */
function decideExpense(ctx, uid, token, data) {
  const d = data && data.decision;
  if (d !== 'APPROVE' && d !== 'REJECT') return Promise.resolve({ error: 'INVALID_ARGUMENT', reason: 'decision: APPROVE or REJECT' });
  return transition(ctx, uid, token, data, d === 'APPROVE' ? 'approve' : 'reject');
}

/** The history of an expense, oldest first (anyone who can see expenses in the branch). */
async function getExpenseHistory(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !validId(data.expenseId)) return { error: 'PERMISSION_DENIED' };
  if (!(await authorize(db, uid, token, schoolId, branchId, 'view'))) return { error: 'PERMISSION_DENIED' };
  const ref = expenseCollection(db, schoolId, branchId).doc(data.expenseId);
  if (!(await ref.get()).exists) return { error: 'NOT_FOUND', reason: 'that expense does not exist' };
  const snap = await historyCol(ref).orderBy('seq', 'asc').limit(200).get();
  return {
    result: {
      history: snap.docs.map((d) => {
        const h = d.data();
        return { seq: h.seq, action: h.action, from: h.from, to: h.to, reason: h.reason || null, auto: h.auto === true, actorName: h.actorName || null, actorRole: h.actorRole || null, atMs: h.atMs || null };
      }),
    },
  };
}

module.exports = {
  TRANSITIONS, CAP, REASON_MIN, mayAct, needsReason, transition,
  submitExpense, decideExpense, payExpense, cancelExpense, reopenExpense, getExpenseHistory,
  expenseView,
};

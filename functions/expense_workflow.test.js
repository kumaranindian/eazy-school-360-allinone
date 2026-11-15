'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const x = require('./expenses');
const w = require('./expense_workflow');

const NOW = new Date('2026-11-15T10:00:00Z');
const T = {};
const base = (extra = {}) => ({
  'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
  'schools/sA/branches/b1': { name: 'Main' },
  'schools/sA/branches/b2': { name: 'Second' },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN', displayName: 'Owner One' },
  'users/owner2': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN', displayName: 'Branch One' },
  'users/ba2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  'users/fin2': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  'users/finB2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'FINANCE' },
  'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  ...extra,
});
const env = (extra) => {
  const db = fakeDb(base(extra));
  return { db, ctx: { db, now: 'TS', wall: () => NOW, nowDate: () => NOW } };
};
const setSettings = (e, s) => x.saveExpenseSettings(e.ctx, 'owner', T, { schoolId: 'sA', settings: s });
const key = (id) => `schools/sA/branches/b1/expenses/${id}`;
const ids = (id, o = {}) => ({ schoolId: 'sA', branchId: 'b1', expenseId: id, ...o });
const draft = async (e, uid = 'fin', amount = 5000) => {
  await x.listExpenseCategories(e.ctx, 'owner', T, { schoolId: 'sA' });
  return (await x.createExpense(e.ctx, uid, T, { schoolId: 'sA', branchId: 'b1', expense: { categoryId: 'cat_other', amountMinor: amount, expenseDate: '2026-11-10' } })).result.id;
};
const history = async (e, id) => (await w.getExpenseHistory(e.ctx, 'owner', T, ids(id))).result.history;
const status = (e, id) => e.db.store.get(key(id)).status;
const pay = { paymentMode: 'UPI', paymentReference: 'UTR123' };
const notifs = (e) => [...e.db.store.entries()].filter(([k]) => k.includes('/notifications/')).map(([k, v]) => ({ k, ...v }));

test('the transition table is the only way the status moves', () => {
  assert.deepEqual(Object.keys(w.TRANSITIONS).sort(), ['approve', 'cancel', 'pay', 'reject', 'reopen', 'submit']);
  assert.deepEqual(w.TRANSITIONS.pay, { from: ['APPROVED'], to: 'PAID' });
  assert.ok(!w.TRANSITIONS.cancel.from.includes('PAID'), 'a paid expense is never cancelled');
  assert.ok(!w.TRANSITIONS.cancel.from.includes('REJECTED'));
  assert.ok(!Object.values(w.TRANSITIONS).some((t) => t.from.includes('PAID')), 'nothing leaves PAID');
});

test('mayAct: who may do what (pure)', () => {
  const ex = (o = {}) => ({ createdBy: 'maker', status: 'SUBMITTED', ...o });
  const s = (o = {}) => ({ approverRoles: ['SCHOOL_ADMIN'], allowSelfApproval: false, ...o });
  const can = (action, role, uid, expense, settings) => w.mayAct(action, { role, uid, expense, settings: settings || s() }) === null;
  assert.ok(can('submit', 'FINANCE', 'maker', ex()));
  assert.ok(!can('submit', 'FINANCE', 'other', ex()));
  assert.ok(can('submit', 'BRANCH_ADMIN', 'other', ex()));
  assert.ok(can('approve', 'SCHOOL_ADMIN', 'a', ex()));
  assert.ok(!can('approve', 'BRANCH_ADMIN', 'a', ex()), 'a branch admin only when the school lists the role');
  assert.ok(can('approve', 'BRANCH_ADMIN', 'a', ex(), s({ approverRoles: ['SCHOOL_ADMIN', 'BRANCH_ADMIN'] })));
  assert.ok(!can('approve', 'FINANCE', 'a', ex(), s({ approverRoles: ['SCHOOL_ADMIN', 'BRANCH_ADMIN', 'FINANCE'] })), 'finance can never approve');
  assert.ok(!can('approve', 'SCHOOL_ADMIN', 'maker', ex()), 'no approving your own');
  assert.ok(!can('reject', 'SCHOOL_ADMIN', 'maker', ex()));
  assert.ok(can('approve', 'SCHOOL_ADMIN', 'maker', ex(), s({ allowSelfApproval: true })));
  assert.ok(!can('approve', 'SCHOOL_ADMIN', 'sub', ex({ submittedBy: 'sub', createdBy: 'maker' })), 'nor the person who submitted it');
  assert.ok(can('pay', 'FINANCE', 'f', ex()));
  assert.ok(can('pay', 'SCHOOL_ADMIN', 'f', ex()));
  assert.ok(!can('pay', 'BRANCH_ADMIN', 'f', ex()));
  assert.ok(can('cancel', 'FINANCE', 'maker', ex()));
  assert.ok(!can('cancel', 'FINANCE', 'maker', ex({ status: 'APPROVED' })), 'the maker cannot cancel after approval');
  assert.ok(can('cancel', 'BRANCH_ADMIN', 'x', ex({ status: 'APPROVED' })));
  assert.ok(!can('cancel', 'FINANCE', 'other', ex()));
  assert.ok(w.mayAct('nonsense', { role: 'SCHOOL_ADMIN', uid: 'a', expense: ex(), settings: s() }));
});

test('submit with approval required: SUBMITTED, a history entry and a notice to the approvers (not the maker)', async () => {
  const e = env({ 'users/owner3': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' } });
  const id = await draft(e);
  const r = await w.submitExpense(e.ctx, 'fin', T, ids(id));
  assert.equal(r.result.status, 'SUBMITTED');
  assert.equal(r.result.version, 2);
  assert.equal(status(e, id), 'SUBMITTED');
  const h = await history(e, id);
  assert.deepEqual(h.map((x_) => [x_.seq, x_.action, x_.from, x_.to]), [[1, 'submit', 'DRAFT', 'SUBMITTED']]);
  assert.equal(h[0].actorRole, 'FINANCE');
  const n = notifs(e);
  assert.deepEqual(n.map((v) => v.recipientUserId).sort(), ['owner', 'owner2', 'owner3']);
  assert.ok(n.every((v) => v.type === 'EXPENSE_SUBMITTED' && v.refType === 'EXPENSE' && v.refId === id && v.createdBy === 'system'));
  assert.ok(!JSON.stringify(n).includes('5000') && !JSON.stringify(n).includes('Raj'), 'no amount or payee in the notice');
  assert.match(n[0].body, /EXP-2026-00001/);
});

test('submit twice returns the first result and notifies once; after a decision nothing changes', async () => {
  const e = env();
  const id = await draft(e);
  await w.submitExpense(e.ctx, 'fin', T, ids(id));
  const again = await w.submitExpense(e.ctx, 'fin', T, ids(id));
  assert.equal(again.result.duplicate, true);
  assert.equal((await history(e, id)).length, 1);
  assert.equal(notifs(e).length, 2, 'one per approver, not doubled');
  await w.decideExpense(e.ctx, 'owner', T, ids(id, { decision: 'APPROVE' }));
  assert.equal((await w.submitExpense(e.ctx, 'fin', T, ids(id))).error, 'FAILED_PRECONDITION');
});

test('who may submit: the maker or an admin; not another finance user, a teacher or another branch', async () => {
  const e = env();
  const id = await draft(e, 'fin');
  assert.equal((await w.submitExpense(e.ctx, 'fin2', T, ids(id))).error, 'PERMISSION_DENIED');
  assert.equal((await w.submitExpense(e.ctx, 'teacher', T, ids(id))).error, 'PERMISSION_DENIED');
  assert.equal((await w.submitExpense(e.ctx, 'ba2', T, ids(id))).error, 'PERMISSION_DENIED');
  assert.equal((await w.submitExpense(e.ctx, 'ba1', T, ids(id))).result.status, 'SUBMITTED');
  assert.equal(status(e, id), 'SUBMITTED');
  assert.equal((await w.submitExpense(e.ctx, 'owner', T, ids('ghost'))).error, 'NOT_FOUND');
  assert.equal((await w.submitExpense(e.ctx, 'owner', T, ids('../x'))).error, 'PERMISSION_DENIED');
});

test('approval switched off: submit approves at once, both steps recorded, the second as automatic; finance is told it is ready', async () => {
  const e = env();
  await setSettings(e, { approvalRequired: false });
  const id = await draft(e);
  const r = await w.submitExpense(e.ctx, 'fin', T, ids(id));
  assert.equal(r.result.status, 'APPROVED');
  assert.equal(r.result.version, 2);
  const h = await history(e, id);
  assert.deepEqual(h.map((x_) => [x_.action, x_.to, x_.auto]), [['submit', 'SUBMITTED', false], ['approve', 'APPROVED', true]]);
  assert.equal(h[1].actorRole, 'SYSTEM');
  assert.equal(h[1].actorName, null);
  assert.deepEqual(notifs(e).map((v) => [v.type, v.recipientUserId]).sort(), [['EXPENSE_READY_TO_PAY', 'fin2']], 'finance of the branch except the actor; no approver notice');
  assert.equal(e.db.store.get(key(id)).decidedBy, null);
});

test('the receipt rule: over the limit a receipt is needed to submit', async () => {
  const e = env();
  await setSettings(e, { receiptRequiredOverMinor: 10000 });
  const small = await draft(e, 'fin', 10000);
  assert.equal((await w.submitExpense(e.ctx, 'fin', T, ids(small))).result.status, 'SUBMITTED', 'exactly at the limit needs none');
  const big = await draft(e, 'fin', 10001);
  const refused = await w.submitExpense(e.ctx, 'fin', T, ids(big));
  assert.equal(refused.error, 'FAILED_PRECONDITION');
  assert.match(refused.reason, /receipt/);
  assert.equal(status(e, big), 'DRAFT');
  e.db.store.set(key(big), { ...e.db.store.get(key(big)), receiptCount: 1 });
  assert.equal((await w.submitExpense(e.ctx, 'fin', T, ids(big))).result.status, 'SUBMITTED');
});

test('approve and reject: only an allowed approver, not your own, reject needs a reason; the maker is told', async () => {
  const e = env();
  const id = await draft(e, 'ba1');
  await w.submitExpense(e.ctx, 'ba1', T, ids(id));
  const decide = (uid, decision, o = {}) => w.decideExpense(e.ctx, uid, T, ids(id, { decision, ...o }));
  assert.equal((await decide('fin', 'APPROVE')).error, 'PERMISSION_DENIED', 'finance never approves');
  assert.equal((await decide('teacher', 'APPROVE')).error, 'PERMISSION_DENIED');
  assert.equal((await decide('ba1', 'APPROVE')).error, 'PERMISSION_DENIED', 'a branch admin is not an approver by default (and it is their own)');
  assert.equal((await decide('owner', 'MAYBE')).error, 'INVALID_ARGUMENT');
  assert.equal((await decide('owner', 'REJECT')).error, 'INVALID_ARGUMENT', 'a rejection needs a reason');
  assert.equal((await decide('owner', 'REJECT', { reason: 'too short' })).error, 'INVALID_ARGUMENT');
  const rej = await decide('owner', 'REJECT', { reason: 'Please attach the supplier invoice.' });
  assert.equal(rej.result.status, 'REJECTED');
  const d = e.db.store.get(key(id));
  assert.equal(d.decidedBy, 'owner');
  assert.equal(d.decidedByName, 'Owner One');
  assert.equal(d.decisionReason, 'Please attach the supplier invoice.');
  const maker = notifs(e).filter((v) => v.type === 'EXPENSE_REJECTED');
  assert.deepEqual(maker.map((v) => v.recipientUserId), ['ba1']);
  assert.ok(!JSON.stringify(maker).includes('supplier invoice'), 'the reason is not in the notice');
  assert.equal((await decide('owner', 'APPROVE')).error, 'FAILED_PRECONDITION', 'already decided');
});

test('self approval is refused unless the school allows it; a branch admin approves when the school lists the role', async () => {
  const e = env();
  const id = await draft(e, 'owner');
  await w.submitExpense(e.ctx, 'owner', T, ids(id));
  assert.equal((await w.decideExpense(e.ctx, 'owner', T, ids(id, { decision: 'APPROVE' }))).error, 'PERMISSION_DENIED');
  assert.equal((await w.decideExpense(e.ctx, 'owner2', T, ids(id, { decision: 'APPROVE' }))).result.status, 'APPROVED', 'another school admin may');
  const id2 = await draft(e, 'owner');
  await w.submitExpense(e.ctx, 'owner', T, ids(id2));
  await setSettings(e, { allowSelfApproval: true });
  assert.equal((await w.decideExpense(e.ctx, 'owner', T, ids(id2, { decision: 'APPROVE' }))).result.status, 'APPROVED');
  const id3 = await draft(e, 'fin');
  await w.submitExpense(e.ctx, 'fin', T, ids(id3));
  assert.equal((await w.decideExpense(e.ctx, 'ba1', T, ids(id3, { decision: 'APPROVE' }))).error, 'PERMISSION_DENIED');
  await setSettings(e, { approverRoles: ['SCHOOL_ADMIN', 'BRANCH_ADMIN'] });
  assert.equal((await w.decideExpense(e.ctx, 'ba1', T, ids(id3, { decision: 'APPROVE' }))).result.status, 'APPROVED');
  assert.equal((await w.decideExpense(e.ctx, 'ba2', T, ids(id3, { decision: 'APPROVE' }))).error, 'PERMISSION_DENIED', 'a branch admin of another branch');
});

test('approving tells the maker and the branch finance team (not the approver)', async () => {
  const e = env();
  const id = await draft(e, 'fin');
  await w.submitExpense(e.ctx, 'fin', T, ids(id));
  await w.decideExpense(e.ctx, 'owner', T, ids(id, { decision: 'APPROVE' }));
  const out = notifs(e).filter((v) => v.type !== 'EXPENSE_SUBMITTED').map((v) => [v.type, v.recipientUserId]).sort();
  assert.deepEqual(out, [['EXPENSE_APPROVED', 'fin'], ['EXPENSE_READY_TO_PAY', 'fin'], ['EXPENSE_READY_TO_PAY', 'fin2']]);
});

test('pay: finance or the school admin, only when approved; the payment is validated; paid is final', async () => {
  const e = env();
  const id = await draft(e, 'fin');
  assert.equal((await w.payExpense(e.ctx, 'fin', T, ids(id, { payment: pay }))).error, 'FAILED_PRECONDITION', 'not approved yet');
  await w.submitExpense(e.ctx, 'fin', T, ids(id));
  await w.decideExpense(e.ctx, 'owner', T, ids(id, { decision: 'APPROVE' }));
  assert.equal((await w.payExpense(e.ctx, 'ba1', T, ids(id, { payment: pay }))).error, 'PERMISSION_DENIED', 'a branch admin cannot pay');
  assert.equal((await w.payExpense(e.ctx, 'teacher', T, ids(id, { payment: pay }))).error, 'PERMISSION_DENIED');
  assert.equal((await w.payExpense(e.ctx, 'finB2', T, ids(id, { payment: pay }))).error, 'PERMISSION_DENIED', 'finance of another branch');
  for (const bad of [{}, { paymentMode: 'BITCOIN' }, { ...pay, paidDate: '2026-12-01' }, { ...pay, paidDate: 'x' }, { ...pay, paymentReference: 'x'.repeat(61) }]) {
    assert.equal((await w.payExpense(e.ctx, 'fin', T, ids(id, { payment: bad }))).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
  assert.equal(status(e, id), 'APPROVED');
  const ok = await w.payExpense(e.ctx, 'fin2', T, ids(id, { payment: { ...pay, paidDate: '2026-11-14' } }));
  assert.equal(ok.result.status, 'PAID');
  const d = e.db.store.get(key(id));
  assert.deepEqual([d.paymentMode, d.paymentReference, d.paidDate, d.paidBy], ['UPI', 'UTR123', '2026-11-14', 'fin2']);
  assert.equal((await w.payExpense(e.ctx, 'fin', T, ids(id, { payment: { ...pay, paymentMode: 'CASH' } }))).result.duplicate, true, 'a second pay is a no-op');
  assert.equal(e.db.store.get(key(id)).paymentMode, 'UPI', 'the first payment stands');
  assert.equal((await w.cancelExpense(e.ctx, 'owner', T, ids(id, { reason: 'I changed my mind about this.' }))).error, 'FAILED_PRECONDITION', 'paid is final');
  assert.equal((await w.reopenExpense(e.ctx, 'owner', T, ids(id))).error, 'FAILED_PRECONDITION');
  assert.ok(notifs(e).some((v) => v.type === 'EXPENSE_PAID' && v.recipientUserId === 'fin'));
});

test('pay defaults the paid date to the school day (not the server clock)', async () => {
  const e = env();
  e.ctx.wall = () => new Date('2026-11-15T20:00:00Z'); // already the 16th in Kolkata
  const id = await draft(e);
  await w.submitExpense(e.ctx, 'fin', T, ids(id));
  await w.decideExpense(e.ctx, 'owner', T, ids(id, { decision: 'APPROVE' }));
  await w.payExpense(e.ctx, 'fin', T, ids(id, { payment: pay }));
  assert.equal(e.db.store.get(key(id)).paidDate, '2026-11-16');
});

test('cancel: a draft freely by its maker; later needs a reason; the maker cannot after approval', async () => {
  const e = env();
  const a = await draft(e, 'fin');
  assert.equal((await w.cancelExpense(e.ctx, 'fin2', T, ids(a))).error, 'PERMISSION_DENIED');
  assert.equal((await w.cancelExpense(e.ctx, 'fin', T, ids(a))).result.status, 'CANCELLED');
  assert.equal((await w.submitExpense(e.ctx, 'fin', T, ids(a))).error, 'FAILED_PRECONDITION');
  const b = await draft(e, 'fin');
  await w.submitExpense(e.ctx, 'fin', T, ids(b));
  assert.equal((await w.cancelExpense(e.ctx, 'fin', T, ids(b))).error, 'INVALID_ARGUMENT', 'a submitted expense needs a reason');
  assert.equal((await w.cancelExpense(e.ctx, 'fin', T, ids(b, { reason: 'Entered twice by mistake.' }))).result.status, 'CANCELLED');
  const c = await draft(e, 'fin');
  await w.submitExpense(e.ctx, 'fin', T, ids(c));
  await w.decideExpense(e.ctx, 'owner', T, ids(c, { decision: 'APPROVE' }));
  assert.equal((await w.cancelExpense(e.ctx, 'fin', T, ids(c, { reason: 'Entered twice by mistake.' }))).error, 'PERMISSION_DENIED');
  assert.equal((await w.cancelExpense(e.ctx, 'ba1', T, ids(c, { reason: 'Entered twice by mistake.' }))).result.status, 'CANCELLED');
  assert.equal(e.db.store.get(key(c)).cancelReason, 'Entered twice by mistake.');
});

test('reopen: a rejected expense goes back to a draft its maker can fix and submit again', async () => {
  const e = env();
  const id = await draft(e, 'fin');
  await w.submitExpense(e.ctx, 'fin', T, ids(id));
  await w.decideExpense(e.ctx, 'owner', T, ids(id, { decision: 'REJECT', reason: 'Wrong category, please fix.' }));
  assert.equal((await w.reopenExpense(e.ctx, 'fin2', T, ids(id))).error, 'PERMISSION_DENIED');
  assert.equal((await w.reopenExpense(e.ctx, 'fin', T, ids(id))).result.status, 'DRAFT');
  const d = e.db.store.get(key(id));
  assert.equal(d.decisionReason, null);
  assert.equal((await x.updateExpense(e.ctx, 'fin', T, { schoolId: 'sA', branchId: 'b1', expenseId: id, expense: { categoryId: 'cat_utilities', amountMinor: 5000, expenseDate: '2026-11-10' } })).result.version, d.version + 1, 'editable again');
  assert.equal((await w.submitExpense(e.ctx, 'fin', T, ids(id))).result.status, 'SUBMITTED');
  const h = await history(e, id);
  assert.deepEqual(h.map((v) => v.action), ['submit', 'reject', 'reopen', 'submit']);
  assert.deepEqual(h.map((v) => v.seq), [1, 2, 3, 4]);
});

test('a stale version is refused; a retry of the same decision is harmless', async () => {
  const e = env();
  const id = await draft(e);
  assert.equal((await w.submitExpense(e.ctx, 'fin', T, ids(id, { baseVersion: 7 }))).error, 'ABORTED');
  assert.equal((await w.submitExpense(e.ctx, 'fin', T, ids(id, { baseVersion: 1 }))).result.status, 'SUBMITTED');
});

test('the history is append-only, ordered, readable by anyone who can see expenses in the branch, nobody else', async () => {
  const e = env();
  const id = await draft(e);
  await w.submitExpense(e.ctx, 'fin', T, ids(id));
  await w.decideExpense(e.ctx, 'owner', T, ids(id, { decision: 'APPROVE', reason: 'ok' }));
  for (const uid of ['fin', 'fin2', 'ba1', 'owner']) assert.equal((await w.getExpenseHistory(e.ctx, uid, T, ids(id))).result.history.length, 2, uid);
  for (const uid of ['teacher', 'ba2', 'finB2']) assert.equal((await w.getExpenseHistory(e.ctx, uid, T, ids(id))).error, 'PERMISSION_DENIED', uid);
  assert.equal((await w.getExpenseHistory(e.ctx, 'owner', T, ids('ghost'))).error, 'NOT_FOUND');
  const h = (await history(e, id))[1];
  assert.deepEqual([h.action, h.actorName, h.actorRole, h.reason, h.auto], ['approve', 'Owner One', 'SCHOOL_ADMIN', 'ok', false]);
  assert.ok(Number.isFinite(h.atMs));
  assert.equal([...e.db.store.keys()].filter((k) => k.includes('/history/')).length, 2);
});

test('the module switch applies to every transition', async () => {
  const e = env({ 'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'UTC', features: { expenses: false } } });
  assert.equal((await w.submitExpense(e.ctx, 'owner', T, ids('x'))).error, 'PERMISSION_DENIED');
});

test('a notice that cannot be written never undoes the change', async () => {
  const e = env();
  const id = await draft(e);
  const real = e.db.collection;
  e.db.collection = (p) => (p === 'users' ? { where: () => { throw new Error('index missing'); }, doc: real('users').doc } : real(p));
  const r = await w.submitExpense(e.ctx, 'fin', T, ids(id));
  assert.equal(r.result.status, 'SUBMITTED');
});

test('the workflow callables are wired', () => {
  const m = require('./index.js');
  for (const n of ['submitExpense', 'decideExpense', 'payExpense', 'cancelExpense', 'reopenExpense', 'getExpenseHistory']) assert.ok(m[n], n);
});

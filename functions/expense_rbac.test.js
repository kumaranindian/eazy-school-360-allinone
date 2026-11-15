'use strict';
// Role-by-callable proof for expense management: every callable, every kind of caller, one table.
// "allowed" means the call gets past the permission check (it may still be refused for another reason,
// such as a status); everyone else must get PERMISSION_DENIED and change nothing.
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const x = require('./expenses');
const w = require('./expense_workflow');
const rc = require('./expense_receipts');
const rp = require('./expense_reports');

const NOW = new Date('2026-11-15T10:00:00Z');
const T = {};
const USERS = {
  owner: { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  owner2: { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  ba1: { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  ba2: { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  fin: { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  fin2: { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  finB2: { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'FINANCE' },
  finOff: { schoolId: 'sA', branchId: 'b1', status: 'INACTIVE', role: 'FINANCE' },
  teacher: { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  parent: { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  outsider: { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  platform: { schoolId: null, status: 'ACTIVE', role: 'PLATFORM_ADMIN' },
};
const ALL = [...Object.keys(USERS), 'ghost'];
const key = (id) => `schools/sA/branches/b1/expenses/${id}`;
const expenseDoc = (status, o = {}) => ({
  schoolId: 'sA', branchId: 'b1', number: 'EXP-2026-00001', categoryId: 'cat_other', categoryName: 'Other', amountMinor: 5000, currency: 'INR',
  expenseDate: '2026-11-10', payee: '', description: '', paymentMode: null, paymentReference: '', status, version: 3, createdBy: 'fin', createdByName: null, ...o,
});

// A fresh world per call, so one call's change never affects the next. Statuses are seeded directly.
function world(extra = {}) {
  const seed = {
    'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
    'schools/sB': { name: 'B', status: 'ACTIVE', currency: 'INR' },
    'schools/sA/branches/b1': { name: 'Main' },
    'schools/sA/branches/b2': { name: 'North' },
    ...Object.fromEntries(Object.entries(USERS).map(([k, v]) => [`users/${k}`, v])),
    ...Object.fromEntries(['draft', 'submitted', 'approved', 'rejected'].map((s) => [key(s), expenseDoc(s.toUpperCase())])),
    'schools/sA/branches/b1/expenseReceipts/rc1': { schoolId: 'sA', branchId: 'b1', expenseId: 'draft', fileName: 'a.pdf', contentType: 'application/pdf', sizeBytes: 5, storagePath: 'p', status: 'UPLOADED', revision: 1, createdBy: 'fin' },
    'schools/sA/branches/b1/expenseReceipts/rc2': { schoolId: 'sA', branchId: 'b1', expenseId: 'draft', fileName: 'b.pdf', contentType: 'application/pdf', sizeBytes: 5, storagePath: 'q', status: 'UPLOADING', revision: 1, createdBy: 'fin', expiresAt: new Date(NOW.getTime() + 3600000) },
    'schools/sA/expenseCategories/cat_other': { schoolId: 'sA', key: 'OTHER', name: 'Other', active: true, system: false },
    ...extra,
  };
  const db = fakeDb(seed);
  const storage = { stat: async () => ({ exists: false }), head: async () => Buffer.alloc(12), deleteFile: async () => {} };
  const ctx = { db, now: 'TS', wall: () => NOW, nowDate: () => NOW, storage };
  return { db, ctx, before: JSON.stringify([...db.store.entries()]) };
}

const ids = (expenseId, o = {}) => ({ schoolId: 'sA', branchId: 'b1', expenseId, ...o });
const exp = { categoryId: 'cat_other', amountMinor: 5000, expenseDate: '2026-11-10' };
const SCHOOL_LEVEL = ['owner', 'owner2', 'ba1', 'ba2', 'fin', 'fin2', 'finB2']; // any expense role of the school
const B1_VIEW = ['owner', 'owner2', 'ba1', 'fin', 'fin2'];
const B1_MAKER_OR_ADMIN = ['fin', 'owner', 'owner2', 'ba1'];
const ADMINS = ['owner', 'owner2'];

// [name, call(ctx, uid), allowed uids]
const CASES = [
  ['getExpenseSettings', (c, u) => x.getExpenseSettings(c, u, T, { schoolId: 'sA' }), SCHOOL_LEVEL],
  ['saveExpenseSettings', (c, u) => x.saveExpenseSettings(c, u, T, { schoolId: 'sA', settings: {} }), ADMINS],
  ['listExpenseCategories', (c, u) => x.listExpenseCategories(c, u, T, { schoolId: 'sA' }), SCHOOL_LEVEL],
  ['saveExpenseCategory', (c, u) => x.saveExpenseCategory(c, u, T, { schoolId: 'sA', name: 'Garden' }), ADMINS],
  ['createExpense', (c, u) => x.createExpense(c, u, T, { schoolId: 'sA', branchId: 'b1', expense: exp }), B1_VIEW],
  ['updateExpense (a draft)', (c, u) => x.updateExpense(c, u, T, ids('draft', { expense: exp })), B1_MAKER_OR_ADMIN],
  ['getExpense', (c, u) => x.getExpense(c, u, T, ids('draft')), B1_VIEW],
  ['listExpenses', (c, u) => x.listExpenses(c, u, T, { schoolId: 'sA', branchId: 'b1' }), B1_VIEW],
  ['getExpenseHistory', (c, u) => w.getExpenseHistory(c, u, T, ids('draft')), B1_VIEW],
  ['submitExpense', (c, u) => w.submitExpense(c, u, T, ids('draft')), B1_MAKER_OR_ADMIN],
  ['decideExpense approve (made by fin)', (c, u) => w.decideExpense(c, u, T, ids('submitted', { decision: 'APPROVE' })), ADMINS],
  ['decideExpense reject (made by fin)', (c, u) => w.decideExpense(c, u, T, ids('submitted', { decision: 'REJECT', reason: 'Not a school expense at all.' })), ADMINS],
  ['payExpense', (c, u) => w.payExpense(c, u, T, ids('approved', { payment: { paymentMode: 'CASH' } })), ['owner', 'owner2', 'fin', 'fin2']],
  ['cancelExpense (a draft)', (c, u) => w.cancelExpense(c, u, T, ids('draft')), B1_MAKER_OR_ADMIN],
  ['cancelExpense (approved)', (c, u) => w.cancelExpense(c, u, T, ids('approved', { reason: 'Entered twice by mistake.' })), ['owner', 'owner2', 'ba1']],
  ['reopenExpense', (c, u) => w.reopenExpense(c, u, T, ids('rejected')), B1_MAKER_OR_ADMIN],
  ['requestExpenseReceiptUpload', (c, u) => rc.requestUpload(c, u, T, ids('draft', { receipt: { fileName: 'a.pdf', contentType: 'application/pdf', sizeBytes: 5 } })), B1_MAKER_OR_ADMIN],
  ['confirmExpenseReceiptUpload', (c, u) => rc.confirmUpload(c, u, T, ids('draft', { receiptId: 'rc2' })), B1_MAKER_OR_ADMIN],
  ['removeExpenseReceipt', (c, u) => rc.removeReceipt(c, u, T, ids('draft', { receiptId: 'rc1' })), B1_MAKER_OR_ADMIN],
  ['listExpenseReceipts', (c, u) => rc.listReceipts(c, u, T, ids('draft')), B1_VIEW],
  ['getExpenseReport (own branch)', (c, u) => rp.getExpenseReport(c, u, T, { schoolId: 'sA', branchId: 'b1', fromDate: '2026-11-01', toDate: '2026-11-15' }), B1_VIEW],
  ['getExpenseReport (whole school)', (c, u) => rp.getExpenseReport(c, u, T, { schoolId: 'sA', fromDate: '2026-11-01', toDate: '2026-11-15' }), ADMINS],
  ['exportExpenses (own branch)', (c, u) => rp.exportExpenses(c, u, T, { schoolId: 'sA', branchId: 'b1', fromDate: '2026-11-01', toDate: '2026-11-15' }), B1_VIEW],
  ['exportExpenses (whole school)', (c, u) => rp.exportExpenses(c, u, T, { schoolId: 'sA', fromDate: '2026-11-01', toDate: '2026-11-15' }), ADMINS],
];

for (const [name, call, allowed] of CASES) {
  test(`${name}: allowed for ${allowed.join(', ')}; everyone else is refused and changes nothing`, async () => {
    for (const uid of ALL) {
      const w_ = world();
      const out = await call(w_.ctx, uid);
      const denied = out && out.error === 'PERMISSION_DENIED';
      if (allowed.includes(uid)) {
        assert.ok(!denied, `${uid} should be allowed to ${name} (got ${JSON.stringify(out)})`);
      } else {
        assert.ok(denied, `${uid} must be refused ${name} (got ${JSON.stringify(out)})`);
        // refused means nothing was written (reads of the categories are the one lazy write, only for allowed roles)
        assert.equal(JSON.stringify([...w_.db.store.entries()]), w_.before, `${uid}: a refused ${name} wrote something`);
      }
    }
  });

  test(`${name}: refused for everyone when the module is off, the school is suspended, or the caller is deactivated`, async () => {
    const off = world({ 'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata', features: { expenses: false } } });
    const sus = world({ 'schools/sA': { name: 'A', status: 'SUSPENDED', currency: 'INR', timezone: 'Asia/Kolkata' } });
    const closed = world({ 'schools/sA': { name: 'A', status: 'CLOSED', currency: 'INR', timezone: 'Asia/Kolkata' } });
    for (const [label, w_] of [['module off', off], ['suspended', sus], ['closed', closed]]) {
      for (const uid of allowed) assert.equal((await call(w_.ctx, uid)).error, 'PERMISSION_DENIED', `${label}: ${uid}`);
    }
  });
}

test('hostile input never throws: odd ids, wrong types and prototype keys are refused or rejected, never a crash', async () => {
  const w_ = world();
  const junk = [undefined, null, 0, 1, '', '..', 'a/b', '__x__', {}, [], ['b1'], { $set: 1 }, 'constructor', '__proto__', true];
  const fns = [
    (v) => x.getExpenseSettings(w_.ctx, 'owner', T, { schoolId: v }),
    (v) => x.createExpense(w_.ctx, 'owner', T, { schoolId: 'sA', branchId: v, expense: exp }),
    (v) => x.createExpense(w_.ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', expense: v }),
    (v) => x.updateExpense(w_.ctx, 'owner', T, ids(v, { expense: exp })),
    (v) => x.listExpenses(w_.ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', status: v, categoryId: v, cursor: v, limit: v }),
    (v) => w.submitExpense(w_.ctx, 'owner', T, ids(v)),
    (v) => w.decideExpense(w_.ctx, 'owner', T, ids('submitted', { decision: v })),
    (v) => w.payExpense(w_.ctx, 'owner', T, ids('approved', { payment: v })),
    (v) => w.cancelExpense(w_.ctx, 'owner', T, ids('draft', { reason: v })),
    (v) => rc.requestUpload(w_.ctx, 'owner', T, ids('draft', { receipt: v, requestId: v })),
    (v) => rc.confirmUpload(w_.ctx, 'owner', T, ids('draft', { receiptId: v })),
    (v) => rc.removeReceipt(w_.ctx, 'owner', T, ids('draft', { receiptId: v })),
    (v) => rp.getExpenseReport(w_.ctx, 'owner', T, { schoolId: 'sA', fromDate: v, toDate: v, branchId: v }),
    (v) => rp.exportExpenses(w_.ctx, 'owner', T, { schoolId: 'sA', fromDate: '2026-11-01', toDate: '2026-11-15', status: v }),
    (v) => w.getExpenseHistory(w_.ctx, 'owner', T, ids(v)),
    (v) => x.saveExpenseCategory(w_.ctx, 'owner', T, { schoolId: 'sA', name: v, categoryId: v }),
    (v) => x.saveExpenseSettings(w_.ctx, 'owner', T, { schoolId: 'sA', settings: v }),
  ];
  for (const [i, f] of fns.entries()) {
    for (const v of junk) {
      let out;
      try {
        out = await f(v);
      } catch (e) {
        assert.fail(`callable #${i} threw for ${JSON.stringify(v)}: ${e.message}`);
      }
      assert.ok(out && (out.error || out.result || out.settings || out.categories), `callable #${i} returned nothing useful for ${JSON.stringify(v)}`);
    }
  }
});

test('a client cannot plant server-owned fields: status, number, currency, creator, version, counters, history', async () => {
  const w_ = world();
  const r = await x.createExpense(w_.ctx, 'fin', T, {
    schoolId: 'sA', branchId: 'b1', expense: { ...exp, status: 'PAID', number: 'X', currency: 'USD', createdBy: 'owner', version: 99, receiptCount: 9, historyCount: 9, paidBy: 'owner', decidedBy: 'owner', submittedBy: 'owner' },
  });
  const d = w_.db.store.get(key(r.result.id));
  assert.deepEqual([d.status, d.currency, d.createdBy, d.version], ['DRAFT', 'INR', 'fin', 1]);
  assert.notEqual(d.number, 'X');
  for (const f of ['receiptCount', 'historyCount', 'paidBy', 'decidedBy', 'submittedBy']) assert.equal(d[f], undefined, f);
  // and an update cannot either
  const up = await x.updateExpense(w_.ctx, 'fin', T, ids(r.result.id, { expense: { ...exp, status: 'PAID', createdBy: 'owner', version: 50, receiptCount: 9 } }));
  const d2 = w_.db.store.get(key(r.result.id));
  assert.deepEqual([d2.status, d2.createdBy, d2.version, d2.receiptCount], ['DRAFT', 'fin', up.result.version, undefined]);
});

test('an expense of one school is invisible to another school, even by id', async () => {
  const w_ = world({
    'schools/sB/branches/b1': { name: 'B main' },
    'schools/sB/branches/b1/expenses/draft': expenseDoc('DRAFT', { schoolId: 'sB' }),
  });
  const own = await x.getExpense(w_.ctx, 'outsider', T, { schoolId: 'sB', branchId: 'b1', expenseId: 'draft' });
  assert.ok(own.result, 'a school sees its own');
  assert.equal((await x.getExpense(w_.ctx, 'outsider', T, ids('draft'))).error, 'PERMISSION_DENIED', "another school's expense by id");
  assert.equal((await x.getExpense(w_.ctx, 'owner', T, { schoolId: 'sB', branchId: 'b1', expenseId: 'draft' })).error, 'PERMISSION_DENIED');
  const listed = await x.listExpenses(w_.ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1' });
  assert.ok(listed.result.expenses.every((e) => e.id !== 'x' && e.branchId === 'b1'));
});

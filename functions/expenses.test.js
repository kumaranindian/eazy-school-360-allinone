'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const x = require('./expenses');
const features = require('./features');

const now = 'TS';
const seed = (extra = {}) => ({
  'schools/sA': { name: 'A', status: 'ACTIVE' },
  'schools/sB': { name: 'B', status: 'ACTIVE' },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/ba2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  'users/finOff': { schoolId: 'sA', branchId: 'b1', status: 'INACTIVE', role: 'FINANCE' },
  'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/parent': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  'users/otherOwner': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/multi': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'TEACHER', branchRoles: { b1: 'FINANCE' } },
  ...extra,
});
const env = (extra) => {
  const db = fakeDb(seed(extra));
  return { db, ctx: { db, now } };
};
const T = {};

test('the capability table: who can do what', () => {
  assert.deepEqual(x.CAPS.manage, ['SCHOOL_ADMIN']);
  assert.ok(x.CAPS.pay.includes('FINANCE') && !x.CAPS.pay.includes('BRANCH_ADMIN'));
  assert.ok(x.CAPS.approve.includes('BRANCH_ADMIN') && !x.CAPS.approve.includes('FINANCE'));
  for (const cap of ['view', 'create', 'report']) {
    assert.deepEqual([...x.CAPS[cap]].sort(), ['BRANCH_ADMIN', 'FINANCE', 'SCHOOL_ADMIN']);
    assert.ok(!x.CAPS[cap].includes('TEACHER') && !x.CAPS[cap].includes('PARENT'));
  }
});

test('authorize: roles, branch scope, own school, login state, module switch, school state', async () => {
  const { db } = env();
  const a = (uid, branch, cap, school = 'sA') => x.authorize(db, uid, T, school, branch, cap);
  assert.equal((await a('owner', null, 'manage')).role, 'SCHOOL_ADMIN');
  assert.equal((await a('owner', 'b9', 'create')).role, 'SCHOOL_ADMIN', 'a school admin acts in any branch');
  assert.ok(await a('fin', 'b1', 'create'));
  assert.equal(await a('fin', 'b2', 'create'), null, 'finance only in their own branch');
  assert.equal(await a('fin', 'b1', 'manage'), null);
  assert.ok(await a('fin', 'b1', 'pay'));
  assert.equal(await a('ba1', 'b1', 'pay'), null, 'a branch admin cannot pay');
  assert.ok(await a('ba1', 'b1', 'approve'));
  assert.equal(await a('ba1', 'b2', 'approve'), null);
  assert.equal(await a('teacher', 'b1', 'view'), null);
  assert.equal(await a('parent', null, 'view'), null);
  assert.equal(await a('finOff', 'b1', 'view'), null, 'a deactivated user');
  assert.equal(await a('otherOwner', null, 'view'), null, "another school's admin");
  assert.equal(await a('owner', null, 'view', 'sB'), null, 'a school id that is not the caller\'s');
  assert.equal((await a('multi', 'b1', 'create')).role, 'FINANCE', 'a per-branch role counts in that branch');
  assert.equal(await a('multi', 'b2', 'create'), null, 'the home role there is a teacher');
  assert.equal(await a('ghost', null, 'view'), null);
  for (const bad of ['../x', 'a/b', '', null, 5, '__x__']) assert.equal(await x.authorize(db, 'owner', T, bad, null, 'view'), null);
  assert.equal(await x.authorize(db, 'owner', T, 'sA', '../b', 'view'), null);
  assert.equal(await x.authorize(db, 'owner', T, 'sA', null, 'constructor'), null, 'an unknown capability');
  // module switched off
  const off = env({ 'schools/sA': { name: 'A', status: 'ACTIVE', features: { expenses: false } } });
  assert.equal(await x.authorize(off.db, 'owner', T, 'sA', null, 'view'), null);
  // school suspended
  const sus = env({ 'schools/sA': { name: 'A', status: 'SUSPENDED' } });
  assert.equal(await x.authorize(sus.db, 'owner', T, 'sA', null, 'view'), null);
});

test('the module is in the feature catalogue, on by default, with no dependencies', () => {
  assert.ok(features.CATALOGUE.some((f) => f.key === 'expenses' && f.dependsOn.length === 0));
  assert.equal(features.usable({}, 'expenses'), true);
  assert.equal(features.usable({ expenses: false }, 'expenses'), false);
});

test('settings default to approval required, no self approval, school admin approves', async () => {
  const { ctx } = env();
  const r = await x.getExpenseSettings(ctx, 'fin', T, { schoolId: 'sA' });
  assert.deepEqual(r.settings, { approvalRequired: true, allowSelfApproval: false, approverRoles: ['SCHOOL_ADMIN'], receiptRequiredOverMinor: null, version: 0 });
  assert.equal(r.canManage, false);
  assert.equal((await x.getExpenseSettings(ctx, 'owner', T, { schoolId: 'sA' })).canManage, true);
  assert.equal((await x.getExpenseSettings(ctx, 'teacher', T, { schoolId: 'sA' })).error, 'PERMISSION_DENIED');
});

test('only a school admin saves settings; validation; versions; the stored record is exactly the allowed fields', async () => {
  const { ctx, db } = env();
  const save = (uid, settings, extra = {}) => x.saveExpenseSettings(ctx, uid, T, { schoolId: 'sA', settings, ...extra });
  assert.equal((await save('fin', {})).error, 'PERMISSION_DENIED');
  assert.equal((await save('ba1', {})).error, 'PERMISSION_DENIED');
  assert.equal((await save('owner', { approvalRequired: 'yes' })).error, 'INVALID_ARGUMENT');
  assert.equal((await save('owner', { approverRoles: [] })).error, 'INVALID_ARGUMENT');
  assert.equal((await save('owner', { approverRoles: ['FINANCE'] })).error, 'INVALID_ARGUMENT', 'finance cannot be an approver');
  assert.equal((await save('owner', { receiptRequiredOverMinor: -1 })).error, 'INVALID_ARGUMENT');
  assert.equal((await save('owner', { receiptRequiredOverMinor: 1.5 })).error, 'INVALID_ARGUMENT');
  const ok = await save('owner', { approvalRequired: false, approverRoles: ['SCHOOL_ADMIN', 'BRANCH_ADMIN', 'BRANCH_ADMIN'], receiptRequiredOverMinor: 50000, evil: { $set: 1 } });
  assert.equal(ok.result.version, 1);
  const stored = db.store.get('schools/sA/expenseSettings/config');
  assert.deepEqual(Object.keys(stored).sort(), ['allowSelfApproval', 'approvalRequired', 'approverRoles', 'receiptRequiredOverMinor', 'schoolId', 'updatedAt', 'updatedBy', 'version']);
  assert.deepEqual(stored.approverRoles, ['BRANCH_ADMIN', 'SCHOOL_ADMIN']);
  assert.equal((await save('owner', {}, { baseVersion: 0 })).error, 'ABORTED', 'a stale version is refused');
  assert.equal((await save('owner', {}, { baseVersion: 1 })).result.version, 2);
  // the read reflects what was saved
  const got = await x.getExpenseSettings(ctx, 'ba1', T, { schoolId: 'sA' });
  assert.equal(got.settings.version, 2);
  // never writes into another school
  assert.equal(db.store.has('schools/sB/expenseSettings/config'), false);
});

test('categories are seeded once, listed to every expense role, and the built-in Salaries is a system category', async () => {
  const { ctx, db } = env();
  const r = await x.listExpenseCategories(ctx, 'fin', T, { schoolId: 'sA' });
  assert.equal(r.categories.length, x.DEFAULT_CATEGORIES.length);
  assert.equal(r.categories[0].key, 'SALARIES');
  assert.equal(r.categories[0].system, true);
  assert.ok(db.store.has('schools/sA/expenseCategories/cat_salaries'));
  await x.listExpenseCategories(ctx, 'owner', T, { schoolId: 'sA' });
  assert.equal([...db.store.keys()].filter((k) => k.startsWith('schools/sA/expenseCategories/')).length, x.DEFAULT_CATEGORIES.length, 'seeding twice does not duplicate');
  assert.equal((await x.listExpenseCategories(ctx, 'teacher', T, { schoolId: 'sA' })).error, 'PERMISSION_DENIED');
  assert.equal((await x.listExpenseCategories(ctx, 'otherOwner', T, { schoolId: 'sA' })).error, 'PERMISSION_DENIED');
  assert.equal(db.store.has('schools/sB/expenseCategories/cat_salaries'), false);
});

test('adding, renaming and switching off categories: school admin only; unique names; system ones are protected', async () => {
  const { ctx } = env();
  const save = (uid, d) => x.saveExpenseCategory(ctx, uid, T, { schoolId: 'sA', ...d });
  assert.equal((await save('fin', { name: 'Garden' })).error, 'PERMISSION_DENIED');
  assert.equal((await save('owner', { name: 'G' })).error, 'INVALID_ARGUMENT');
  assert.equal((await save('owner', { name: 'x'.repeat(61) })).error, 'INVALID_ARGUMENT');
  const added = await save('owner', { name: 'Garden' });
  const id = added.result.id;
  assert.ok(id);
  assert.equal((await save('owner', { name: '  garden ' })).error, 'ALREADY_EXISTS', 'names are unique ignoring case and spacing');
  assert.equal((await save('owner', { name: 'Utilities (electricity, water, internet)' })).error, 'ALREADY_EXISTS', 'also against the seeded ones');
  assert.equal((await save('owner', { categoryId: id, name: 'Gardening' })).result.id, id);
  assert.equal((await save('owner', { categoryId: id, name: 'Gardening', active: false })).result.id, id);
  const visible = (await x.listExpenseCategories(ctx, 'fin', T, { schoolId: 'sA', includeInactive: true })).categories;
  assert.ok(!visible.some((c) => c.id === id), 'a non-manager never sees switched-off categories, even when asking');
  const adminView = (await x.listExpenseCategories(ctx, 'owner', T, { schoolId: 'sA', includeInactive: true })).categories;
  assert.equal(adminView.find((c) => c.id === id).active, false);
  assert.equal((await save('owner', { categoryId: 'cat_salaries', name: 'Pay' })).error, 'FAILED_PRECONDITION');
  assert.equal((await save('owner', { categoryId: 'cat_salaries', name: 'Salaries', active: false })).error, 'FAILED_PRECONDITION');
  assert.equal((await save('owner', { categoryId: 'nope', name: 'Zed' })).error, 'NOT_FOUND');
  assert.equal((await save('owner', { categoryId: '../x', name: 'Zed' })).error, 'INVALID_ARGUMENT');
  assert.equal((await save('owner', { name: 'Zed', active: 'no' })).error, 'INVALID_ARGUMENT');
});

test('the callables are wired in index.js', () => {
  const m = require('./index.js');
  for (const n of ['getExpenseSettings', 'saveExpenseSettings', 'listExpenseCategories', 'saveExpenseCategory']) assert.ok(m[n], n);
});

// ---- phase E2: create, edit a draft, list, read ---------------------------------------------------

const NOW = new Date('2026-11-15T10:00:00Z');
const e2 = (extra = {}) => {
  const db = fakeDb(seed({
    'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
    'schools/sA/branches/b1': { name: 'Main' },
    'schools/sA/branches/b2': { name: 'Second' },
    'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN', displayName: 'Owner One' },
    ...extra,
  }));
  return { db, ctx: { db, now, wall: () => NOW, nowDate: () => NOW } };
};
const exp = (o = {}) => ({ categoryId: 'cat_other', amountMinor: 125000, expenseDate: '2026-11-10', payee: 'Raj Hardware', description: 'Door lock', ...o });
const create = async (ctx, uid, o = {}, extra = {}) => {
  await x.listExpenseCategories(ctx, 'owner', T, { schoolId: 'sA' }); // seeds the categories
  return x.createExpense(ctx, uid, T, { schoolId: 'sA', branchId: 'b1', expense: exp(o), ...extra });
};

test('validateExpense: every field, in the school\'s own today', () => {
  const v = (o) => x.validateExpense(exp(o), { today: '2026-11-15' });
  assert.ok(v({}).value);
  assert.deepEqual(v({ payee: undefined, description: undefined }).value.payee, '');
  for (const bad of [{ amountMinor: 0 }, { amountMinor: -5 }, { amountMinor: 1.5 }, { amountMinor: '100' }, { amountMinor: 1e13 }, { amountMinor: NaN }]) assert.ok(v(bad).errors.amountMinor, JSON.stringify(bad));
  assert.ok(v({ expenseDate: '2026-11-16' }).errors.expenseDate, 'tomorrow');
  assert.ok(v({ expenseDate: '2021-11-14' }).errors.expenseDate, 'over 5 years');
  assert.ok(v({ expenseDate: '2026-02-30' }).errors.expenseDate, 'not a real date');
  assert.ok(v({ expenseDate: '10/11/2026' }).errors.expenseDate);
  assert.ok(v({ categoryId: '../x' }).errors.categoryId);
  assert.ok(v({ payee: 'x'.repeat(121) }).errors.payee);
  assert.ok(v({ description: 'x'.repeat(501) }).errors.description);
  assert.ok(v({ paymentMode: 'BITCOIN' }).errors.paymentMode);
  assert.equal(v({ paymentMode: 'UPI' }).value.paymentMode, 'UPI');
  assert.ok(v({ paymentReference: 'x'.repeat(61) }).errors.paymentReference);
  assert.equal(x.validateExpense(exp({ expenseDate: '2026-11-15' }), { today: '2026-11-15' }).value.expenseDate, '2026-11-15', 'today is allowed');
});

test('the date limit uses the school zone, not the server clock', () => {
  assert.equal(x.civilToday(new Date('2026-11-15T20:00:00Z'), 'Asia/Kolkata'), '2026-11-16');
  assert.equal(x.civilToday(new Date('2026-11-15T20:00:00Z'), 'America/New_York'), '2026-11-15');
});

test('create: a numbered DRAFT in the school currency, with the category name captured and the currency locked', async () => {
  const { ctx, db } = e2();
  const r = await create(ctx, 'fin');
  assert.ok(r.result.id);
  const d = db.store.get(`schools/sA/branches/b1/expenses/${r.result.id}`);
  assert.equal(d.status, 'DRAFT');
  assert.equal(d.number, 'EXP-2026-00001');
  assert.equal(d.currency, 'INR');
  assert.equal(d.categoryName, 'Other');
  assert.equal(d.createdBy, 'fin');
  assert.equal(d.version, 1);
  assert.equal(d.source, 'MANUAL');
  assert.equal(db.store.get('schools/sA').currencyLocked, true);
  assert.equal((await create(ctx, 'fin')).result.id !== r.result.id, true);
  assert.equal([...db.store.values()].filter((v) => v.number === 'EXP-2026-00002').length, 1, 'numbers are sequential per branch and year');
  assert.equal(db.store.get('schools/sA/branches/b1/expenseSequences/EXP-2026').next, 2);
});

test('create: who may, where, and what is refused', async () => {
  const { ctx, db } = e2();
  assert.equal((await create(ctx, 'teacher')).error, 'PERMISSION_DENIED');
  assert.equal((await create(ctx, 'parent')).error, 'PERMISSION_DENIED');
  assert.equal((await x.createExpense(ctx, 'fin', T, { schoolId: 'sA', branchId: 'b2', expense: exp() })).error, 'PERMISSION_DENIED', 'finance in another branch');
  assert.ok((await x.createExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b2', expense: exp() })).result.id, 'a school admin in any branch');
  assert.equal((await x.createExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'ghost', expense: exp() })).error, 'NOT_FOUND');
  assert.equal((await x.createExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: '../x', expense: exp() })).error, 'PERMISSION_DENIED');
  assert.equal((await x.createExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', expense: exp({ amountMinor: -1 }) })).error, 'INVALID_ARGUMENT');
  assert.equal((await x.createExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', expense: exp({ categoryId: 'nope' }) })).error, 'INVALID_ARGUMENT');
  await x.saveExpenseCategory(ctx, 'owner', T, { schoolId: 'sA', categoryId: 'cat_other', name: 'Other', active: false });
  assert.equal((await x.createExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', expense: exp() })).error, 'INVALID_ARGUMENT', 'a switched-off category');
  assert.equal((await x.createExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', expense: exp(), clientRequestId: 'short' })).error, 'INVALID_ARGUMENT');
  // a client cannot choose the status, number, currency or creator
  const sneaky = await x.createExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b2', expense: { ...exp({ categoryId: 'cat_utilities' }), status: 'PAID', number: 'X', currency: 'USD', createdBy: 'someone', version: 99 } });
  const d = db.store.get(`schools/sA/branches/b2/expenses/${sneaky.result.id}`);
  assert.deepEqual([d.status, d.currency, d.createdBy, d.version], ['DRAFT', 'INR', 'owner', 1]);
  assert.notEqual(d.number, 'X');
});

test('create is idempotent per clientRequestId and person; nothing is created in a switched-off module', async () => {
  const { ctx, db } = e2();
  const a = await create(ctx, 'fin', {}, { clientRequestId: 'req-0001-abcd' });
  const b = await create(ctx, 'fin', {}, { clientRequestId: 'req-0001-abcd' });
  assert.equal(b.result.id, a.result.id);
  assert.equal(b.result.duplicate, true);
  assert.equal([...db.store.keys()].filter((k) => k.includes('/expenses/')).length, 1);
  assert.equal(db.store.get('schools/sA/branches/b1/expenseSequences/EXP-2026').next, 1, 'the number is not burned by a retry');
  const c = await create(ctx, 'ba1', {}, { clientRequestId: 'req-0001-abcd' });
  assert.notEqual(c.result.id, a.result.id, 'another person with the same key is a different request');
  const off = e2({ 'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'UTC', features: { expenses: false } } });
  assert.equal((await create(off.ctx, 'owner')).error, 'PERMISSION_DENIED');
});

test('edit a draft: the creator or an admin; not another finance user; not after DRAFT; version checked', async () => {
  const { ctx, db } = e2({ 'users/fin2': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' } });
  const id = (await create(ctx, 'fin')).result.id;
  const upd = (uid, o = {}, extra = {}) => x.updateExpense(ctx, uid, T, { schoolId: 'sA', branchId: 'b1', expenseId: id, expense: exp(o), ...extra });
  assert.equal((await upd('fin2', { amountMinor: 5 })).error, 'PERMISSION_DENIED', "another finance user cannot edit someone else's draft");
  assert.equal((await upd('teacher')).error, 'PERMISSION_DENIED');
  const ok = await upd('fin', { amountMinor: 99900, categoryId: 'cat_utilities' }, { baseVersion: 1 });
  assert.equal(ok.result.version, 2);
  const d = db.store.get(`schools/sA/branches/b1/expenses/${id}`);
  assert.equal(d.amountMinor, 99900);
  assert.equal(d.categoryName, 'Utilities (electricity, water, internet)');
  assert.equal(d.number, 'EXP-2026-00001', 'the number never changes');
  assert.equal(d.createdBy, 'fin');
  assert.equal(d.updatedBy, 'fin');
  assert.equal((await upd('fin', {}, { baseVersion: 1 })).error, 'ABORTED');
  assert.equal((await upd('ba1')).result.version, 3, 'a branch admin may edit a draft');
  assert.equal((await upd('owner')).result.version, 4);
  assert.equal((await upd('fin', { amountMinor: 0 })).error, 'INVALID_ARGUMENT');
  assert.equal((await x.updateExpense(ctx, 'fin', T, { schoolId: 'sA', branchId: 'b1', expenseId: 'ghost', expense: exp() })).error, 'NOT_FOUND');
  db.store.set(`schools/sA/branches/b1/expenses/${id}`, { ...db.store.get(`schools/sA/branches/b1/expenses/${id}`), status: 'SUBMITTED' });
  assert.equal((await upd('owner')).error, 'FAILED_PRECONDITION', 'only a draft can be edited');
  assert.equal((await x.updateExpense(ctx, 'ba2', T, { schoolId: 'sA', branchId: 'b1', expenseId: id, expense: exp() })).error, 'PERMISSION_DENIED', 'a branch admin of another branch');
});

test('list: newest first, filters, paging, branch scope', async () => {
  const { ctx, db } = e2();
  const dates = ['2026-11-01', '2026-11-05', '2026-11-05', '2026-11-09', '2026-11-12'];
  const ids = [];
  for (const [n, expenseDate] of dates.entries()) ids.push((await create(ctx, 'fin', { expenseDate, categoryId: n % 2 ? 'cat_utilities' : 'cat_other' })).result.id);
  db.store.set(`schools/sA/branches/b1/expenses/${ids[0]}`, { ...db.store.get(`schools/sA/branches/b1/expenses/${ids[0]}`), status: 'PAID' });
  const list = (uid, o = {}) => x.listExpenses(ctx, uid, T, { schoolId: 'sA', branchId: 'b1', ...o });
  const all = (await list('fin')).result.expenses;
  assert.deepEqual(all.map((e) => e.expenseDate), ['2026-11-12', '2026-11-09', '2026-11-05', '2026-11-05', '2026-11-01']);
  assert.deepEqual((await list('fin', { status: 'PAID' })).result.expenses.map((e) => e.id), [ids[0]]);
  assert.equal((await list('fin', { categoryId: 'cat_utilities' })).result.expenses.length, 2);
  assert.equal((await list('fin', { status: 'DRAFT', categoryId: 'cat_utilities' })).result.expenses.length, 2);
  assert.deepEqual((await list('fin', { fromDate: '2026-11-05', toDate: '2026-11-09' })).result.expenses.map((e) => e.expenseDate), ['2026-11-09', '2026-11-05', '2026-11-05']);
  const p1 = (await list('fin', { limit: 2 })).result;
  assert.equal(p1.expenses.length, 2);
  assert.ok(p1.nextCursor);
  const p2 = (await list('fin', { limit: 2, cursor: p1.nextCursor })).result;
  const p3 = (await list('fin', { limit: 2, cursor: p2.nextCursor })).result;
  assert.deepEqual([...p1.expenses, ...p2.expenses, ...p3.expenses].map((e) => e.id), all.map((e) => e.id), 'paging covers every row once, in order');
  assert.equal(p3.nextCursor, null);
  assert.equal((await list('teacher')).error, 'PERMISSION_DENIED');
  assert.equal((await x.listExpenses(ctx, 'fin', T, { schoolId: 'sA', branchId: 'b2' })).error, 'PERMISSION_DENIED', "finance cannot read another branch's expenses");
  assert.equal((await x.listExpenses(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b2' })).result.expenses.length, 0, 'branches are separate');
  for (const bad of [{ status: 'NOPE' }, { categoryId: '../x' }, { fromDate: 'x' }, { cursor: { id: '../x' } }, { cursor: { id: 'ghost' } }]) assert.equal((await list('fin', bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  assert.equal((await list('fin', { limit: 9999 })).result.expenses.length, 5, 'the page size is capped, not an error');
  assert.ok(!('createdAt' in all[0]) && !('schoolId' in all[0]), 'the view is a fixed list of fields');
});

test('get: one expense, same scope as the list', async () => {
  const { ctx } = e2();
  const id = (await create(ctx, 'fin')).result.id;
  const g = (uid, o = {}) => x.getExpense(ctx, uid, T, { schoolId: 'sA', branchId: 'b1', expenseId: id, ...o });
  const r = await g('ba1');
  assert.equal(r.result.expense.number, 'EXP-2026-00001');
  assert.equal(r.result.expense.createdByName, null);
  assert.equal((await g('teacher')).error, 'PERMISSION_DENIED');
  assert.equal((await g('ba2')).error, 'PERMISSION_DENIED');
  assert.equal((await g('owner', { expenseId: 'ghost' })).error, 'NOT_FOUND');
  assert.equal((await g('owner', { expenseId: '../x' })).error, 'PERMISSION_DENIED');
  assert.equal((await create(ctx, 'owner')).result.id !== undefined, true);
  assert.equal((await x.getExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', expenseId: (await create(ctx, 'owner')).result.id })).result.expense.createdByName, 'Owner One');
});

test('the E2 callables are wired', () => {
  const m = require('./index.js');
  for (const n of ['createExpense', 'updateExpense', 'getExpense', 'listExpenses']) assert.ok(m[n], n);
});

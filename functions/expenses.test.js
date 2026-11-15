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

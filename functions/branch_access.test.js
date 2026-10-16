'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { fakeDb } = require('./test_support');
const { setBranchAccess, revokeIfStaffInactive } = require('./branch_access');

const S = 'schools/s1';
const seed = () => ({
  'schools/s1': { name: 'S' },
  [`${S}/branches/north`]: { name: 'N' },
  [`${S}/branches/south`]: { name: 'S' },
  'users/admin': { schoolId: 's1', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
  'users/branchadmin': { schoolId: 's1', role: 'BRANCH_ADMIN', branchId: 'south', status: 'ACTIVE' },
  'users/t1': { schoolId: 's1', role: 'TEACHER', branchId: 'north', status: 'ACTIVE' },
  'users/p1': { schoolId: 's1', role: 'PARENT', branchId: 'north', status: 'ACTIVE' },
  'users/other': { schoolId: 's2', role: 'TEACHER', branchId: 'north', status: 'ACTIVE' },
  [`${S}/branches/north/staff/st-n`]: { userId: 't1', status: 'ACTIVE' },
  [`${S}/branches/south/staff/st-s`]: { userId: 't1', status: 'ACTIVE' },
});
const run = (db, data, uid = 'admin') => setBranchAccess({ db, now: 'NOW' }, uid, { schoolId: 's1', ...data }, {});

test('a school admin grants a second-branch role; it is audited', async () => {
  const db = fakeDb(seed());
  const out = await run(db, { branchId: 'south', uid: 't1', role: 'FINANCE' });
  assert.deepEqual(out.branchRoles, { south: 'FINANCE' });
  assert.deepEqual((await db.collection('users').doc('t1').get()).data().branchRoles, { south: 'FINANCE' });
  const audit = [...db.store.entries()].filter(([k]) => k.includes('branchAccessAudit'));
  assert.equal(audit.length, 1);
  assert.deepEqual({ ...audit[0][1], at: undefined }, { schoolId: 's1', uid: 't1', branchId: 'south', from: null, to: 'FINANCE', by: 'admin', at: undefined });
});

test('change and revoke; repeating the same change writes nothing', async () => {
  const db = fakeDb(seed());
  await run(db, { branchId: 'south', uid: 't1', role: 'TEACHER' });
  assert.equal((await run(db, { branchId: 'south', uid: 't1', role: 'TEACHER' })).unchanged, true);
  await run(db, { branchId: 'south', uid: 't1', role: 'BRANCH_ADMIN' });
  assert.deepEqual((await run(db, { branchId: 'south', uid: 't1', role: null })).branchRoles, {});
  assert.equal([...db.store.keys()].filter((k) => k.includes('branchAccessAudit')).length, 3);
});

test('only an ACTIVE school admin of the school may change access', async () => {
  const db = fakeDb(seed());
  const d = { branchId: 'south', uid: 't1', role: 'TEACHER' };
  assert.equal((await run(db, d, 'branchadmin')).error, 'PERMISSION_DENIED');
  assert.equal((await run(db, d, 't1')).error, 'PERMISSION_DENIED');
  assert.equal((await run(db, d, 'nobody')).error, 'PERMISSION_DENIED');
  db.store.set('users/admin', { schoolId: 's1', role: 'SCHOOL_ADMIN', status: 'DISABLED' });
  assert.equal((await run(db, d)).error, 'PERMISSION_DENIED');
});

test('validation: roles, eligible users, home branch, other schools, branch must exist, staff record needed', async () => {
  const db = fakeDb(seed());
  assert.equal((await run(db, { branchId: 'south', uid: 't1', role: 'SCHOOL_ADMIN' })).error, 'INVALID_ARGUMENT');
  assert.equal((await run(db, { branchId: 'south', uid: 't1', role: 'PARENT' })).error, 'INVALID_ARGUMENT');
  assert.equal((await run(db, { branchId: 'south', uid: 't1' })).error, 'INVALID_ARGUMENT');
  assert.equal((await run(db, { branchId: 'south', uid: 'p1', role: 'TEACHER' })).error, 'ROLE_NOT_ELIGIBLE');
  assert.equal((await run(db, { branchId: 'south', uid: 'admin', role: 'TEACHER' })).error, 'ROLE_NOT_ELIGIBLE');
  assert.equal((await run(db, { branchId: 'north', uid: 't1', role: 'TEACHER' })).error, 'HOME_BRANCH');
  assert.equal((await run(db, { branchId: 'south', uid: 'other', role: 'TEACHER' })).error, 'NOT_FOUND');
  assert.equal((await run(db, { branchId: 'nowhere', uid: 't1', role: 'TEACHER' })).error, 'NOT_FOUND');
  db.store.set(`${S}/branches/south/staff/st-s`, { userId: 't1', status: 'INACTIVE' });
  assert.equal((await run(db, { branchId: 'south', uid: 't1', role: 'TEACHER' })).error, 'NO_STAFF_RECORD');
});

test('the role is removed when the staff record behind it stops being ACTIVE', async () => {
  const db = fakeDb(seed());
  await run(db, { branchId: 'south', uid: 't1', role: 'TEACHER' });
  const ctx = { db, now: 'NOW' };
  const base = { schoolId: 's1', branchId: 'south' };
  // still active: nothing happens
  assert.equal((await revokeIfStaffInactive(ctx, { ...base, before: { userId: 't1', status: 'ACTIVE' }, after: { userId: 't1', status: 'ACTIVE' } })).changed, false);
  // deactivated
  assert.equal((await revokeIfStaffInactive(ctx, { ...base, before: { userId: 't1', status: 'ACTIVE' }, after: { userId: 't1', status: 'INACTIVE' } })).changed, true);
  assert.deepEqual((await db.collection('users').doc('t1').get()).data().branchRoles, {});
  // idempotent
  assert.equal((await revokeIfStaffInactive(ctx, { ...base, before: { userId: 't1', status: 'ACTIVE' }, after: null })).changed, false);
});

test('a home-branch staff record going inactive never touches branchRoles', async () => {
  const db = fakeDb(seed());
  await run(db, { branchId: 'south', uid: 't1', role: 'TEACHER' });
  const out = await revokeIfStaffInactive({ db, now: 'NOW' }, { schoolId: 's1', branchId: 'north', before: { userId: 't1', status: 'ACTIVE' }, after: { userId: 't1', status: 'INACTIVE' } });
  assert.equal(out.changed, false);
  assert.deepEqual((await db.collection('users').doc('t1').get()).data().branchRoles, { south: 'TEACHER' });
});

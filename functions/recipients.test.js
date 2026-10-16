'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { fakeDb } = require('./test_support');
const { broadcastRecipients, targetedRecipients } = require('./recipients');

const user = (o) => ({ schoolId: 's1', status: 'ACTIVE', ...o });
const seed = () => ({
  'users/admin': user({ role: 'SCHOOL_ADMIN' }),
  'users/ba-n': user({ role: 'BRANCH_ADMIN', branchId: 'north' }),
  'users/ba-s': user({ role: 'BRANCH_ADMIN', branchId: 'south' }),
  'users/t-n': user({ role: 'TEACHER', branchId: 'north' }),
  'users/t-s': user({ role: 'TEACHER', branchId: 'south' }),
  // home north, also FINANCE in south
  'users/multi': user({ role: 'TEACHER', branchId: 'north', branchRoles: { south: 'FINANCE' } }),
  // home north teacher, also BRANCH_ADMIN in south
  'users/multi-admin': user({ role: 'TEACHER', branchId: 'north', branchRoles: { south: 'BRANCH_ADMIN' } }),
  'users/off': user({ role: 'TEACHER', branchId: 'north', status: 'DISABLED', branchRoles: { south: 'TEACHER' } }),
  'users/other': { schoolId: 's2', status: 'ACTIVE', role: 'TEACHER', branchId: 'south', branchRoles: { south: 'TEACHER' } },
  'schools/s1/branches/south/staff/st-m': { userId: 'multi', status: 'ACTIVE' },
  'schools/s1/branches/south/teacherAssignments/a1': { status: 'ACTIVE', classId: 'c1', sectionId: 'a', teacherStaffId: 'st-m' },
});

test('a branch-wide notice reaches staff who work there via a per-branch role', async () => {
  const db = fakeDb(seed());
  const south = await broadcastRecipients(db, { schoolId: 's1', branchId: 'south', audienceKind: 'STAFF' });
  assert.deepEqual([...south].sort(), ['admin', 'ba-s', 'multi', 'multi-admin', 't-s']);
  const north = await broadcastRecipients(db, { schoolId: 's1', branchId: 'north', audienceKind: 'STAFF' });
  // multi/multi-admin are home-north teachers; the disabled account never receives
  assert.deepEqual([...north].sort(), ['admin', 'ba-n', 'multi', 'multi-admin', 't-n']);
});

test('leave reviewers include a branch admin through a per-branch role', async () => {
  const db = fakeDb(seed());
  const r = await targetedRecipients(db, { audience: 'REVIEWERS', schoolId: 's1', branchId: 'south' });
  assert.deepEqual([...r].sort(), ['admin', 'ba-s', 'multi-admin']);
});

test('a class notice reaches a teacher assigned in their second branch only with a TEACHER role there', async () => {
  const db = fakeDb(seed());
  // multi is FINANCE in south: not a teacher there, so a class notice skips them
  let r = await broadcastRecipients(db, { schoolId: 's1', branchId: 'south', audienceKind: 'CLASS', classId: 'c1' });
  assert.ok(!r.has('multi'));
  db.store.set('users/multi', user({ role: 'TEACHER', branchId: 'north', branchRoles: { south: 'TEACHER' } }));
  r = await broadcastRecipients(db, { schoolId: 's1', branchId: 'south', audienceKind: 'CLASS', classId: 'c1' });
  assert.ok(r.has('multi'));
});

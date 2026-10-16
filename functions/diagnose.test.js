'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const { diagnoseAccess } = require('./diagnose');

const B = 'schools/s1/branches/b1';
const TOKEN = { firebase: { sign_in_provider: 'password' } };
const base = (extra = {}) => ({
  'users/admin': { schoolId: 's1', branchId: 'b1', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
  ...extra,
});
const run = (seed, uid) =>
  diagnoseAccess({ db: fakeDb(base(seed)) }, 'admin', TOKEN, { schoolId: 's1', branchId: 'b1', uid });
const failing = (r) => r.result.checks.filter((c) => !c.ok).map((c) => c.id);

test('only admins of the school may diagnose; other schools are invisible', async () => {
  const db = fakeDb(base({ 'users/t': { schoolId: 's2', role: 'TEACHER', status: 'ACTIVE' }, 'users/x': { schoolId: 's1', role: 'TEACHER', status: 'ACTIVE' } }));
  assert.strictEqual((await diagnoseAccess({ db }, 'x', TOKEN, { schoolId: 's1', branchId: 'b1', uid: 'x' })).error, 'PERMISSION_DENIED');
  assert.strictEqual((await diagnoseAccess({ db }, 'admin', TOKEN, { schoolId: 's1', branchId: 'b1', uid: 't' })).error, 'PERMISSION_DENIED');
  assert.strictEqual((await diagnoseAccess({ db }, 'admin', TOKEN, { schoolId: 's1' })).error, 'INVALID_ARGUMENT');
});

test('missing profile / bad role / wrong branch / inactive are named', async () => {
  assert.deepStrictEqual(failing(await run({}, 'nobody')), ['PROFILE_EXISTS']);
  const r = await run({ 'users/u': { schoolId: 's1', branchId: 'zz', role: 'teacher', status: 'INVITED' } }, 'u');
  assert.deepStrictEqual(failing(r).sort(), ['BRANCH_MATCH', 'ROLE_VALID', 'STATUS_ACTIVE', 'STAFF_LINK'].sort().filter((x) => x !== 'STAFF_LINK'));
});

test('teacher: healthy when linked, active and assigned', async () => {
  const r = await run({
    'users/t': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE' },
    [`${B}/staff/st1`]: { userId: 't', status: 'ACTIVE', isTeacher: true },
    [`${B}/teacherAssignments/a1`]: { teacherStaffId: 'st1', status: 'ACTIVE', isClassTeacher: true, academicYearId: 'y', classId: 'c', sectionId: 's' },
    [`${B}/assignmentSlots/y__c__s__CLASS_TEACHER`]: { teacherStaffId: 'st1' },
    [`${B}/teacherAccess/t`]: { sectionKeys: ['c__s'] },
  }, 't');
  assert.strictEqual(r.result.healthy, true, JSON.stringify(failing(r)));
});

test('teacher: unlinked staff, no assignments and a broken class-teacher slot are each reported', async () => {
  assert.deepStrictEqual(failing(await run({ 'users/t': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE' } }, 't')), ['STAFF_LINK']);
  const noAssign = await run({
    'users/t': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE' },
    [`${B}/staff/st1`]: { userId: 't', status: 'ACTIVE', isTeacher: true },
  }, 't');
  assert.deepStrictEqual(failing(noAssign), ['ASSIGNMENTS']);
  const noIndex = await run({
    'users/t': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE' },
    [`${B}/staff/st1`]: { userId: 't', status: 'ACTIVE', isTeacher: true },
    [`${B}/teacherAssignments/a1`]: { teacherStaffId: 'st1', status: 'ACTIVE', isClassTeacher: true, academicYearId: 'y', classId: 'c', sectionId: 's' },
    [`${B}/assignmentSlots/y__c__s__CLASS_TEACHER`]: { teacherStaffId: 'st1' },
  }, 't');
  assert.deepStrictEqual(failing(noIndex), ['TEACHER_ACCESS']);
  const slot = await run({
    'users/t': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE' },
    [`${B}/staff/st1`]: { userId: 't', status: 'ACTIVE', isTeacher: true },
    [`${B}/teacherAssignments/a1`]: { teacherStaffId: 'st1', status: 'ACTIVE', isClassTeacher: true, academicYearId: 'y', classId: 'c', sectionId: 's' },
    [`${B}/teacherAccess/t`]: { sectionKeys: ['c__s'] },
  }, 't');
  assert.deepStrictEqual(failing(slot), ['ASSIGNMENT_SLOT']);
});

const parent = (extra = {}) => ({
  'users/p': { schoolId: 's1', branchId: 'b1', role: 'PARENT', status: 'ACTIVE', linkedParentId: 'pr1' },
  [`${B}/parents/pr1`]: { linkedUserId: 'p', status: 'ACTIVE' },
  [`${B}/students/st1`]: { status: 'ACTIVE', currentClassId: 'c1', currentSectionId: 'sa' },
  [`${B}/students/st1/parentLinks/pr1`]: { schoolId: 's1', branchId: 'b1', parentId: 'pr1', studentId: 'st1', status: 'ACTIVE', canAccessPortal: true },
  [`${B}/parentAccess/pr1`]: { classKeys: ['c1'], sectionKeys: ['c1__sa'] },
  ...extra,
});

test('teacher: a subject assignment without its slot is reported too', async () => {
  const r = await run({
    'users/t': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE' },
    [`${B}/staff/st1`]: { userId: 't', status: 'ACTIVE', isTeacher: true },
    [`${B}/teacherAssignments/a1`]: { teacherStaffId: 'st1', status: 'ACTIVE', isClassTeacher: false, subjectId: 'math', academicYearId: 'y', classId: 'c', sectionId: 's' },
    [`${B}/teacherAccess/t`]: { sectionKeys: ['c__s'] },
  }, 't');
  assert.deepStrictEqual(failing(r), ['ASSIGNMENT_SLOT']);
});

test('parent: healthy with link, portal access and a current parentAccess index', async () => {
  const r = await run(parent(), 'p');
  assert.strictEqual(r.result.healthy, true, JSON.stringify(failing(r)));
});

test('parent: each missing prerequisite is named', async () => {
  const noLink = parent();
  delete noLink['users/p'].linkedParentId;
  assert.deepStrictEqual(failing(await run(noLink, 'p')), ['LINKED_PARENT_ID']);
  assert.deepStrictEqual(failing(await run(parent({ [`${B}/students/st1/parentLinks/pr1`]: { schoolId: 's1', branchId: 'b1', parentId: 'pr1', status: 'ACTIVE', canAccessPortal: false } }), 'p')), ['PORTAL_ENABLED']);
  const noIndex = parent();
  delete noIndex[`${B}/parentAccess/pr1`];
  assert.deepStrictEqual(failing(await run(noIndex, 'p')), ['PARENT_ACCESS']);
  assert.deepStrictEqual(failing(await run(parent({ [`${B}/parentAccess/pr1`]: { classKeys: [], sectionKeys: [] } }), 'p')), ['PARENT_ACCESS']);
  assert.deepStrictEqual(failing(await run(parent({ [`${B}/parents/pr1`]: { linkedUserId: 'other', status: 'ACTIVE' } }), 'p')), ['PARENT_BACKLINK']);
});

test('a per-branch role passes the branch check and gets the teacher checks there', async () => {
  const { fakeDb } = require('./test_support');
  const db = fakeDb({
    'users/admin': { schoolId: 's1', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
    'users/m': { schoolId: 's1', role: 'FINANCE', status: 'ACTIVE', branchId: 'b1', branchRoles: { b2: 'TEACHER' } },
    'schools/s1/branches/b2/staff/st1': { userId: 'm', status: 'ACTIVE', isTeacher: true },
  });
  const out = await diagnoseAccess({ db }, 'admin', TOKEN, { schoolId: 's1', branchId: 'b2', uid: 'm' });
  const by = Object.fromEntries(out.result.checks.map((c) => [c.id, c]));
  assert.equal(by.BRANCH_MATCH.ok, true);
  assert.equal(out.result.role, 'TEACHER');
  assert.ok(Object.keys(by).some((k) => k.startsWith('TEACHER') || k.includes('STAFF')));
  // a branch the person has no role in is still reported
  const none = await diagnoseAccess({ db }, 'admin', TOKEN, { schoolId: 's1', branchId: 'b9', uid: 'm' });
  assert.equal(Object.fromEntries(none.result.checks.map((c) => [c.id, c])).BRANCH_MATCH.ok, false);
});

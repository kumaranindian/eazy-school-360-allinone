'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const ta = require('./teacher_access');

const B = 'schools/s1/branches/b1';
const asg = (o) => ({ status: 'ACTIVE', academicYearId: 'y1', ...o });
const seed = (extra = {}) => ({
  [`${B}/staff/st1`]: { userId: 'u1', status: 'ACTIVE', isTeacher: true },
  [`${B}/teacherAssignments/a1`]: asg({ teacherStaffId: 'st1', classId: 'c5', sectionId: 'sa', isClassTeacher: true }),
  [`${B}/teacherAssignments/a2`]: asg({ teacherStaffId: 'st1', classId: 'c5', sectionId: 'sa', subjectId: 'math' }),
  [`${B}/teacherAssignments/a3`]: asg({ teacherStaffId: 'st1', classId: 'c6', sectionId: 'sb', subjectId: 'sci' }),
  [`${B}/teacherAssignments/a4`]: asg({ teacherStaffId: 'st1', classId: 'c7', sectionId: 'sa', status: 'ENDED' }),
  [`${B}/teacherAssignments/a5`]: asg({ teacherStaffId: 'st2', classId: 'c9', sectionId: 'sa' }),
  ...extra,
});
const ctx = (db) => ({ db, now: 'NOW' });

test('sections come from ACTIVE assignments of this teacher only, once each', async () => {
  const db = fakeDb(seed());
  const r = await ta.refreshStaffAccess(ctx(db), 's1', 'b1', 'st1');
  assert.deepStrictEqual(r, { uid: 'u1', sections: 2 });
  const d = db.store.get(`${B}/teacherAccess/u1`);
  assert.deepStrictEqual(d.sectionKeys, ['c5__sa', 'c6__sb']);
  assert.strictEqual(d.userId, 'u1');
  assert.strictEqual(d.staffId, 'st1');
  assert.deepStrictEqual(d.scopes[0], { academicYearId: 'y1', classId: 'c5', sectionId: 'sa' });
});

test('no login link, inactive, or non-teacher staff get no access document', async () => {
  for (const staff of [{ status: 'ACTIVE', isTeacher: true }, { userId: 'u1', status: 'RESIGNED', isTeacher: true }, { userId: 'u1', status: 'ACTIVE', isTeacher: false }]) {
    const db = fakeDb(seed({ [`${B}/staff/st1`]: staff }));
    const r = await ta.refreshStaffAccess(ctx(db), 's1', 'b1', 'st1');
    assert.strictEqual(r.uid, null);
    assert.ok(![...db.store.keys()].some((k) => k.includes('/teacherAccess/')));
  }
});

test('a teacher with no active assignment gets an empty (not missing) document', async () => {
  const db = fakeDb(seed({ [`${B}/teacherAssignments/a1`]: asg({ teacherStaffId: 'st1', classId: 'c5', sectionId: 'sa', status: 'ENDED' }), [`${B}/teacherAssignments/a2`]: asg({ teacherStaffId: 'st1', classId: 'c5', sectionId: 'sa', status: 'ENDED' }), [`${B}/teacherAssignments/a3`]: asg({ teacherStaffId: 'st1', classId: 'c6', sectionId: 'sb', status: 'ENDED' }) }));
  await ta.refreshStaffAccess(ctx(db), 's1', 'b1', 'st1');
  assert.deepStrictEqual(db.store.get(`${B}/teacherAccess/u1`).sectionKeys, []);
});

test('removing a login link removes the old access document, never another teacher\'s', async () => {
  const db = fakeDb(seed({ [`${B}/teacherAccess/u1`]: { staffId: 'st1' }, [`${B}/teacherAccess/u2`]: { staffId: 'stX' } }));
  await ta.removeAccessFor(db, 's1', 'b1', 'u1', 'st1');
  await ta.removeAccessFor(db, 's1', 'b1', 'u2', 'st1'); // belongs to another staff record
  assert.ok(!db.store.has(`${B}/teacherAccess/u1`));
  assert.ok(db.store.has(`${B}/teacherAccess/u2`));
});

test('branch backfill rebuilds every linked teacher', async () => {
  const db = fakeDb(seed({ [`${B}/staff/st2`]: { userId: 'u2', status: 'ACTIVE', isTeacher: true }, [`${B}/staff/st3`]: { status: 'ACTIVE', isTeacher: true } }));
  const r = await ta.refreshBranchAccess(ctx(db), 's1', 'b1');
  assert.deepStrictEqual(r, { teachers: 3, written: 2 });
  assert.deepStrictEqual(db.store.get(`${B}/teacherAccess/u2`).sectionKeys, ['c9__sa']);
});

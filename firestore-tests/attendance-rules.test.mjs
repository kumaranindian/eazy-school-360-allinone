// Firestore security-rules tests for Milestone 5 — Attendance (see
// ../firestore.rules and ../docs/milestone-5-attendance-management.md).
// Own school ids (`att-a-<n>`) and uid prefix (`att-`) so this file can run
// beside the others on the shared emulator without interfering.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, where, writeBatch,
} from 'firebase/firestore';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

let A = 'att-a';
let B = 'att-b';
let counter = 0;
const NORTH = 'north';
const SOUTH = 'south';
const YEAR = 'year-1';
const CLASS5 = 'class-5';
const SEC_A = 'sec-a';
const SEC_B = 'sec-b';
const DATE = '2026-06-10';

const branch = (s, b) => ['schools', s, 'branches', b];
const seed = (fn) => testEnv.withSecurityRulesDisabled(async (c) => fn(c.firestore()));
const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const userDoc = ({ schoolId, branchId = null, role }) => ({
  schoolId, branchId, name: 'T', email: 't@example.com', role, status: 'ACTIVE', ...audit('seed'),
});

function studentAtt({
  schoolId = A, branchId = NORTH, dateKey = DATE, studentId = 'stu-1', sectionId = SEC_A, classId = CLASS5,
  status = 'PRESENT', revision = 1, remarks = null, lastChangeReason = null, uid,
}) {
  return {
    schoolId, branchId, academicYearId: YEAR, dateKey, attendanceDate: new Date(`${dateKey}T00:00:00Z`),
    studentId, academicRecordId: 'rec-1', classId, sectionId, status, remarks, revision, lastChangeReason, ...audit(uid),
  };
}
const attRef = (db, studentId = 'stu-1', dateKey = DATE, b = NORTH, s = A) =>
  doc(db, ...branch(s, b), 'studentAttendance', `${dateKey}_${studentId}`);

const sessionId = ({ dateKey = DATE, sectionId = SEC_A, classId = CLASS5 } = {}) => [dateKey, YEAR, classId, sectionId].join('__');
function sessionDoc({
  schoolId = A, branchId = NORTH, dateKey = DATE, sectionId = SEC_A, classId = CLASS5, status = 'DRAFT', revision = 1,
  counts = {}, uid,
}) {
  return {
    schoolId, branchId, academicYearId: YEAR, classId, sectionId, dateKey, attendanceDate: new Date(`${dateKey}T00:00:00Z`),
    status, enrolled: 3, present: 2, absent: 1, late: 0, halfDay: 0, notMarked: 0, dayKind: 'workingDay', overrideReason: null,
    revision, finalizedAt: status === 'FINALIZED' ? serverTimestamp() : null, finalizedBy: status === 'FINALIZED' ? uid : null,
    ...counts, ...audit(uid),
  };
}
const sessRef = (db, opts = {}, b = NORTH, s = A) => doc(db, ...branch(s, b), 'attendanceSessions', sessionId(opts));

function historyDoc({ uid, revision = 1, studentId = 'stu-1', sectionId = SEC_A, schoolId = A, branchId = NORTH }) {
  return {
    schoolId, branchId, academicYearId: YEAR, classId: CLASS5, sectionId, dateKey: DATE, studentId, revision,
    previousStatus: null, previousRemarks: null, newStatus: 'PRESENT', newRemarks: null, reason: null,
    changedBy: uid, changedAt: serverTimestamp(),
  };
}

async function seedWorld() {
  counter += 1;
  A = `att-a-${counter}`;
  B = `att-b-${counter}`;
  await seed(async (db) => {
    for (const s of [A, B]) {
      await setDoc(doc(db, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      for (const b of s === A ? [NORTH, SOUTH] : [NORTH]) await setDoc(doc(db, ...branch(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'att-admin': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'att-admin-b': { schoolId: B, branchId: NORTH, role: 'SCHOOL_ADMIN' },
      'att-br-north': { schoolId: A, branchId: NORTH, role: 'BRANCH_ADMIN' },
      'att-br-south': { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' },
      'att-teacher-ct': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'att-teacher-other': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'att-finance': { schoolId: A, branchId: NORTH, role: 'FINANCE' },
      'att-parent': { schoolId: A, branchId: NORTH, role: 'PARENT' },
    };
    for (const [uid, u] of Object.entries(users)) await setDoc(doc(db, 'users', uid), userDoc(u));

    const n = branch(A, NORTH);
    const staff = (userId, status = 'ACTIVE') => ({
      schoolId: A, branchId: NORTH, userId, status, isTeacher: true, displayName: 'T', ...audit('seed'),
    });
    await setDoc(doc(db, ...n, 'staff', 'staff-ct'), staff('att-teacher-ct'));
    await setDoc(doc(db, ...n, 'staff', 'staff-other'), staff('att-teacher-other'));
    // teacherAccess (server-written in production): the class teacher is assigned to class5/section A only.
    await setDoc(doc(db, ...n, 'teacherAccess', 'att-teacher-ct'), { schoolId: A, branchId: NORTH, staffId: 'staff-ct', userId: 'att-teacher-ct', sectionKeys: [`${CLASS5}__${SEC_A}`], scopes: [], updatedAt: serverTimestamp() });
    // staff-ct is the class teacher of Class 5-A only.
    await setDoc(doc(db, ...n, 'assignmentSlots', [YEAR, CLASS5, SEC_A, 'CLASS_TEACHER'].join('__')), {
      schoolId: A, branchId: NORTH, assignmentId: 'asg-1', teacherStaffId: 'staff-ct', createdAt: serverTimestamp(), createdBy: 'seed',
    });
    // enrollment history, for the roster query
    for (const [sid, sec] of [['stu-1', SEC_A], ['stu-2', SEC_B]]) {
      await setDoc(doc(db, ...n, 'students', sid, 'academicRecords', `rec-${sid}`), {
        schoolId: A, branchId: NORTH, studentId: sid, academicYearId: YEAR, classId: CLASS5, sectionId: sec, status: 'ACTIVE',
        startDate: new Date('2026-06-01'), endDate: null, ...audit('seed'),
      });
    }
  });
}

// ---------------------------------------------------------------------
// Tenant + branch isolation
// ---------------------------------------------------------------------

test('School isolation: School A admin marks/reads School A attendance; School B admin is denied both', async () => {
  await seedWorld();
  await assertSucceeds(setDoc(attRef(asUser('att-admin')), studentAtt({ uid: 'att-admin' })));
  await assertSucceeds(getDoc(attRef(asUser('att-admin'))));

  const adminB = asUser('att-admin-b');
  await assertFails(getDoc(attRef(adminB)));
  await assertFails(setDoc(attRef(adminB, 'stu-9'), studentAtt({ studentId: 'stu-9', uid: 'att-admin-b' })));
  await assertFails(updateDoc(attRef(adminB), { status: 'ABSENT', revision: 2, updatedAt: serverTimestamp(), updatedBy: 'att-admin-b' }));
  await assertFails(getDocs(query(collection(adminB, ...branch(A, NORTH), 'studentAttendance'), where('academicYearId', '==', YEAR), where('classId', '==', CLASS5), where('sectionId', '==', SEC_A))));
  await assertFails(setDoc(sessRef(adminB), sessionDoc({ uid: 'att-admin-b' })));
  await assertFails(setDoc(doc(adminB, ...branch(A, NORTH), 'staffAttendance', `${DATE}_staff-ct`), { schoolId: A }));
});

test('Branch isolation: North branch admin manages North; South branch admin is denied North', async () => {
  await seedWorld();
  await assertSucceeds(setDoc(attRef(asUser('att-br-north')), studentAtt({ uid: 'att-br-north' })));
  const south = asUser('att-br-south');
  await assertFails(getDoc(attRef(south)));
  await assertFails(setDoc(attRef(south, 'stu-7'), studentAtt({ studentId: 'stu-7', uid: 'att-br-south' })));
  await assertFails(setDoc(sessRef(south), sessionDoc({ uid: 'att-br-south' })));
  // A South admin cannot write a record that merely CLAIMS to be South while living in North's path.
  await assertFails(setDoc(attRef(south, 'stu-8'), studentAtt({ studentId: 'stu-8', branchId: SOUTH, uid: 'att-br-south' })));
  // and can mark their own branch
  await assertSucceeds(setDoc(attRef(south, 'stu-8', DATE, SOUTH), studentAtt({ studentId: 'stu-8', branchId: SOUTH, uid: 'att-br-south' })));
});

// ---------------------------------------------------------------------
// Roles: class-teacher scope, finance, parent
// ---------------------------------------------------------------------

test('Teacher: the CLASS TEACHER of 5-A marks and reads 5-A, but not 5-B; an unassigned teacher marks nothing', async () => {
  await seedWorld();
  const ct = asUser('att-teacher-ct');
  await assertSucceeds(setDoc(attRef(ct), studentAtt({ uid: 'att-teacher-ct' })));
  await assertSucceeds(getDoc(attRef(ct)));
  await assertSucceeds(setDoc(sessRef(ct), sessionDoc({ uid: 'att-teacher-ct' })));
  await assertSucceeds(getDocs(query(collection(ct, ...branch(A, NORTH), 'studentAttendance'),
    where('academicYearId', '==', YEAR), where('classId', '==', CLASS5), where('sectionId', '==', SEC_A), where('dateKey', '==', DATE))));

  // another section of the same class
  await assertFails(setDoc(attRef(ct, 'stu-2'), studentAtt({ studentId: 'stu-2', sectionId: SEC_B, uid: 'att-teacher-ct' })));
  await assertFails(setDoc(sessRef(ct, { sectionId: SEC_B }), sessionDoc({ sectionId: SEC_B, uid: 'att-teacher-ct' })));
  // cannot read a section that is not theirs, nor query the whole branch
  await seed((db) => setDoc(attRef(db, 'stu-2'), studentAtt({ studentId: 'stu-2', sectionId: SEC_B, uid: 'seed' })));
  await assertFails(getDoc(attRef(ct, 'stu-2')));
  await assertFails(getDocs(collection(ct, ...branch(A, NORTH), 'studentAttendance')));

  const other = asUser('att-teacher-other'); // TEACHER role, but not class teacher of anything
  await assertFails(setDoc(attRef(other, 'stu-3'), studentAtt({ studentId: 'stu-3', uid: 'att-teacher-other' })));
  await assertFails(getDoc(attRef(other)));
});

test('A teacher who stops being ACTIVE loses marking rights; a TEACHER role alone grants nothing', async () => {
  await seedWorld();
  await seed((db) => updateDoc(doc(db, ...branch(A, NORTH), 'staff', 'staff-ct'), { status: 'RESIGNED' }));
  await assertFails(setDoc(attRef(asUser('att-teacher-ct')), studentAtt({ uid: 'att-teacher-ct' })));
});

test('Finance and Parent cannot read or write student attendance', async () => {
  await seedWorld();
  await seed((db) => setDoc(attRef(db), studentAtt({ uid: 'seed' })));
  for (const uid of ['att-finance', 'att-parent']) {
    const db = asUser(uid);
    await assertFails(getDoc(attRef(db)));
    await assertFails(setDoc(attRef(db, 'stu-5'), studentAtt({ studentId: 'stu-5', uid })));
    await assertFails(updateDoc(attRef(db), { status: 'ABSENT', revision: 2, updatedAt: serverTimestamp(), updatedBy: uid }));
    await assertFails(getDoc(sessRef(db)));
  }
});

// ---------------------------------------------------------------------
// Record integrity: deterministic id, revision, immutables, validation
// ---------------------------------------------------------------------

test('The document id must be dateKey_studentId — a duplicate under another id is impossible', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  await assertFails(setDoc(doc(admin, ...branch(A, NORTH), 'studentAttendance', 'random-id'), studentAtt({ uid: 'att-admin' })));
  await assertFails(setDoc(attRef(admin, 'stu-1', '2026-06-11'), studentAtt({ uid: 'att-admin' }))); // id date != data date
  await assertSucceeds(setDoc(attRef(admin), studentAtt({ uid: 'att-admin' })));
});

test('A second "create" of the same student+date is rejected (it would be an unversioned overwrite)', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  await assertSucceeds(setDoc(attRef(admin), studentAtt({ uid: 'att-admin' })));
  await assertFails(setDoc(attRef(admin), studentAtt({ status: 'ABSENT', uid: 'att-admin' })));
});

test('Updates must advance the revision by exactly one; stale or skipped revisions are refused', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  await assertSucceeds(setDoc(attRef(admin), studentAtt({ uid: 'att-admin' })));
  const meta = { updatedAt: serverTimestamp(), updatedBy: 'att-admin' };
  await assertFails(updateDoc(attRef(admin), { status: 'ABSENT', revision: 1, ...meta })); // not advanced
  await assertFails(updateDoc(attRef(admin), { status: 'ABSENT', revision: 3, ...meta })); // skipped
  await assertSucceeds(updateDoc(attRef(admin), { status: 'ABSENT', revision: 2, ...meta }));
  await assertFails(updateDoc(attRef(admin), { status: 'LATE', revision: 2, ...meta })); // stale writer
  await assertSucceeds(updateDoc(attRef(admin), { status: 'LATE', revision: 3, ...meta }));
});

test('Student, date, tenant and placement snapshot are immutable; only status/remarks/reason change', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  await assertSucceeds(setDoc(attRef(admin), studentAtt({ uid: 'att-admin' })));
  const next = { revision: 2, updatedAt: serverTimestamp(), updatedBy: 'att-admin' };
  for (const change of [
    { studentId: 'someone-else' }, { dateKey: '2026-06-12' }, { classId: 'class-6' }, { sectionId: SEC_B },
    { academicYearId: 'year-2' }, { schoolId: B }, { branchId: SOUTH }, { createdBy: 'x' }, { academicRecordId: 'rec-2' },
  ]) {
    await assertFails(updateDoc(attRef(admin), { ...change, ...next }));
  }
  await assertFails(updateDoc(attRef(admin), { status: 'ABSENT', updatedBy: 'forged', revision: 2, updatedAt: serverTimestamp() }));
  await assertSucceeds(updateDoc(attRef(admin), { status: 'HALF_DAY', remarks: 'left at noon', ...next }));
});

test('Invalid statuses, oversized remarks, malformed dates and future dates are refused; no leave status exists', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  await assertFails(setDoc(attRef(admin, 'stu-1'), studentAtt({ status: 'LEAVE', uid: 'att-admin' })));
  await assertFails(setDoc(attRef(admin, 'stu-1'), studentAtt({ status: 'present', uid: 'att-admin' })));
  await assertFails(setDoc(attRef(admin, 'stu-1'), studentAtt({ remarks: 'x'.repeat(201), uid: 'att-admin' })));
  await assertFails(setDoc(attRef(admin, 'stu-1', '2026-6-10'), studentAtt({ dateKey: '2026-6-10', uid: 'att-admin' })));
  await assertFails(setDoc(attRef(admin, 'stu-1', '2099-01-01'), studentAtt({ dateKey: '2099-01-01', uid: 'att-admin' })));
  await assertFails(setDoc(attRef(admin), studentAtt({ revision: 5, uid: 'att-admin' }))); // must start at 1
  await assertFails(setDoc(attRef(admin), studentAtt({ uid: 'someone-else' }))); // audit actor must be the caller
  await assertSucceeds(setDoc(attRef(admin), studentAtt({ remarks: 'ok', uid: 'att-admin' })));
});

test('Attendance is never hard-deleted', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  await assertSucceeds(setDoc(attRef(admin), studentAtt({ uid: 'att-admin' })));
  await assertFails(deleteDoc(attRef(admin)));
  await assertSucceeds(setDoc(sessRef(admin), sessionDoc({ uid: 'att-admin' })));
  await assertFails(deleteDoc(sessRef(admin)));
});

// ---------------------------------------------------------------------
// Sessions and finalization
// ---------------------------------------------------------------------

test('Session id must match its fields; counts must be non-negative integers; revision starts at 1', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  await assertFails(setDoc(doc(admin, ...branch(A, NORTH), 'attendanceSessions', 'wrong'), sessionDoc({ uid: 'att-admin' })));
  await assertFails(setDoc(sessRef(admin), sessionDoc({ counts: { present: -1 }, uid: 'att-admin' })));
  await assertFails(setDoc(sessRef(admin), sessionDoc({ counts: { absent: 1.5 }, uid: 'att-admin' })));
  await assertFails(setDoc(sessRef(admin), sessionDoc({ revision: 4, uid: 'att-admin' })));
  await assertSucceeds(setDoc(sessRef(admin), sessionDoc({ uid: 'att-admin' })));
});

test('Finalization locks the register: the class teacher can finalize but then cannot edit or re-open; a manager needs a reason', async () => {
  await seedWorld();
  const ct = asUser('att-teacher-ct');
  const manager = asUser('att-br-north');

  await assertSucceeds(setDoc(attRef(ct), studentAtt({ uid: 'att-teacher-ct' })));
  await assertSucceeds(setDoc(sessRef(ct), sessionDoc({ uid: 'att-teacher-ct' })));

  // the teacher finalizes (DRAFT -> FINALIZED)
  const finalize = {
    status: 'FINALIZED', revision: 2, finalizedAt: serverTimestamp(), finalizedBy: 'att-teacher-ct',
    updatedAt: serverTimestamp(), updatedBy: 'att-teacher-ct',
  };
  await assertSucceeds(updateDoc(sessRef(ct), finalize));

  // now locked for the teacher
  const edit = { status: 'ABSENT', revision: 2, lastChangeReason: 'oops', updatedAt: serverTimestamp(), updatedBy: 'att-teacher-ct' };
  await assertFails(updateDoc(attRef(ct), edit));
  await assertFails(setDoc(attRef(ct, 'stu-4'), studentAtt({ studentId: 'stu-4', uid: 'att-teacher-ct' })));
  await assertFails(updateDoc(sessRef(ct), { status: 'DRAFT', revision: 3, finalizedAt: null, finalizedBy: null, updatedAt: serverTimestamp(), updatedBy: 'att-teacher-ct' }));

  // a manager may correct it — but only with a written reason
  const m = { status: 'ABSENT', revision: 2, updatedAt: serverTimestamp(), updatedBy: 'att-br-north' };
  await assertFails(updateDoc(attRef(manager), m)); // no reason
  await assertFails(updateDoc(attRef(manager), { ...m, lastChangeReason: '' }));
  await assertSucceeds(updateDoc(attRef(manager), { ...m, lastChangeReason: 'Parent confirmed absence' }));
  // adding a student to a finalized register is a correction too
  await assertFails(setDoc(attRef(manager, 'stu-4'), studentAtt({ studentId: 'stu-4', uid: 'att-br-north' })));
  await assertSucceeds(setDoc(attRef(manager, 'stu-4'), studentAtt({ studentId: 'stu-4', lastChangeReason: 'Joined late', uid: 'att-br-north' })));
  // and may re-open the register
  await assertSucceeds(updateDoc(sessRef(manager), { status: 'DRAFT', revision: 3, finalizedAt: null, finalizedBy: null, updatedAt: serverTimestamp(), updatedBy: 'att-br-north' }));
});

test('Finalizing must be stamped by the caller at server time (no forged finalizer)', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  await assertFails(setDoc(sessRef(admin), { ...sessionDoc({ status: 'FINALIZED', uid: 'att-admin' }), finalizedBy: 'someone-else' }));
  await assertSucceeds(setDoc(sessRef(admin), sessionDoc({ status: 'FINALIZED', uid: 'att-admin' })));
});

// ---------------------------------------------------------------------
// History
// ---------------------------------------------------------------------

test('History entries: authorized, one per revision, immutable, and never forged', async () => {
  await seedWorld();
  const ct = asUser('att-teacher-ct');
  const hist = (db, rev) => doc(db, ...branch(A, NORTH), 'studentAttendance', `${DATE}_stu-1`, 'history', String(rev));

  await assertSucceeds(setDoc(hist(ct, 1), historyDoc({ uid: 'att-teacher-ct' })));
  await assertFails(setDoc(hist(ct, 2), historyDoc({ uid: 'att-teacher-ct', revision: 1 }))); // id != revision
  await assertFails(setDoc(hist(ct, 3), historyDoc({ uid: 'someone-else', revision: 3 }))); // forged actor
  await assertFails(setDoc(hist(ct, 4), { ...historyDoc({ uid: 'att-teacher-ct', revision: 4 }), changedAt: new Date('2020-01-01') }));
  await assertFails(updateDoc(hist(ct, 1), { reason: 'rewritten' }));
  await assertFails(deleteDoc(hist(ct, 1)));
  await assertSucceeds(getDoc(hist(ct, 1)));

  // a teacher of another section cannot write or read history for 5-A
  const other = asUser('att-teacher-other');
  await assertFails(setDoc(hist(other, 5), historyDoc({ uid: 'att-teacher-other', revision: 5 })));
  await assertFails(getDoc(hist(other, 1)));
  // the class teacher cannot write history claiming it belongs to another section
  await assertFails(setDoc(hist(ct, 6), historyDoc({ uid: 'att-teacher-ct', revision: 6, sectionId: SEC_B })));
});

// ---------------------------------------------------------------------
// Atomic class save (what the app actually does)
// ---------------------------------------------------------------------

test('A whole class save (records + history + session) is one batch the rules accept for the class teacher', async () => {
  await seedWorld();
  const ct = asUser('att-teacher-ct');
  const batch = writeBatch(ct);
  for (const sid of ['stu-1', 'stu-2', 'stu-3']) {
    batch.set(attRef(ct, sid), studentAtt({ studentId: sid, uid: 'att-teacher-ct' }));
    batch.set(doc(ct, ...branch(A, NORTH), 'studentAttendance', `${DATE}_${sid}`, 'history', '1'), historyDoc({ uid: 'att-teacher-ct', studentId: sid }));
  }
  batch.set(sessRef(ct), sessionDoc({ uid: 'att-teacher-ct' }));
  await assertSucceeds(batch.commit());
});

// ---------------------------------------------------------------------
// Staff attendance
// ---------------------------------------------------------------------

const staffAtt = ({ staffId = 'staff-ct', dateKey = DATE, status = 'PRESENT', revision = 1, lastChangeReason = null, uid }) => ({
  schoolId: A, branchId: NORTH, dateKey, attendanceDate: new Date(`${dateKey}T00:00:00Z`), staffId, status,
  remarks: null, revision, lastChangeReason, ...audit(uid),
});
const staffRef = (db, staffId = 'staff-ct', dateKey = DATE, b = NORTH) => doc(db, ...branch(A, b), 'staffAttendance', `${dateKey}_${staffId}`);
const dayRef = (db, dateKey = DATE) => doc(db, ...branch(A, NORTH), 'staffAttendanceDays', dateKey);
const dayDoc = ({ status = 'DRAFT', revision = 1, uid }) => ({
  schoolId: A, branchId: NORTH, dateKey: DATE, attendanceDate: new Date(`${DATE}T00:00:00Z`), status, enrolled: 2, present: 2,
  absent: 0, late: 0, halfDay: 0, notMarked: 0, dayKind: 'workingDay', overrideReason: null, revision,
  finalizedAt: status === 'FINALIZED' ? serverTimestamp() : null, finalizedBy: status === 'FINALIZED' ? uid : null, ...audit(uid),
});

test('Staff attendance: branch admin and school admin write their scope; teachers, finance and parents cannot; other schools/branches denied', async () => {
  await seedWorld();
  await assertSucceeds(setDoc(staffRef(asUser('att-br-north')), staffAtt({ uid: 'att-br-north' })));
  await assertSucceeds(setDoc(dayRef(asUser('att-br-north')), dayDoc({ uid: 'att-br-north' })));
  await assertSucceeds(setDoc(staffRef(asUser('att-admin'), 'staff-other'), staffAtt({ staffId: 'staff-other', uid: 'att-admin' })));

  for (const uid of ['att-teacher-ct', 'att-teacher-other', 'att-finance', 'att-parent', 'att-br-south', 'att-admin-b']) {
    await assertFails(setDoc(staffRef(asUser(uid), 'staff-x'), staffAtt({ staffId: 'staff-x', uid })));
    await assertFails(setDoc(dayRef(asUser(uid), '2026-06-11'), { ...dayDoc({ uid }), dateKey: '2026-06-11' }));
  }
});

test('Staff attendance reads: finance and managers read the branch; a staff member reads only their own; others denied', async () => {
  await seedWorld();
  await seed(async (db) => {
    await setDoc(staffRef(db, 'staff-ct'), staffAtt({ staffId: 'staff-ct', uid: 'seed' }));
    await setDoc(staffRef(db, 'staff-other'), staffAtt({ staffId: 'staff-other', uid: 'seed' }));
  });
  await assertSucceeds(getDoc(staffRef(asUser('att-finance'))));
  await assertSucceeds(getDocs(query(collection(asUser('att-finance'), ...branch(A, NORTH), 'staffAttendance'), where('dateKey', '==', DATE))));
  await assertSucceeds(getDoc(staffRef(asUser('att-teacher-ct'), 'staff-ct')));
  await assertFails(getDoc(staffRef(asUser('att-teacher-ct'), 'staff-other')));
  await assertFails(getDoc(staffRef(asUser('att-parent'))));
  await assertFails(getDoc(staffRef(asUser('att-br-south'))));
  await assertFails(getDoc(staffRef(asUser('att-admin-b'))));
});

test('Staff attendance: id, revision, immutables and finalization are enforced like student attendance', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  await assertFails(setDoc(doc(admin, ...branch(A, NORTH), 'staffAttendance', 'random'), staffAtt({ uid: 'att-admin' })));
  await assertSucceeds(setDoc(staffRef(admin), staffAtt({ uid: 'att-admin' })));
  await assertFails(setDoc(staffRef(admin), staffAtt({ status: 'ABSENT', uid: 'att-admin' }))); // duplicate create

  const meta = { updatedAt: serverTimestamp(), updatedBy: 'att-admin' };
  await assertFails(updateDoc(staffRef(admin), { status: 'ABSENT', revision: 1, ...meta }));
  await assertFails(updateDoc(staffRef(admin), { staffId: 'staff-other', revision: 2, ...meta }));
  await assertSucceeds(updateDoc(staffRef(admin), { status: 'LATE', revision: 2, ...meta }));

  // finalize the day; corrections then need a reason
  await assertSucceeds(setDoc(dayRef(admin), dayDoc({ status: 'FINALIZED', uid: 'att-admin' })));
  await assertFails(updateDoc(staffRef(admin), { status: 'ABSENT', revision: 3, ...meta }));
  await assertSucceeds(updateDoc(staffRef(admin), { status: 'ABSENT', revision: 3, lastChangeReason: 'Medical certificate', ...meta }));
  await assertFails(deleteDoc(staffRef(admin)));
});

test('Staff attendance history is manager-only and immutable', async () => {
  await seedWorld();
  const admin = asUser('att-admin');
  const hist = (db, rev) => doc(db, ...branch(A, NORTH), 'staffAttendance', `${DATE}_staff-ct`, 'history', String(rev));
  const entry = (rev, uid) => ({
    schoolId: A, branchId: NORTH, dateKey: DATE, staffId: 'staff-ct', revision: rev, previousStatus: null, newStatus: 'PRESENT',
    reason: null, changedBy: uid, changedAt: serverTimestamp(),
  });
  await assertSucceeds(setDoc(hist(admin, 1), entry(1, 'att-admin')));
  await assertFails(setDoc(hist(admin, 2), entry(1, 'att-admin')));
  await assertFails(updateDoc(hist(admin, 1), { reason: 'x' }));
  await assertFails(deleteDoc(hist(admin, 1)));
  await assertFails(setDoc(hist(asUser('att-teacher-ct'), 3), entry(3, 'att-teacher-ct')));
  await assertFails(getDoc(hist(asUser('att-teacher-ct'), 1)));
});

// ---------------------------------------------------------------------
// Roster (collection-group over academicRecords)
// ---------------------------------------------------------------------

test('Roster query: staff of the branch can query enrollment for their own school; other schools cannot', async () => {
  await seedWorld();
  const roster = (db, school) => getDocs(query(collectionGroup(db, 'academicRecords'),
    where('schoolId', '==', school), where('branchId', '==', NORTH), where('academicYearId', '==', YEAR), where('classId', '==', CLASS5), where('sectionId', '==', SEC_A)));

  const snap = await assertSucceeds(roster(asUser('att-teacher-ct'), A));
  if (snap.size !== 1) throw new Error(`expected 1 record, got ${snap.size}`);
  await assertSucceeds(roster(asUser('att-admin'), A));
  await assertFails(roster(asUser('att-admin-b'), A)); // another school
  await assertFails(roster(asUser('att-parent'), A)); // no student-data permission
  await assertFails(roster(asUser('att-teacher-other'), A)); // a teacher not assigned to this section
});

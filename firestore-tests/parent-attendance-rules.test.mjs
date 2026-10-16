// A parent reads the attendance records of their own linked, portal-enabled
// child only (the same canAccessAsParent check as invoices/receipts). Read
// only: parents never write attendance, and registers/history stay staff-only.
// Own school ids and uid prefix (`pa-`) so it can share the emulator.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, deleteDoc, where, orderBy,
} from 'firebase/firestore';

let env;
const A = 'pa-a';
const B = 'pa-b';
const N = 'north';
const S = 'south';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const nb = (s = A, b = N) => ['schools', s, 'branches', b];
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const att = (d, b = N, s = A) => collection(d, ...nb(s, b), 'studentAttendance');
const rec = (studentId, dateKey = '2026-06-10', b = N, s = A) => ({
  schoolId: s, branchId: b, academicYearId: 'y1', dateKey, studentId, academicRecordId: 'r1',
  classId: 'c5', sectionId: 'sa', status: 'PRESENT', remarks: null, revision: 1, ...base,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...base });
    for (const [s, b] of [[A, N], [A, S], [B, N]]) await setDoc(doc(d, ...nb(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...base });
    const users = {
      'pa-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'pa-teacher': { schoolId: A, branchId: N, role: 'TEACHER' },
      'pa-p1': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par-1' },
      'pa-p2': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par-2' },
      'pa-p-noportal': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par-np' },
      'pa-p-inactive': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par-in' },
      'pa-p-unlinked': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: null },
      'pa-p-clash': { schoolId: B, branchId: N, role: 'PARENT', linkedParentId: 'par-1' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: 't@example.com', status: 'ACTIVE', ...u, ...base });
    }
    const link = (b, student, parent, extra = {}) => setDoc(doc(d, ...nb(A, b), 'students', student, 'parentLinks', parent), {
      schoolId: A, branchId: b, studentId: student, parentId: parent, canAccessPortal: true, status: 'ACTIVE', ...base, ...extra,
    });
    await link(N, 'stu-1', 'par-1');
    await link(N, 'stu-1b', 'par-1'); // a sibling of the same parent
    await link(N, 'stu-2', 'par-2');
    await link(N, 'stu-np', 'par-np', { canAccessPortal: false });
    await link(N, 'stu-in', 'par-in', { status: 'INACTIVE' });
    for (const id of ['stu-1', 'stu-1b', 'stu-2', 'stu-np', 'stu-in']) {
      await setDoc(doc(d, ...nb(A, N), 'attendanceSessions', 'x'), { schoolId: A, branchId: N, dateKey: '2026-06-10', academicYearId: 'y1', classId: 'c5', sectionId: 'sa', ...base });
      await setDoc(doc(d, ...nb(A, N), 'studentAttendance', `2026-06-10_${id}`), rec(id));
      await setDoc(doc(d, ...nb(A, N), 'studentAttendance', `2026-06-11_${id}`), rec(id, '2026-06-11'));
      await setDoc(doc(d, ...nb(A, N), 'studentAttendance', `2026-06-10_${id}`, 'history', '1'), { schoolId: A, branchId: N, newStatus: 'PRESENT', revision: 1 });
    }
    await setDoc(doc(d, ...nb(A, S), 'studentAttendance', '2026-06-10_stu-1'), rec('stu-1', '2026-06-10', S));
  });
});
after(async () => env.cleanup());

test('a parent reads their own child\'s attendance record and month range', async () => {
  const d = as('pa-p1');
  await assertSucceeds(getDoc(doc(d, ...nb(), 'studentAttendance', '2026-06-10_stu-1')));
  const q = query(att(d), where('studentId', '==', 'stu-1'), where('dateKey', '>=', '2026-06-01'), where('dateKey', '<=', '2026-06-30'), orderBy('dateKey'));
  const snap = await assertSucceeds(getDocs(q));
  if (snap.size !== 2) throw new Error(`expected 2 records, got ${snap.size}`);
});

test('a parent with two linked children reads both', async () => {
  const d = as('pa-p1');
  await assertSucceeds(getDoc(doc(d, ...nb(), 'studentAttendance', '2026-06-10_stu-1b')));
  await assertSucceeds(getDocs(query(att(d), where('studentId', '==', 'stu-1b'))));
});

test('a parent cannot read another family\'s child, by id or by query', async () => {
  const d = as('pa-p1');
  await assertFails(getDoc(doc(d, ...nb(), 'studentAttendance', '2026-06-10_stu-2')));
  await assertFails(getDocs(query(att(d), where('studentId', '==', 'stu-2'))));
});

test('an unfiltered branch-wide list is denied to a parent', async () => {
  await assertFails(getDocs(att(as('pa-p1'))));
  await assertFails(getDocs(query(att(as('pa-p1')), where('dateKey', '==', '2026-06-10'))));
});

test('no access without an active, portal-enabled link', async () => {
  await assertFails(getDoc(doc(as('pa-p-noportal'), ...nb(), 'studentAttendance', '2026-06-10_stu-np')));
  await assertFails(getDoc(doc(as('pa-p-inactive'), ...nb(), 'studentAttendance', '2026-06-10_stu-in')));
  await assertFails(getDoc(doc(as('pa-p-unlinked'), ...nb(), 'studentAttendance', '2026-06-10_stu-1')));
});

test('no cross-school or cross-branch access', async () => {
  // Same parent id in another school resolves to that school's (absent) link.
  await assertFails(getDoc(doc(as('pa-p-clash'), ...nb(A, N), 'studentAttendance', '2026-06-10_stu-1')));
  // A record under a branch where the parent has no link.
  await assertFails(getDoc(doc(as('pa-p1'), ...nb(A, S), 'studentAttendance', '2026-06-10_stu-1')));
});

test('parents cannot write attendance, history or registers', async () => {
  const d = as('pa-p1');
  await assertFails(setDoc(doc(d, ...nb(), 'studentAttendance', '2026-06-12_stu-1'), rec('stu-1', '2026-06-12')));
  await assertFails(updateDoc(doc(d, ...nb(), 'studentAttendance', '2026-06-10_stu-1'), { status: 'PRESENT', revision: 2 }));
  await assertFails(deleteDoc(doc(d, ...nb(), 'studentAttendance', '2026-06-10_stu-1')));
  await assertFails(getDoc(doc(d, ...nb(), 'studentAttendance', '2026-06-10_stu-1', 'history', '1')));
  await assertFails(getDoc(doc(d, ...nb(), 'attendanceSessions', 'x')));
});

test('staff access is unchanged; anonymous is denied', async () => {
  await assertSucceeds(getDoc(doc(as('pa-admin'), ...nb(), 'studentAttendance', '2026-06-10_stu-2')));
  await assertFails(getDoc(doc(as('pa-teacher'), ...nb(), 'studentAttendance', '2026-06-10_stu-2')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), ...nb(), 'studentAttendance', '2026-06-10_stu-1')));
});

// Extra classes (e.g. morning pre-school + afternoon day care): the student
// document carries extraPlacements/extraPlacementKeys and each extra class is
// an ACTIVE academicRecords document of kind EXTRA. Prefix: xc-.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, serverTimestamp, Timestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const A = 'xc-a';
const B = 'xc-b';
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const as = (uid) => env.authenticatedContext(uid).firestore();
const P = (s, ...rest) => ['schools', s, 'branches', 'north', ...rest];

const extra = { recordId: 'rec-x', academicYearId: 'y1', classId: 'daycare', sectionId: 'd1', label: 'Afternoon', rollNumber: null };
const extraFields = { extraPlacements: [extra], extraPlacementKeys: ['y1|daycare', 'y1|daycare|d1'] };
const upd = (uid, more = {}) => ({ ...more, updatedAt: serverTimestamp(), updatedBy: uid });
const record = (uid, more = {}) => ({
  studentId: 'xc-stu', schoolId: A, branchId: 'north', academicYearId: 'y1', classId: 'daycare', sectionId: 'd1',
  rollNumber: null, startDate: Timestamp.now(), endDate: null, status: 'ACTIVE', kind: 'EXTRA', label: 'Afternoon', ...audit(uid), ...more,
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) {
      await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      await setDoc(doc(d, 'schools', s, 'branches', 'north'), { schoolId: s, name: 'north', status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'xc-admin': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN' },
      'xc-teacher': { schoolId: A, branchId: 'north', role: 'TEACHER' },
      'xc-admin-b': { schoolId: B, branchId: 'north', role: 'BRANCH_ADMIN' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    await setDoc(doc(d, ...P(A, 'students', 'xc-stu')), {
      schoolId: A, branchId: 'north', admissionNumber: 'XC-1', firstName: 'Kid', lastName: 'One', status: 'ACTIVE',
      currentAcademicYearId: 'y1', currentClassId: 'pre', currentSectionId: 'p1', ...audit('seed'),
    });
  });
});

test('an admin adds an extra class: the cache on the student and the EXTRA academic record', async () => {
  const db = as('xc-admin');
  await assertSucceeds(setDoc(doc(db, ...P(A, 'students', 'xc-stu', 'academicRecords', 'rec-x')), record('xc-admin')));
  await assertSucceeds(updateDoc(doc(db, ...P(A, 'students', 'xc-stu')), upd('xc-admin', extraFields)));
});

test('removing an extra class closes its record and clears the cache', async () => {
  const db = as('xc-admin');
  await assertSucceeds(setDoc(doc(db, ...P(A, 'students', 'xc-stu', 'academicRecords', 'rec-x')), record('xc-admin')));
  await assertSucceeds(updateDoc(doc(db, ...P(A, 'students', 'xc-stu')), upd('xc-admin', extraFields)));
  await assertSucceeds(updateDoc(doc(db, ...P(A, 'students', 'xc-stu', 'academicRecords', 'rec-x')), upd('xc-admin', { status: 'COMPLETED', endDate: Timestamp.now() })));
  await assertSucceeds(updateDoc(doc(db, ...P(A, 'students', 'xc-stu')), upd('xc-admin', { extraPlacements: [], extraPlacementKeys: [] })));
});

test('a teacher cannot add or change extra classes', async () => {
  const db = as('xc-teacher');
  await assertFails(setDoc(doc(db, ...P(A, 'students', 'xc-stu', 'academicRecords', 'rec-x')), record('xc-teacher')));
  await assertFails(updateDoc(doc(db, ...P(A, 'students', 'xc-stu')), upd('xc-teacher', extraFields)));
});

test("another school's admin cannot touch them", async () => {
  const db = as('xc-admin-b');
  await assertFails(setDoc(doc(db, ...P(A, 'students', 'xc-stu', 'academicRecords', 'rec-x')), record('xc-admin-b')));
  await assertFails(updateDoc(doc(db, ...P(A, 'students', 'xc-stu')), upd('xc-admin-b', extraFields)));
});

test('an unlisted field on the student is still refused', async () => {
  const db = as('xc-admin');
  await assertFails(updateDoc(doc(db, ...P(A, 'students', 'xc-stu')), upd('xc-admin', { extraStuff: 1 })));
});

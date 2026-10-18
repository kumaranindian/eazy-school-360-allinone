// ACAD-2: one admission number per branch, enforced by create-only
// reservation documents written in the same batch as the student.
// Prefix: adn-.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteDoc, serverTimestamp, writeBatch } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const A = 'adn-a';
const B = 'adn-b';
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const as = (uid) => env.authenticatedContext(uid).firestore();
const P = (s, b, ...rest) => ['schools', s, 'branches', b, ...rest];

// Same key as lib/features/students/domain/admission_key.dart.
const key = (n) => n.trim().toLowerCase().replaceAll('/', '~');
const studentData = (uid, number, extra = {}) => ({
  schoolId: A, branchId: 'north', admissionNumber: number, firstName: 'X', lastName: 'Y', status: 'ACTIVE', ...audit(uid), ...extra,
});
const reservation = (uid, studentId, extra = {}) => ({
  schoolId: A, branchId: 'north', studentId, createdAt: serverTimestamp(), createdBy: uid, ...extra,
});

/** The admission batch: the student and its reservation. */
function admit(db, uid, id, number, { reservationKey = key(number), resStudent = id } = {}) {
  const b = writeBatch(db);
  b.set(doc(db, ...P(A, 'north', 'students', id)), studentData(uid, number));
  b.set(doc(db, ...P(A, 'north', 'admissionNumbers', reservationKey)), reservation(uid, resStudent));
  return b.commit();
}

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) {
      await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      await setDoc(doc(d, 'schools', s, 'branches', 'north'), { schoolId: s, name: 'north', status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'adn-admin': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN' },
      'adn-teacher': { schoolId: A, branchId: 'north', role: 'TEACHER' },
      'adn-admin-b': { schoolId: B, branchId: 'north', role: 'BRANCH_ADMIN' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    // a student admitted before reservations existed
    await setDoc(doc(d, ...P(A, 'north', 'students', 'legacy')), studentData('seed', 'OLD-1'));
  });
});

test('admitting a student with its reservation is allowed', async () => {
  await assertSucceeds(admit(as('adn-admin'), 'adn-admin', 's1', 'ADM-001'));
});

test('a student without a reservation is refused', async () => {
  const db = as('adn-admin');
  await assertFails(setDoc(doc(db, ...P(A, 'north', 'students', 's1')), studentData('adn-admin', 'ADM-001')));
});

test('the reservation must be under the number\'s own key', async () => {
  await assertFails(admit(as('adn-admin'), 'adn-admin', 's1', 'ADM-001', { reservationKey: 'something-else' }));
});

test('a reservation naming another student does not cover this one', async () => {
  await assertFails(admit(as('adn-admin'), 'adn-admin', 's1', 'ADM-001', { resStudent: 'someone-else' }));
});

test('the same number cannot be taken twice, however it is spelled', async () => {
  const db = as('adn-admin');
  await assertSucceeds(admit(db, 'adn-admin', 's1', 'ADM-001'));
  await assertFails(admit(db, 'adn-admin', 's2', 'ADM-001'));
  await assertFails(admit(db, 'adn-admin', 's3', 'adm-001'));
  await assertFails(admit(db, 'adn-admin', 's4', ' Adm-001 '));
});

test('two admins racing for one number: exactly one batch commits', async () => {
  const db = as('adn-admin');
  const results = await Promise.allSettled([
    admit(db, 'adn-admin', 'r1', 'RACE-1'),
    admit(db, 'adn-admin', 'r2', 'RACE-1'),
    admit(db, 'adn-admin', 'r3', 'race-1'),
  ]);
  assertEq(results.filter((r) => r.status === 'fulfilled').length, 1);
});

test('numbers with a slash are reserved under a safe key', async () => {
  await assertSucceeds(admit(as('adn-admin'), 'adn-admin', 's1', '2024/001'));
  await assertFails(admit(as('adn-admin'), 'adn-admin', 's2', '2024/001'));
});

test('the same number may exist in another branch / school', async () => {
  const dbB = as('adn-admin-b');
  const b = writeBatch(dbB);
  b.set(doc(dbB, ...P(B, 'north', 'students', 's1')), { ...studentData('adn-admin-b', 'ADM-001'), schoolId: B });
  b.set(doc(dbB, ...P(B, 'north', 'admissionNumbers', 'adm-001')), { ...reservation('adn-admin-b', 's1'), schoolId: B });
  await assertSucceeds(b.commit());
  await assertSucceeds(admit(as('adn-admin'), 'adn-admin', 's1', 'ADM-001'));
});

test('a teacher, or an admin of another school, cannot reserve numbers', async () => {
  await assertFails(admit(as('adn-teacher'), 'adn-teacher', 's1', 'T-1'));
  await assertFails(admit(as('adn-admin-b'), 'adn-admin-b', 's1', 'X-1'));
});

test('an invalid number is refused', async () => {
  for (const bad of ['', '   ', '.hidden', '_x', 'a'.repeat(61)]) {
    await assertFails(admit(as('adn-admin'), 'adn-admin', 's1', bad, { reservationKey: key(bad) || 'x' }));
  }
});

test('changing the number swaps the reservation and frees the old one', async () => {
  const db = as('adn-admin');
  await assertSucceeds(admit(db, 'adn-admin', 's1', 'ADM-001'));
  const b = writeBatch(db);
  b.delete(doc(db, ...P(A, 'north', 'admissionNumbers', 'adm-001')));
  b.set(doc(db, ...P(A, 'north', 'admissionNumbers', 'adm-002')), reservation('adn-admin', 's1'));
  b.update(doc(db, ...P(A, 'north', 'students', 's1')), { admissionNumber: 'ADM-002', updatedAt: serverTimestamp(), updatedBy: 'adn-admin' });
  await assertSucceeds(b.commit());
  await assertSucceeds(admit(db, 'adn-admin', 's2', 'ADM-001')); // freed
});

test('changing the number without reserving the new one is refused', async () => {
  const db = as('adn-admin');
  await assertSucceeds(admit(db, 'adn-admin', 's1', 'ADM-001'));
  await assertFails(updateDoc(doc(db, ...P(A, 'north', 'students', 's1')), { admissionNumber: 'ADM-009', updatedAt: serverTimestamp(), updatedBy: 'adn-admin' }));
});

test('a number cannot be taken over by renaming another student to it', async () => {
  const db = as('adn-admin');
  await assertSucceeds(admit(db, 'adn-admin', 's1', 'ADM-001'));
  await assertSucceeds(admit(db, 'adn-admin', 's2', 'ADM-002'));
  const b = writeBatch(db);
  b.update(doc(db, ...P(A, 'north', 'students', 's2')), { admissionNumber: 'ADM-001', updatedAt: serverTimestamp(), updatedBy: 'adn-admin' });
  b.set(doc(db, ...P(A, 'north', 'admissionNumbers', 'adm-001')), reservation('adn-admin', 's2'));
  await assertFails(b.commit());
});

test('a held reservation cannot be deleted or rewritten', async () => {
  const db = as('adn-admin');
  await assertSucceeds(admit(db, 'adn-admin', 's1', 'ADM-001'));
  const r = doc(db, ...P(A, 'north', 'admissionNumbers', 'adm-001'));
  await assertFails(deleteDoc(r));
  await assertFails(updateDoc(r, { studentId: 's9' }));
});

test('a student that predates reservations can still be edited, but not renumbered freely', async () => {
  const db = as('adn-admin');
  await assertSucceeds(updateDoc(doc(db, ...P(A, 'north', 'students', 'legacy')), { firstName: 'New', updatedAt: serverTimestamp(), updatedBy: 'adn-admin' }));
  await assertFails(updateDoc(doc(db, ...P(A, 'north', 'students', 'legacy')), { admissionNumber: 'NEW-2', updatedAt: serverTimestamp(), updatedBy: 'adn-admin' }));
  const b = writeBatch(db);
  b.set(doc(db, ...P(A, 'north', 'admissionNumbers', 'new-2')), reservation('adn-admin', 'legacy'));
  b.update(doc(db, ...P(A, 'north', 'students', 'legacy')), { admissionNumber: 'NEW-2', updatedAt: serverTimestamp(), updatedBy: 'adn-admin' });
  await assertSucceeds(b.commit());
});

function assertEq(a, b) {
  if (a !== b) throw new Error(`expected ${b}, got ${a}`);
}

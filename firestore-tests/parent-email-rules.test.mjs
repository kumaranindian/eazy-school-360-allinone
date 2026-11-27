// STU-02-DEF-01: one parent per email in a school, enforced by
// schools/{s}/parentEmails/{key} reservations written with the parent.
// Prefix: pem-.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, serverTimestamp, writeBatch } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const A = 'pem-a';
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const as = (uid) => env.authenticatedContext(uid).firestore();
const P = (b, ...rest) => ['schools', A, 'branches', b, ...rest];
// Same key as lib/features/students/data/parent_email_reservation.dart.
const key = (e) => e.trim().toLowerCase().replaceAll('/', '%2F');
const parent = (uid, branch, email, extra = {}) => ({
  schoolId: A, branchId: branch, firstName: 'P', lastName: 'Q', displayName: 'P Q', displayNameLower: 'p q',
  phone: '9876543210', email, status: 'ACTIVE', linkedUserId: null, ...audit(uid), ...extra,
});
const reservation = (uid, branch, parentId, email) => ({
  schoolId: A, branchId: branch, parentId, email: email.toLowerCase(), createdAt: serverTimestamp(), createdBy: uid,
});

function createParent(db, uid, id, email, { branch = 'north', resKey = key(email), resParent = id } = {}) {
  const b = writeBatch(db);
  b.set(doc(db, ...P(branch, 'parents', id)), parent(uid, branch, email));
  b.set(doc(db, 'schools', A, 'parentEmails', resKey), reservation(uid, branch, resParent, email));
  return b.commit();
}

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    await setDoc(doc(d, 'schools', A), { name: A, status: 'ACTIVE', ...audit('seed') });
    for (const b of ['north', 'south']) {
      await setDoc(doc(d, 'schools', A, 'branches', b), { schoolId: A, name: b, status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'pem-admin': { branchId: 'north', role: 'SCHOOL_ADMIN' },
      'pem-teacher': { branchId: 'north', role: 'TEACHER' },
      'pem-parent': { branchId: 'north', role: 'PARENT' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { schoolId: A, name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    // an existing parent that holds m@example.com
    await setDoc(doc(d, ...P('north', 'parents', 'p1')), parent('seed', 'north', 'm@example.com'));
    await setDoc(doc(d, 'schools', A, 'parentEmails', 'm@example.com'), reservation('seed', 'north', 'p1', 'm@example.com'));
  });
});

test('a new parent with its email reservation is allowed', async () => {
  await assertSucceeds(createParent(as('pem-admin'), 'pem-admin', 'p2', 'new@example.com'));
});

test('a parent with an email but no reservation is refused', async () => {
  const db = as('pem-admin');
  await assertFails(setDoc(doc(db, ...P('north', 'parents', 'p2')), parent('pem-admin', 'north', 'new@example.com')));
});

test('a parent without an email needs no reservation', async () => {
  const db = as('pem-admin');
  await assertSucceeds(setDoc(doc(db, ...P('north', 'parents', 'p2')), parent('pem-admin', 'north', null)));
});

test('a second parent with an email already in the school is refused, in any case or branch', async () => {
  await assertFails(createParent(as('pem-admin'), 'pem-admin', 'p2', 'm@example.com'));
  await assertFails(createParent(as('pem-admin'), 'pem-admin', 'p2', 'M@Example.com'));
  await assertFails(createParent(as('pem-admin'), 'pem-admin', 'p2', 'm@example.com', { branch: 'south' }));
});

test('the reservation must name this parent and use the email key', async () => {
  await assertFails(createParent(as('pem-admin'), 'pem-admin', 'p2', 'new@example.com', { resParent: 'other' }));
  await assertFails(createParent(as('pem-admin'), 'pem-admin', 'p2', 'new@example.com', { resKey: 'x@example.com' }));
});

test('the same parent copied to another branch (transfer) is covered by its reservation', async () => {
  const db = as('pem-admin');
  await assertSucceeds(setDoc(doc(db, ...P('south', 'parents', 'p1')), parent('pem-admin', 'south', 'm@example.com')));
});

test('changing a parent\'s email needs the new email reserved; other edits do not', async () => {
  const db = as('pem-admin');
  const ref = doc(db, ...P('north', 'parents', 'p1'));
  await assertSucceeds(updateDoc(ref, { phone: '9000000000', updatedAt: serverTimestamp(), updatedBy: 'pem-admin' }));
  await assertFails(updateDoc(ref, { email: 'n@example.com', updatedAt: serverTimestamp(), updatedBy: 'pem-admin' }));
  const b = writeBatch(db);
  b.update(ref, { email: 'n@example.com', updatedAt: serverTimestamp(), updatedBy: 'pem-admin' });
  b.set(doc(db, 'schools', A, 'parentEmails', 'n@example.com'), reservation('pem-admin', 'north', 'p1', 'n@example.com'));
  await assertSucceeds(b.commit());
});

test('a reservation is taken over only once its parent no longer has that email', async () => {
  const db = as('pem-admin');
  // p1 still has the email: no take-over.
  await assertFails(createParent(db, 'pem-admin', 'p2', 'm@example.com'));
  await env.withSecurityRulesDisabled(async (c) => {
    await updateDoc(doc(c.firestore(), ...P('north', 'parents', 'p1')), { email: 'changed@example.com' });
  });
  await assertSucceeds(createParent(db, 'pem-admin', 'p2', 'm@example.com'));
});

test('teachers cannot reserve; parents cannot read reservations; admins can check one', async () => {
  await assertFails(createParent(as('pem-teacher'), 'pem-teacher', 'p2', 'new@example.com'));
  await assertFails(getDoc(doc(as('pem-parent'), 'schools', A, 'parentEmails', 'm@example.com')));
  await assertSucceeds(getDoc(doc(as('pem-admin'), 'schools', A, 'parentEmails', 'm@example.com')));
  await assertSucceeds(getDoc(doc(as('pem-admin'), 'schools', A, 'parentEmails', 'none@example.com')));
});

// Account deletion requests are written and read only by the server (Admin
// SDK). No client - not the owner, a school admin, a platform admin, or an
// unauthenticated visitor - can read, create, change or delete them, their
// locks or their rate counters, and the public form cannot be used to read or
// forge a request straight from the browser.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, query, where, serverTimestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
    await setDoc(doc(d, 'schools', 'ad-s1'), { name: 'S', status: 'ACTIVE', ...base });
    for (const [uid, u] of Object.entries({
      'ad-parent': { schoolId: 'ad-s1', role: 'PARENT' },
      'ad-admin': { schoolId: 'ad-s1', role: 'SCHOOL_ADMIN' },
      'ad-platform': { role: 'PLATFORM_ADMIN' },
    })) {
      await setDoc(doc(d, 'users', uid), { name: 'T', status: 'ACTIVE', branchId: null, linkedParentId: null, ...u, ...base });
    }
    await setDoc(doc(d, 'accountDeletionRequests', 'DEL-AAAAAAAAAAAAAAAA'), { status: 'UNDER_REVIEW', uid: 'ad-parent', history: [] });
    await setDoc(doc(d, 'accountDeletionLocks', 'ad-parent'), { reference: 'DEL-AAAAAAAAAAAAAAAA' });
    await setDoc(doc(d, 'accountDeletionRate', 'e_x'), { count: 1 });
  });
});
after(async () => env.cleanup());

const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' }, email: 'x@x.com', email_verified: true }).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const REQ = ['accountDeletionRequests', 'DEL-AAAAAAAAAAAAAAAA'];

test('nobody can read a deletion request - not the owner, an admin, a platform admin or a visitor', async () => {
  for (const d of [as('ad-parent'), as('ad-admin'), as('ad-platform'), anon()]) {
    await assertFails(getDoc(doc(d, ...REQ)));
    await assertFails(getDocs(collection(d, 'accountDeletionRequests')));
    await assertFails(getDocs(query(collection(d, 'accountDeletionRequests'), where('uid', '==', 'ad-parent'))));
  }
});

test('nobody can create, change or delete a request from a client', async () => {
  for (const d of [as('ad-parent'), as('ad-admin'), as('ad-platform'), anon()]) {
    await assertFails(setDoc(doc(d, 'accountDeletionRequests', 'DEL-BBBBBBBBBBBBBBBB'), { status: 'PENDING_VERIFICATION', contactEmail: 'a@b.co' }));
    await assertFails(updateDoc(doc(d, ...REQ), { status: 'APPROVED' }));
    await assertFails(deleteDoc(doc(d, ...REQ)));
  }
});

test('a user cannot approve their own request or free their own lock', async () => {
  const p = as('ad-parent');
  await assertFails(updateDoc(doc(p, ...REQ), { status: 'APPROVED', reviewedBy: 'ad-platform' }));
  await assertFails(deleteDoc(doc(p, 'accountDeletionLocks', 'ad-parent')));
  await assertFails(getDoc(doc(p, 'accountDeletionLocks', 'ad-parent')));
});

test('rate counters are server-only', async () => {
  for (const d of [as('ad-admin'), anon()]) {
    await assertFails(getDoc(doc(d, 'accountDeletionRate', 'e_x')));
    await assertFails(setDoc(doc(d, 'accountDeletionRate', 'e_x'), { count: 0 }));
  }
});

test('ordinary access around the feature is unaffected', async () => {
  await assertSucceeds(getDoc(doc(as('ad-parent'), 'users', 'ad-parent')));
  await assertSucceeds(getDoc(doc(as('ad-parent'), 'schools', 'ad-s1')));
});

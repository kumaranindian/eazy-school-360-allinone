// Fee reminder settings: schools/{s}/feeReminderSettings/config. School admins
// read; nobody writes from a client (the updateFeeReminderSettings callable does,
// after validating). Prefix: frs-.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const A = 'frs-a';
const B = 'frs-b';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const cfg = (d, s = A) => doc(d, 'schools', s, 'feeReminderSettings', 'config');
const settings = { enabled: true, deliveryTime: '08:00', includeAmount: true };

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) await setDoc(doc(d, 'schools', s), { name: s, email: `${s}@example.com`, status: 'ACTIVE', ...base });
    const users = {
      'frs-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'frs-admin-b': { schoolId: B, branchId: null, role: 'SCHOOL_ADMIN' },
      'frs-ba': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN' },
      'frs-teacher': { schoolId: A, branchId: 'north', role: 'TEACHER' },
      'frs-parent': { schoolId: A, branchId: 'north', role: 'PARENT', linkedParentId: 'p1' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    await setDoc(cfg(d), settings);
  });
});

test('the school admin reads the school\'s reminder settings', async () => {
  await assertSucceeds(getDoc(cfg(as('frs-admin'))));
});

test('teachers, parents and another school\'s admin cannot read them', async () => {
  await assertFails(getDoc(cfg(as('frs-teacher'))));
  await assertFails(getDoc(cfg(as('frs-parent'))));
  await assertFails(getDoc(cfg(as('frs-admin-b'))));
  await assertFails(getDoc(cfg(env.unauthenticatedContext().firestore())));
});

test('nobody can write them from a client, not even the school admin', async () => {
  for (const uid of ['frs-admin', 'frs-ba', 'frs-teacher', 'frs-parent', 'frs-admin-b']) {
    await assertFails(setDoc(cfg(as(uid)), { ...settings, enabled: false }));
    await assertFails(updateDoc(cfg(as(uid)), { enabled: false }));
    await assertFails(deleteDoc(cfg(as(uid))));
  }
  await assertFails(setDoc(doc(as('frs-admin'), 'schools', A, 'feeReminderSettings', 'other'), settings));
});

test('the school document still cannot carry a settings field of its own', async () => {
  await assertFails(updateDoc(doc(as('frs-admin'), 'schools', A), { feeReminders: { enabled: false }, updatedAt: serverTimestamp(), updatedBy: 'frs-admin' }));
});

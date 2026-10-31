// In-app user manual: a person's progress through each guide lives in their
// own users/{uid}/manualProgress/{guideId} document. Prefix: mp-.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const as = (uid) => env.authenticatedContext(uid).firestore();
const progress = (db, uid, guide = 'invoices') => doc(db, 'users', uid, 'manualProgress', guide);
const body = (o = {}) => ({ completed: [0, 1], version: 1, lastStep: 1, updatedAt: serverTimestamp(), ...o });

test('a person reads, writes and resets only their own manual progress', async () => {
  const me = as('mp-a');
  await assertSucceeds(setDoc(progress(me, 'mp-a'), body()));
  await assertSucceeds(getDoc(progress(me, 'mp-a')));
  await assertSucceeds(setDoc(progress(me, 'mp-a'), body({ completed: [0, 1, 2] })));
  await assertSucceeds(deleteDoc(progress(me, 'mp-a')));
});

test('nobody else can read, write or delete it', async () => {
  await env.withSecurityRulesDisabled(async (c) => setDoc(progress(c.firestore(), 'mp-a'), body()));
  const other = as('mp-b');
  await assertFails(getDoc(progress(other, 'mp-a')));
  await assertFails(setDoc(progress(other, 'mp-a'), body()));
  await assertFails(deleteDoc(progress(other, 'mp-a')));
  await assertFails(getDoc(progress(env.unauthenticatedContext().firestore(), 'mp-a')));
});

test('the completed list must be a list of at most 60 steps', async () => {
  const me = as('mp-a');
  await assertFails(setDoc(progress(me, 'mp-a'), body({ completed: 'all' })));
  await assertFails(setDoc(progress(me, 'mp-a'), { version: 1 }));
  await assertFails(setDoc(progress(me, 'mp-a'), body({ completed: Array.from({ length: 61 }, (_, i) => i) })));
  await assertSucceeds(setDoc(progress(me, 'mp-a'), body({ completed: Array.from({ length: 60 }, (_, i) => i) })));
});

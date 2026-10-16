// Storage rules for multi-branch staff (`branchRoles`). Prefix: mbs-.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
    storage: { rules: readFileSync('../storage.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

const A = 'mbs-a';
const stamp = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const BYTES = new Uint8Array([1, 2, 3, 4]);
const storageFor = (uid) => testEnv.authenticatedContext(uid).storage();
const photo = (b) => `schools/${A}/branches/${b}/staff/s1/photo`;
const png = { contentType: 'image/png' };

async function profile(uid, o) {
  await testEnv.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'users', uid), {
      schoolId: A, branchId: 'north', name: 'T', email: 't@x.com', status: 'ACTIVE', linkedParentId: null, ...o, ...stamp,
    });
  });
}

test('a branch admin in a second branch manages that branch only; a teacher there reads but cannot write', async () => {
  await profile('mbs-admin', { role: 'TEACHER', branchRoles: { south: 'BRANCH_ADMIN' } });
  await profile('mbs-teach', { role: 'FINANCE', branchRoles: { south: 'TEACHER' } });
  const admin = storageFor('mbs-admin');
  await assertSucceeds(uploadBytes(ref(admin, photo('south')), BYTES, png));
  await assertFails(uploadBytes(ref(admin, photo('north')), BYTES, png)); // home role is teacher
  await assertFails(uploadBytes(ref(admin, photo('east')), BYTES, png)); // unassigned

  const teach = storageFor('mbs-teach');
  await assertSucceeds(getBytes(ref(teach, photo('south'))));
  await assertFails(uploadBytes(ref(teach, photo('south')), BYTES, png));
  await assertFails(getBytes(ref(teach, photo('east'))));
});

test('corrupt branchRoles values and disabled accounts get nothing', async () => {
  await profile('mbs-bad', { role: 'TEACHER', branchRoles: { south: 'SCHOOL_ADMIN' } });
  await profile('mbs-off', { role: 'BRANCH_ADMIN', status: 'DISABLED', branchRoles: { south: 'BRANCH_ADMIN' } });
  await assertFails(uploadBytes(ref(storageFor('mbs-bad'), photo('south')), BYTES, png));
  await assertFails(getBytes(ref(storageFor('mbs-bad'), photo('south'))));
  await assertFails(uploadBytes(ref(storageFor('mbs-off'), photo('south')), BYTES, png));
});

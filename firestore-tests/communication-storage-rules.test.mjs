// Storage rules tests for Milestone 11 — conversation attachments.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
    storage: { rules: readFileSync('../storage.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

const A = 'cst-a';
const stamp = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const storageFor = (uid) => testEnv.authenticatedContext(uid).storage();
const BYTES = new Uint8Array([1, 2, 3, 4]);
const PDF = { contentType: 'application/pdf' };
const path = (conv = 'cv1', f = 'a.pdf') => `schools/${A}/branches/north/conversations/${conv}/files/${f}`;

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const user = (uid, o) => setDoc(doc(db, 'users', uid), { branchId: 'north', name: 'T', email: 't@x.com', status: 'ACTIVE', linkedParentId: null, schoolId: A, ...o, ...stamp });
    await user('cst-p1', { role: 'PARENT', linkedParentId: 'par1' });
    await user('cst-t1', { role: 'TEACHER' });
    await user('cst-t2', { role: 'TEACHER' });
    await user('cst-admin', { role: 'SCHOOL_ADMIN', branchId: null });
    const conv = (id, status) => setDoc(doc(db, 'schools', A, 'branches', 'north', 'conversations', id), {
      schoolId: A, branchId: 'north', participants: ['cst-p1', 'cst-t1'], parentUserId: 'cst-p1', teacherUserId: 'cst-t1', status, flagged: true, ...stamp,
    });
    await conv('cv1', 'OPEN');
    await conv('cv-closed', 'CLOSED');
  });
}

test('conversation attachments: members upload to an open conversation, create-only, typed and sized', async () => {
  await seed();
  await assertSucceeds(uploadBytes(ref(storageFor('cst-p1'), path('cv1', 'p.pdf')), BYTES, PDF));
  await assertSucceeds(uploadBytes(ref(storageFor('cst-t1'), path('cv1', 't.png')), BYTES, { contentType: 'image/png' }));
  // no overwrite, no delete
  await assertFails(uploadBytes(ref(storageFor('cst-p1'), path('cv1', 'p.pdf')), BYTES, PDF));
  await assertFails(deleteObject(ref(storageFor('cst-p1'), path('cv1', 'p.pdf'))));
  // outsiders, a closed conversation, a conversation that does not exist
  await assertFails(uploadBytes(ref(storageFor('cst-t2'), path('cv1', 'x.pdf')), BYTES, PDF));
  await assertFails(uploadBytes(ref(storageFor('cst-p1'), path('cv-closed', 'x.pdf')), BYTES, PDF));
  await assertFails(uploadBytes(ref(storageFor('cst-p1'), path('nope', 'x.pdf')), BYTES, PDF));
  // type and size
  await assertFails(uploadBytes(ref(storageFor('cst-p1'), path('cv1', 'x.exe')), BYTES, { contentType: 'application/x-msdownload' }));
  await assertFails(uploadBytes(ref(storageFor('cst-p1'), path('cv1', 'big.pdf')), new Uint8Array(10 * 1024 * 1024 + 1), PDF));
});

test('conversation attachments are readable by the two members only — not even a reporting administrator', async () => {
  await seed();
  await assertSucceeds(uploadBytes(ref(storageFor('cst-p1'), path('cv1', 'r.pdf')), BYTES, PDF));
  for (const uid of ['cst-p1', 'cst-t1']) await assertSucceeds(getBytes(ref(storageFor(uid), path('cv1', 'r.pdf'))));
  for (const uid of ['cst-t2', 'cst-admin']) await assertFails(getBytes(ref(storageFor(uid), path('cv1', 'r.pdf'))));
  await assertFails(getBytes(ref(testEnv.unauthenticatedContext().storage(), path('cv1', 'r.pdf'))));
});

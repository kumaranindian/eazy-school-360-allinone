// Firebase Storage rules tests for Milestone 7 — leave supporting documents
// (see ../storage.rules). Own school ids/uids so it runs next to the others.
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

const A = 'lst-a';
const B = 'lst-b';
const NORTH = 'north';
const SOUTH = 'south';

async function seedProfile(uid, { schoolId, branchId = NORTH, role }) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', uid), {
      schoolId, branchId, name: 'T', email: 't@example.com', role, status: 'ACTIVE',
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed',
    });
  });
}

const storageFor = (uid) => testEnv.authenticatedContext(uid).storage();
const BYTES = new Uint8Array([1, 2, 3, 4]);
const path = (owner = 'lst-parent', s = A, b = NORTH, app = 'lv-1', file = 'note.pdf') => `schools/${s}/branches/${b}/leaveDocs/${owner}/${app}/${file}`;

async function seedAll() {
  await seedProfile('lst-parent', { schoolId: A, role: 'PARENT' });
  await seedProfile('lst-parent2', { schoolId: A, role: 'PARENT' });
  await seedProfile('lst-admin-north', { schoolId: A, role: 'BRANCH_ADMIN' });
  await seedProfile('lst-admin-south', { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' });
  await seedProfile('lst-school-admin', { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' });
  await seedProfile('lst-teacher', { schoolId: A, role: 'TEACHER' });
  await seedProfile('lst-fin', { schoolId: A, role: 'FINANCE' });
  await seedProfile('lst-admin-b', { schoolId: B, role: 'SCHOOL_ADMIN' });
}

test('leave documents: the applicant uploads their own; reviewing admins read; nobody replaces or deletes', async () => {
  await seedAll();
  const parent = storageFor('lst-parent');
  await assertSucceeds(uploadBytes(ref(parent, path()), BYTES, { contentType: 'application/pdf' }));
  await assertSucceeds(uploadBytes(ref(parent, path('lst-parent', A, NORTH, 'lv-1', 'scan.jpg')), BYTES, { contentType: 'image/jpeg' }));
  await assertSucceeds(getBytes(ref(parent, path())));
  await assertSucceeds(getBytes(ref(storageFor('lst-admin-north'), path())));
  await assertSucceeds(getBytes(ref(storageFor('lst-school-admin'), path())));
  // create-only: no overwrite, no delete — even by the owner or an admin
  await assertFails(uploadBytes(ref(parent, path()), BYTES, { contentType: 'application/pdf' }));
  await assertFails(deleteObject(ref(parent, path())));
  await assertFails(deleteObject(ref(storageFor('lst-admin-north'), path())));
});

test('leave documents are confidential: teacher, finance, other parents, other branches and other schools cannot read', async () => {
  await seedAll();
  await assertSucceeds(uploadBytes(ref(storageFor('lst-parent'), path('lst-parent', A, NORTH, 'lv-conf')), BYTES, { contentType: 'application/pdf' }));
  for (const uid of ['lst-teacher', 'lst-fin', 'lst-parent2', 'lst-admin-south', 'lst-admin-b']) {
    await assertFails(getBytes(ref(storageFor(uid), path('lst-parent', A, NORTH, 'lv-conf'))));
  }
});

test('leave documents: nobody can write into another applicant\'s folder; only pdf/jpeg/png under 5MB', async () => {
  await seedAll();
  await assertFails(uploadBytes(ref(storageFor('lst-parent2'), path('lst-parent')), BYTES, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(storageFor('lst-admin-north'), path('lst-parent')), BYTES, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(storageFor('lst-admin-b'), path('lst-admin-b', A)), BYTES, { contentType: 'application/pdf' }));
  const parent = storageFor('lst-parent');
  await assertFails(uploadBytes(ref(parent, path('lst-parent', A, NORTH, 'lv-2', 'a.exe')), BYTES, { contentType: 'application/x-msdownload' }));
  await assertFails(uploadBytes(ref(parent, path('lst-parent', A, NORTH, 'lv-2', 'a.txt')), BYTES, { contentType: 'text/plain' }));
  await assertFails(uploadBytes(ref(parent, path('lst-parent', A, NORTH, 'lv-2', 'big.pdf')), new Uint8Array(5 * 1024 * 1024 + 1), { contentType: 'application/pdf' }));
  await assertSucceeds(uploadBytes(ref(parent, path('lst-parent', A, NORTH, 'lv-2', 'ok.png')), BYTES, { contentType: 'image/png' }));
});

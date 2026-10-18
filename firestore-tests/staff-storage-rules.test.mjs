// Firebase Storage rules tests for Milestone 4 — staff photos and staff
// documents (see ../storage.rules). Own school ids/uids so it can run next
// to the other test files on the shared emulator.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
    storage: { rules: readFileSync(process.env.STORAGE_RULES_FILE || '../storage.rules', 'utf8') },
  });
});

after(async () => {
  await testEnv.cleanup();
});

const A = 'sst-a';
const B = 'sst-b';
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
const photoPath = (s = A, b = NORTH) => `schools/${s}/branches/${b}/staff/staff-1/photo`;
const docPath = (s = A, b = NORTH) => `schools/${s}/branches/${b}/staff/staff-1/documents/d1/id.pdf`;

test('staff photo: branch admin uploads, replaces and removes; same-branch teacher reads but cannot write', async () => {
  await seedProfile('sst-admin-north', { schoolId: A, role: 'BRANCH_ADMIN' });
  await seedProfile('sst-teacher', { schoolId: A, role: 'TEACHER' });
  const admin = storageFor('sst-admin-north');

  await assertSucceeds(uploadBytes(ref(admin, photoPath()), BYTES, { contentType: 'image/png' }));
  await assertSucceeds(uploadBytes(ref(admin, photoPath()), BYTES, { contentType: 'image/jpeg' })); // replace

  const teacher = storageFor('sst-teacher');
  await assertSucceeds(getBytes(ref(teacher, photoPath())));
  await assertFails(uploadBytes(ref(teacher, photoPath()), BYTES, { contentType: 'image/png' }));
  await assertFails(deleteObject(ref(teacher, photoPath())));

  await assertSucceeds(deleteObject(ref(admin, photoPath())));
});

test('staff photo: only the fixed object name, images only, and under the size cap', async () => {
  await seedProfile('sst-admin-north', { schoolId: A, role: 'BRANCH_ADMIN' });
  const admin = storageFor('sst-admin-north');
  await assertFails(uploadBytes(ref(admin, `${photoPath()}.png`), BYTES, { contentType: 'image/png' })); // not "photo"
  await assertFails(uploadBytes(ref(admin, photoPath()), BYTES, { contentType: 'application/pdf' }));
  await assertFails(uploadBytes(ref(admin, photoPath()), new Uint8Array(2 * 1024 * 1024 + 1), { contentType: 'image/png' }));
});

test('staff photo: another school, another branch, and unauthenticated callers are denied', async () => {
  await seedProfile('sst-admin-north', { schoolId: A, role: 'BRANCH_ADMIN' });
  await seedProfile('sst-admin-south', { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' });
  await seedProfile('sst-admin-b', { schoolId: B, role: 'SCHOOL_ADMIN' });
  await assertSucceeds(uploadBytes(ref(storageFor('sst-admin-north'), photoPath()), BYTES, { contentType: 'image/png' }));

  await assertFails(uploadBytes(ref(storageFor('sst-admin-south'), photoPath()), BYTES, { contentType: 'image/png' }));
  await assertFails(getBytes(ref(storageFor('sst-admin-south'), photoPath())));
  await assertFails(getBytes(ref(storageFor('sst-admin-b'), photoPath())));
  await assertFails(uploadBytes(ref(storageFor('sst-admin-b'), photoPath()), BYTES, { contentType: 'image/png' }));
  await assertFails(getBytes(ref(testEnv.unauthenticatedContext().storage(), photoPath())));
});

test('staff documents: managers only for read and write; PDF/JPEG/PNG up to 5MB; never deletable', async () => {
  await seedProfile('sst-admin-north', { schoolId: A, role: 'BRANCH_ADMIN' });
  await seedProfile('sst-teacher', { schoolId: A, role: 'TEACHER' });
  await seedProfile('sst-finance', { schoolId: A, role: 'FINANCE' });
  await seedProfile('sst-admin-south', { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' });
  await seedProfile('sst-admin-b', { schoolId: B, role: 'SCHOOL_ADMIN' });
  const admin = storageFor('sst-admin-north');

  await assertSucceeds(uploadBytes(ref(admin, docPath()), BYTES, { contentType: 'application/pdf' }));
  await assertSucceeds(getBytes(ref(admin, docPath())));

  await assertFails(uploadBytes(ref(admin, docPath()), BYTES, { contentType: 'text/html' })); // type
  await assertFails(uploadBytes(ref(admin, docPath()), new Uint8Array(5 * 1024 * 1024 + 1), { contentType: 'application/pdf' })); // size
  await assertFails(deleteObject(ref(admin, docPath())));

  // Sensitive: not even same-branch teachers or finance, and not other branches/schools.
  for (const uid of ['sst-teacher', 'sst-finance', 'sst-admin-south', 'sst-admin-b']) {
    await assertFails(getBytes(ref(storageFor(uid), docPath())));
    await assertFails(uploadBytes(ref(storageFor(uid), docPath()), BYTES, { contentType: 'application/pdf' }));
  }
});

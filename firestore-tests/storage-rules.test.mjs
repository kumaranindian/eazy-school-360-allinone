// Firebase Storage rules tests — the Milestone 2 school-logo path (see
// ../storage.rules and ../docs/milestone-2-school-setup.md). Run as part
// of the same `firebase emulators:exec` session as the Firestore rules
// tests (storage.rules calls firestore.get() to look up the caller's
// profile, exactly like firestore.rules does internally — both emulators
// need to be running together for that cross-service call to resolve).
//
// Run with: firebase emulators:exec --only firestore,storage
//   "cd firestore-tests && npm test" — see ../DEVELOPMENT_GUIDE.md.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

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

const SCHOOL_A = 'school-a';
const SCHOOL_B = 'school-b';

function userDoc({ schoolId, role, status = 'ACTIVE' }) {
  return {
    schoolId,
    branchId: 'main',
    name: 'Test User',
    email: 'user@example.com',
    role,
    status,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy: 'seed',
    updatedBy: 'seed',
  };
}

async function seedProfile(uid, profile) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', uid), profile);
  });
}

const PNG_BYTES = new Uint8Array([0x89, 0x50, 0x4e, 0x47]); // not a full PNG, just non-empty bytes

test('a school admin can upload their own school\'s logo', async () => {
  await seedProfile('admin-a', userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  const adminA = testEnv.authenticatedContext('admin-a').storage();

  await assertSucceeds(
    uploadBytes(ref(adminA, `schools/${SCHOOL_A}/logo.png`), PNG_BYTES, { contentType: 'image/png' }),
  );
});

test('a school admin cannot upload into another school\'s logo path', async () => {
  await seedProfile('admin-a', userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  const adminA = testEnv.authenticatedContext('admin-a').storage();

  await assertFails(
    uploadBytes(ref(adminA, `schools/${SCHOOL_B}/logo.png`), PNG_BYTES, { contentType: 'image/png' }),
  );
});

test('a teacher cannot upload a logo, but can read their own school\'s logo', async () => {
  await seedProfile('admin-a', userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  await seedProfile('teacher-a', userDoc({ schoolId: SCHOOL_A, role: 'TEACHER' }));

  const adminA = testEnv.authenticatedContext('admin-a').storage();
  await assertSucceeds(uploadBytes(ref(adminA, `schools/${SCHOOL_A}/logo.png`), PNG_BYTES, { contentType: 'image/png' }));

  const teacherA = testEnv.authenticatedContext('teacher-a').storage();
  await assertFails(uploadBytes(ref(teacherA, `schools/${SCHOOL_A}/logo.png`), PNG_BYTES, { contentType: 'image/png' }));
  await assertSucceeds(getBytes(ref(teacherA, `schools/${SCHOOL_A}/logo.png`)));
});

test('a user from School B cannot read School A\'s logo', async () => {
  await seedProfile('admin-a', userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  await seedProfile('admin-b', userDoc({ schoolId: SCHOOL_B, role: 'SCHOOL_ADMIN' }));

  const adminA = testEnv.authenticatedContext('admin-a').storage();
  await assertSucceeds(uploadBytes(ref(adminA, `schools/${SCHOOL_A}/logo.png`), PNG_BYTES, { contentType: 'image/png' }));

  const adminB = testEnv.authenticatedContext('admin-b').storage();
  await assertFails(getBytes(ref(adminB, `schools/${SCHOOL_A}/logo.png`)));
});

test('a non-image content type is rejected even from the owning school admin', async () => {
  await seedProfile('admin-a', userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  const adminA = testEnv.authenticatedContext('admin-a').storage();

  await assertFails(
    uploadBytes(ref(adminA, `schools/${SCHOOL_A}/logo.txt`), PNG_BYTES, { contentType: 'text/plain' }),
  );
});

test('an unauthenticated caller cannot read or write any logo', async () => {
  await seedProfile('admin-a', userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  const anon = testEnv.unauthenticatedContext().storage();

  await assertFails(uploadBytes(ref(anon, `schools/${SCHOOL_A}/logo.png`), PNG_BYTES, { contentType: 'image/png' }));
  await assertFails(getBytes(ref(anon, `schools/${SCHOOL_A}/logo.png`)));
});

test('everything outside schools/{schoolId}/... is default-denied', async () => {
  await seedProfile('admin-a', userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  const adminA = testEnv.authenticatedContext('admin-a').storage();

  await assertFails(uploadBytes(ref(adminA, 'random/path.png'), PNG_BYTES, { contentType: 'image/png' }));
});

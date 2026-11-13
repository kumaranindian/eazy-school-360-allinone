// Storage rules for admission application documents (see ../storage.rules,
// admissionDocs). Own ids (adx-) so it can run next to the other files.
//   read: school admin, branch admin of THAT branch, platform admin (support);
//         never teacher / finance / parent / another school / another branch / signed out
//   create: only against a server-approved upload (admissionDocuments/{id} in
//         status UPLOADING for this enquiry, same path, size and content type)
//   never updated or deleted from a client
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
    storage: { rules: readFileSync(process.env.STORAGE_RULES_FILE || '../storage.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const A = 'adx-a';
const B = 'adx-b';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const BYTES = new Uint8Array([1, 2, 3, 4]);
const path = (s = A, b = 'north', e = 'e1', d = 'd1', f = 'document.pdf') => `schools/${s}/branches/${b}/admissionDocs/${e}/${d}/${f}`;
const meta = (over = {}) => ({
  schoolId: A, branchId: 'north', enquiryId: 'e1', applicationId: 'e1', type: 'BIRTH_CERTIFICATE', status: 'UPLOADING',
  storagePath: path(), contentType: 'application/pdf', sizeBytes: 4, ...over,
});
// Platform admins always sign in with a second factor (rules require it).
const store = (uid) => env.authenticatedContext(uid, uid.includes('platform') ? { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } } : undefined).storage();

async function seed(docMeta = meta()) {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    const users = {
      'adx-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'adx-admin-b': { schoolId: B, branchId: null, role: 'SCHOOL_ADMIN' },
      'adx-north': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN' },
      'adx-south': { schoolId: A, branchId: 'south', role: 'BRANCH_ADMIN' },
      'adx-teacher': { schoolId: A, branchId: 'north', role: 'TEACHER' },
      'adx-finance': { schoolId: A, branchId: 'north', role: 'FINANCE' },
      'adx-parent': { schoolId: A, branchId: 'north', role: 'PARENT' },
      'adx-platform': { schoolId: null, branchId: null, role: 'PLATFORM_ADMIN' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', ...u, ...base });
    }
    if (docMeta) await setDoc(doc(d, 'schools', A, 'branches', 'north', 'admissionDocuments', 'd1'), docMeta);
  });
}
const put = (uid, p = path(), opts = { contentType: 'application/pdf' }, bytes = BYTES) => uploadBytes(ref(store(uid), p), bytes, opts);

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
});

test('an approved upload by the school admin or the branch admin of that branch succeeds, once', async () => {
  await seed();
  await assertSucceeds(put('adx-north'));
  await assertFails(put('adx-north'), 'create-only: no overwrite');
});

test('nobody else can upload: teacher, finance, parent, another branch, another school, signed out', async () => {
  await seed();
  for (const uid of ['adx-teacher', 'adx-finance', 'adx-parent', 'adx-south', 'adx-admin-b', 'adx-platform']) {
    await assertFails(put(uid));
  }
  await assertFails(uploadBytes(ref(env.unauthenticatedContext().storage(), path()), BYTES, { contentType: 'application/pdf' }));
});

test('no upload without a server-approved request, or against a different one', async () => {
  await seed(null);
  await assertFails(put('adx-north'), 'no admissionDocuments record');
  for (const over of [
    { status: 'UPLOADED' },
    { status: 'ABANDONED' },
    { enquiryId: 'other' },
    { storagePath: path(A, 'north', 'e1', 'd1', 'other.pdf') },
    { sizeBytes: 5 },
    { contentType: 'image/png' },
  ]) {
    await env.clearFirestore();
    await seed(meta(over));
    await assertFails(put('adx-north'), JSON.stringify(over));
  }
});

test('size and type are enforced even when the record agrees', async () => {
  const big = new Uint8Array(5 * 1024 * 1024 + 1);
  await seed(meta({ sizeBytes: big.length }));
  await assertFails(put('adx-north', path(), { contentType: 'application/pdf' }, big));
  await env.clearFirestore();
  await seed(meta({ contentType: 'application/zip', storagePath: path(A, 'north', 'e1', 'd1', 'document.zip') }));
  await assertFails(put('adx-north', path(A, 'north', 'e1', 'd1', 'document.zip'), { contentType: 'application/zip' }));
});

test('reading: school admin and branch admin of that branch; nobody else, not even a platform admin', async () => {
  await seed();
  await assertSucceeds(put('adx-north'));
  for (const uid of ['adx-admin', 'adx-north']) await assertSucceeds(getBytes(ref(store(uid), path())));
  // Support access is Firestore-only: a platform admin never reads uploaded documents.
  await assertFails(getBytes(ref(store('adx-platform'), path())));
  for (const uid of ['adx-teacher', 'adx-finance', 'adx-parent', 'adx-south', 'adx-admin-b']) await assertFails(getBytes(ref(store(uid), path())));
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), path())));
});

test('a stored document is never deleted from a client', async () => {
  await seed();
  await assertSucceeds(put('adx-north'));
  for (const uid of ['adx-admin', 'adx-north', 'adx-platform']) await assertFails(deleteObject(ref(store(uid), path())));
});

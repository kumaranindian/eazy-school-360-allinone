// Storage rules for expense receipts (see ../storage.rules, expenseReceipts). Own ids (exr-) so it can
// run next to the other files.
//   read: school admin, branch admin and finance of THAT branch; nobody else (no teacher, parent,
//         other branch/school, platform admin, signed out)
//   create: only against a server-approved upload (expenseReceipts/{id} UPLOADING, created by the
//         uploader, same expense, path, size and content type)
//   never updated or deleted from a client
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject, listAll } from 'firebase/storage';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
    storage: { rules: readFileSync(process.env.STORAGE_RULES_FILE || '../storage.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const A = 'exr-a';
const B = 'exr-b';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const BYTES = new Uint8Array([1, 2, 3, 4]);
const path = (s = A, b = 'north', e = 'e1', r = 'r1', f = 'receipt.pdf') => `schools/${s}/branches/${b}/expenseReceipts/${e}/${r}/${f}`;
const meta = (over = {}) => ({
  schoolId: A, branchId: 'north', expenseId: 'e1', status: 'UPLOADING', createdBy: 'exr-finance',
  storagePath: path(), contentType: 'application/pdf', sizeBytes: 4, ...over,
});
const store = (uid) => env.authenticatedContext(uid, uid.includes('platform') ? { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } } : undefined).storage();

async function seed(docMeta = meta()) {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    const users = {
      'exr-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'exr-admin-b': { schoolId: B, branchId: null, role: 'SCHOOL_ADMIN' },
      'exr-north': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN' },
      'exr-south': { schoolId: A, branchId: 'south', role: 'BRANCH_ADMIN' },
      'exr-finance': { schoolId: A, branchId: 'north', role: 'FINANCE' },
      'exr-finance2': { schoolId: A, branchId: 'north', role: 'FINANCE' },
      'exr-finance-south': { schoolId: A, branchId: 'south', role: 'FINANCE' },
      'exr-teacher': { schoolId: A, branchId: 'north', role: 'TEACHER' },
      'exr-parent': { schoolId: A, branchId: 'north', role: 'PARENT' },
      'exr-platform': { schoolId: null, branchId: null, role: 'PLATFORM_ADMIN' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', ...u, ...base });
    }
    if (docMeta) await setDoc(doc(d, 'schools', A, 'branches', 'north', 'expenseReceipts', 'r1'), docMeta);
  });
}
const put = (uid, p = path(), opts = { contentType: 'application/pdf' }, bytes = BYTES) => uploadBytes(ref(store(uid), p), bytes, opts);

// The rule is create-only, and clearStorage() did not remove uploaded objects between tests in CI.
async function wipeStorage() {
  await env.withSecurityRulesDisabled(async (c) => {
    const walk = async (r) => {
      const l = await listAll(r);
      await Promise.all(l.items.map((i) => deleteObject(i)));
      await Promise.all(l.prefixes.map(walk));
    };
    await walk(ref(c.storage(), 'schools'));
  });
}

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await wipeStorage();
});

test('the uploader (created the request) can upload an approved receipt, once', async () => {
  await seed();
  await assertSucceeds(put('exr-finance'));
  await assertFails(put('exr-finance'), 'create-only: no overwrite');
});

test('an admin who created the request can upload; someone else in the branch cannot upload into it', async () => {
  await seed(meta({ createdBy: 'exr-north' }));
  await assertSucceeds(put('exr-north'));
  await wipeStorage();
  await env.clearFirestore();
  await seed();
  for (const uid of ['exr-finance2', 'exr-north', 'exr-admin']) await assertFails(put(uid), `${uid} did not create the request`);
});

test('nobody else can upload: teacher, parent, other branch, other school, platform admin, signed out', async () => {
  await seed(meta({ createdBy: 'exr-teacher' }));
  for (const uid of ['exr-teacher', 'exr-parent', 'exr-south', 'exr-finance-south', 'exr-admin-b', 'exr-platform']) await assertFails(put(uid), uid);
  await assertFails(uploadBytes(ref(env.unauthenticatedContext().storage(), path()), BYTES, { contentType: 'application/pdf' }));
});

test('no upload without a server-approved request, or against a different one', async () => {
  await seed(null);
  await assertFails(put('exr-finance'), 'no expenseReceipts record');
  for (const over of [
    { status: 'UPLOADED' },
    { status: 'ABANDONED' },
    { status: 'REMOVED' },
    { expenseId: 'other' },
    { storagePath: path(A, 'north', 'e1', 'r1', 'other.pdf') },
    { sizeBytes: 5 },
    { contentType: 'image/png' },
  ]) {
    await env.clearFirestore();
    await seed(meta(over));
    await assertFails(put('exr-finance'), JSON.stringify(over));
  }
});

test('size and type are enforced even when the record agrees', async () => {
  const big = new Uint8Array(5 * 1024 * 1024 + 1);
  await seed(meta({ sizeBytes: big.length }));
  await assertFails(put('exr-finance', path(), { contentType: 'application/pdf' }, big));
  await env.clearFirestore();
  await seed(meta({ contentType: 'image/webp', storagePath: path(A, 'north', 'e1', 'r1', 'receipt.webp') }));
  await assertFails(put('exr-finance', path(A, 'north', 'e1', 'r1', 'receipt.webp'), { contentType: 'image/webp' }));
  await env.clearFirestore();
  await seed(meta({ contentType: 'application/zip', storagePath: path(A, 'north', 'e1', 'r1', 'receipt.zip') }));
  await assertFails(put('exr-finance', path(A, 'north', 'e1', 'r1', 'receipt.zip'), { contentType: 'application/zip' }));
});

test('reading: school admin, and branch admin and finance of that branch; nobody else', async () => {
  await seed();
  await assertSucceeds(put('exr-finance'));
  for (const uid of ['exr-admin', 'exr-north', 'exr-finance', 'exr-finance2']) await assertSucceeds(getBytes(ref(store(uid), path())));
  for (const uid of ['exr-teacher', 'exr-parent', 'exr-south', 'exr-finance-south', 'exr-admin-b', 'exr-platform']) await assertFails(getBytes(ref(store(uid), path())), uid);
  await assertFails(getBytes(ref(env.unauthenticatedContext().storage(), path())));
});

test('a stored receipt is never deleted from a client', async () => {
  await seed();
  await assertSucceeds(put('exr-finance'));
  for (const uid of ['exr-admin', 'exr-north', 'exr-finance', 'exr-platform']) await assertFails(deleteObject(ref(store(uid), path())));
});

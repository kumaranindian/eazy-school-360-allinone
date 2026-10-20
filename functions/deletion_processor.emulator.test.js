'use strict';
// Runs the deletion processor against the real Firestore and Auth emulators, to
// prove the query and batch behaviour the in-memory fake only imitates.
// Skipped unless the emulators are up:
//   firebase emulators:exec --only firestore,auth --project demo-eazy-school-360 \
//     "cd functions && node --test deletion_processor.emulator.test.js"
const test = require('node:test');
const assert = require('node:assert');

const live = !!process.env.FIRESTORE_EMULATOR_HOST && !!process.env.FIREBASE_AUTH_EMULATOR_HOST;

test('processor against the real emulators', { skip: !live && 'emulators not running' }, async () => {
  const { initializeApp } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');
  const { getAuth } = require('firebase-admin/auth');
  const ad = require('./account_deletion');
  const dp = require('./deletion_processor');
  const { B1, B2, S, FILES, fakeStorage, seed } = require('./deletion_fixtures');

  initializeApp({ projectId: 'demo-eazy-school-360' });
  const db = getFirestore();
  const auth = getAuth();
  for (const [path, data] of Object.entries(seed())) await db.doc(path).set(data);
  for (const [email, uid] of [['p@x.com', 'parent'], ['t@x.com', 'teacher'], ['o@x.com', 'other']]) {
    await auth.createUser({ uid, email });
  }
  const storage = fakeStorage(FILES);
  const now = () => new Date();
  const ctx = { db, auth, storage, now, key: 'k', enabled: true };
  const token = dp.tokenFor('k', 'teacher');

  // request + approve through the real lifecycle code
  const c = { db, now };
  const r = await ad.requestOwn(c, 'teacher', { auth_time: Math.floor(Date.now() / 1000) }, { confirm: true });
  await ad.review(c, 'reviewer', { reference: r.result.reference, decision: 'APPROVE' });

  const out = await dp.processRequest(ctx, r.result.reference);
  assert.strictEqual(out.status, 'COMPLETED', JSON.stringify(out));

  // the login is gone, the stub remains
  await assert.rejects(auth.getUser('teacher'), (e) => e.code === 'auth/user-not-found');
  const stub = (await db.doc('users/teacher').get()).data();
  assert.strictEqual(stub.deleted, true);
  assert.strictEqual(stub.name, 'Deleted user');
  // authored content in both branches, a nested collection and the school audit log
  const get = async (p) => (await db.doc(p).get()).data();
  assert.strictEqual((await get(`${B1}/homework/hw1`)).createdBy, token);
  assert.strictEqual((await get(`${B2}/homework/hw2`)).createdBy, token);
  assert.strictEqual((await get(`${B1}/studentAttendance/a1/history/h1`)).changedBy, token);
  assert.strictEqual((await get(`${S}/authAudit/e2`)).actorId, token);
  // leave: reason gone, someone else's untouched
  assert.strictEqual((await get(`${B1}/leaveApplications/l1`)).reason, null);
  assert.strictEqual((await get(`${B1}/leaveApplications/l2`)).reason, 'fever');
  // conversation participants (array-contains) and nested messages
  assert.deepStrictEqual((await get(`${B1}/conversations/c1`)).participants, ['parent', token]);
  assert.strictEqual((await get(`${B1}/conversations/c1/messages/m2`)).senderUserId, token);
  // financial untouched, other people untouched
  assert.strictEqual((await get(`${B1}/payments/p1`)).collectedBy, 'teacher');
  assert.strictEqual((await get(`${B1}/homework/hw3`)).createdBy, 'adminA');
  assert.ok((await get('users/other')).email);
  assert.ok((await auth.getUser('other')).uid);
  // staff record unlinked, not deleted
  assert.strictEqual((await get(`${B1}/staff/st1`)).userId, null);
  assert.strictEqual((await get(`${B1}/staff/st1`)).employeeCode, 'E1');
});

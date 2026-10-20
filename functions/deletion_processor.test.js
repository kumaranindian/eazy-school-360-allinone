'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb, fakeAuth } = require('./test_support');
const ad = require('./account_deletion');
const dp = require('./deletion_processor');

const T0 = Date.UTC(2026, 9, 19, 10, 0, 0);
const now = () => new Date(T0);
const { S, B1, B2, fakeStorage, seed, authUsers } = require('./deletion_fixtures');
const KEY = 'test-key';

function setup(over = {}) {
  const db = fakeDb(seed());
  const storage = fakeStorage();
  const auth = fakeAuth(authUsers());
  const ctx = { db, auth, storage, now, key: KEY, enabled: true, ...over };
  return { db, storage, auth, ctx };
}

async function approved(db, uid) {
  const c = { db, now };
  const token = { auth_time: Math.floor(T0 / 1000) - 30 };
  const r = await ad.requestOwn(c, uid, token, { confirm: true });
  const ref = r.result.reference;
  await ad.review(c, 'reviewer', { reference: ref, decision: 'APPROVE' });
  return ref;
}
const get = (db, path) => db.store.get(path);
const reqOf = (db, ref) => db.store.get(`accountDeletionRequests/${ref}`);

// ---- gating -------------------------------------------------------------

test('does nothing unless processing is explicitly enabled', async () => {
  const { db, ctx } = setup({ enabled: false });
  const ref = await approved(db, 'parent');
  assert.deepStrictEqual(await dp.processRequest(ctx, ref), { error: 'PROCESSING_DISABLED' });
  assert.ok(get(db, 'users/parent').email);
  assert.strictEqual(reqOf(db, ref).status, 'APPROVED');
  assert.deepStrictEqual(await dp.sweep(ctx), { skipped: true });
});

test('the flag reads the environment and is off by default', () => {
  assert.strictEqual(dp.enabled({}), false);
  assert.strictEqual(dp.enabled({ ACCOUNT_DELETION_PROCESSING_ENABLED: 'false' }), false);
  assert.strictEqual(dp.enabled({ ACCOUNT_DELETION_PROCESSING_ENABLED: 'TRUE' }), true);
});

test('only an approved (or interrupted) request is processed', async () => {
  const { db, ctx } = setup();
  const c = { db, now };
  const r = await ad.requestOwn(c, 'parent', { auth_time: Math.floor(T0 / 1000) - 30 }, { confirm: true });
  // still UNDER_REVIEW: Avail404 has not approved it
  assert.deepStrictEqual(await dp.processRequest(ctx, r.result.reference), { error: 'NOT_PROCESSABLE' });
  assert.deepStrictEqual(await dp.processRequest(ctx, 'DEL-AAAAAAAAAAAAAAAA'), { error: 'NOT_PROCESSABLE' });
  assert.ok(get(db, 'users/parent').email);
});

test('the only school admin is held and nothing is deleted', async () => {
  const { db, auth, ctx } = setup();
  const c = { db, now };
  const r = await ad.requestOwn(c, 'solo', { auth_time: Math.floor(T0 / 1000) - 30 }, { confirm: true });
  const ref = r.result.reference;
  // force it to APPROVED as if the school had had another admin at approval time
  db.store.set(`accountDeletionRequests/${ref}`, { ...reqOf(db, ref), status: 'APPROVED' });
  const out = await dp.processRequest(ctx, ref);
  assert.strictEqual(out.status, 'ACTION_REQUIRED');
  assert.strictEqual(out.reason, 'SOLE_ADMIN');
  assert.ok(auth.users.solo);
  assert.strictEqual(get(db, 'users/solo').status, 'ACTIVE');
});

test('a platform administrator is never processed', async () => {
  const { db, auth, ctx } = setup();
  db.store.set('accountDeletionRequests/DEL-BBBBBBBBBBBBBBBB', { status: 'APPROVED', uid: 'reviewer', history: [], source: 'APP' });
  const out = await dp.processRequest(ctx, 'DEL-BBBBBBBBBBBBBBBB');
  assert.strictEqual(out.reason, 'PLATFORM_ADMIN');
  assert.strictEqual(get(db, 'users/reviewer').role, 'PLATFORM_ADMIN');
  assert.strictEqual(Object.keys(auth.users).includes('reviewer'), false); // never in the fake; nothing touched
});

// ---- a parent -----------------------------------------------------------

test('a parent: login, profile, devices, inbox and guardian contact details are removed', async () => {
  const { db, storage, auth, ctx } = setup();
  const ref = await approved(db, 'parent');
  const out = await dp.processRequest(ctx, ref);
  assert.strictEqual(out.status, 'COMPLETED');

  // the login is gone, last
  assert.strictEqual(auth.users.parent, undefined);
  // the profile is a stub, not a person
  const stub = get(db, 'users/parent');
  assert.strictEqual(stub.deleted, true);
  assert.strictEqual(stub.status, 'DISABLED');
  assert.strictEqual(stub.name, 'Deleted user');
  for (const f of ['email', 'phone', 'photoUrl', 'login', 'linkedParentId']) assert.strictEqual(stub[f], null, f);
  assert.deepStrictEqual(stub.branchRoles, {});
  assert.strictEqual(stub.schoolId, 's1'); // kept so references stay valid
  // devices, preferences, read state
  assert.deepStrictEqual([...db.store.keys()].filter((k) => k.startsWith('users/parent/')), []);
  // only their own inbox
  assert.strictEqual(db.store.has(`${B1}/notifications/n1`), false);
  assert.ok(db.store.has(`${B1}/notifications/n2`));
  assert.ok(db.store.has(`${B1}/notifications/n3`));
  // guardian record: contact details gone, record and link kept
  const par = get(db, `${B1}/parents/par1`);
  assert.strictEqual(par.displayName, 'Deleted guardian');
  for (const f of ['email', 'photoUrl', 'occupation', 'addressLine1', 'city', 'linkedUserId']) assert.strictEqual(par[f], null, f);
  assert.strictEqual(par.phone, '');
  assert.strictEqual(db.store.has(`${B1}/parentAccess/par1`), false);
  assert.ok(!storage.files.has(`${B1}/parents/par1/photo.jpg`));
  // the request is closed and the account may no longer ask again
  const r = reqOf(db, ref);
  assert.strictEqual(r.status, 'COMPLETED');
  assert.strictEqual(r.contactEmail, null);
  assert.ok(!db.store.has('accountDeletionLocks/parent'));
});

test('a parent request never touches the child or other families', async () => {
  const { db, ctx } = setup();
  const before = structuredClone({
    kid: get(db, `${B1}/students/stu1`),
    par2: get(db, `${B1}/parents/par2`),
    other: get(db, 'users/other'),
    otherDevice: get(db, 'users/other/devices/d9'),
    access2: get(db, `${B1}/parentAccess/par2`),
  });
  await dp.processRequest(ctx, await approved(db, 'parent'));
  assert.deepStrictEqual(get(db, `${B1}/students/stu1`), before.kid);
  assert.deepStrictEqual(get(db, `${B1}/parents/par2`), before.par2);
  assert.deepStrictEqual(get(db, 'users/other'), before.other);
  assert.deepStrictEqual(get(db, 'users/other/devices/d9'), before.otherDevice);
  assert.deepStrictEqual(get(db, `${B1}/parentAccess/par2`), before.access2);
  assert.ok(db.store.has(`${B1}/leaveApplications/l2`));
});

test('their messages keep the text but lose the name, the participant id and attachments', async () => {
  const { db, storage, ctx } = setup();
  await dp.processRequest(ctx, await approved(db, 'parent'));
  const token = dp.tokenFor(KEY, 'parent');
  const m1 = get(db, `${B1}/conversations/c1/messages/m1`);
  assert.strictEqual(m1.senderUserId, token);
  assert.strictEqual(m1.senderName, 'Deleted user');
  assert.strictEqual(m1.body, 'hello');
  assert.deepStrictEqual(m1.attachments, []);
  assert.ok(!storage.files.has(`${B1}/conversations/c1/files/f.png`));
  const c1 = get(db, `${B1}/conversations/c1`);
  assert.deepStrictEqual(c1.participants, [token, 'teacher']);
  assert.strictEqual(c1.parentUserId, token);
  assert.strictEqual(c1.parentName, 'Deleted user');
  // the other person's side is intact
  const m2 = get(db, `${B1}/conversations/c1/messages/m2`);
  assert.strictEqual(m2.senderName, 'Tia Teacher');
  assert.ok(storage.files.has(`${B1}/conversations/c1/files/g.png`));
  assert.strictEqual(c1.teacherName, 'Tia Teacher');
});

// ---- a teacher ----------------------------------------------------------

test('a teacher: login unlinked, optional details gone, employment facts and HR documents kept', async () => {
  const { db, storage, ctx } = setup();
  const out = await dp.processRequest(ctx, await approved(db, 'teacher'));
  assert.strictEqual(out.status, 'COMPLETED');
  const st = get(db, `${B1}/staff/st1`);
  assert.strictEqual(st.userId, null);
  for (const f of ['photoUrl', 'bloodGroup', 'alternatePhone', 'address', 'city', 'state', 'country', 'postalCode']) {
    assert.strictEqual(st[f], null, f);
  }
  // employment facts remain until the school confirms (matrix B2, D5)
  for (const f of ['employeeCode', 'joiningDate', 'departmentId', 'firstName', 'lastName', 'phone', 'email']) {
    assert.ok(st[f], f);
  }
  assert.ok(!storage.files.has(`${B1}/staff/st1/photo.jpg`));
  assert.ok(storage.files.has(`${B1}/staff/st1/documents/d1/contract.pdf`), 'HR documents are the school\'s');
  assert.strictEqual(db.store.has(`${B1}/teacherAccess/teacher`), false);
  assert.ok(db.store.has(`${B1}/teacherAccess/other`));
});

test('leave: the reason and attachments are removed, dates and the decision stay', async () => {
  const { db, storage, ctx } = setup();
  await dp.processRequest(ctx, await approved(db, 'teacher'));
  const token = dp.tokenFor(KEY, 'teacher');
  const l1 = get(db, `${B1}/leaveApplications/l1`);
  assert.strictEqual(l1.reason, null);
  assert.deepStrictEqual(l1.attachments, []);
  assert.strictEqual(l1.applicantUserId, token);
  assert.strictEqual(l1.applicantName, 'Deleted user');
  assert.strictEqual(l1.startDateKey, '2026-10-01');
  assert.strictEqual(l1.status, 'APPROVED');
  assert.strictEqual(l1.decidedByName, 'Admin A');
  assert.ok(!storage.files.has(`${B1}/leaveDocs/teacher/l1/note.pdf`));
  // someone else's leave is untouched, but a decision this teacher made is anonymised
  const l2 = get(db, `${B1}/leaveApplications/l2`);
  assert.strictEqual(l2.reason, 'fever');
  assert.strictEqual(l2.applicantName, 'Olly Other');
  assert.ok(storage.files.has(`${B1}/leaveDocs/other/l2/x.pdf`));
  assert.strictEqual(l2.decidedBy, token);
  assert.strictEqual(l2.decidedByName, 'Deleted user');
});

test('authored records get the non-identifying token in every branch, other people\'s do not', async () => {
  const { db, ctx } = setup();
  await dp.processRequest(ctx, await approved(db, 'teacher'));
  const token = dp.tokenFor(KEY, 'teacher');
  assert.ok(token.startsWith('deleted:') && !token.includes('teacher'));
  const hw1 = get(db, `${B1}/homework/hw1`);
  assert.deepStrictEqual([hw1.createdBy, hw1.publishedBy, hw1.createdByName], [token, token, 'Deleted user']);
  assert.strictEqual(get(db, `${B2}/homework/hw2`).createdBy, token);
  assert.strictEqual(get(db, `${B2}/homework/hw2`).updatedBy, token);
  assert.strictEqual(get(db, `${B1}/homework/hw3`).createdBy, 'adminA');
  // the child's own record: only the audit uid changes, never the child's data
  const kid = get(db, `${B1}/students/stu1`);
  assert.strictEqual(kid.createdBy, token);
  assert.strictEqual(kid.updatedBy, 'adminA');
  assert.deepStrictEqual([kid.firstName, kid.lastName, kid.dateOfBirth], ['Kid', 'Student', '2015']);
  // nested history and school-level audit
  assert.strictEqual(get(db, `${B1}/studentAttendance/a1/history/h1`).changedBy, token);
  assert.strictEqual(get(db, `${B1}/studentAttendance/a1/history/h1`).changedByName, 'Deleted user');
  assert.strictEqual(get(db, `${S}/authAudit/e2`).actorId, token);
  assert.strictEqual(get(db, `${S}/authAudit/e1`).actorId, 'adminA');
});

test('the token is stable per person, different between people, and keyed', () => {
  assert.strictEqual(dp.tokenFor('k', 'u1'), dp.tokenFor('k', 'u1'));
  assert.notStrictEqual(dp.tokenFor('k', 'u1'), dp.tokenFor('k', 'u2'));
  assert.notStrictEqual(dp.tokenFor('k', 'u1'), dp.tokenFor('other-key', 'u1'));
});

test('financial records are retained exactly as they were', async () => {
  const { db, ctx } = setup();
  const before = structuredClone({
    payment: get(db, `${B1}/payments/p1`),
    invoice: get(db, `${B1}/invoices/i1`),
    audit: get(db, `${B1}/financialAuditLogs/f1`),
  });
  await dp.processRequest(ctx, await approved(db, 'teacher'));
  assert.deepStrictEqual(get(db, `${B1}/payments/p1`), before.payment);
  assert.deepStrictEqual(get(db, `${B1}/invoices/i1`), before.invoice);
  assert.deepStrictEqual(get(db, `${B1}/financialAuditLogs/f1`), before.audit);
});

test('no personal identifier of the person is left in non-financial records', async () => {
  const { db, ctx } = setup();
  await dp.processRequest(ctx, await approved(db, 'teacher'));
  const financial = new RegExp(`/(${dp.FINANCIAL.join('|')})/`);
  const leftovers = [...db.store.entries()]
    .filter(([k]) => !financial.test(k) && !k.startsWith('accountDeletion') && !k.startsWith('users/teacher'))
    .filter(([, v]) => JSON.stringify(v).includes('"teacher"'))
    .map(([k]) => k);
  // the only mentions left are other people's docs that mention the id as a map key / the staff
  // record's own id; list them so a regression is visible
  assert.deepStrictEqual(leftovers.sort(), []);
});

// ---- resilience ----------------------------------------------------------

test('a failing last step leaves the request retryable and a rerun finishes it', async () => {
  const { db, auth, ctx } = setup();
  const ref = await approved(db, 'parent');
  const real = auth.deleteUser;
  let failures = 1;
  auth.deleteUser = async (uid) => {
    if (failures-- > 0) throw new Error('boom');
    return real(uid);
  };
  const first = await dp.processRequest(ctx, ref);
  assert.strictEqual(first.status, 'FAILED_RETRYABLE');
  assert.ok(reqOf(db, ref).progress.done.includes('PROFILE'));
  assert.ok(!reqOf(db, ref).progress.done.includes('AUTH'));
  assert.ok(auth.users.parent, 'the login was not removed yet');
  const second = await dp.processRequest(ctx, ref);
  assert.strictEqual(second.status, 'COMPLETED');
  assert.strictEqual(auth.users.parent, undefined);
  assert.strictEqual(reqOf(db, ref).status, 'COMPLETED');
});

test('running out of time stops cleanly, saves its place and resumes', async () => {
  const { db, ctx } = setup();
  const ref = await approved(db, 'teacher');
  const first = await dp.processRequest({ ...ctx, deadline: Date.now() - 1 }, ref);
  assert.strictEqual(first.status, 'FAILED_RETRYABLE');
  assert.strictEqual(first.outOfTime, true);
  assert.ok(get(db, 'users/teacher').email, 'nothing destructive happened before the first step');
  const done = await dp.processRequest(ctx, ref);
  assert.strictEqual(done.status, 'COMPLETED');
});

test('a completed request cannot be processed again', async () => {
  const { db, ctx } = setup();
  const ref = await approved(db, 'parent');
  await dp.processRequest(ctx, ref);
  assert.deepStrictEqual(await dp.processRequest(ctx, ref), { error: 'NOT_PROCESSABLE' });
});

test('a login that is already gone does not stop the deletion', async () => {
  const { db, auth, ctx } = setup();
  const ref = await approved(db, 'parent');
  delete auth.users.parent;
  assert.strictEqual((await dp.processRequest(ctx, ref)).status, 'COMPLETED');
});

test('an interrupted run is picked up by the sweep, and the sweep is bounded', async () => {
  const { db, ctx } = setup();
  const a = await approved(db, 'parent');
  const b = await approved(db, 'teacher');
  const r = await dp.sweep(ctx, 1);
  assert.strictEqual(r.results.length, 1);
  const r2 = await dp.sweep(ctx, 5);
  const statuses = [a, b].map((x) => reqOf(db, x).status);
  assert.deepStrictEqual(statuses, ['COMPLETED', 'COMPLETED']);
  assert.ok(r2.results.length >= 1);
});

test('only the stored account is processed: a client-style uid in the request body changes nothing', async () => {
  const { db, ctx } = setup();
  const ref = await approved(db, 'parent');
  db.store.set(`accountDeletionRequests/${ref}`, { ...reqOf(db, ref), requestedUid: 'teacher', schoolId: 'someone-else' });
  await dp.processRequest(ctx, ref);
  assert.ok(get(db, 'users/teacher').email);
  assert.ok(db.store.has(`${B1}/staff/st1`));
  assert.strictEqual(get(db, `${B1}/staff/st1`).userId, 'teacher');
});

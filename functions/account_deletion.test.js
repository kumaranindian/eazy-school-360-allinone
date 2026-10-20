'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb, fakeAuth } = require('./test_support');
const ad = require('./account_deletion');

const T0 = Date.UTC(2026, 9, 19, 10, 0, 0);
let clock = 0;
const now = () => new Date(T0 + clock);
const secs = (offsetMs = 0) => Math.floor((T0 + clock + offsetMs) / 1000);
const fresh = () => ({ auth_time: secs(-30 * 1000) });

const users = () => ({
  'users/parent': { schoolId: 's1', branchId: 'b1', role: 'PARENT', status: 'ACTIVE' },
  'users/other': { schoolId: 's2', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE' },
  'users/adminA': { schoolId: 's1', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
  'users/adminB': { schoolId: 's1', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
  'users/solo': { schoolId: 's3', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
  'users/soloWithDisabled': { schoolId: 's4', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
  'users/disabledAdmin': { schoolId: 's4', role: 'SCHOOL_ADMIN', status: 'DISABLED' },
  'users/platform': { role: 'PLATFORM_ADMIN', status: 'ACTIVE' },
  'users/reviewer': { role: 'PLATFORM_ADMIN', status: 'ACTIVE' },
  'users/schoolAdminFake': { schoolId: 's9', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
});
const mk = (seed = users()) => {
  clock = 0;
  const db = fakeDb(seed);
  return { db, ctx: { db, now } };
};
const requests = (db) => [...db.store.keys()].filter((k) => k.startsWith('accountDeletionRequests/'));
const get = (db, ref) => db.store.get(`accountDeletionRequests/${ref}`);

// ---- signed-in request ----------------------------------------------------

test('a signed-in user requests deletion of their own account and gets a reference', async () => {
  const { db, ctx } = mk();
  const r = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  assert.match(r.result.reference, /^DEL-[A-Z2-7]{16}$/);
  assert.strictEqual(r.result.status, 'UNDER_REVIEW');
  const doc = get(db, r.result.reference);
  assert.strictEqual(doc.uid, 'parent');
  assert.strictEqual(doc.schoolId, 's1');
  assert.strictEqual(doc.role, 'PARENT');
  // a status record carries ids and a role, not a name, e-mail or phone
  assert.deepStrictEqual(Object.keys(doc).filter((k) => /email|phone|name/i.test(k)), []);
});

test('the account comes from the verified token, never from the request body', async () => {
  const { db, ctx } = mk();
  const r = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true, uid: 'adminA', schoolId: 's2', role: 'SCHOOL_ADMIN' });
  const doc = get(db, r.result.reference);
  assert.strictEqual(doc.uid, 'parent');
  assert.strictEqual(doc.schoolId, 's1');
  assert.strictEqual(doc.role, 'PARENT');
  assert.ok(!db.store.has('accountDeletionLocks/adminA'));
});

test('the request must be explicitly confirmed', async () => {
  const { db, ctx } = mk();
  for (const body of [{}, { confirm: 'true' }, { confirm: 1 }, null]) {
    assert.strictEqual((await ad.requestOwn(ctx, 'parent', fresh(), body)).error, 'INVALID_ARGUMENT');
  }
  assert.strictEqual(requests(db).length, 0);
});

test('a stale sign-in must re-authenticate first', async () => {
  const { db, ctx } = mk();
  const stale = { auth_time: secs(-6 * 60 * 1000) };
  assert.strictEqual((await ad.requestOwn(ctx, 'parent', stale, { confirm: true })).error, 'REAUTH_REQUIRED');
  assert.strictEqual((await ad.requestOwn(ctx, 'parent', {}, { confirm: true })).error, 'REAUTH_REQUIRED');
  assert.strictEqual(requests(db).length, 0);
});

test('repeating the request returns the same open request instead of a second one', async () => {
  const { db, ctx } = mk();
  const a = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  const b = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  assert.strictEqual(b.duplicate, true);
  assert.strictEqual(b.result.reference, a.result.reference);
  assert.strictEqual(requests(db).length, 1);
});

test('two simultaneous taps still create exactly one request', async () => {
  const { db, ctx } = mk();
  const rs = await Promise.all([1, 2, 3].map(() => ad.requestOwn(ctx, 'parent', fresh(), { confirm: true })));
  assert.strictEqual(requests(db).length, 1);
  assert.strictEqual(new Set(rs.map((r) => r.result.reference)).size, 1);
});

test('a platform administrator cannot use the self-service request', async () => {
  const { db, ctx } = mk();
  assert.strictEqual((await ad.requestOwn(ctx, 'platform', fresh(), { confirm: true })).error, 'PLATFORM_ADMIN');
  assert.strictEqual(requests(db).length, 0);
});

test('the only active school admin is held for action, never auto-processed', async () => {
  const { ctx } = mk();
  const r = await ad.requestOwn(ctx, 'solo', fresh(), { confirm: true });
  assert.strictEqual(r.result.status, 'ACTION_REQUIRED');
  assert.strictEqual(r.result.reason, 'SOLE_ADMIN');
});

test('a disabled second admin does not count as another administrator', async () => {
  const { ctx } = mk();
  const r = await ad.requestOwn(ctx, 'soloWithDisabled', fresh(), { confirm: true });
  assert.strictEqual(r.result.status, 'ACTION_REQUIRED');
});

test('an admin who is not the only one is queued for review', async () => {
  const { ctx } = mk();
  const r = await ad.requestOwn(ctx, 'adminA', fresh(), { confirm: true });
  assert.strictEqual(r.result.status, 'UNDER_REVIEW');
});

test('a user sees only their own requests', async () => {
  const { ctx } = mk();
  await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  await ad.requestOwn(ctx, 'other', fresh(), { confirm: true });
  const mine = await ad.listOwn(ctx, 'parent');
  assert.strictEqual(mine.result.length, 1);
  assert.strictEqual((await ad.listOwn(ctx, 'adminA')).result.length, 0);
});

test('cancelling: only your own request, and only before approval', async () => {
  const { db, ctx } = mk();
  const a = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  const ref = a.result.reference;
  // someone else's reference is indistinguishable from a missing one
  assert.strictEqual((await ad.cancelOwn(ctx, 'other', { reference: ref })).error, 'NOT_FOUND');
  assert.strictEqual((await ad.cancelOwn(ctx, 'parent', { reference: 'junk' })).error, 'INVALID_ARGUMENT');
  const c = await ad.cancelOwn(ctx, 'parent', { reference: ref });
  assert.strictEqual(c.result.status, 'CANCELLED');
  assert.ok(!db.store.has('accountDeletionLocks/parent'));
  // a new request is possible again
  const again = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  assert.notStrictEqual(again.result.reference, ref);
  // once approved it can no longer be withdrawn here
  const doc = get(db, again.result.reference);
  db.store.set(`accountDeletionRequests/${again.result.reference}`, { ...doc, status: 'APPROVED' });
  assert.strictEqual((await ad.cancelOwn(ctx, 'parent', { reference: again.result.reference })).error, 'NOT_CANCELLABLE');
});

// ---- public form ----------------------------------------------------------

const form = (over = {}) => ({ email: 'Parent@Example.com', schoolName: 'Sunrise', role: 'PARENT', ...over });

test('the public form stores a pending request with the normalised address', async () => {
  const { db, ctx } = mk();
  const r = await ad.requestPublic(ctx, form(), '1.2.3.4');
  assert.strictEqual(r.result.status, 'PENDING_VERIFICATION');
  const doc = get(db, r.result.reference);
  assert.strictEqual(doc.contactEmail, 'parent@example.com');
  assert.strictEqual(doc.uid, null);
  assert.ok(doc.expireAt > now());
});

test('registered and unknown addresses get the same answer shape (no enumeration)', async () => {
  const { ctx } = mk();
  const known = await ad.requestPublic(ctx, form({ email: 'known@example.com' }), '1.1.1.1');
  const unknown = await ad.requestPublic(ctx, form({ email: 'nobody@example.com' }), '1.1.1.2');
  assert.deepStrictEqual(Object.keys(known.result).sort(), Object.keys(unknown.result).sort());
  assert.strictEqual(known.result.status, unknown.result.status);
  assert.notStrictEqual(known.result.reference, unknown.result.reference);
});

test('submitting the same address twice never hands back the first reference', async () => {
  const { ctx } = mk();
  const a = await ad.requestPublic(ctx, form(), '1.1.1.1');
  const b = await ad.requestPublic(ctx, form(), '1.1.1.1');
  assert.notStrictEqual(a.result.reference, b.result.reference);
});

test('invalid input is refused', async () => {
  const { db, ctx } = mk();
  for (const email of ['', 'x', 'a@b', 'a b@c.com', `${'a'.repeat(300)}@x.com`, 42, null]) {
    assert.strictEqual((await ad.requestPublic(ctx, { email }, 'ip')).error, 'INVALID_ARGUMENT', String(email));
  }
  assert.strictEqual((await ad.requestPublic(ctx, null, 'ip')).error, 'INVALID_ARGUMENT');
  assert.strictEqual(requests(db).length, 0);
});

test('free-text fields are trimmed and unknown roles collapse to OTHER', async () => {
  const { db, ctx } = mk();
  const r = await ad.requestPublic(ctx, form({ schoolName: ` ${'x'.repeat(500)} `, role: 'GOD' }), 'ip');
  const doc = get(db, r.result.reference);
  assert.strictEqual(doc.claimedSchool.length, 100);
  assert.strictEqual(doc.claimedRole, 'OTHER');
});

test('a filled honeypot looks accepted but stores nothing', async () => {
  const { db, ctx } = mk();
  const r = await ad.requestPublic(ctx, form({ website: 'http://spam' }), 'ip');
  assert.strictEqual(r.result.status, 'PENDING_VERIFICATION');
  assert.strictEqual(requests(db).length, 0);
});

test('one address is limited to three submissions an hour, then freed', async () => {
  const { ctx } = mk();
  for (let i = 0; i < 3; i++) assert.ok((await ad.requestPublic(ctx, form(), `ip${i}`)).result);
  const limited = await ad.requestPublic(ctx, form(), 'ipX');
  assert.strictEqual(limited.error, 'RATE_LIMITED');
  assert.ok(limited.retryAfterSec > 0);
  clock += 61 * 60 * 1000;
  assert.ok((await ad.requestPublic(ctx, form(), 'ipY')).result);
});

test('one network address is limited across different e-mail addresses', async () => {
  const { ctx } = mk();
  for (let i = 0; i < 10; i++) assert.ok((await ad.requestPublic(ctx, form({ email: `u${i}@example.com` }), '9.9.9.9')).result);
  assert.strictEqual((await ad.requestPublic(ctx, form({ email: 'u99@example.com' }), '9.9.9.9')).error, 'RATE_LIMITED');
  assert.ok((await ad.requestPublic(ctx, form({ email: 'u98@example.com' }), '8.8.8.8')).result);
});

test('rate-limit records hold hashes, never the address or the IP', async () => {
  const { db, ctx } = mk();
  await ad.requestPublic(ctx, form(), '4.4.4.4');
  const keys = [...db.store.keys()].filter((k) => k.startsWith('accountDeletionRate/')).join(' ');
  assert.ok(!/example|parent|4\.4\.4\.4/i.test(keys));
});

// ---- e-mail link confirmation --------------------------------------------

async function submitted(email = 'parent@example.com') {
  const m = mk();
  const r = await ad.requestPublic(m.ctx, form({ email }), 'ip');
  return { ...m, reference: r.result.reference };
}
const linkToken = (over = {}) => ({ email: 'parent@example.com', email_verified: true, auth_time: secs(-60 * 1000), ...over });

test('confirming with the verified address moves the request to review and drops the address', async () => {
  const { db, ctx, reference } = await submitted();
  const r = await ad.confirmPublic(ctx, 'parent', linkToken(), { reference }, fakeAuth());
  assert.strictEqual(r.result.status, 'UNDER_REVIEW');
  const doc = get(db, reference);
  assert.strictEqual(doc.uid, 'parent');
  assert.strictEqual(doc.schoolId, 's1');
  assert.strictEqual(doc.contactEmail, null);
  assert.strictEqual(doc.claimedSchool, 'Sunrise');
  assert.strictEqual(db.store.get('accountDeletionLocks/parent').reference, reference);
});

test('a different, unverified or stale e-mail sign-in is refused and the request stays pending', async () => {
  for (const bad of [
    linkToken({ email: 'attacker@example.com' }),
    linkToken({ email_verified: false }),
    linkToken({ email_verified: undefined }),
    linkToken({ email: undefined }),
    linkToken({ auth_time: secs(-20 * 60 * 1000) }),
  ]) {
    const { db, ctx, reference } = await submitted();
    const r = await ad.confirmPublic(ctx, 'parent', bad, { reference }, fakeAuth());
    assert.ok(['VERIFICATION_FAILED', 'REAUTH_REQUIRED'].includes(r.error), JSON.stringify(bad));
    assert.strictEqual(get(db, reference).status, 'PENDING_VERIFICATION');
    assert.ok(!db.store.has('accountDeletionLocks/parent'));
  }
});

test('knowing a reference is not enough: another signed-in user cannot confirm it', async () => {
  const { db, ctx, reference } = await submitted();
  const r = await ad.confirmPublic(ctx, 'other', linkToken({ email: 'other@example.com' }), { reference }, fakeAuth());
  assert.strictEqual(r.error, 'VERIFICATION_FAILED');
  assert.strictEqual(get(db, reference).status, 'PENDING_VERIFICATION');
});

test('an expired pending request cannot be confirmed', async () => {
  const { ctx, reference } = await submitted();
  clock += 25 * 60 * 60 * 1000;
  const t = linkToken({ auth_time: secs(-60 * 1000) });
  assert.strictEqual((await ad.confirmPublic(ctx, 'parent', t, { reference }, fakeAuth())).error, 'EXPIRED');
});

test('an unknown or malformed reference is refused', async () => {
  const { ctx } = mk();
  assert.strictEqual((await ad.confirmPublic(ctx, 'parent', linkToken(), { reference: 'nope' }, fakeAuth())).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await ad.confirmPublic(ctx, 'parent', linkToken(), { reference: 'DEL-AAAAAAAAAAAAAAAA' }, fakeAuth())).error, 'NOT_FOUND');
});

test('an address with no account is rejected and the login the link created is removed', async () => {
  const { db, ctx, reference } = await submitted('ghost@example.com');
  const auth = fakeAuth();
  const created = await auth.createUser({ email: 'ghost@example.com' });
  auth.users[created.uid].metadata = { creationTime: new Date(T0 + 1000).toUTCString() };
  const r = await ad.confirmPublic(ctx, created.uid, linkToken({ email: 'ghost@example.com' }), { reference }, auth);
  assert.strictEqual(r.result.status, 'REJECTED');
  assert.strictEqual(r.result.reason, 'NO_ACCOUNT');
  assert.strictEqual(auth.users[created.uid], undefined);
  assert.strictEqual(get(db, reference).contactEmail, null);
});

test('an old login without a profile is NOT deleted by this path', async () => {
  const { ctx, reference } = await submitted('old@example.com');
  const auth = fakeAuth();
  const created = await auth.createUser({ email: 'old@example.com' });
  auth.users[created.uid].metadata = { creationTime: new Date(T0 - 86400000 * 30).toUTCString() };
  await ad.confirmPublic(ctx, created.uid, linkToken({ email: 'old@example.com' }), { reference }, auth);
  assert.ok(auth.users[created.uid]);
});

test('confirming twice is harmless', async () => {
  const { db, ctx, reference } = await submitted();
  await ad.confirmPublic(ctx, 'parent', linkToken(), { reference }, fakeAuth());
  const again = await ad.confirmPublic(ctx, 'parent', linkToken(), { reference }, fakeAuth());
  assert.strictEqual(again.result.status, 'UNDER_REVIEW');
  assert.strictEqual(requests(db).length, 1);
});

test('web confirmation of an account that already has an open request points at the original', async () => {
  const { db, ctx } = mk();
  const first = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  const sub = await ad.requestPublic(ctx, form(), 'ip');
  const r = await ad.confirmPublic(ctx, 'parent', linkToken(), { reference: sub.result.reference }, fakeAuth());
  assert.strictEqual(r.duplicate, true);
  assert.strictEqual(r.result.reference, first.result.reference);
  assert.strictEqual(get(db, sub.result.reference).status, 'REJECTED');
  assert.strictEqual(get(db, sub.result.reference).reason, 'DUPLICATE');
});

test('web confirmation by a sole admin is held; by a platform admin is refused', async () => {
  const a = await submitted('solo@example.com');
  const solo = await ad.confirmPublic(a.ctx, 'solo', linkToken({ email: 'solo@example.com' }), { reference: a.reference }, fakeAuth());
  assert.strictEqual(solo.result.status, 'ACTION_REQUIRED');
  const b = await submitted('platform@example.com');
  const plat = await ad.confirmPublic(b.ctx, 'platform', linkToken({ email: 'platform@example.com' }), { reference: b.reference }, fakeAuth());
  assert.strictEqual(plat.result.status, 'REJECTED');
  assert.strictEqual(plat.result.reason, 'PLATFORM_ADMIN');
});

test('public status shows the category only', async () => {
  const { ctx, reference } = await submitted();
  const s = await ad.statusPublic(ctx, { reference });
  assert.deepStrictEqual(Object.keys(s.result).sort(), ['reference', 'status', 'updatedAt']);
  assert.strictEqual((await ad.statusPublic(ctx, { reference: 'DEL-AAAAAAAAAAAAAAAA' })).error, 'NOT_FOUND');
  assert.strictEqual((await ad.statusPublic(ctx, { reference: '../users/parent' })).error, 'INVALID_ARGUMENT');
});

test('unverified requests lapse after a day and lose the address', async () => {
  const { db, ctx, reference } = await submitted();
  assert.strictEqual(await ad.expireUnverified(ctx), 0);
  clock += 25 * 60 * 60 * 1000;
  assert.strictEqual(await ad.expireUnverified(ctx), 1);
  assert.strictEqual(get(db, reference).status, 'EXPIRED');
  assert.strictEqual(get(db, reference).contactEmail, null);
});

// ---- Avail404 review ------------------------------------------------------

test('only an active platform administrator can review', async () => {
  const { ctx } = mk();
  const a = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  const ref = a.result.reference;
  for (const who of ['parent', 'adminA', 'other', 'nobody']) {
    assert.strictEqual((await ad.review(ctx, who, { reference: ref, decision: 'APPROVE' })).error, 'PERMISSION_DENIED', who);
  }
  const ok = await ad.review(ctx, 'reviewer', { reference: ref, decision: 'APPROVE' });
  assert.strictEqual(ok.result.status, 'APPROVED');
});

test('a client cannot become a reviewer by claiming a role', async () => {
  const { ctx } = mk();
  const a = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  const r = await ad.review(ctx, 'schoolAdminFake', { reference: a.result.reference, decision: 'APPROVE', role: 'PLATFORM_ADMIN' });
  assert.strictEqual(r.error, 'PERMISSION_DENIED');
});

test('nobody approves their own deletion request', async () => {
  const { db, ctx } = mk();
  const a = await ad.requestOwn(ctx, 'platform', fresh(), { confirm: true });
  assert.strictEqual(a.error, 'PLATFORM_ADMIN');
  // a reviewer who somehow has an open request of their own still cannot approve it
  db.store.set('accountDeletionRequests/DEL-AAAAAAAAAAAAAAAA', { status: 'UNDER_REVIEW', uid: 'reviewer', history: [] });
  const r = await ad.review(ctx, 'reviewer', { reference: 'DEL-AAAAAAAAAAAAAAAA', decision: 'APPROVE' });
  assert.strictEqual(r.error, 'PERMISSION_DENIED');
});

test('approval re-checks the sole-admin rule at the moment of approval', async () => {
  const { db, ctx } = mk();
  const a = await ad.requestOwn(ctx, 'adminA', fresh(), { confirm: true });
  assert.strictEqual(a.result.status, 'UNDER_REVIEW');
  db.store.set('users/adminB', { ...db.store.get('users/adminB'), status: 'DISABLED' });
  const r = await ad.review(ctx, 'reviewer', { reference: a.result.reference, decision: 'APPROVE' });
  assert.strictEqual(r.result.status, 'ACTION_REQUIRED');
  assert.strictEqual(r.result.reason, 'SOLE_ADMIN');
});

test('a held request can be reopened once the school has another admin', async () => {
  const { db, ctx } = mk();
  const a = await ad.requestOwn(ctx, 'solo', fresh(), { confirm: true });
  assert.strictEqual(a.result.status, 'ACTION_REQUIRED');
  const still = await ad.review(ctx, 'reviewer', { reference: a.result.reference, decision: 'REOPEN' });
  assert.strictEqual(still.result.status, 'ACTION_REQUIRED');
  db.store.set('users/newAdmin', { schoolId: 's3', role: 'SCHOOL_ADMIN', status: 'ACTIVE' });
  const ok = await ad.review(ctx, 'reviewer', { reference: a.result.reference, decision: 'REOPEN' });
  assert.strictEqual(ok.result.status, 'UNDER_REVIEW');
  assert.strictEqual(ok.result.reason, null);
});

test('terminal requests cannot be revived, and rejecting frees the account to ask again', async () => {
  const { db, ctx } = mk();
  const a = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  const ref = a.result.reference;
  const rej = await ad.review(ctx, 'reviewer', { reference: ref, decision: 'REJECT', reasonCode: 'DECLINED' });
  assert.strictEqual(rej.result.status, 'REJECTED');
  assert.ok(!db.store.has('accountDeletionLocks/parent'));
  assert.strictEqual((await ad.review(ctx, 'reviewer', { reference: ref, decision: 'APPROVE' })).error, 'INVALID_TRANSITION');
  assert.strictEqual((await ad.review(ctx, 'reviewer', { reference: ref, decision: 'EXPLODE' })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await ad.review(ctx, 'reviewer', { reference: 'DEL-AAAAAAAAAAAAAAAA', decision: 'APPROVE' })).error, 'NOT_FOUND');
  assert.ok((await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true })).result);
});

test('history records every transition and is bounded', async () => {
  const { db, ctx } = mk();
  const a = await ad.requestOwn(ctx, 'parent', fresh(), { confirm: true });
  await ad.review(ctx, 'reviewer', { reference: a.result.reference, decision: 'APPROVE' });
  const h = get(db, a.result.reference).history.map((e) => e.status);
  assert.deepStrictEqual(h, ['UNDER_REVIEW', 'APPROVED']);
});

test('the lifecycle table has no way out of a terminal state and no destructive shortcut', () => {
  for (const s of ad.TERMINAL) assert.deepStrictEqual(ad.TRANSITIONS[s], []);
  // nothing can jump straight to COMPLETED/PROCESSING from review
  assert.ok(!ad.TRANSITIONS.UNDER_REVIEW.includes('PROCESSING'));
  assert.ok(!ad.TRANSITIONS.UNDER_REVIEW.includes('COMPLETED'));
  assert.ok(!ad.TRANSITIONS.PENDING_VERIFICATION.includes('APPROVED'));
});

test('references are unguessable and well-formed', () => {
  const seen = new Set(Array.from({ length: 500 }, () => ad.newReference()));
  assert.strictEqual(seen.size, 500);
  for (const r of seen) assert.match(r, /^DEL-[A-Z2-7]{16}$/);
});

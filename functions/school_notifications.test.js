'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const N = require('./school_notifications');
const L = require('./school_lifecycle');

const PW = { firebase: { sign_in_provider: 'password' } };
const ctxOf = (db) => ({ db, now: 'NOW', nowDate: () => new Date(1700000000000) });
const OWNER = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };

function world(extra = {}) {
  return fakeDb({
    'schools/s1': { name: 'S1', status: 'INACTIVE', lifecycleVersion: 1 },
    'schools/s2': { name: 'S2', status: 'ACTIVE' },
    'users/owner': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'OWNER', schoolId: null },
    'users/a1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1', schoolAccess: 'INACTIVE' },
    'users/a2': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1', schoolAccess: 'INACTIVE' },
    'users/gone': { role: 'SCHOOL_ADMIN', status: 'DISABLED', schoolId: 's1' },
    'users/t1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1' },
    'users/b1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's2' },
    ...extra,
  });
}
const all = async (db) => (await db.collection('platformNotifications').get()).docs.map((d) => ({ id: d.id, ...d.data() }));

test('activation notifies every active school admin once, with the owner message and no internal text', async () => {
  const db = world();
  const out = await L.transitionSchool(ctxOf(db), 'owner', OWNER, {
    schoolId: 's1', to: 'ACTIVE', remarks: 'verified', internalNotes: 'SECRET NOTE', message: 'Welcome aboard', idempotencyKey: 'k1',
  });
  assert.equal(out.ok, true);
  assert.deepEqual(out.notified, { created: 2, recipients: 2 });
  const rows = await all(db);
  assert.deepEqual(rows.map((r) => r.recipientUserId).sort(), ['a1', 'a2']);
  for (const r of rows) {
    assert.equal(r.schoolId, 's1');
    assert.equal(r.type, 'SCHOOL_ACTIVATED');
    assert.equal(r.state, 'CREATED');
    assert.ok(r.body.includes('Welcome aboard'));
    assert.ok(!JSON.stringify(r).includes('SECRET NOTE'));
    assert.ok(!JSON.stringify(r).includes('verified'));
  }
});

test('a retried change does not duplicate notifications; a fresh change creates new ones', async () => {
  const db = world();
  const c = ctxOf(db);
  await L.transitionSchool(c, 'owner', OWNER, { schoolId: 's1', to: 'ACTIVE', idempotencyKey: 'k1' });
  await L.transitionSchool(c, 'owner', OWNER, { schoolId: 's1', to: 'ACTIVE', idempotencyKey: 'k1' });
  const first = await all(db);
  assert.equal(first.length, 2);
  await N.notifySchoolAdmins(c, { schoolId: 's1', sourceEventId: first[0].sourceEventId, type: 'X', title: 't', body: 'b' });
  assert.equal((await all(db)).length, 2, 'same source event never duplicates');
  await L.transitionSchool(c, 'owner', OWNER, { schoolId: 's1', to: 'SUSPENDED', reason: 'Unpaid for three months', idempotencyKey: 'k2' });
  const rows = await all(db);
  assert.equal(rows.length, 4);
  const susp = rows.filter((r) => r.type === 'SCHOOL_SUSPENDED');
  assert.equal(susp.length, 2);
  assert.ok(susp.every((r) => r.severity === 'CRITICAL' && !r.body.includes('Unpaid')), 'the internal reason is not exposed');
});

test('every lifecycle event has school-facing copy; the support address is the fixed one', () => {
  for (const rule of Object.values(L.TRANSITIONS)) {
    const n = N.lifecycleNotification(rule.event, '');
    assert.ok(n && n.title && n.body, rule.event);
  }
  assert.equal(N.lifecycleNotification('SOMETHING_ELSE'), null);
  assert.ok(N.lifecycleNotification('SCHOOL_SUSPENDED').body.includes('admin@avail404.com'));
});

test('a notification failure never undoes the change', async () => {
  const db = world();
  const real = db.collection.bind(db);
  db.collection = (p) => {
    if (p === 'platformNotifications') throw new Error('boom');
    return real(p);
  };
  const out = await L.transitionSchool(ctxOf(db), 'owner', OWNER, { schoolId: 's1', to: 'ACTIVE' });
  assert.equal(out.ok, true);
  assert.deepEqual(out.notified, { failed: true });
  assert.equal((await real('schools').doc('s1').get()).data().status, 'ACTIVE');
});

test('list: only my own, first sight marks DELIVERED, newest first, pending counted', async () => {
  const db = world();
  const c = ctxOf(db);
  await L.transitionSchool(c, 'owner', OWNER, { schoolId: 's1', to: 'ACTIVE', idempotencyKey: 'k1' });
  await L.transitionSchool(c, 'owner', OWNER, { schoolId: 's1', to: 'SUSPENDED', reason: 'Unpaid for three months', idempotencyKey: 'k2' });
  const mine = await N.listMyPlatformNotifications(c, 'a1', PW);
  assert.equal(mine.notifications.length, 2);
  assert.equal(mine.pending, 2);
  assert.ok(mine.notifications.every((n) => n.state === 'DELIVERED' && n.requiresAck));
  assert.ok(mine.notifications.every((n) => !('recipientUserId' in n) && !('sourceEventId' in n)));
  const rows = (await all(db)).filter((r) => r.recipientUserId === 'a2');
  assert.ok(rows.every((r) => r.state === 'CREATED'), 'a2 has not seen theirs yet');
  assert.equal((await N.listMyPlatformNotifications(c, 'b1', PW)).notifications.length, 0, 'another school sees nothing');
});

test('a user paused by their school can still read why (no school-state check)', async () => {
  const db = world();
  const c = ctxOf(db);
  await L.transitionSchool(c, 'owner', OWNER, { schoolId: 's1', to: 'ACTIVE', idempotencyKey: 'k1' });
  await db.collection('schools').doc('s1').update({ status: 'SUSPENDED' });
  const r = await N.listMyPlatformNotifications(c, 'a1', PW);
  assert.equal(r.notifications.length, 1);
});

test('acknowledge: own only, idempotent, never someone else\'s (looks missing)', async () => {
  const db = world();
  const c = ctxOf(db);
  await L.transitionSchool(c, 'owner', OWNER, { schoolId: 's1', to: 'ACTIVE', idempotencyKey: 'k1' });
  const [mine] = (await N.listMyPlatformNotifications(c, 'a1', PW)).notifications;
  assert.deepEqual(await N.acknowledgeNotification(c, 'a2', PW, { id: mine.id }), { error: 'NOT_FOUND' });
  assert.deepEqual(await N.acknowledgeNotification(c, 'b1', PW, { id: mine.id }), { error: 'NOT_FOUND' });
  assert.deepEqual(await N.acknowledgeNotification(c, 'a1', PW, { id: 'nope' }), { error: 'NOT_FOUND' });
  assert.deepEqual(await N.acknowledgeNotification(c, 'a1', PW, {}), { error: 'INVALID_ARGUMENT', reason: 'id' });
  assert.deepEqual(await N.acknowledgeNotification(c, 'a1', PW, { id: mine.id }), { ok: true });
  assert.deepEqual(await N.acknowledgeNotification(c, 'a1', PW, { id: mine.id }), { ok: true, unchanged: true });
  const after = await N.listMyPlatformNotifications(c, 'a1', PW);
  assert.equal(after.notifications[0].state, 'ACKNOWLEDGED');
  assert.equal(after.pending, 0);
});

test('dismiss: refused while acknowledgement is required, allowed otherwise', async () => {
  const db = world();
  const c = ctxOf(db);
  await L.transitionSchool(c, 'owner', OWNER, { schoolId: 's1', to: 'ACTIVE', idempotencyKey: 'k1' });
  const [req] = (await N.listMyPlatformNotifications(c, 'a1', PW)).notifications;
  assert.deepEqual(await N.dismissNotification(c, 'a1', PW, { id: req.id }), { error: 'FAILED_PRECONDITION', reason: 'ACK_REQUIRED' });
  await N.notifySchoolAdmins(c, { schoolId: 's1', sourceEventId: 'misc:1', type: 'NOTE', title: 'FYI', body: 'x', requiresAck: false });
  const note = (await N.listMyPlatformNotifications(c, 'a1', PW)).notifications.find((n) => n.type === 'NOTE');
  assert.deepEqual(await N.dismissNotification(c, 'a1', PW, { id: note.id }), { ok: true });
  assert.ok(!(await N.listMyPlatformNotifications(c, 'a1', PW)).notifications.some((n) => n.type === 'NOTE'), 'dismissed ones leave the inbox');
});

test('callers who may not read: unknown, disabled, no school, sign-in method off', async () => {
  const db = world({
    'users/off': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1', login: { enabled: false, effective: ['PASSWORD'] } },
  });
  const c = ctxOf(db);
  for (const uid of ['ghost', 'gone', 'owner', 'off']) {
    assert.deepEqual(await N.listMyPlatformNotifications(c, uid, PW), { error: 'PERMISSION_DENIED' }, uid);
    assert.deepEqual(await N.acknowledgeNotification(c, uid, PW, { id: 'x' }), { error: 'PERMISSION_DENIED' }, uid);
  }
});

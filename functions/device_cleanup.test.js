'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { fakeDb } = require('./test_support');
const { canReceive, isStaleDevice, lostAccess, removeAllDevices, STALE_DEVICE_MS } = require('./device_cleanup');
const { pushToUsers } = require('./push');
const { registerDevice } = require('./devices');

const DAY = 24 * 60 * 60 * 1000;
const now = () => new Date();
const user = (o = {}) => ({ schoolId: 's1', status: 'ACTIVE', role: 'PARENT', ...o });
const TOK = (n) => `tok-${String(n).padStart(24, 'a')}`;

test('canReceive: ACTIVE and (no login grant, or login enabled)', () => {
  assert.equal(canReceive(user()), true);
  assert.equal(canReceive(user({ login: { enabled: true, effective: ['PASSWORD'] } })), true);
  assert.equal(canReceive(user({ login: { enabled: false } })), false);
  assert.equal(canReceive(user({ status: 'DISABLED' })), false);
  assert.equal(canReceive(user({ status: 'INVITED' })), false);
  assert.equal(canReceive(null), false);
});

test('lostAccess only on the transition from allowed to not allowed', () => {
  assert.equal(lostAccess(user(), user({ status: 'DISABLED' })), true);
  assert.equal(lostAccess(user(), user({ login: { enabled: false } })), true);
  assert.equal(lostAccess(user({ status: 'DISABLED' }), user({ status: 'DISABLED', name: 'x' })), false);
  assert.equal(lostAccess(user(), user({ name: 'renamed' })), false);
  assert.equal(lostAccess(user({ login: { enabled: false } }), user()), false);
});

test('isStaleDevice: judged by lastSeenAt, then updatedAt; unknown age is kept', () => {
  const t = Date.now();
  assert.equal(isStaleDevice({ lastSeenAt: new Date(t - 30 * DAY) }, t), false);
  assert.equal(isStaleDevice({ lastSeenAt: new Date(t - STALE_DEVICE_MS - DAY) }, t), true);
  assert.equal(isStaleDevice({ updatedAt: new Date(t - STALE_DEVICE_MS - DAY) }, t), true);
  assert.equal(isStaleDevice({ lastSeenAt: new Date(t - DAY), updatedAt: new Date(t - 400 * DAY) }, t), false);
  assert.equal(isStaleDevice({}, t), false);
});

test('removeAllDevices deletes only that user\'s devices', async () => {
  const db = fakeDb({
    'users/u1/devices/a': { token: TOK(1) },
    'users/u1/devices/b': { token: TOK(2) },
    'users/u2/devices/c': { token: TOK(3) },
  });
  assert.equal(await removeAllDevices(db, 'u1'), 2);
  assert.equal(db.store.has('users/u1/devices/a'), false);
  assert.equal(db.store.has('users/u2/devices/c'), true);
  assert.equal(await removeAllDevices(db, 'u1'), 0); // idempotent
});

function pushWorld(users, devices) {
  const seed = {};
  for (const [id, u] of Object.entries(users)) seed[`users/${id}`] = u;
  for (const [id, list] of Object.entries(devices)) list.forEach((d, i) => (seed[`users/${id}/devices/d${i}`] = d));
  const db = fakeDb(seed);
  const sent = [];
  const messaging = {
    sendEachForMulticast: async (m) => {
      sent.push(...m.tokens);
      return { successCount: m.tokens.length, responses: m.tokens.map(() => ({ success: true })) };
    },
  };
  return { db, messaging, sent };
}
const push = (w, ids) =>
  pushToUsers({ db: w.db, messaging: w.messaging, schoolId: 's1', userIds: new Set(ids), type: 'ANNOUNCEMENT_PUBLISHED', title: 't', body: 'b', notificationId: 'n', wait: async () => {} });

test('NOTIF-1: a device that stopped checking in no longer receives the previous user\'s notices', async () => {
  const t = Date.now();
  const w = pushWorld(
    { u1: user() },
    { u1: [{ token: TOK(1), lastSeenAt: new Date(t - 3 * DAY) }, { token: TOK(2), lastSeenAt: new Date(t - 90 * DAY) }] },
  );
  const s = await push(w, ['u1']);
  assert.deepEqual(w.sent, [TOK(1)]);
  assert.equal(s.devices, 1);
});

test('NOTIF-2: an ACTIVE user whose login was switched off receives nothing', async () => {
  const w = pushWorld(
    { u1: user({ login: { enabled: false, effective: [] } }), u2: user({ login: { enabled: true, effective: ['PASSWORD'] } }) },
    { u1: [{ token: TOK(1), lastSeenAt: now() }], u2: [{ token: TOK(2), lastSeenAt: now() }] },
  );
  const s = await push(w, ['u1', 'u2']);
  assert.deepEqual(w.sent, [TOK(2)]);
  assert.equal(s.ineligible, 1);
});

test('NOTIF-2: a login that is switched off cannot register a device', async () => {
  const db = fakeDb({ 'users/u1': user({ login: { enabled: false } }), 'users/u2': user() });
  const ctx = { db, now };
  assert.equal((await registerDevice(ctx, 'u1', { token: TOK(1), platform: 'android' })).error, 'PERMISSION_DENIED');
  assert.ok((await registerDevice(ctx, 'u2', { token: TOK(2), platform: 'android' })).result);
});

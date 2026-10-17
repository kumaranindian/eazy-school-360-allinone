'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const { pushToUsers, buildMessage, collapseId, STALE, TRANSIENT, ANDROID_CHANNEL } = require('./push');

const no = () => Promise.resolve(); // no real waiting in tests
const user = (o = {}) => ({ schoolId: 's1', status: 'ACTIVE', role: 'PARENT', ...o });
const device = (token, o = {}) => ({ token, platform: 'android', ...o });

/** Seeds users with devices; `script` decides what FCM answers per call. */
function world({ users = {}, devices = {}, prefs = {}, script } = {}) {
  const seed = {};
  for (const [id, u] of Object.entries(users)) seed[`users/${id}`] = u;
  for (const [id, list] of Object.entries(devices)) list.forEach((d, i) => (seed[`users/${id}/devices/d${i}`] = d));
  for (const [id, p] of Object.entries(prefs)) seed[`users/${id}/preferences/notifications`] = p;
  const db = fakeDb(seed);
  const calls = [];
  const messaging = {
    sendEachForMulticast: async (msg) => {
      calls.push(msg);
      const answer = script ? script(msg, calls.length) : null;
      return {
        successCount: 0,
        responses: msg.tokens.map((t, i) => (answer ? answer(t, i) : { success: true })),
      };
    },
  };
  return { db, messaging, calls };
}
const send = (w, o = {}) =>
  pushToUsers({
    db: w.db,
    messaging: w.messaging,
    schoolId: 's1',
    userIds: new Set(['u1']),
    type: 'ANNOUNCEMENT_PUBLISHED',
    title: 'Hello',
    body: 'World',
    notificationId: 'n1',
    wait: no,
    ...o,
  });

test('invalid-argument (bad payload) never deletes a device token', async () => {
  assert.ok(!STALE.has('messaging/invalid-argument'));
  const w = world({
    users: { u1: user() },
    devices: { u1: [device('tok-aaaaaaaaaaaaaaaaaaaaaa')] },
    script: () => () => ({ success: false, error: { code: 'messaging/invalid-argument' } }),
  });
  const r = await send(w);
  assert.strictEqual(r.permanentFailed, 1);
  assert.strictEqual(r.staleRemoved, 0);
  assert.ok(w.db.store.has('users/u1/devices/d0'));
});

test('tokens FCM reports as unregistered or invalid are removed', async () => {
  for (const code of ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']) {
    const w = world({
      users: { u1: user() },
      devices: { u1: [device('tok-aaaaaaaaaaaaaaaaaaaaaa')] },
      script: () => () => ({ success: false, error: { code } }),
    });
    const r = await send(w);
    assert.strictEqual(r.staleRemoved, 1, code);
    assert.ok(!w.db.store.has('users/u1/devices/d0'), code);
  }
});

test('only active users of the notification\'s own school are sent to', async () => {
  const w = world({
    users: {
      u1: user(),
      other: user({ schoolId: 's2' }), // another school
      off: user({ status: 'DISABLED' }), // deactivated
    },
    devices: {
      u1: [device('tok-u1-aaaaaaaaaaaaaaaaaaaa')],
      other: [device('tok-other-aaaaaaaaaaaaaaaaa')],
      off: [device('tok-off-aaaaaaaaaaaaaaaaaaa')],
    },
  });
  const r = await send(w, { userIds: new Set(['u1', 'other', 'off', 'ghost']) });
  assert.deepStrictEqual(w.calls.flatMap((c) => c.tokens), ['tok-u1-aaaaaaaaaaaaaaaaaaaa']);
  assert.strictEqual(r.requested, 4);
  assert.strictEqual(r.ineligible, 3); // other school, deactivated, missing
  assert.strictEqual(r.accepted, 1);
});

test('without a school nobody is eligible (fails closed)', async () => {
  const w = world({ users: { u1: user() }, devices: { u1: [device('tok-aaaaaaaaaaaaaaaaaaaaaa')] } });
  const r = await send(w, { schoolId: undefined });
  assert.strictEqual(w.calls.length, 0);
  assert.strictEqual(r.ineligible, 1);
});

test('the sender is never notified of their own action', async () => {
  const w = world({
    users: { u1: user(), u2: user() },
    devices: { u1: [device('tok-u1-aaaaaaaaaaaaaaaaaaaa')], u2: [device('tok-u2-aaaaaaaaaaaaaaaaaaaa')] },
  });
  await send(w, { userIds: new Set(['u1', 'u2']), exclude: 'u1' });
  assert.deepStrictEqual(w.calls.flatMap((c) => c.tokens), ['tok-u2-aaaaaaaaaaaaaaaaaaaa']);
});

test('push turned off or a muted category is respected; administrative notices cannot be muted', async () => {
  const w = world({
    users: { off: user(), muted: user(), plain: user() },
    devices: {
      off: [device('tok-off-aaaaaaaaaaaaaaaaaaa')],
      muted: [device('tok-muted-aaaaaaaaaaaaaaaaa')],
      plain: [device('tok-plain-aaaaaaaaaaaaaaaaa')],
    },
    prefs: { off: { pushEnabled: false }, muted: { mutedCategories: ['FEES'] } },
  });
  const ids = new Set(['off', 'muted', 'plain']);
  let r = await send(w, { userIds: ids, type: 'PAYMENT_RECORDED' });
  assert.deepStrictEqual(w.calls[0].tokens, ['tok-plain-aaaaaaaaaaaaaaaaa']);
  assert.strictEqual(r.muted, 2);
  w.calls.length = 0;
  r = await send(w, { userIds: new Set(['muted']), type: 'SOMETHING_ADMINISTRATIVE' });
  assert.strictEqual(w.calls[0].tokens[0], 'tok-muted-aaaaaaaaaaaaaaaaa'); // cannot be muted
});

test('a token registered under two accounts is sent once; deactivated devices are skipped', async () => {
  const w = world({
    users: { u1: user(), u2: user() },
    devices: {
      u1: [device('tok-shared-aaaaaaaaaaaaaaaaa'), device('tok-gone-aaaaaaaaaaaaaaaaaaa', { status: 'INACTIVE' })],
      u2: [device('tok-shared-aaaaaaaaaaaaaaaaa')],
    },
  });
  const r = await send(w, { userIds: new Set(['u1', 'u2']) });
  assert.deepStrictEqual(w.calls.flatMap((c) => c.tokens), ['tok-shared-aaaaaaaaaaaaaaaaa']);
  assert.strictEqual(r.devices, 1);
});

test('a transient failure is retried and then accepted, with no duplicate for the others', async () => {
  let attempt = 0;
  const w = world({
    users: { u1: user() },
    devices: { u1: [device('tok-a-aaaaaaaaaaaaaaaaaaaaa'), device('tok-b-aaaaaaaaaaaaaaaaaaaaa')] },
    script: () => (t) => {
      if (t.startsWith('tok-b') && attempt++ === 0) return { success: false, error: { code: 'messaging/server-unavailable' } };
      return { success: true };
    },
  });
  const r = await send(w);
  assert.strictEqual(r.accepted, 2);
  assert.strictEqual(r.transientFailed, 0);
  assert.strictEqual(w.calls.length, 2);
  assert.deepStrictEqual(w.calls[1].tokens, ['tok-b-aaaaaaaaaaaaaaaaaaaaa']); // only the failed one again
});

test('retries are bounded: a token that keeps failing is counted, not retried forever', async () => {
  const w = world({
    users: { u1: user() },
    devices: { u1: [device('tok-aaaaaaaaaaaaaaaaaaaaaa')] },
    script: () => () => ({ success: false, error: { code: 'messaging/internal-error' } }),
  });
  const r = await send(w);
  assert.strictEqual(w.calls.length, 3);
  assert.strictEqual(r.transientFailed, 1);
  assert.strictEqual(r.accepted, 0);
});

test('a permanent failure is not retried', async () => {
  const w = world({
    users: { u1: user() },
    devices: { u1: [device('tok-aaaaaaaaaaaaaaaaaaaaaa')] },
    script: () => () => ({ success: false, error: { code: 'messaging/third-party-auth-error' } }),
  });
  const r = await send(w);
  assert.strictEqual(w.calls.length, 1);
  assert.strictEqual(r.permanentFailed, 1);
});

test('a partial batch: accepted, dead and permanently failed tokens are each handled', async () => {
  const w = world({
    users: { u1: user() },
    devices: {
      u1: [device('tok-ok-aaaaaaaaaaaaaaaaaaaaa'), device('tok-dead-aaaaaaaaaaaaaaaaaaa'), device('tok-bad-aaaaaaaaaaaaaaaaaaaa')],
    },
    script: () => (t) => {
      if (t.startsWith('tok-dead')) return { success: false, error: { code: 'messaging/registration-token-not-registered' } };
      if (t.startsWith('tok-bad')) return { success: false, error: { code: 'messaging/invalid-argument' } };
      return { success: true };
    },
  });
  const r = await send(w);
  assert.deepStrictEqual(
    { a: r.accepted, s: r.staleRemoved, p: r.permanentFailed },
    { a: 1, s: 1, p: 1 },
  );
  assert.ok(!w.db.store.has('users/u1/devices/d1')); // only the dead one
  assert.ok(w.db.store.has('users/u1/devices/d2'));
});

test('a whole-call failure is retried and then reported, never thrown', async () => {
  const w = world({ users: { u1: user() }, devices: { u1: [device('tok-aaaaaaaaaaaaaaaaaaaaaa')] } });
  w.messaging.sendEachForMulticast = async () => {
    throw new Error('network down');
  };
  const r = await send(w);
  assert.strictEqual(r.transientFailed, 1);
});

test('more than 500 devices are sent in batches', async () => {
  const list = Array.from({ length: 620 }, (_, i) => device(`tok-${String(i).padStart(4, '0')}-aaaaaaaaaaaaaaaaa`));
  const w = world({ users: { u1: user() }, devices: { u1: list } });
  const r = await send(w);
  assert.deepStrictEqual(w.calls.map((c) => c.tokens.length), [500, 120]);
  assert.strictEqual(r.accepted, 620);
});

test('the payload: Android channel + sound, iOS sound, a tagged web notification, safe data only', () => {
  const m = buildMessage({
    type: 'PAYMENT_RECORDED',
    title: 'Payment received',
    body: 'A fee payment was recorded.',
    notificationId: 'n-1',
    data: { refType: 'RECEIPT', refId: 'pay-1', branchId: 'main', route: '/admin-only', secret: 'x', amount: '500' },
  });
  assert.strictEqual(m.android.notification.channelId, ANDROID_CHANNEL);
  assert.strictEqual(m.android.notification.defaultSound, true);
  assert.strictEqual(m.android.priority, 'high');
  assert.strictEqual(m.apns.payload.aps.sound, 'default');
  assert.strictEqual(m.apns.headers['apns-push-type'], 'alert');
  assert.strictEqual(m.webpush.notification.tag, 'n-1');
  // data: only the allowlisted keys, and the route is always the safe default
  assert.deepStrictEqual(m.data, {
    type: 'PAYMENT_RECORDED',
    route: '/notifications',
    notificationId: 'n-1',
    refType: 'RECEIPT',
    refId: 'pay-1',
    branchId: 'main',
  });
  assert.ok(Object.values(m.data).every((v) => typeof v === 'string'));
});

test('collapse ids stay within the APNs 64-byte limit', () => {
  assert.strictEqual(collapseId('short'), 'short');
  const long = 'PAYMENT_RECORDED__' + 'x'.repeat(80);
  assert.ok(collapseId(long).length <= 64);
  assert.strictEqual(collapseId(long), collapseId(long)); // stable, so a resend collapses
  assert.strictEqual(collapseId(''), undefined);
});

test('which errors are dead and which are transient never overlap', () => {
  for (const c of TRANSIENT) assert.ok(!STALE.has(c), c);
});

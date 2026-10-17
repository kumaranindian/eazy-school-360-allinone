'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const { registerDevice, unregisterDevice, deviceId, MAX_DEVICES } = require('./devices');

const T1 = 'tokenAAAAAAAAAAAAAAAAAAAAAA1';
const T2 = 'tokenBBBBBBBBBBBBBBBBBBBBBB2';
let clock = 0;
const now = () => new Date(Date.UTC(2026, 7, 3, 10, 0, 0) + clock++ * 1000);
const users = () => ({
  'users/a': { schoolId: 's1', branchId: 'main', status: 'ACTIVE', role: 'PARENT' },
  'users/b': { schoolId: 's2', branchId: 'main', status: 'ACTIVE', role: 'TEACHER' },
  'users/off': { schoolId: 's1', status: 'DISABLED' },
  'users/noschool': { status: 'ACTIVE' },
});
const reg = (db, uid, data) => registerDevice({ db, now }, uid, data);

test('a new registration is stored under the caller, with their school and a hashed id', async () => {
  const db = fakeDb(users());
  const r = await reg(db, 'a', { token: T1, platform: 'android', schoolId: 's2', userId: 'b' });
  assert.strictEqual(r.result.deviceId, deviceId(T1));
  assert.notStrictEqual(r.result.deviceId, T1);
  const d = db.store.get(`users/a/devices/${deviceId(T1)}`);
  // the school comes from the account, never from the request
  assert.deepStrictEqual(
    { school: d.schoolId, branch: d.branchId, status: d.status, platform: d.platform, token: d.token },
    { school: 's1', branch: 'main', status: 'ACTIVE', platform: 'android', token: T1 },
  );
  assert.ok(d.createdAt && d.updatedAt && d.lastSeenAt);
  assert.ok(![...db.store.keys()].some((k) => k.startsWith('users/b/devices')));
});

test('registering again refreshes the same document and keeps its creation time', async () => {
  const db = fakeDb(users());
  await reg(db, 'a', { token: T1, platform: 'web' });
  const first = db.store.get(`users/a/devices/${deviceId(T1)}`);
  await reg(db, 'a', { token: T1, platform: 'web' });
  const again = db.store.get(`users/a/devices/${deviceId(T1)}`);
  assert.strictEqual([...db.store.keys()].filter((k) => k.startsWith('users/a/devices')).length, 1);
  assert.strictEqual(again.createdAt.getTime(), first.createdAt.getTime());
  assert.ok(again.updatedAt.getTime() > first.updatedAt.getTime());
});

test('one user can have several devices', async () => {
  const db = fakeDb(users());
  await reg(db, 'a', { token: T1, platform: 'android' });
  await reg(db, 'a', { token: T2, platform: 'ios' });
  assert.strictEqual([...db.store.keys()].filter((k) => k.startsWith('users/a/devices')).length, 2);
});

test('a token handed to another account leaves the previous one (shared device)', async () => {
  const db = fakeDb(users());
  await reg(db, 'a', { token: T1, platform: 'android' });
  const r = await reg(db, 'b', { token: T1, platform: 'android' });
  assert.strictEqual(r.result.released, 1);
  assert.ok(!db.store.has(`users/a/devices/${deviceId(T1)}`));
  assert.ok(db.store.has(`users/b/devices/${deviceId(T1)}`));
});

test('legacy documents of the same token (an old id) are folded into the new one', async () => {
  const db = fakeDb({ ...users(), 'users/a/devices/old-id': { token: T1, platform: 'android' } });
  const r = await reg(db, 'a', { token: T1, platform: 'android' });
  assert.strictEqual(r.result.released, 0); // same account: not "released from someone else"
  assert.ok(!db.store.has('users/a/devices/old-id'));
  assert.ok(db.store.has(`users/a/devices/${deviceId(T1)}`));
});

test('inactive, unknown and school-less accounts cannot register a device', async () => {
  const db = fakeDb(users());
  for (const uid of ['off', 'noschool', 'ghost']) {
    assert.deepStrictEqual(await reg(db, uid, { token: T1, platform: 'web' }), { error: 'PERMISSION_DENIED' }, uid);
  }
  assert.strictEqual([...db.store.keys()].filter((k) => k.includes('/devices/')).length, 0);
});

test('malformed requests are refused', async () => {
  const db = fakeDb(users());
  for (const bad of [
    { token: 'short', platform: 'web' },
    { token: T1, platform: 'windows' },
    { token: T1 },
    { token: `${T1}<script>`, platform: 'web' },
    { token: 12345, platform: 'web' },
    null,
  ]) {
    assert.deepStrictEqual(await reg(db, 'a', bad), { error: 'INVALID_ARGUMENT' }, JSON.stringify(bad));
  }
});

test('a user keeps at most MAX_DEVICES, dropping the least recently seen', async () => {
  const db = fakeDb(users());
  for (let i = 0; i < MAX_DEVICES + 3; i++) {
    await reg(db, 'a', { token: `tokenCCCCCCCCCCCCCCCCCCCC${String(i).padStart(3, '0')}`, platform: 'android' });
  }
  const left = [...db.store.keys()].filter((k) => k.startsWith('users/a/devices'));
  assert.strictEqual(left.length, MAX_DEVICES);
  assert.ok(!db.store.has(`users/a/devices/${deviceId('tokenCCCCCCCCCCCCCCCCCCCC000')}`)); // the oldest went
  assert.ok(db.store.has(`users/a/devices/${deviceId(`tokenCCCCCCCCCCCCCCCCCCCC${String(MAX_DEVICES + 2).padStart(3, '0')}`)}`));
});

test('unregistering removes only the caller\'s registration', async () => {
  const db = fakeDb(users());
  await reg(db, 'a', { token: T1, platform: 'android' });
  await reg(db, 'a', { token: T2, platform: 'android' });
  const r = await unregisterDevice({ db }, 'a', { token: T1 });
  assert.strictEqual(r.result.removed, 1);
  assert.ok(!db.store.has(`users/a/devices/${deviceId(T1)}`));
  assert.ok(db.store.has(`users/a/devices/${deviceId(T2)}`));
});

test('a user cannot unregister a token that belongs to another account', async () => {
  const db = fakeDb(users());
  await reg(db, 'a', { token: T1, platform: 'android' });
  const r = await unregisterDevice({ db }, 'b', { token: T1 });
  assert.strictEqual(r.result.removed, 0);
  assert.ok(db.store.has(`users/a/devices/${deviceId(T1)}`));
  assert.deepStrictEqual(await unregisterDevice({ db }, 'a', { token: 'nope' }), { error: 'INVALID_ARGUMENT' });
});

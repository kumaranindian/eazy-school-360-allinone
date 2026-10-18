'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const { makeDelivery } = require('./deliver');
const { RETRY_BACKOFF_MS } = require('./delivery_log');

const no = () => Promise.resolve();
const logger = { info() {}, error() {} };
const PATH = 'schools/s1/branches/b1/broadcastNotices/n1';
const t0 = new Date('2026-08-03T10:00:00Z');

/** [n] parents with one device each, plus the notice they are addressed by. */
function world(n, { notice = true } = {}) {
  const seed = {};
  if (notice) seed[PATH] = { type: 'ANNOUNCEMENT_PUBLISHED', title: 'Hi', body: 'There', audienceKind: 'ALL', createdBy: 'nobody' };
  for (let i = 0; i < n; i++) {
    seed[`users/u${i}`] = { schoolId: 's1', status: 'ACTIVE', role: 'PARENT' };
    seed[`users/u${i}/devices/d`] = { token: `tok-${i}-aaaaaaaaaaaaaaaaaaaa`, platform: 'android' };
  }
  const db = fakeDb(seed);
  const sentTo = [];
  const state = { failing: new Set() };
  const messaging = {
    sendEachForMulticast: async (msg) => ({
      responses: msg.tokens.map((t) => {
        if (state.failing.has(t)) return { success: false, error: { code: 'messaging/server-unavailable' } };
        sentTo.push(t);
        return { success: true };
      }),
    }),
  };
  let clock = 0;
  const now = () => new Date(t0.getTime() + clock);
  const advance = (ms) => (clock += ms);
  const d = makeDelivery({ db, messaging, logger, now, wait: no });
  const run = () => d.runDelivery({ eventId: 'evt', schoolId: 's1', branchId: 'b1', ref: db.doc ? db.doc(PATH) : { path: PATH }, id: 'n1', data: db.store.get(PATH), kind: 'broadcastNotices' });
  return { db, d, run, sentTo, state, advance };
}

// fakeDb has no db.doc(); give redrive a way to read the source.
function withDoc(w) {
  const { db } = w;
  db.doc = (p) => ({
    path: p,
    get: async () => ({ exists: db.store.has(p), id: p.split('/').pop(), ref: { path: p }, data: () => structuredClone(db.store.get(p)) }),
  });
  return w;
}

test('a transient FCM failure leaves the delivery PARTIAL and retryable', async () => {
  const w = withDoc(world(3));
  w.state.failing.add('tok-1-aaaaaaaaaaaaaaaaaaaa');
  assert.strictEqual(await w.run(), 'PARTIAL');
  const rec = w.db.store.get('pushDeliveries/evt');
  assert.strictEqual(rec.status, 'PARTIAL');
  assert.strictEqual(rec.retryable, true);
  assert.strictEqual(rec.doneDevices.length, 2);
});

test('redrive finishes the job and never re-sends to a device already accepted', async () => {
  const w = withDoc(world(3));
  w.state.failing.add('tok-1-aaaaaaaaaaaaaaaaaaaa');
  await w.run();
  assert.strictEqual(w.sentTo.length, 2);
  w.state.failing.clear(); // FCM recovered
  assert.strictEqual((await w.d.redrive()).due, 0); // not due yet
  w.advance(RETRY_BACKOFF_MS[0] + 1000);
  const out = await w.d.redrive();
  assert.deepStrictEqual(out, { due: 1, ran: 1, gone: 0 });
  assert.strictEqual(w.sentTo.length, 3);
  assert.strictEqual(new Set(w.sentTo).size, 3); // no duplicates
  assert.strictEqual(w.db.store.get('pushDeliveries/evt').status, 'SENT');
  w.advance(10 * 3600 * 1000);
  assert.strictEqual((await w.d.redrive()).due, 0); // final
});

test('NOTIF-4: a large audience is attempted in full, not truncated at 2,000', async () => {
  const w = withDoc(world(2500));
  assert.strictEqual(await w.run(), 'SENT');
  assert.strictEqual(w.sentTo.length, 2500);
  assert.strictEqual(w.db.store.get('pushDeliveries/evt').accepted, 2500);
});

test('NOTIF-4: running out of time is INCOMPLETE and finished by the redrive', async () => {
  const w = withDoc(world(5));
  const slow = makeDelivery({ db: w.db, messaging: { sendEachForMulticast: async () => ({ responses: [] }) }, logger, budgetMs: -1, now: () => t0, wait: no });
  const status = await slow.runDelivery({ eventId: 'evt', schoolId: 's1', branchId: 'b1', ref: { path: PATH }, id: 'n1', data: w.db.store.get(PATH), kind: 'broadcastNotices' });
  assert.strictEqual(status, 'INCOMPLETE');
  assert.strictEqual(w.db.store.get('pushDeliveries/evt').retryable, true);
  w.advance(RETRY_BACKOFF_MS[0] + 1000);
  await w.d.redrive();
  assert.strictEqual(w.sentTo.length, 5);
  assert.strictEqual(w.db.store.get('pushDeliveries/evt').status, 'SENT');
});

test('a deleted source notice is marked non-retryable, not retried forever', async () => {
  const w = withDoc(world(2));
  w.state.failing.add('tok-0-aaaaaaaaaaaaaaaaaaaa');
  await w.run();
  w.db.store.delete(PATH);
  w.advance(RETRY_BACKOFF_MS[0] + 1000);
  assert.deepStrictEqual(await w.d.redrive(), { due: 1, ran: 0, gone: 1 });
  const rec = w.db.store.get('pushDeliveries/evt');
  assert.strictEqual(rec.retryable, false);
  assert.strictEqual(rec.status, 'SOURCE_DELETED');
});

test('NOTIF-5: concurrent redrives of one due delivery send once', async () => {
  const w = withDoc(world(3));
  w.state.failing.add('tok-1-aaaaaaaaaaaaaaaaaaaa');
  await w.run();
  w.state.failing.clear();
  w.advance(RETRY_BACKOFF_MS[0] + 1000);
  await Promise.all([w.d.redrive(), w.d.redrive(), w.d.redrive()]);
  assert.strictEqual(w.sentTo.length, 3);
  assert.strictEqual(new Set(w.sentTo).size, 3);
});

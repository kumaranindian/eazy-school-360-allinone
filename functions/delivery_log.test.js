'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const {
  claimDelivery,
  finishDelivery,
  dueDeliveries,
  errorCategory,
  STALE_CLAIM_MS,
  RETENTION_DAYS,
  MAX_ATTEMPTS,
  RETRY_BACKOFF_MS,
} = require('./delivery_log');

const meta = { schoolId: 's1', branchId: 'b1', path: 'schools/s1/branches/b1/notifications/n1', type: 'LEAVE_APPROVED' };
const t0 = new Date('2026-08-03T10:00:00Z');
const at = (ms) => () => new Date(t0.getTime() + ms);

test('the first arrival of an event claims it; a repeat does nothing', async () => {
  const db = fakeDb();
  const first = await claimDelivery(db, 'evt-1', meta, at(0));
  assert.ok(first);
  assert.strictEqual(first.attempt, 1);
  assert.strictEqual(db.store.get('pushDeliveries/evt-1').status, 'PROCESSING');
  assert.strictEqual(await claimDelivery(db, 'evt-1', meta, at(1000)), null); // duplicate delivery while running
  assert.ok(await claimDelivery(db, 'evt-2', meta, at(0))); // another event is independent
});

test('a claim expires for TTL cleanup and holds no message content', async () => {
  const db = fakeDb();
  await claimDelivery(db, 'evt-1', meta, at(0));
  const d = db.store.get('pushDeliveries/evt-1');
  assert.strictEqual(d.expireAt.getTime() - t0.getTime(), RETENTION_DAYS * 24 * 3600 * 1000);
  assert.deepStrictEqual(Object.keys(d).sort(), [
    'attempts', 'branchId', 'createdAt', 'expireAt', 'nextAttemptAt', 'path', 'retryable', 'schoolId', 'startedAt', 'status', 'type',
  ]);
});

test('a SENT delivery is final and never re-run', async () => {
  const db = fakeDb();
  const claim = await claimDelivery(db, 'evt-1', meta, at(0));
  await finishDelivery(claim, { status: 'SENT', accepted: 3, staleRemoved: 1 }, at(1000));
  const d = db.store.get('pushDeliveries/evt-1');
  assert.strictEqual(d.status, 'SENT');
  assert.strictEqual(d.retryable, false);
  assert.strictEqual(d.nextAttemptAt, null);
  assert.strictEqual(await claimDelivery(db, 'evt-1', meta, at(24 * 3600 * 1000)), null);
});

test('NOTIF-3: FAILED / PARTIAL / INCOMPLETE are retried after a back-off, not lost', async () => {
  for (const status of ['FAILED', 'PARTIAL', 'INCOMPLETE']) {
    const db = fakeDb();
    const claim = await claimDelivery(db, 'e', meta, at(0));
    await finishDelivery(claim, { status, doneDevices: ['k1', 'k2'] }, at(1000));
    const d = db.store.get('pushDeliveries/e');
    assert.strictEqual(d.retryable, true, status);
    assert.strictEqual(d.nextAttemptAt.getTime(), t0.getTime() + 1000 + RETRY_BACKOFF_MS[0]);
    // not due yet
    assert.strictEqual(await claimDelivery(db, 'e', meta, at(1000 + RETRY_BACKOFF_MS[0] - 1)), null);
    // due: attempt 2 carries the devices already sent to
    const again = await claimDelivery(db, 'e', meta, at(1000 + RETRY_BACKOFF_MS[0] + 1));
    assert.strictEqual(again.attempt, 2);
    assert.deepStrictEqual([...again.doneDevices].sort(), ['k1', 'k2']);
  }
});

test('retries are bounded: after MAX_ATTEMPTS the record is final and visible', async () => {
  const db = fakeDb();
  let clock = 0;
  let claim = await claimDelivery(db, 'e', meta, at(clock));
  for (let i = 1; i < MAX_ATTEMPTS; i++) {
    await finishDelivery(claim, { status: 'FAILED' }, at(clock));
    clock += 24 * 3600 * 1000;
    claim = await claimDelivery(db, 'e', meta, at(clock));
    assert.ok(claim, `attempt ${i + 1} is allowed`);
    assert.strictEqual(claim.attempt, i + 1);
  }
  await finishDelivery(claim, { status: 'FAILED' }, at(clock));
  const d = db.store.get('pushDeliveries/e');
  assert.strictEqual(d.retryable, false);
  assert.strictEqual(d.status, 'FAILED');
  assert.strictEqual(await claimDelivery(db, 'e', meta, at(clock + 7 * 24 * 3600 * 1000)), null);
});

test('a claim stuck in PROCESSING from a crash is retried once stale, not before', async () => {
  const db = fakeDb();
  await claimDelivery(db, 'evt-1', meta, at(0));
  assert.strictEqual(await claimDelivery(db, 'evt-1', meta, at(60 * 1000)), null); // still running
  const taken = await claimDelivery(db, 'evt-1', meta, at(STALE_CLAIM_MS + 1000)); // the invocation died
  assert.ok(taken);
  assert.strictEqual(taken.attempt, 2);
  assert.strictEqual(db.store.get('pushDeliveries/evt-1').takeovers, 1);
});

test('NOTIF-5: two concurrent takeovers of the same stale claim: exactly one wins', async () => {
  const db = fakeDb();
  await claimDelivery(db, 'evt-1', meta, at(0));
  const later = at(STALE_CLAIM_MS + 1000);
  const results = await Promise.all([claimDelivery(db, 'evt-1', meta, later), claimDelivery(db, 'evt-1', meta, later), claimDelivery(db, 'evt-1', meta, later)]);
  assert.strictEqual(results.filter(Boolean).length, 1);
  assert.strictEqual(db.store.get('pushDeliveries/evt-1').takeovers, 1);
  assert.strictEqual(db.store.get('pushDeliveries/evt-1').attempts, 2);
});

test('dueDeliveries finds exactly the retryable ones that are due', async () => {
  const db = fakeDb();
  const a = await claimDelivery(db, 'a', meta, at(0)); // PROCESSING, due at +10 min
  const b = await claimDelivery(db, 'b', meta, at(0));
  await finishDelivery(b, { status: 'PARTIAL' }, at(1000)); // due at +1 min
  const c = await claimDelivery(db, 'c', meta, at(0));
  await finishDelivery(c, { status: 'SENT' }, at(1000)); // final
  assert.ok(a);
  assert.deepStrictEqual((await dueDeliveries(db, at(30 * 1000))).map((d) => d.id), []);
  assert.deepStrictEqual((await dueDeliveries(db, at(2 * 60 * 1000))).map((d) => d.id), ['b']);
  assert.deepStrictEqual((await dueDeliveries(db, at(11 * 60 * 1000))).map((d) => d.id).sort(), ['a', 'b']);
});

test('doneDevices are remembered, de-duplicated and capped, never tokens', async () => {
  const db = fakeDb();
  const claim = await claimDelivery(db, 'e', meta, at(0));
  await finishDelivery(claim, { status: 'PARTIAL', doneDevices: ['x', 'y', 'x'] }, at(1));
  assert.deepStrictEqual(db.store.get('pushDeliveries/e').doneDevices.sort(), ['x', 'y']);
});

test('a missing event id never delivers (nothing to be idempotent on)', async () => {
  assert.strictEqual(await claimDelivery(fakeDb(), undefined, meta), null);
});

test('other storage errors are surfaced, not mistaken for "already handled"', async () => {
  const db = fakeDb();
  db.collection = () => ({ doc: () => ({ create: async () => { throw Object.assign(new Error('unavailable'), { code: 14 }); } }) });
  await assert.rejects(claimDelivery(db, 'evt-1', meta), /unavailable/);
});

test('error categories carry a code, not a message', () => {
  assert.strictEqual(errorCategory({ code: 'messaging/server-unavailable', message: 'secret token x' }), 'messaging/server-unavailable');
  assert.strictEqual(errorCategory({ code: 14 }), 'error/14');
  assert.strictEqual(errorCategory(new Error('boom')), 'error/unknown');
});

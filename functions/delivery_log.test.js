'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const { claimDelivery, finishDelivery, errorCategory, STALE_CLAIM_MS, RETENTION_DAYS } = require('./delivery_log');

const meta = { schoolId: 's1', branchId: 'b1', path: 'schools/s1/branches/b1/notifications/n1', type: 'LEAVE_APPROVED' };

test('the first arrival of an event claims it; a repeat does nothing', async () => {
  const db = fakeDb();
  const first = await claimDelivery(db, 'evt-1', meta);
  assert.ok(first);
  assert.strictEqual(db.store.get('pushDeliveries/evt-1').status, 'PROCESSING');
  assert.strictEqual(await claimDelivery(db, 'evt-1', meta), null); // retry / duplicate delivery
  assert.strictEqual(await claimDelivery(db, 'evt-2', meta) !== null, true); // another event is independent
});

test('a claim expires for TTL cleanup and holds no message content', async () => {
  const db = fakeDb();
  const now = new Date('2026-08-03T10:00:00Z');
  await claimDelivery(db, 'evt-1', meta, () => now);
  const d = db.store.get('pushDeliveries/evt-1');
  assert.strictEqual(d.expireAt.getTime() - now.getTime(), RETENTION_DAYS * 24 * 3600 * 1000);
  assert.deepStrictEqual(Object.keys(d).sort(), ['branchId', 'createdAt', 'expireAt', 'path', 'schoolId', 'startedAt', 'status', 'type']);
});

test('a finished delivery records counts, never message text or tokens', async () => {
  const db = fakeDb();
  const ref = await claimDelivery(db, 'evt-1', meta);
  await finishDelivery(ref, { status: 'SENT', accepted: 3, staleRemoved: 1 });
  const d = db.store.get('pushDeliveries/evt-1');
  assert.strictEqual(d.status, 'SENT');
  assert.strictEqual(d.accepted, 3);
  assert.ok(d.finishedAt);
  assert.strictEqual(await claimDelivery(db, 'evt-1', meta), null); // finished: never re-run
});

test('a claim stuck in PROCESSING from a crash can be taken over, a recent one cannot', async () => {
  const db = fakeDb();
  const t0 = new Date('2026-08-03T10:00:00Z');
  await claimDelivery(db, 'evt-1', meta, () => t0);
  const soon = new Date(t0.getTime() + 60 * 1000);
  assert.strictEqual(await claimDelivery(db, 'evt-1', meta, () => soon), null); // still running
  const later = new Date(t0.getTime() + STALE_CLAIM_MS + 1000);
  assert.ok(await claimDelivery(db, 'evt-1', meta, () => later)); // the invocation died
  assert.strictEqual(db.store.get('pushDeliveries/evt-1').takeovers, 1);
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

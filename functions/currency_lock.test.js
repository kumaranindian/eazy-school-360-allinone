'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const { schoolOf, lockCurrency } = require('./currency_lock');

const seed = (o = {}) => ({ 'schools/s1': { name: 'S', currency: 'USD', ...o } });

test('the school id comes from the document path', () => {
  assert.strictEqual(schoolOf('schools/s1/branches/b1/invoices/i1'), 's1');
  assert.strictEqual(schoolOf('users/u1'), null);
});

test('the first money document locks the currency, once', async () => {
  const db = fakeDb(seed());
  const at = new Date('2026-08-03T10:00:00Z');
  assert.strictEqual(await lockCurrency(db, 's1', () => at), true);
  const s = db.store.get('schools/s1');
  assert.strictEqual(s.currencyLocked, true);
  assert.strictEqual(s.currency, 'USD'); // the choice itself is untouched
  assert.strictEqual(await lockCurrency(db, 's1', () => new Date()), false);
  assert.deepStrictEqual(db.store.get('schools/s1').currencyLockedAt, at); // not rewritten
});

test('concurrent first documents lock exactly once', async () => {
  const db = fakeDb(seed());
  const r = await Promise.all([lockCurrency(db, 's1'), lockCurrency(db, 's1'), lockCurrency(db, 's1')]);
  assert.strictEqual(r.filter(Boolean).length, 1);
});

test('a missing school or id is ignored', async () => {
  const db = fakeDb(seed());
  assert.strictEqual(await lockCurrency(db, 'nope'), false);
  assert.strictEqual(await lockCurrency(db, null), false);
  assert.ok(!db.store.has('schools/nope'));
});

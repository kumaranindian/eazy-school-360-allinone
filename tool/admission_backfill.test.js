'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { admissionKey, planBackfill } = require('./admission_backfill');

test('keys match the app and the rules (case, spaces, slash)', () => {
  assert.strictEqual(admissionKey('ADM-001'), 'adm-001');
  assert.strictEqual(admissionKey('  Adm-001 '), 'adm-001');
  assert.strictEqual(admissionKey('2024/001'), '2024~001');
});

test('students without a reservation get one; reserved ones are skipped', () => {
  const plan = planBackfill(
    [{ id: 's1', admissionNumber: 'A-1' }, { id: 's2', admissionNumber: 'A-2' }, { id: 's3', admissionNumber: '' }],
    new Set(['a-2']),
  );
  assert.deepStrictEqual(plan.create, [{ key: 'a-1', studentId: 's1', number: 'A-1' }]);
  assert.deepStrictEqual(plan.duplicates, []);
});

test('numbers that collide are reported, never silently resolved', () => {
  const plan = planBackfill([
    { id: 's2', admissionNumber: 'A-1' },
    { id: 's1', admissionNumber: ' a-1' },
    { id: 's3', admissionNumber: 'A-3' },
  ]);
  assert.deepStrictEqual(plan.duplicates, [{ key: 'a-1', studentIds: ['s1', 's2'] }]);
  assert.deepStrictEqual(plan.create.map((c) => c.key), ['a-3']);
});

test('numbers that cannot be a key are reported', () => {
  const plan = planBackfill([{ id: 's1', admissionNumber: '.x' }, { id: 's2', admissionNumber: 'a'.repeat(61) }]);
  assert.strictEqual(plan.invalid.length, 2);
  assert.deepStrictEqual(plan.create, []);
});

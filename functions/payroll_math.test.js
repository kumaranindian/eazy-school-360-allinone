'use strict';
const test = require('node:test');
const assert = require('node:assert');
const m = require('./payroll_math');

const basic = { componentId: 'basic', kind: 'EARNING', calc: 'FIXED', amountMinor: 3000000 };

test('percentOf rounds half up, exactly, with large bases', () => {
  assert.equal(m.percentOf(1000, 1250), 125);
  assert.equal(m.percentOf(5, 1000), 1, '0.5 rounds up');
  assert.equal(m.percentOf(4, 1000), 0, '0.4 rounds down');
  assert.equal(m.percentOf(15, 1000), 2, '1.5 rounds up');
  assert.equal(m.percentOf(1e12, 10000), 1e12, 'the biggest line at 100% is exact');
  assert.equal(m.percentOf(999999999999, 9999), 999899999999, 'exact where a double would drift');
});

test('a structure: fixed and percentage lines, gross, deductions, net', () => {
  const r = m.evaluate([
    basic,
    { componentId: 'hra', kind: 'EARNING', calc: 'PERCENT', percentBp: 4000, basisId: 'basic' },
    { componentId: 'pf', kind: 'DEDUCTION', calc: 'PERCENT', percentBp: 1200, basisId: 'basic' },
    { componentId: 'adv', kind: 'DEDUCTION', calc: 'FIXED', amountMinor: 50000 },
  ]);
  assert.equal(r.errors, undefined);
  assert.deepEqual(r.lines.map((l) => l.amountMinor), [3000000, 1200000, 360000, 50000]);
  assert.equal(r.grossMinor, 4200000);
  assert.equal(r.deductionsMinor, 410000);
  assert.equal(r.netMinor, 3790000);
});

test('needs an earning; deductions may not exceed earnings; net may be zero', () => {
  assert.ok(m.evaluate([]).errors.lines);
  assert.ok(m.evaluate([{ componentId: 'd', kind: 'DEDUCTION', calc: 'FIXED', amountMinor: 5 }]).errors.lines);
  assert.ok(m.evaluate([{ ...basic, amountMinor: 100 }, { componentId: 'd', kind: 'DEDUCTION', calc: 'FIXED', amountMinor: 101 }]).errors.lines);
  assert.equal(m.evaluate([{ ...basic, amountMinor: 100 }, { componentId: 'd', kind: 'DEDUCTION', calc: 'FIXED', amountMinor: 100 }]).netMinor, 0);
});

test('percentage basis: must be a fixed earning of this structure (no chains, no deductions, no missing)', () => {
  const pct = (basisId, kind = 'EARNING') => ({ componentId: 'p', kind, calc: 'PERCENT', percentBp: 1000, basisId });
  assert.ok(m.evaluate([basic, pct('nope')]).errors);
  assert.ok(m.evaluate([basic, { componentId: 'd', kind: 'DEDUCTION', calc: 'FIXED', amountMinor: 1 }, pct('d')]).errors, 'a deduction is not a basis');
  assert.ok(m.evaluate([basic, { componentId: 'h', kind: 'EARNING', calc: 'PERCENT', percentBp: 1000, basisId: 'basic' }, { ...pct('h'), componentId: 'q' }]).errors, 'a percentage is not a basis (no chains)');
  assert.ok(m.evaluate([basic, pct('p')]).errors, 'a line cannot be its own basis');
});

test('hostile lines are refused, never thrown', () => {
  const bad = [
    null, 5, 'x', [null], [{}], [{ ...basic, amountMinor: 0 }], [{ ...basic, amountMinor: -1 }], [{ ...basic, amountMinor: 1.5 }],
    [{ ...basic, amountMinor: m.MAX_MINOR + 1 }], [{ ...basic, amountMinor: '100' }], [{ ...basic, kind: 'BONUS' }], [{ ...basic, calc: 'WEIRD' }],
    [basic, basic], [basic, { componentId: 'p', kind: 'EARNING', calc: 'PERCENT', percentBp: 0, basisId: 'basic' }],
    [basic, { componentId: 'p', kind: 'EARNING', calc: 'PERCENT', percentBp: 10001, basisId: 'basic' }],
    [basic, { componentId: 'p', kind: 'EARNING', calc: 'PERCENT', percentBp: 1000 }],
    Array.from({ length: 41 }, (_, i) => ({ ...basic, componentId: `c${i}` })),
  ];
  for (const b of bad) assert.ok(m.evaluate(b).errors, JSON.stringify(b));
});

test('many large lines still sum exactly or are refused', () => {
  const lines = Array.from({ length: 40 }, (_, i) => ({ componentId: `c${i}`, kind: 'EARNING', calc: 'FIXED', amountMinor: m.MAX_MINOR }));
  const r = m.evaluate(lines);
  assert.equal(r.grossMinor, 40 * m.MAX_MINOR);
  assert.ok(Number.isSafeInteger(r.grossMinor));
});

'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { civilKeyInZone, planYearUpdate } = require('./year_dates');

const d = (s) => new Date(s);

test('legacy India local-midnight picks recover the intended civil date', () => {
  // 1 April 2026 picked in IST is 2026-03-31T18:30Z; 31 March 2027 is 2027-03-30T18:30Z
  const plan = planYearUpdate({ startDate: d('2026-03-31T18:30:00Z'), endDate: d('2027-03-30T18:30:00Z') }, 'Asia/Kolkata');
  assert.equal(plan.startDateKey, '2026-04-01');
  assert.equal(plan.endDateKey, '2027-03-31');
  assert.equal(plan.startDate.toISOString(), '2026-04-01T00:00:00.000Z');
  assert.equal(plan.endDate.toISOString(), '2027-03-31T00:00:00.000Z');
});

test('the zone decides: the same instant is another civil date elsewhere', () => {
  assert.equal(civilKeyInZone(d('2026-03-31T18:30:00Z'), 'Asia/Kolkata'), '2026-04-01');
  assert.equal(civilKeyInZone(d('2026-03-31T18:30:00Z'), 'America/Los_Angeles'), '2026-03-31');
  assert.equal(civilKeyInZone(d('2026-04-01T07:00:00Z'), 'America/Los_Angeles'), '2026-04-01'); // LA local midnight (PDT)
});

test('already-normalised documents produce no update (idempotent)', () => {
  const ok = {
    startDate: d('2026-04-01T00:00:00Z'), endDate: d('2027-03-31T00:00:00Z'),
    startDateKey: '2026-04-01', endDateKey: '2027-03-31',
  };
  assert.equal(planYearUpdate(ok, 'Asia/Kolkata'), null);
  const first = planYearUpdate({ startDate: d('2026-03-31T18:30:00Z'), endDate: d('2027-03-30T18:30:00Z') }, 'Asia/Kolkata');
  assert.equal(planYearUpdate({ ...first }, 'Asia/Kolkata'), null);
});

test('UTC-midnight timestamps without keys are taken as civil dates, whatever the zone', () => {
  const plan = planYearUpdate({ startDate: d('2026-06-01T00:00:00Z'), endDate: d('2027-03-31T00:00:00Z') }, 'America/Los_Angeles');
  assert.equal(plan.startDateKey, '2026-06-01');
  assert.equal(plan.endDateKey, '2027-03-31');
});

test('an existing valid key wins over the instant', () => {
  const plan = planYearUpdate({
    startDate: d('2026-03-31T18:30:00Z'), endDate: d('2027-03-30T18:30:00Z'), startDateKey: '2026-04-02', endDateKey: '2027-03-31',
  }, 'Asia/Kolkata');
  assert.equal(plan.startDateKey, '2026-04-02');
});

test('an impossible range is refused rather than written', () => {
  assert.throws(() => planYearUpdate({ startDate: d('2027-03-30T18:30:00Z'), endDate: d('2026-03-31T18:30:00Z') }, 'Asia/Kolkata'), /not after/);
});

'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { calculateMonth, proportion } = require('./payroll_calculator');
const cal = require('./payroll_calendar');

// November 2026: 21 school days (Mon-Fri), the 2nd is a Monday.
const DAYS = cal.workingDatesOf('2026-11', null, []);
const LINES = [
  { componentId: 'basic', name: 'Basic', kind: 'EARNING', calc: 'FIXED', amountMinor: 2100000 },
  { componentId: 'hra', name: 'HRA', kind: 'EARNING', calc: 'PERCENT', percentBp: 4000, basisId: 'basic', amountMinor: 840000 },
  { componentId: 'pf', name: 'PF', kind: 'DEDUCTION', calc: 'PERCENT', percentBp: 1200, basisId: 'basic', amountMinor: 252000 },
  { componentId: 'adv', name: 'Advance', kind: 'DEDUCTION', calc: 'FIXED', amountMinor: 100000 },
];
const run = (o = {}) => calculateMonth({ workingDates: DAYS, lines: LINES, ...o });
const present = (dates) => Object.fromEntries(dates.map((d) => [d, 'PRESENT']));
const allPresent = () => present(DAYS);
const amount = (r, id) => r.lines.find((l) => l.componentId === id).amountMinor;

test('proportion rounds half up, exactly, and a zero denominator leaves the amount alone', () => {
  assert.equal(proportion(100, 1, 3), 33);
  assert.equal(proportion(100, 2, 3), 67);
  assert.equal(proportion(5, 1, 2), 3, '2.5 rounds up');
  assert.equal(proportion(3, 1, 2), 2, '1.5 rounds up');
  assert.equal(proportion(1, 1, 3), 0);
  assert.equal(proportion(10, 0, 5), 0);
  assert.equal(proportion(10, 5, 5), 10);
  assert.equal(proportion(77, 3, 0), 77);
  assert.equal(proportion(1e12, 41, 42), 976190476190, 'exact where a double would drift');
});

test('a full month present pays the structure exactly', () => {
  const r = run({ attendance: allPresent() });
  assert.deepEqual(r.lines.map((l) => l.amountMinor), [2100000, 840000, 252000, 100000]);
  assert.equal(r.grossMinor, 2940000);
  assert.equal(r.deductionsMinor, 352000);
  assert.equal(r.netMinor, 2588000);
  assert.equal(r.workingDays, 21);
  assert.equal(r.paidDays, 21);
  assert.equal(r.unpaidDays, 0);
  assert.deepEqual(r.warnings, []);
  assert.equal(r.days.present, 21);
});

test('absences reduce earnings pro rata; fixed deductions stay; percentages follow the prorated basis', () => {
  const att = allPresent();
  att['2026-11-02'] = 'ABSENT';
  att['2026-11-03'] = 'ABSENT';
  att['2026-11-04'] = 'ABSENT';
  const r = run({ attendance: att });
  assert.equal(r.unpaidDays, 3);
  assert.equal(amount(r, 'basic'), 1800000, '2,100,000 x 18/21');
  assert.equal(amount(r, 'hra'), 720000, '40% of the prorated basic');
  assert.equal(amount(r, 'pf'), 216000, '12% of the prorated basic');
  assert.equal(amount(r, 'adv'), 100000, 'an advance recovery is not prorated');
  assert.equal(r.grossMinor, 2520000);
  assert.equal(r.netMinor, 2520000 - 316000);
  assert.equal(r.days.absent, 3);
});

test('a half day pays one half; ABSENT pays none; LATE pays', () => {
  const att = allPresent();
  att['2026-11-02'] = 'HALF_DAY';
  att['2026-11-03'] = 'LATE';
  const r = run({ attendance: att });
  assert.equal(r.unpaidHalves, 1);
  assert.equal(r.unpaidDays, 0.5);
  assert.equal(r.days.halfDay, 1);
  assert.equal(r.days.late, 1);
  assert.equal(amount(r, 'basic'), proportion(2100000, 41, 42));
});

test('approved PAID leave pays; UNPAID leave does not; half-day leave covers one half', () => {
  const att = allPresent();
  for (const d of ['2026-11-02', '2026-11-03']) att[d] = 'ABSENT';
  const paidLeave = { dateKeys: ['2026-11-02', '2026-11-03'], halfDay: 'NONE', payType: 'PAID' };
  let r = run({ attendance: att, leave: [paidLeave] });
  assert.equal(r.unpaidDays, 0, 'leave wins over the ABSENT mark');
  assert.equal(r.days.paidLeave, 2);
  assert.equal(amount(r, 'basic'), 2100000);

  r = run({ attendance: allPresent(), leave: [{ dateKeys: ['2026-11-02', '2026-11-03'], halfDay: 'NONE', payType: 'UNPAID' }] });
  assert.equal(r.unpaidDays, 2);
  assert.equal(r.days.unpaidLeave, 2);
  assert.ok(r.warnings.some((w) => w.code === 'LEAVE_AND_PRESENT'), 'marked present on an unpaid leave day is reported');

  r = run({ attendance: allPresent(), leave: [{ dateKeys: ['2026-11-02'], halfDay: 'FIRST', payType: 'UNPAID' }] });
  assert.equal(r.unpaidHalves, 1, 'one half unpaid, the other half worked');
  assert.equal(r.paidHalves, 41);

  const half = allPresent();
  half['2026-11-02'] = 'ABSENT';
  r = run({ attendance: half, leave: [{ dateKeys: ['2026-11-02'], halfDay: 'SECOND', payType: 'PAID' }] });
  assert.equal(r.unpaidHalves, 1, 'the other half is absent: unpaid');
});

test('leave or attendance on a day that is not a school day changes nothing', () => {
  const att = { ...allPresent(), '2026-11-07': 'ABSENT', '2026-11-08': 'ABSENT' };
  const r = run({ attendance: att, leave: [{ dateKeys: ['2026-11-07', '2026-11-08'], halfDay: 'NONE', payType: 'UNPAID' }] });
  assert.equal(r.unpaidDays, 0);
  assert.equal(r.netMinor, 2588000);
});

test('not marked follows the school policy and is always reported', () => {
  const att = allPresent();
  delete att['2026-11-02'];
  delete att['2026-11-03'];
  let r = run({ attendance: att });
  assert.equal(r.unpaidDays, 0, 'default: paid');
  assert.equal(r.days.unmarked, 2);
  assert.deepEqual(r.warnings.map((w) => w.code), ['NOT_MARKED', 'NOT_MARKED']);
  r = run({ attendance: att, settings: { unmarkedDays: 'UNPAID' } });
  assert.equal(r.unpaidDays, 2);
  assert.equal(r.warnings.length, 2);
  assert.throws(() => run({ settings: { unmarkedDays: 'MAYBE' } }), /unmarkedDays/);
});

test('joining and leaving mid-month: days outside employment are unpaid', () => {
  const r = run({ attendance: allPresent(), employment: { from: '2026-11-16' } });
  assert.equal(r.days.notEmployed, 10, '2nd-13th: 10 school days before joining');
  assert.equal(r.paidDays, 11);
  assert.equal(amount(r, 'basic'), proportion(2100000, 22, 42));
  const left = run({ attendance: allPresent(), employment: { to: '2026-11-13' } });
  assert.equal(left.days.notEmployed, 11);
  const both = run({ attendance: allPresent(), employment: { from: '2026-11-09', to: '2026-11-13' } });
  assert.equal(both.paidDays, 5);
  const whole = run({ attendance: allPresent(), employment: { from: '2020-01-01', to: '2030-01-01' } });
  assert.equal(whole.netMinor, 2588000);
});

test('net is never negative: the last deductions are reduced and the shortfall reported', () => {
  const lines = [
    { componentId: 'basic', kind: 'EARNING', calc: 'FIXED', amountMinor: 2100000 },
    { componentId: 'pf', kind: 'DEDUCTION', calc: 'PERCENT', percentBp: 1200, basisId: 'basic', amountMinor: 252000 },
    { componentId: 'adv', kind: 'DEDUCTION', calc: 'FIXED', amountMinor: 300000 },
  ];
  const att = Object.fromEntries(DAYS.map((d, i) => [d, i < 18 ? 'ABSENT' : 'PRESENT']));
  const r = calculateMonth({ workingDates: DAYS, lines, attendance: att });
  const basic = proportion(2100000, 6, 42);
  assert.equal(basic, 300000);
  const pf = 36000;
  assert.equal(r.grossMinor, 300000);
  assert.equal(amount(r, 'pf'), pf, 'the percentage deduction is taken first, in full');
  assert.equal(amount(r, 'adv'), 300000 - pf, 'the LAST deduction is reduced to fit');
  assert.equal(r.netMinor, 0);
  assert.equal(r.unrecoveredDeductionMinor, 36000);
  assert.equal(r.lines.find((l) => l.componentId === 'adv').plannedMinor, 300000);
  assert.equal(r.deductionsMinor + r.unrecoveredDeductionMinor, pf + 300000);
  // a whole month absent: no earnings, nothing can be recovered
  const none = calculateMonth({ workingDates: DAYS, lines, attendance: Object.fromEntries(DAYS.map((d) => [d, 'ABSENT'])) });
  assert.equal(none.grossMinor, 0);
  assert.equal(none.netMinor, 0);
  assert.equal(none.deductionsMinor, 0);
  assert.equal(none.unrecoveredDeductionMinor, 300000, 'the percentage deduction is 0 of nothing; the whole advance is unrecovered');
});

test('the planned amount stays on each line so a payslip can show what was cut', () => {
  const att = allPresent();
  att['2026-11-02'] = 'ABSENT';
  const r = run({ attendance: att });
  const basic = r.lines.find((l) => l.componentId === 'basic');
  assert.equal(basic.plannedMinor, 2100000);
  assert.ok(basic.amountMinor < basic.plannedMinor);
});

test('a month with no school days pays the structure in full and says so', () => {
  const r = calculateMonth({ workingDates: [], lines: LINES });
  assert.equal(r.netMinor, 2588000);
  assert.deepEqual(r.warnings, [{ code: 'NO_WORKING_DAYS' }]);
  assert.equal(r.period, null);
});

test('overlapping leave on one day is reported and never pays or cuts more than the day', () => {
  const r = run({
    attendance: allPresent(),
    leave: [
      { dateKeys: ['2026-11-02'], halfDay: 'NONE', payType: 'PAID' },
      { dateKeys: ['2026-11-02'], halfDay: 'NONE', payType: 'UNPAID' },
    ],
  });
  assert.equal(r.paidHalves + r.unpaidHalves, 42);
  assert.ok(r.warnings.some((w) => w.code === 'LEAVE_OVERLAP'));
  assert.equal(r.unpaidHalves, 0, 'the first leave to cover the day wins');
});

test('a leave type with no pay concept pays, with a warning', () => {
  const r = run({ attendance: allPresent(), leave: [{ dateKeys: ['2026-11-02'], halfDay: 'NONE', payType: 'NA' }] });
  assert.equal(r.unpaidDays, 0);
  assert.ok(r.warnings.some((w) => w.code === 'LEAVE_PAY_TYPE_UNKNOWN'));
});

test('the same input always gives the same answer, and the input is not changed', () => {
  const att = allPresent();
  att['2026-11-04'] = 'ABSENT';
  const input = { workingDates: [...DAYS], lines: LINES.map((l) => ({ ...l })), attendance: att, leave: [] };
  const snapshot = JSON.stringify(input);
  const a = calculateMonth(input);
  const b = calculateMonth(input);
  assert.deepEqual(a, b);
  assert.equal(JSON.stringify(input), snapshot);
});

test('duplicate dates are counted once; unsorted dates are fine', () => {
  const r = calculateMonth({ workingDates: [...DAYS, ...DAYS].reverse(), lines: LINES, attendance: allPresent() });
  assert.equal(r.workingDays, 21);
  assert.equal(r.netMinor, 2588000);
});

test('paid halves plus unpaid halves always equal the school-day halves (property)', () => {
  const statuses = [undefined, 'PRESENT', 'LATE', 'HALF_DAY', 'ABSENT'];
  const halfs = ['NONE', 'FIRST', 'SECOND'];
  const pay = ['PAID', 'UNPAID', 'NA'];
  let seed = 12345;
  const rnd = (n) => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff), seed % n);
  for (let t = 0; t < 400; t++) {
    const attendance = {};
    for (const d of DAYS) {
      const s = statuses[rnd(statuses.length)];
      if (s) attendance[d] = s;
    }
    const leave = Array.from({ length: rnd(4) }, () => ({ dateKeys: DAYS.filter(() => rnd(6) === 0), halfDay: halfs[rnd(3)], payType: pay[rnd(3)] }));
    const employment = rnd(4) === 0 ? { from: DAYS[rnd(21)] } : {};
    const r = run({ attendance, leave, employment, settings: { unmarkedDays: rnd(2) ? 'PAID' : 'UNPAID' } });
    assert.equal(r.paidHalves + r.unpaidHalves, 42, `case ${t}`);
    assert.ok(r.netMinor >= 0 && r.grossMinor >= r.deductionsMinor, `case ${t}`);
    assert.ok(r.lines.every((l) => Number.isSafeInteger(l.amountMinor) && l.amountMinor >= 0), `case ${t}`);
    assert.ok(r.paidHalves >= 0 && r.unpaidHalves >= 0, `case ${t}`);
  }
});

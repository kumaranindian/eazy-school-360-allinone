'use strict';
const test = require('node:test');
const assert = require('node:assert');
const c = require('./payroll_calendar');

const ts = (key) => ({ toDate: () => new Date(`${key}T00:00:00Z`) });
const hol = (date, type = 'PUBLIC', extra = {}) => ({ date: ts(date), type, status: 'ACTIVE', ...extra });
const wd = (o = {}) => ({ isWorkingDay: { SATURDAY: false, SUNDAY: false }, saturdayOffWeeks: [], effectiveFrom: null, history: [], ...o });

test('weekday and occurrence from civil dates', () => {
  assert.equal(c.weekdayOf('2026-11-17'), 'TUESDAY');
  assert.equal(c.weekdayOf('2026-11-01'), 'SUNDAY');
  assert.equal(c.weekdayOf('2024-02-29'), 'THURSDAY', 'leap day');
  assert.deepEqual([1, 7, 8, 14, 15, 21, 22, 28, 29, 31].map((d) => c.occurrenceOf(`2026-01-${String(d).padStart(2, '0')}`)), [1, 1, 2, 2, 3, 3, 4, 4, 5, 5]);
});

test('datesOf: lengths of months, leap years; bad periods refused', () => {
  assert.equal(c.datesOf('2026-02').length, 28);
  assert.equal(c.datesOf('2028-02').length, 29);
  assert.equal(c.datesOf('2026-11').length, 30);
  assert.equal(c.datesOf('2026-12').length, 31);
  assert.equal(c.datesOf('2026-11')[0], '2026-11-01');
  for (const bad of ['2026-13', '2026-00', '26-11', '2026-1', '', 'x']) assert.throws(() => c.datesOf(bad), /period/);
});

test('default pattern is Monday to Friday; November 2026 has 21 school days', () => {
  assert.equal(c.workingDatesOf('2026-11', null, []).length, 21);
  assert.equal(c.workingDatesOf('2026-11', {}, []).length, 21);
  assert.equal(c.workingDatesOf('2026-11', null, []).includes('2026-11-14'), false, 'a Saturday');
});

test('a Saturday pattern: every Saturday, alternate Saturdays (1st and 3rd off), a 5th-Saturday rule only in months that have one', () => {
  assert.equal(c.workingDatesOf('2026-11', wd({ isWorkingDay: { SATURDAY: true, SUNDAY: false } }), []).length, 21 + 4, 'Saturdays 7, 14, 21, 28 work');
  const alt = wd({ isWorkingDay: { SATURDAY: true, SUNDAY: false }, saturdayOffWeeks: [1, 3] });
  const nov = c.workingDatesOf('2026-11', alt, []);
  assert.equal(nov.includes('2026-11-07'), false, '1st Saturday off');
  assert.equal(nov.includes('2026-11-14'), true, '2nd Saturday works');
  assert.equal(nov.includes('2026-11-21'), false, '3rd Saturday off');
  assert.equal(nov.includes('2026-11-28'), true, '4th Saturday works');
  const fifth = wd({ isWorkingDay: { SATURDAY: true, SUNDAY: false }, saturdayOffWeeks: [5] });
  assert.equal(c.workingDatesOf('2026-10', fifth, []).includes('2026-10-31'), false, 'October 2026 has a 5th Saturday');
  assert.equal(c.workingDatesOf('2026-11', fifth, []).length, 21 + 4, 'November 2026 has none');
});

test('holidays close school days; ranges; inactive and special working day entries', () => {
  assert.equal(c.dayKind('2026-11-17', null, [hol('2026-11-17')]), 'HOLIDAY');
  const range = [hol('2026-11-16', 'VACATION', { endDate: ts('2026-11-18') })];
  assert.deepEqual(['2026-11-15', '2026-11-16', '2026-11-17', '2026-11-18', '2026-11-19'].map((k) => c.dayKind(k, null, range)), ['WEEKLY_OFF', 'HOLIDAY', 'HOLIDAY', 'HOLIDAY', 'WORKING']);
  assert.equal(c.dayKind('2026-11-17', null, [hol('2026-11-17', 'PUBLIC', { status: 'INACTIVE' })]), 'WORKING', 'an inactive entry is ignored');
  assert.equal(c.dayKind('2026-11-14', null, [hol('2026-11-14', 'SPECIAL_WORKING_DAY')]), 'SPECIAL_WORKING_DAY', 'a Saturday made a working day');
  assert.equal(c.dayKind('2026-11-17', null, [hol('2026-11-17', 'SPECIAL_WORKING_DAY')]), 'SPECIAL_WORKING_DAY');
  assert.equal(c.dayKind('2026-11-14', null, [hol('2026-11-14', 'SPECIAL_WORKING_DAY'), hol('2026-11-14', 'FESTIVAL')]), 'HOLIDAY', 'a closing holiday wins over a special working day');
  assert.equal(c.workingDatesOf('2026-11', null, [hol('2026-11-02'), hol('2026-11-03')]).length, 19);
  assert.equal(c.dayKind('2026-11-17', null, [null, {}, { date: 5, status: 'ACTIVE', type: 'PUBLIC' }]), 'WORKING', 'junk entries are ignored');
});

test('holiday dates read as Timestamp, Date or key', () => {
  assert.equal(c.keyOf(ts('2026-11-17')), '2026-11-17');
  assert.equal(c.keyOf(new Date('2026-11-17T00:00:00Z')), '2026-11-17');
  assert.equal(c.keyOf('2026-11-17'), '2026-11-17');
  for (const bad of [null, undefined, 5, '17-11-2026', new Date('x'), {}]) assert.equal(c.keyOf(bad), null);
});

test('effective-dated weekly pattern: earlier dates keep the pattern they had', () => {
  const cfg = wd({
    isWorkingDay: { SATURDAY: false, SUNDAY: false },
    effectiveFrom: '2026-11-01',
    history: [{ isWorkingDay: { SATURDAY: true, SUNDAY: false }, saturdayOffWeeks: [], effectiveFrom: '2026-01-01' }],
  });
  assert.equal(c.dayKind('2026-10-10', cfg, []), 'WORKING', 'a Saturday in October used the old pattern');
  assert.equal(c.dayKind('2026-11-14', cfg, []), 'WEEKLY_OFF', 'a Saturday from November is off');
  assert.equal(c.dayKind('2025-06-07', cfg, []), 'WORKING', 'before every pattern: the oldest one');
});

'use strict';

// Which dates of a month are school days, for payroll. PURE: a port of the app's one calendar
// (lib/features/academic_setup/domain/school_calendar.dart + working_days.dart + weekly_pattern.dart), with
// the same precedence: an active closing holiday wins; otherwise an active special working day opens the
// date; otherwise the weekly pattern in force on that date decides. Dates are civil `yyyy-mm-dd` keys; no
// time zone is ever applied. Pay must count days exactly as attendance and leave already do.

const WEEKDAYS = Object.freeze(['SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY']);
const DEFAULT_PATTERN = Object.freeze({
  isWorkingDay: { MONDAY: true, TUESDAY: true, WEDNESDAY: true, THURSDAY: true, FRIDAY: true, SATURDAY: false, SUNDAY: false },
  saturdayOffWeeks: [],
  effectiveFrom: null,
});
const KEY = /^\d{4}-\d{2}-\d{2}$/;
const PERIOD = /^\d{4}-(0[1-9]|1[0-2])$/;

const weekdayOf = (key) => WEEKDAYS[new Date(`${key}T00:00:00Z`).getUTCDay()];
/** 1st..5th occurrence of a weekday, from the day of month (1-7 -> 1, 8-14 -> 2, ...). */
const occurrenceOf = (key) => Math.floor((Number(key.slice(8, 10)) - 1) / 7) + 1;

/** `yyyy-mm-dd` of a stored date (Firestore Timestamp, Date, or a key). Holiday dates are UTC midnight. */
function keyOf(v) {
  if (typeof v === 'string') return KEY.test(v) ? v : null;
  const d = v && typeof v.toDate === 'function' ? v.toDate() : v instanceof Date ? v : null;
  return d && !Number.isNaN(d.getTime()) ? d.toISOString().slice(0, 10) : null;
}

const asPattern = (p) => ({
  isWorkingDay: { ...DEFAULT_PATTERN.isWorkingDay, ...((p && p.isWorkingDay) || {}) },
  saturdayOffWeeks: Array.isArray(p && p.saturdayOffWeeks) ? p.saturdayOffWeeks : [],
  effectiveFrom: p && typeof p.effectiveFrom === 'string' ? p.effectiveFrom : null,
});

/** The pattern in force on [key] (WorkingDays.patternFor): the latest one effective on or before it. */
function patternFor(workingDays, key) {
  const current = asPattern(workingDays);
  const from = current.effectiveFrom;
  if (from === null || key >= from) return current;
  const history = (Array.isArray(workingDays && workingDays.history) ? workingDays.history : []).map(asPattern);
  let best = null;
  for (const p of history) {
    const f = p.effectiveFrom;
    if (f === null || key >= f) {
      if (best === null || best.effectiveFrom === null || (f !== null && f >= best.effectiveFrom)) best = p;
    }
  }
  return best || (history.length ? history[0] : current);
}

function isWeeklyOff(pattern, key) {
  const name = weekdayOf(key);
  if (pattern.isWorkingDay[name] === false) return true;
  return name === 'SATURDAY' && pattern.saturdayOffWeeks.includes(occurrenceOf(key));
}

/** One date: 'WORKING' | 'SPECIAL_WORKING_DAY' | 'WEEKLY_OFF' | 'HOLIDAY'. [holidays] are { date, endDate, type, status }. */
function dayKind(key, workingDays, holidays) {
  const covering = (holidays || []).filter((h) => {
    if (!h || h.status !== 'ACTIVE') return false;
    const from = keyOf(h.date);
    const to = keyOf(h.endDate) || from;
    return from !== null && key >= from && key <= to;
  });
  if (covering.some((h) => h.type !== 'SPECIAL_WORKING_DAY')) return 'HOLIDAY';
  if (covering.some((h) => h.type === 'SPECIAL_WORKING_DAY')) return 'SPECIAL_WORKING_DAY';
  return isWeeklyOff(patternFor(workingDays, key), key) ? 'WEEKLY_OFF' : 'WORKING';
}

/** Every date key of `yyyy-mm`. */
function datesOf(period) {
  if (!PERIOD.test(period)) throw new Error('period must be yyyy-mm');
  const y = Number(period.slice(0, 4));
  const m = Number(period.slice(5, 7));
  const days = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return Array.from({ length: days }, (_, i) => `${period}-${String(i + 1).padStart(2, '0')}`);
}

/** The school days of `yyyy-mm` (working days and special working days), in order. */
function workingDatesOf(period, workingDays, holidays) {
  return datesOf(period).filter((k) => {
    const kind = dayKind(k, workingDays, holidays);
    return kind === 'WORKING' || kind === 'SPECIAL_WORKING_DAY';
  });
}

module.exports = { WEEKDAYS, DEFAULT_PATTERN, KEY, PERIOD, weekdayOf, occurrenceOf, keyOf, patternFor, isWeeklyOff, dayKind, datesOf, workingDatesOf };

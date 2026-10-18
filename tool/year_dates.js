'use strict';
// Pure helpers for migrating academic-year boundaries to civil dates
// (docs/production-audit ACAD-1). Legacy documents hold the LOCAL-midnight
// instant of whoever picked the date (e.g. 2026-03-31T18:30Z for 1 April in
// India). The intended civil date is that instant's date in the zone it was
// picked in.

const KEY = /^\d{4}-\d{2}-\d{2}$/;

/** yyyy-MM-dd of [instant] in IANA [zone]. */
function civilKeyInZone(instant, zone) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: zone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(instant);
  const get = (t) => parts.find((p) => p.type === t).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

function isUtcMidnight(d) {
  return d.getUTCHours() === 0 && d.getUTCMinutes() === 0 && d.getUTCSeconds() === 0 && d.getUTCMilliseconds() === 0;
}

/** The civil key for one stored boundary. */
function boundaryKey(stored, existingKey, zone) {
  if (typeof existingKey === 'string' && KEY.test(existingKey)) return existingKey;
  const d = stored instanceof Date ? stored : stored.toDate();
  return isUtcMidnight(d) ? d.toISOString().slice(0, 10) : civilKeyInZone(d, zone);
}

/**
 * The update for one academic-year document, or null when it is already
 * normalised. [data] has Date-like `startDate` / `endDate`.
 */
function planYearUpdate(data, zone) {
  const startKey = boundaryKey(data.startDate, data.startDateKey, zone);
  const endKey = boundaryKey(data.endDate, data.endDateKey, zone);
  const startUtc = new Date(`${startKey}T00:00:00.000Z`);
  const endUtc = new Date(`${endKey}T00:00:00.000Z`);
  const asDate = (v) => (v instanceof Date ? v : v.toDate());
  const same =
    data.startDateKey === startKey &&
    data.endDateKey === endKey &&
    asDate(data.startDate).getTime() === startUtc.getTime() &&
    asDate(data.endDate).getTime() === endUtc.getTime();
  if (same) return null;
  if (endUtc.getTime() <= startUtc.getTime()) throw new Error(`end ${endKey} is not after start ${startKey}`);
  return { startDate: startUtc, endDate: endUtc, startDateKey: startKey, endDateKey: endKey };
}

module.exports = { civilKeyInZone, boundaryKey, planYearUpdate };

'use strict';

// School-level fee reminder policy: the stored settings, their validation, the
// calendar arithmetic and the message text. Pure (no Firestore) except for
// `updateFeeReminderSettings`, so the scheduler (notify_events.js) and the
// callable share one definition.
//
//   schools/{s}/feeReminderSettings/config = {
//     schoolId, enabled, deliveryTime: 'HH:MM', includeAmount, includeInvoiceNumber,
//     beforeDue: { enabled, offsets: [{ days, enabled }] },   // days 0..60 before the due date (0 = on it)
//     afterDue:  { enabled, offsets: [{ days, enabled }] },   // days 1..90 after it
//     updatedAt, updatedBy
//   }
//
// Read by school admins, written ONLY by the `updateFeeReminderSettings`
// callable (rules deny client writes). The time zone is not stored here: it is
// the school's Regional setting (`schools/{s}.timezone`).
//
// A school without the document gets DEFAULTS, which keep what every school had
// before this existed (3 days before and on the day, 08:00, no amount in the
// text) and add the overdue steps. Because a reminder is matched to an exact
// due date, switching on overdue steps never reaches back to invoices that
// are already past those days.

const MAX_BEFORE_DAYS = 60;
const MAX_AFTER_DAYS = 90;
const MAX_PER_LIST = 10;
const LATEST_DELIVERY_MINUTE = 21 * 60; // the 3-hour retry window must end before midnight
const WINDOW_MINUTES = 180; // a missed hourly run is retried for this long

const DEFAULTS = Object.freeze({
  enabled: true,
  deliveryTime: '08:00',
  includeAmount: false,
  includeInvoiceNumber: false,
  beforeDue: { enabled: true, offsets: [{ days: 3, enabled: true }, { days: 0, enabled: true }] },
  afterDue: { enabled: true, offsets: [{ days: 1, enabled: true }, { days: 7, enabled: true }, { days: 15, enabled: true }] },
});

const clone = (o) => structuredClone(o);
const defaults = () => clone(DEFAULTS);

function validZone(z) {
  try {
    new Intl.DateTimeFormat('en', { timeZone: z });
    return typeof z === 'string' && z.length > 0;
  } catch {
    return false;
  }
}

/** Minutes after midnight of "HH:MM", or null. */
function minutesOf(t) {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(String(t || ''));
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
}

/**
 * Checks a settings object coming from a client. Returns { value } (normalised,
 * offsets sorted) or { errors: { field: message } }. Nothing is coerced: a
 * wrong type is an error, not a default.
 */
function validateSettings(input) {
  const errors = {};
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { errors: { settings: 'Settings are required.' } };
  const bool = (v, field) => {
    if (typeof v !== 'boolean') errors[field] = 'Must be on or off.';
    return v === true;
  };
  const value = {
    enabled: bool(input.enabled, 'enabled'),
    deliveryTime: input.deliveryTime,
    includeAmount: bool(input.includeAmount, 'includeAmount'),
    includeInvoiceNumber: bool(input.includeInvoiceNumber, 'includeInvoiceNumber'),
  };
  const minute = minutesOf(value.deliveryTime);
  if (minute === null) errors.deliveryTime = 'Use a time like 08:00.';
  else if (minute > LATEST_DELIVERY_MINUTE) errors.deliveryTime = 'Reminders cannot be scheduled after 21:00.';

  const list = (name, min, max) => {
    const g = input[name];
    if (!g || typeof g !== 'object') {
      errors[name] = 'Missing.';
      return { enabled: false, offsets: [] };
    }
    const out = { enabled: bool(g.enabled, `${name}.enabled`), offsets: [] };
    if (!Array.isArray(g.offsets)) {
      errors[name] = 'Reminder days are required.';
      return out;
    }
    if (g.offsets.length > MAX_PER_LIST) errors[name] = `At most ${MAX_PER_LIST} reminders.`;
    const seen = new Set();
    for (const o of g.offsets) {
      const days = o && o.days;
      if (!Number.isInteger(days) || days < min || days > max) {
        errors[name] = `Days must be whole numbers from ${min} to ${max}.`;
        continue;
      }
      if (typeof o.enabled !== 'boolean') {
        errors[name] = 'Each reminder must be on or off.';
        continue;
      }
      if (seen.has(days)) {
        errors[name] = `Day ${days} is listed twice.`;
        continue;
      }
      seen.add(days);
      out.offsets.push({ days, enabled: o.enabled });
    }
    return out;
  };
  // Before the due date the biggest number is the earliest; after it, the smallest.
  value.beforeDue = list('beforeDue', 0, MAX_BEFORE_DAYS);
  value.beforeDue.offsets.sort((a, b) => b.days - a.days);
  value.afterDue = list('afterDue', 1, MAX_AFTER_DAYS);
  value.afterDue.offsets.sort((a, b) => a.days - b.days);
  return Object.keys(errors).length ? { errors } : { value };
}

/**
 * The policy the scheduler runs with. Lenient on purpose: a missing document
 * is the defaults, and a stored value that fails validation (written by hand,
 * or by a future version) falls back to the defaults rather than silently
 * stopping every reminder.
 */
function effectiveSettings(stored) {
  if (!stored) return defaults();
  const r = validateSettings({
    enabled: stored.enabled,
    deliveryTime: stored.deliveryTime,
    includeAmount: stored.includeAmount,
    includeInvoiceNumber: stored.includeInvoiceNumber,
    beforeDue: stored.beforeDue,
    afterDue: stored.afterDue,
  });
  return r.value || defaults();
}

// ---- calendar arithmetic (civil dates, never 24-hour spans) ---------------

/** yyyy-MM-dd of [now] on the calendar of [timeZone]. */
function civilToday(now, timeZone) {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

/** [key] shifted by [days] calendar days (pure date arithmetic: DST cannot move it). */
function addDays(key, days) {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/** Whole days from [fromKey] to [toKey] (positive when [toKey] is later). */
function daysBetween(fromKey, toKey) {
  const t = (k) => {
    const [y, m, d] = k.split('-').map(Number);
    return Date.UTC(y, m - 1, d);
  };
  return Math.round((t(toKey) - t(fromKey)) / 86400000);
}

/** Minutes after local midnight in [timeZone] at [now]. */
function localMinutes(now, timeZone) {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
  const get = (t) => Number(parts.find((p) => p.type === t).value);
  return get('hour') * 60 + get('minute');
}

/** True from the delivery time for [WINDOW_MINUTES] (so a missed hourly run is retried). */
function inDeliveryWindow(now, timeZone, deliveryTime) {
  const start = minutesOf(deliveryTime);
  if (start === null) return false;
  const m = localMinutes(now, timeZone);
  return m >= start && m < start + WINDOW_MINUTES;
}

/**
 * The reminders that look for a given due date today: [{ kind, days, dueKey }].
 * kind BEFORE: due date is [days] ahead (0 = today). kind AFTER: it was [days] ago.
 */
function activeReminders(settings, todayKey) {
  if (!settings.enabled) return [];
  const out = [];
  if (settings.beforeDue.enabled) {
    for (const o of settings.beforeDue.offsets) if (o.enabled) out.push({ kind: 'BEFORE', days: o.days, dueKey: addDays(todayKey, o.days) });
  }
  if (settings.afterDue.enabled) {
    for (const o of settings.afterDue.offsets) if (o.enabled) out.push({ kind: 'AFTER', days: o.days, dueKey: addDays(todayKey, -o.days) });
  }
  return out;
}

// ---- eligibility ----------------------------------------------------------

const OPEN_INVOICE = new Set(['ISSUED', 'PARTIALLY_PAID']);

/** Only a live, issued, unsettled invoice with a due date is reminded. */
function isRemindable(inv) {
  return !!inv && OPEN_INVOICE.has(inv.status) && Number.isFinite(inv.balanceMinor) && inv.balanceMinor > 0 &&
    /^\d{4}-\d{2}-\d{2}$/.test(String(inv.dueDateKey || ''));
}

// ---- message text ---------------------------------------------------------

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
function dateText(key) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ''));
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : String(key || '');
}

/** "₹1,500.00" for integer minor units; the decimals come from the currency. */
function formatMoney(minor, currency) {
  const code = typeof currency === 'string' && /^[A-Z]{3}$/.test(currency) ? currency : 'INR';
  try {
    const f = new Intl.NumberFormat(code === 'INR' ? 'en-IN' : 'en', { style: 'currency', currency: code });
    const digits = f.resolvedOptions().maximumFractionDigits;
    return f.format(minor / 10 ** digits);
  } catch {
    return `${code} ${minor}`;
  }
}

/**
 * Title and body of one reminder. [reminder] is { kind, days }; [invoice] the
 * freshly read invoice (so the amount is the CURRENT balance); [settings] says
 * whether the amount and invoice number are included.
 */
function buildMessage(reminder, invoice, settings) {
  const student = String(invoice.studentName || '').trim() || 'your child';
  const ref = settings.includeInvoiceNumber && invoice.invoiceNumber ? ` (invoice ${invoice.invoiceNumber})` : '';
  const amount = settings.includeAmount ? formatMoney(invoice.balanceMinor, invoice.currency) : null;
  const due = dateText(invoice.dueDateKey);
  const amt = (label) => (amount ? ` ${label}: ${amount}.` : '');
  if (reminder.kind === 'AFTER') {
    const n = reminder.days;
    return {
      title: 'Fee overdue',
      body: `Dear Parent, the fee payment for ${student}${ref} is overdue by ${n} day${n === 1 ? '' : 's'}.` +
        `${amt('Outstanding amount')} Please contact the school office if payment has already been made.`,
    };
  }
  if (reminder.days === 0) {
    return { title: 'Fee due today', body: `Dear Parent, the fee payment for ${student}${ref} is due today.${amt('Amount')}` };
  }
  return {
    title: 'Fee due soon',
    body: `Dear Parent, the fee invoice for ${student}${ref} is due on ${due}.${amt('Amount')} Please complete the payment on time.`,
  };
}

// ---- the callable ---------------------------------------------------------

const settingsDoc = (db, schoolId) => db.collection('schools').doc(schoolId).collection('feeReminderSettings').doc('config');

/**
 * Saves a school's policy. SCHOOL_ADMIN of that school only; the school id is
 * checked against the caller's own profile (never trusted from the client) and
 * every value is validated here.
 */
async function updateFeeReminderSettings(ctx, callerUid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  if (typeof schoolId !== 'string' || !schoolId) return { error: 'INVALID_ARGUMENT' };
  const caller = await require('./access').assertAdmin(db, callerUid, schoolId, null, token);
  if (!caller || caller.role !== 'SCHOOL_ADMIN') return { error: 'PERMISSION_DENIED' };
  const parsed = validateSettings(data.settings);
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: Object.entries(parsed.errors).map(([k, v]) => `${k}: ${v}`).join('; ') };
  await settingsDoc(db, schoolId).set({ schoolId, ...parsed.value, updatedAt: now, updatedBy: callerUid });
  return { result: { settings: parsed.value } };
}

module.exports = {
  DEFAULTS,
  MAX_BEFORE_DAYS,
  MAX_AFTER_DAYS,
  MAX_PER_LIST,
  WINDOW_MINUTES,
  defaults,
  validZone,
  minutesOf,
  validateSettings,
  effectiveSettings,
  civilToday,
  addDays,
  daysBetween,
  localMinutes,
  inDeliveryWindow,
  activeReminders,
  isRemindable,
  dateText,
  formatMoney,
  buildMessage,
  settingsDoc,
  updateFeeReminderSettings,
};

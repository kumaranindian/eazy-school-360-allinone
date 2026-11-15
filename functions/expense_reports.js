'use strict';

// Expense reports and export (docs/expense-management/, phase E5).
//
//   getExpenseReport  totals by status, by category, by month (and by branch for the whole school) over a
//                     date range of at most 366 days
//   exportExpenses    the same rows as a CSV (capped, spreadsheet-safe)
//
// "Spent" means APPROVED + PAID: money the school has committed to. Drafts, submitted (awaiting a decision),
// rejected and cancelled expenses are shown separately and never counted as spend. Money is integer minor
// units of the school's one currency. The whole school (every branch) is for school administrators only;
// a branch admin or finance user sees their own branch.

const { authorize, expenseCollection, expenseView, validDate, civilToday, wall, STATUSES } = require('./expenses');
const { validId } = require('./ids');
const { csvCell } = require('./audit');

const SPEND = Object.freeze(['APPROVED', 'PAID']);
const MAX_SPAN_DAYS = 366;
const SCAN_CAP = 20000;
const EXPORT_CAP = 10000;
const MAX_BRANCHES = 50;
const PAGE = 500;
const DAY = 86400000;

const dayMs = (key) => Date.parse(`${key}T00:00:00Z`);

/** Validates the range. Returns { errors } or { value: { fromDate, toDate } }. */
function validateRange(data, today) {
  const d = data && typeof data === 'object' ? data : {};
  const errors = {};
  if (!validDate(d.fromDate)) errors.fromDate = 'a date (yyyy-mm-dd)';
  if (!validDate(d.toDate)) errors.toDate = 'a date (yyyy-mm-dd)';
  if (!Object.keys(errors).length) {
    if (d.fromDate > d.toDate) errors.toDate = 'cannot be before the start date';
    else if (d.toDate > today) errors.toDate = 'cannot be in the future';
    else if ((dayMs(d.toDate) - dayMs(d.fromDate)) / DAY >= MAX_SPAN_DAYS) errors.toDate = `the range is at most ${MAX_SPAN_DAYS} days`;
  }
  if (Object.keys(errors).length) return { errors };
  return { value: { fromDate: d.fromDate, toDate: d.toDate } };
}
const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');

/** Pure: the report numbers for [rows] (expense views). [branchNames] maps branch id -> name. */
function aggregate(rows, { branchNames = {}, includeBranches = false } = {}) {
  const byStatus = Object.fromEntries(STATUSES.map((s) => [s, { count: 0, totalMinor: 0 }]));
  const cat = new Map();
  const month = new Map();
  const branch = new Map();
  let spent = 0;
  let paid = 0;
  for (const r of rows) {
    const st = byStatus[r.status];
    if (!st) continue; // an unknown status from the future is not counted as anything
    st.count += 1;
    st.totalMinor += r.amountMinor;
    if (!SPEND.includes(r.status)) continue;
    spent += r.amountMinor;
    const isPaid = r.status === 'PAID';
    if (isPaid) paid += r.amountMinor;
    const bump = (map, key, init) => {
      const cur = map.get(key) || { ...init, count: 0, totalMinor: 0, paidMinor: 0 };
      cur.count += 1;
      cur.totalMinor += r.amountMinor;
      if (isPaid) cur.paidMinor += r.amountMinor;
      map.set(key, cur);
    };
    bump(cat, r.categoryId, { categoryId: r.categoryId, name: r.categoryName });
    bump(month, String(r.expenseDate).slice(0, 7), { month: String(r.expenseDate).slice(0, 7) });
    if (includeBranches) bump(branch, r.branchId, { branchId: r.branchId, name: branchNames[r.branchId] || r.branchId });
  }
  const desc = (a, b) => b.totalMinor - a.totalMinor || String(a.name).localeCompare(String(b.name));
  return {
    totals: {
      spentMinor: spent,
      paidMinor: paid,
      unpaidApprovedMinor: spent - paid,
      awaitingApprovalMinor: byStatus.SUBMITTED.totalMinor,
    },
    byStatus,
    byCategory: [...cat.values()].sort(desc),
    byMonth: [...month.values()].sort((a, b) => a.month.localeCompare(b.month)),
    byBranch: includeBranches ? [...branch.values()].sort(desc) : [],
  };
}

/** The branches the caller may report on, or { error }. */
async function scope(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  if (data && data.branchId !== undefined && data.branchId !== null && data.branchId !== '') {
    if (!validId(data.branchId)) return { error: 'PERMISSION_DENIED' };
    const caller = await authorize(db, uid, token, schoolId, data.branchId, 'report');
    if (!caller) return { error: 'PERMISSION_DENIED' };
    return { schoolId, branchIds: [data.branchId], whole: false, caller };
  }
  // The whole school: school administrators only.
  const caller = await authorize(db, uid, token, schoolId, null, 'report');
  if (!caller || caller.role !== 'SCHOOL_ADMIN') return { error: 'PERMISSION_DENIED' };
  const snap = await db.collection('schools').doc(schoolId).collection('branches').limit(MAX_BRANCHES + 1).get();
  if (snap.docs.length > MAX_BRANCHES) return { error: 'FAILED_PRECONDITION', reason: `report one branch at a time (more than ${MAX_BRANCHES} branches)` };
  return { schoolId, branchIds: snap.docs.map((d) => d.id), branchNames: Object.fromEntries(snap.docs.map((d) => [d.id, (d.data() || {}).name || d.id])), whole: true, caller };
}

/** Reads the expenses of [branchIds] dated within the range. Returns { rows, truncated }. */
async function collect(db, schoolId, branchIds, { fromDate, toDate }, cap) {
  const rows = [];
  let truncated = false;
  for (const b of branchIds) {
    let last = null;
    for (;;) {
      let q = expenseCollection(db, schoolId, b).where('expenseDate', '>=', fromDate).where('expenseDate', '<=', toDate).orderBy('expenseDate', 'asc');
      if (last) q = q.startAfter(last);
      const snap = await q.limit(PAGE).get();
      for (const d of snap.docs) {
        if (rows.length >= cap) {
          truncated = true;
          break;
        }
        rows.push({ ...expenseView(d.id, d.data()), branchId: b });
        last = d;
      }
      if (truncated || snap.docs.length < PAGE) break;
    }
    if (truncated) break;
  }
  return { rows, truncated };
}

async function schoolFacts(db, schoolId, now) {
  const s = (await db.collection('schools').doc(schoolId).get()).data() || {};
  return { currency: s.currency || 'INR', today: civilToday(now, s.timezone || 'UTC') };
}

async function getExpenseReport(ctx, uid, token, data) {
  const { db } = ctx;
  const sc = await scope(ctx, uid, token, data);
  if (sc.error) return sc;
  const facts = await schoolFacts(db, sc.schoolId, wall(ctx));
  const range = validateRange(data, facts.today);
  if (range.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(range.errors) };
  const { rows, truncated } = await collect(db, sc.schoolId, sc.branchIds, range.value, SCAN_CAP);
  return {
    result: {
      currency: facts.currency,
      ...range.value,
      scope: sc.whole ? 'SCHOOL' : 'BRANCH',
      rows: rows.length,
      truncated,
      ...aggregate(rows, { branchNames: sc.branchNames || {}, includeBranches: sc.whole }),
    },
  };
}

// ---- CSV ---------------------------------------------------------------------------------------------

/** "1250.50" for integer minor units; the decimals come from the currency; exact (no floating point). */
function plainAmount(minor, currency) {
  let digits = 2;
  try {
    digits = new Intl.NumberFormat('en', { style: 'currency', currency }).resolvedOptions().maximumFractionDigits;
  } catch (_) {
    digits = 2;
  }
  const neg = minor < 0;
  const s = String(Math.abs(minor)).padStart(digits + 1, '0');
  const out = digits === 0 ? s : `${s.slice(0, -digits)}.${s.slice(-digits)}`;
  return neg ? `-${out}` : out;
}

const CSV_HEADER = ['number', 'branch', 'date', 'category', 'payee', 'details', 'amount', 'currency', 'status', 'payment_mode', 'payment_reference', 'paid_date', 'recorded_by', 'decided_by', 'decision_reason'];

function toCsv(rows, { currency, branchNames = {} }) {
  const lines = [CSV_HEADER.join(',')];
  for (const r of rows) {
    lines.push([
      r.number, branchNames[r.branchId] || r.branchId, r.expenseDate, r.categoryName, r.payee, r.description, plainAmount(r.amountMinor, currency), currency, r.status,
      r.paymentMode || '', r.paymentReference, r.paidDate || '', r.createdByName || '', r.decidedByName || '', r.decisionReason || '',
    ].map(csvCell).join(','));
  }
  return lines.join('\n');
}

/** The expenses of the range as CSV (capped at EXPORT_CAP rows). [data.status] narrows to one status. */
async function exportExpenses(ctx, uid, token, data) {
  const { db } = ctx;
  const sc = await scope(ctx, uid, token, data);
  if (sc.error) return sc;
  if (data.status !== undefined && data.status !== null && !STATUSES.includes(data.status)) return { error: 'INVALID_ARGUMENT', reason: 'status' };
  const facts = await schoolFacts(db, sc.schoolId, wall(ctx));
  const range = validateRange(data, facts.today);
  if (range.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(range.errors) };
  const all = await collect(db, sc.schoolId, sc.branchIds, range.value, EXPORT_CAP);
  const rows = (data.status ? all.rows.filter((r) => r.status === data.status) : all.rows)
    .sort((a, b) => a.expenseDate.localeCompare(b.expenseDate) || a.number.localeCompare(b.number));
  const branchNames = sc.branchNames || {};
  if (!sc.whole) branchNames[sc.branchIds[0]] = ((await db.collection('schools').doc(sc.schoolId).collection('branches').doc(sc.branchIds[0]).get()).data() || {}).name;
  return { result: { csv: toCsv(rows, { currency: facts.currency, branchNames }), rows: rows.length, capped: all.truncated, currency: facts.currency } };
}

module.exports = {
  SPEND, MAX_SPAN_DAYS, SCAN_CAP, EXPORT_CAP, CSV_HEADER,
  validateRange, aggregate, plainAmount, toCsv, getExpenseReport, exportExpenses,
};

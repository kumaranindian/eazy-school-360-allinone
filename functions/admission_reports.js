'use strict';

// Admission reports (docs/admission-management/, phase 11).
//
// The numbers are computed HERE, on the trusted side, from the branch's own
// documents, and only aggregates leave: counts, rates and money totals, never a
// name, a phone number or a remark. A branch administrator sees their branch; a
// school administrator sees one branch or all of them. The scan is bounded
// (MAX_ENQUIRIES per branch) and the reply says when it was cut short, so a
// number is never silently wrong.

const a = require('./admission');
const fees = require('./admission_fees');

const MAX_ENQUIRIES = 5000;
const MAX_REASONS = 10;
const CLOSED_LOST = ['NOT_INTERESTED', 'REJECTED', 'WITHDRAWN'];
const DATE = /^\d{4}-\d{2}-\d{2}$/;

const pct = (n, d) => (d > 0 ? Math.round((n / d) * 1000) / 10 : 0);
const bump = (map, key, f) => {
  const row = map.get(key) || { key, count: 0, confirmed: 0 };
  row.count += 1;
  if (f) row.confirmed += 1;
  map.set(key, row);
};
const rows = (map) => [...map.values()].sort((x, y) => y.count - x.count || String(x.key).localeCompare(String(y.key)));

/** Validates the filters; returns { errors } or { value }. */
function validateFilters(i) {
  const errors = {};
  const f = i || {};
  for (const k of ['from', 'to']) {
    if (f[k] !== undefined && f[k] !== null && f[k] !== '' && (typeof f[k] !== 'string' || !DATE.test(f[k]) || Number.isNaN(Date.parse(f[k])))) errors[k] = 'must be a date (yyyy-mm-dd)';
  }
  if (!errors.from && !errors.to && f.from && f.to && f.from > f.to) errors.to = 'must not be before the start date';
  if (f.academicYearId !== undefined && f.academicYearId !== null && f.academicYearId !== '' && (!a.isStr(f.academicYearId) || !a.ID.test(f.academicYearId))) errors.academicYearId = 'is not valid';
  if (Object.keys(errors).length) return { errors };
  return { value: { from: f.from || null, to: f.to || null, academicYearId: f.academicYearId || null } };
}

/**
 * Pure: the report from already-fetched documents.
 * [enquiries] {id, branchId, data}; [activities] and [fees] are plain data objects.
 */
function buildReport({ enquiries, activities = [], feeRecords = [], today, branchNames = {}, userNames = {}, currency = 'INR' }) {
  const byStatus = new Map();
  const bySource = new Map();
  const byClass = new Map();
  const byMonth = new Map();
  const byAssignee = new Map();
  const byBranch = new Map();
  const reasons = new Map();
  const lost = { total: 0, NOT_INTERESTED: 0, REJECTED: 0, WITHDRAWN: 0 };
  const ids = new Set();
  let confirmed = 0;
  for (const { id, branchId, data: e } of enquiries) {
    ids.add(id);
    const won = e.status === 'ADMISSION_CONFIRMED';
    if (won) confirmed++;
    byStatus.set(e.status, (byStatus.get(e.status) || 0) + 1);
    bump(bySource, e.source || 'Unknown', won);
    bump(byClass, e.interestedClassId || 'Unknown', won);
    bump(byMonth, String(e.enquiryDate || '').slice(0, 7) || 'Unknown', won);
    bump(byAssignee, e.assignedTo || '(unassigned)', won);
    bump(byBranch, branchId, won);
    if (CLOSED_LOST.includes(e.status)) {
      lost.total++;
      lost[e.status]++;
      const reason = a.trim(e.statusReason).toLowerCase().slice(0, 80) || '(no reason given)';
      reasons.set(reason, (reasons.get(reason) || 0) + 1);
    }
  }
  const mine = activities.filter((x) => ids.has(x.enquiryId));
  const open = mine.filter((x) => x.status === 'SCHEDULED');
  const done = mine.filter((x) => x.status === 'COMPLETED').length;
  const cancelled = mine.filter((x) => x.status === 'CANCELLED').length;
  const overdue = open.filter((x) => x.scheduledDate < today).length;
  const live = feeRecords.filter((f) => ids.has(f.enquiryId));
  const summary = fees.summarize(live);
  const cats = new Map();
  for (const f of live.filter((x) => x.status !== 'CANCELLED')) {
    const row = cats.get(f.category) || { category: f.category, amountMinor: 0, netPaidMinor: 0, balanceMinor: 0 };
    row.amountMinor += f.amountMinor;
    row.netPaidMinor += fees.netPaid(f);
    row.balanceMinor += fees.balanceOf(f);
    cats.set(f.category, row);
  }
  const total = enquiries.length;
  return {
    total,
    byStatus: Object.fromEntries([...byStatus.entries()].sort()),
    conversion: { confirmed, total, ratePercent: pct(confirmed, total) },
    bySource: rows(bySource).map((r) => ({ source: r.key, count: r.count, confirmed: r.confirmed, ratePercent: pct(r.confirmed, r.count) })),
    byClass: rows(byClass).map((r) => ({ classId: r.key, count: r.count, confirmed: r.confirmed, ratePercent: pct(r.confirmed, r.count) })),
    byMonth: [...byMonth.values()].sort((x, y) => String(x.key).localeCompare(String(y.key))).map((r) => ({ month: r.key, count: r.count, confirmed: r.confirmed })),
    byAssignee: rows(byAssignee).map((r) => ({ userId: r.key.startsWith('(') ? null : r.key, name: r.key.startsWith('(') ? 'Unassigned' : userNames[r.key] || 'Former staff member', count: r.count, confirmed: r.confirmed, ratePercent: pct(r.confirmed, r.count) })),
    byBranch: rows(byBranch).map((r) => ({ branchId: r.key, name: branchNames[r.key] || r.key, count: r.count, confirmed: r.confirmed, ratePercent: pct(r.confirmed, r.count) })),
    lost: { ...lost, reasons: [...reasons.entries()].sort((x, y) => y[1] - x[1] || x[0].localeCompare(y[0])).slice(0, MAX_REASONS).map(([reason, count]) => ({ reason, count })) },
    followUps: { total: mine.length, completed: done, cancelled, open: open.length, overdueOpen: overdue, completionRatePercent: pct(done, done + cancelled + open.length) },
    fees: { currency, amountMinor: summary.amountMinor, netPaidMinor: summary.netPaidMinor, balanceMinor: summary.balanceMinor, byCategory: [...cats.values()] },
  };
}

async function loadBranch(db, schoolId, branchId, filters, max = MAX_ENQUIRIES) {
  const b = a.branchRef(db, schoolId, branchId);
  let q = b.collection('admissionEnquiries');
  if (filters.academicYearId) q = q.where('academicYearId', '==', filters.academicYearId);
  const snap = await q.limit(max + 1).get();
  const truncated = snap.docs.length > max;
  const docs = snap.docs.slice(0, max).filter((d) => {
    const day = String(d.data().enquiryDate || '');
    return (!filters.from || day >= filters.from) && (!filters.to || day <= filters.to);
  });
  const acts = await b.collection('admissionActivities').get();
  const fs = await b.collection('admissionFees').get();
  return {
    truncated,
    enquiries: docs.map((d) => ({ id: d.id, branchId, data: d.data() })),
    activities: acts.docs.map((d) => d.data()),
    feeRecords: fs.docs.map((d) => d.data()),
  };
}

/**
 * `{schoolId, branchId|null, from?, to?, academicYearId?}`. branchId null = every
 * branch of the school (school administrators only).
 */
async function getAdmissionReport(ctx, uid, token, data) {
  const { db } = ctx;
  const d = data || {};
  const branchId = d.branchId === undefined || d.branchId === '' ? null : d.branchId;
  const caller = await a.authorize(db, uid, token, d.schoolId, branchId);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  if (branchId === null && caller.role !== 'SCHOOL_ADMIN') return { error: 'PERMISSION_DENIED' };
  const settings = await a.loadSettings(db, d.schoolId);
  if (!settings.enabled) return { error: 'FAILED_PRECONDITION', reason: 'admissions are not enabled for this school' };
  const parsed = validateFilters(d);
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(parsed.errors) };
  const filters = parsed.value;

  const school = (await db.collection('schools').doc(d.schoolId).get()).data() || {};
  const today = a.civilToday(a.wall(ctx), school.timezone || 'UTC');
  const branchDocs = branchId ? [{ id: branchId, data: () => ({}) }] : (await db.collection('schools').doc(d.schoolId).collection('branches').get()).docs;
  const branchNames = {};
  const all = { enquiries: [], activities: [], feeRecords: [] };
  let truncated = false;
  for (const bd of branchDocs) {
    const got = await loadBranch(db, d.schoolId, bd.id, filters, ctx.maxEnquiries || MAX_ENQUIRIES);
    truncated = truncated || got.truncated;
    all.enquiries.push(...got.enquiries);
    all.activities.push(...got.activities);
    all.feeRecords.push(...got.feeRecords);
    branchNames[bd.id] = (bd.data() || {}).name || bd.id;
  }
  if (branchId) branchNames[branchId] = ((await a.branchRef(db, d.schoolId, branchId).get()).data() || {}).name || branchId;

  const userNames = {};
  for (const uidOf of new Set(all.enquiries.map((e) => e.data.assignedTo).filter(Boolean))) {
    const u = (await db.collection('users').doc(uidOf).get()).data();
    if (u && u.schoolId === d.schoolId) userNames[uidOf] = u.name || 'Staff member';
  }
  // Class names for the ids in the report (one read per distinct class).
  const classNames = {};
  const pairs = new Set(all.enquiries.filter((e) => e.data.academicYearId && e.data.interestedClassId).map((e) => `${e.branchId}/${e.data.academicYearId}/${e.data.interestedClassId}`));
  for (const pair of pairs) {
    const [bId, ay, cls] = pair.split('/');
    if (classNames[cls]) continue;
    const c = (await a.branchRef(db, d.schoolId, bId).collection('academicYears').doc(ay).collection('classes').doc(cls).get()).data();
    if (c && c.name) classNames[cls] = c.name;
  }
  const report = buildReport({ ...all, today, branchNames, userNames, currency: school.currency || 'INR' });
  return { result: { ...report, classNames, truncated, filters, scope: branchId ? 'BRANCH' : 'SCHOOL', generatedAt: a.wall(ctx).toISOString() } };
}

module.exports = { buildReport, validateFilters, getAdmissionReport, MAX_ENQUIRIES };

'use strict';

// Manual billing records per school (Avail404's own invoicing of schools).
// Nothing is collected online: an owner records what is due and marks it paid,
// waived or void. Owner-only, server-written, audited. Amounts are integer minor
// units with their own currency. Collection `platformBilling` has no client
// access (default deny); the app reads through listBillingRecords.

const { platformCaller, auditRecord } = require('./platform_admin');

const STATUSES = ['DUE', 'PAID', 'WAIVED', 'VOID'];
const NEXT = { DUE: ['PAID', 'WAIVED', 'VOID'], PAID: [], WAIVED: [], VOID: [] };
const MAX_AMOUNT = 1e12;
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

const isDateKey = (v) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(`${v}T00:00:00Z`)) && new Date(`${v}T00:00:00Z`).toISOString().startsWith(v);
const dayKey = (d) => d.toISOString().slice(0, 10);
const toMs = (t) => (t instanceof Date ? t.getTime() : t && t.toMillis ? t.toMillis() : typeof t === 'number' ? t : null);

function view(id, r) {
  return {
    id,
    schoolId: r.schoolId,
    schoolName: r.schoolName || '',
    period: r.period,
    amountMinor: r.amountMinor,
    currency: r.currency,
    dueDate: r.dueDate,
    status: r.status,
    paidDate: r.paidDate || null,
    reference: r.reference || null,
    note: r.note || null,
    createdAtMs: toMs(r.createdAt),
  };
}

/** Owner-only: records an amount due from a school. */
async function saveBillingRecord(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = text(data && data.schoolId, 128);
  const period = text(data && data.period, 40);
  const amount = data && data.amountMinor;
  const currency = typeof (data && data.currency) === 'string' ? data.currency.trim().toUpperCase() : '';
  const dueDate = data && data.dueDate;
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  if (period.length < 2) return { error: 'INVALID_ARGUMENT', reason: 'period' };
  if (!Number.isInteger(amount) || amount <= 0 || amount > MAX_AMOUNT) return { error: 'INVALID_ARGUMENT', reason: 'amount' };
  if (!/^[A-Z]{3}$/.test(currency)) return { error: 'INVALID_ARGUMENT', reason: 'currency' };
  if (!isDateKey(dueDate)) return { error: 'INVALID_ARGUMENT', reason: 'dueDate' };
  const school = (await ctx.db.collection('schools').doc(schoolId).get()).data();
  if (!school) return { error: 'NOT_FOUND' };
  const ref = ctx.db.collection('platformBilling').doc();
  const rec = {
    schoolId,
    schoolName: school.name || '',
    period,
    amountMinor: amount,
    currency,
    dueDate,
    status: 'DUE',
    paidDate: null,
    reference: text(data.reference, 60) || null,
    note: text(data.note, 300) || null,
    createdBy: callerUid,
    createdAt: ctx.now,
    updatedAt: ctx.now,
  };
  const batch = ctx.db.batch();
  batch.set(ref, rec);
  const a = auditRecord(ctx, {
    action: 'BILLING_RECORD_CREATED',
    actorUid: callerUid,
    actorEmail: caller.profile.email,
    actorPlatformRole: caller.platformRole,
    schoolId,
    meta: { period, amountMinor: amount, currency },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, id: ref.id };
}

/** Owner-only: DUE -> PAID (with the day it was paid), WAIVED or VOID. Final. */
async function setBillingStatus(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const id = text(data && data.id, 128);
  const status = data && data.status;
  if (!id || !STATUSES.includes(status)) return { error: 'INVALID_ARGUMENT', reason: 'status' };
  const ref = ctx.db.collection('platformBilling').doc(id);
  const r = (await ref.get()).data();
  if (!r) return { error: 'NOT_FOUND' };
  if (!NEXT[r.status].includes(status)) return { error: 'FAILED_PRECONDITION', reason: 'FINAL' };
  const update = { status, updatedAt: ctx.now };
  if (status === 'PAID') {
    const paid = data.paidDate;
    if (!isDateKey(paid) || paid > dayKey(ctx.nowDate())) return { error: 'INVALID_ARGUMENT', reason: 'paidDate' };
    update.paidDate = paid;
  }
  const note = text(data.note, 300);
  if (note) update.note = note;
  const batch = ctx.db.batch();
  batch.update(ref, update);
  const a = auditRecord(ctx, {
    action: `BILLING_RECORD_${status}`,
    actorUid: callerUid,
    actorEmail: caller.profile.email,
    actorPlatformRole: caller.platformRole,
    schoolId: r.schoolId,
    meta: { id, period: r.period, amountMinor: r.amountMinor, currency: r.currency },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, status };
}

/** Owner-only: records (newest first) and what is still owed, per currency. */
async function listBillingRecords(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = text(data && data.schoolId, 128);
  let q = ctx.db.collection('platformBilling');
  if (schoolId) q = q.where('schoolId', '==', schoolId);
  const snap = await q.limit(500).get();
  const records = snap.docs
    .map((d) => view(d.id, d.data()))
    .sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0))
    .slice(0, 200);
  const today = dayKey(ctx.nowDate());
  const owed = {};
  for (const r of records) {
    if (r.status !== 'DUE') continue;
    const o = (owed[r.currency] ||= { dueMinor: 0, overdueMinor: 0 });
    o.dueMinor += r.amountMinor;
    if (r.dueDate < today) o.overdueMinor += r.amountMinor;
  }
  return { records, owed };
}

module.exports = { STATUSES, saveBillingRecord, setBillingStatus, listBillingRecords };

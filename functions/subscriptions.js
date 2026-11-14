'use strict';

// School subscriptions (docs/platform-governance/SUBSCRIPTION_DESIGN.md, Phases 5-6).
//
// `schoolSubscriptions/{schoolId}` is the current subscription; `schoolSubscriptionHistory`
// is append-only; `platformPlans/{id}` are plans (a name and a period, never a price: money
// stays in `platformBilling`). Dates are plain calendar dates in the SCHOOL'S time zone;
// `endDate` is valid through its last millisecond of local time. No client rules exist for
// any of these collections: reads and writes go through the callables below.
//
// Statuses: NOT_STARTED, TRIAL, ACTIVE, GRACE_PERIOD, EXPIRED, CANCELLED. A school with no
// subscription document is a legacy school and is allowed (decision D2).

const { idOf, own } = require('./ids');
const crypto = require('node:crypto');
const { platformCaller, auditRecord } = require('./platform_admin');
const { validZone, civilToday, addDays } = require('./fee_reminders');

const PERIODS = ['MONTHLY', 'QUARTERLY', 'HALF_YEARLY', 'ANNUAL', 'CUSTOM'];
const CLASSES = ['TRIAL', 'PAID'];
const BLOCKING = ['EXPIRED', 'CANCELLED'];
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const REASON_MIN = 10;
const MAX_GRACE = 90;
const MAX_TRIAL_DAYS = 90;
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const toMs = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : t instanceof Date ? t.getTime() : null);

const subRef = (db, schoolId) => db.collection('schoolSubscriptions').doc(schoolId);
const planRef = (db, id) => db.collection('platformPlans').doc(id);
const histRef = (db, id) => (id ? db.collection('schoolSubscriptionHistory').doc(id) : db.collection('schoolSubscriptionHistory').doc());

/** A real calendar date `yyyy-MM-dd` (2026-02-30 is not one). */
function validDate(s) {
  if (typeof s !== 'string' || !DATE.test(s)) return false;
  const [y, m, d] = s.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}

const zoneOf = (school) => (school && validZone(school.timezone) ? school.timezone : 'UTC');

/**
 * The status of [sub] at instant [now] for a school in [zone]. Pure: the callables, the
 * scheduler, the access engine and the tests all use this one function.
 * No subscription (null) is a legacy school: returns null.
 */
function statusAt(sub, now, zone) {
  if (!sub || !validDate(sub.startDate) || !validDate(sub.endDate)) return null;
  if (sub.cancelled === true || sub.status === 'CANCELLED') return 'CANCELLED';
  const today = civilToday(now, validZone(zone) ? zone : 'UTC');
  if (today < sub.startDate) return 'NOT_STARTED';
  if (today <= sub.endDate) return sub.classification === 'TRIAL' ? 'TRIAL' : 'ACTIVE';
  const grace = Number.isInteger(sub.gracePeriodDays) ? sub.gracePeriodDays : 0;
  if (grace > 0 && today <= addDays(sub.endDate, grace)) return 'GRACE_PERIOD';
  return 'EXPIRED';
}

/** The value mirrored onto users.schoolAccess for [school] ('ACTIVE' = nothing mirrored). */
function mirrorFor(school) {
  const s = ['INACTIVE', 'SUSPENDED', 'EXPIRED', 'CLOSED'].includes(school && school.status) ? school.status : 'ACTIVE';
  if (s !== 'ACTIVE') return s;
  return school && school.subscriptionStatus === 'NOT_STARTED' ? 'SUBSCRIPTION_NOT_STARTED' : 'ACTIVE';
}

const isBlocking = (status) => BLOCKING.includes(status);

// ---- validation -------------------------------------------------------------------

function parsePeriod(d) {
  const startDate = text(d && d.startDate, 10);
  const endDate = text(d && d.endDate, 10);
  if (!validDate(startDate)) return { error: 'INVALID_ARGUMENT', reason: 'startDate' };
  if (!validDate(endDate)) return { error: 'INVALID_ARGUMENT', reason: 'endDate' };
  if (endDate < startDate) return { error: 'INVALID_ARGUMENT', reason: 'endBeforeStart' };
  return { startDate, endDate };
}

function parseGrace(v) {
  if (v === undefined || v === null || v === '') return 0;
  return Number.isInteger(v) && v >= 0 && v <= MAX_GRACE ? v : null;
}

/** An optional plan id: absent is fine, present-but-invalid is REFUSED (never silently ignored). */
const planIdOf = (v) => (v === undefined || v === null || v === '' ? { id: '' } : idOf(v, 64) ? { id: idOf(v, 64) } : { error: 'INVALID_ARGUMENT', reason: 'planId' });

const hashKey = (schoolId, key) => crypto.createHash('sha256').update(`sub|${schoolId}|${key}`).digest('hex').slice(0, 32);

// ---- plans --------------------------------------------------------------------------

/** Owner: creates or edits a plan. A plan is a name, a period type and an optional default feature set. */
async function savePlan(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const name = text(data && data.name, 80);
  const periodType = data && data.periodType;
  if (name.length < 2) return { error: 'INVALID_ARGUMENT', reason: 'name' };
  if (!PERIODS.includes(periodType)) return { error: 'INVALID_ARGUMENT', reason: 'periodType' };
  const active = data && data.active === false ? false : true;
  const featureSet = {};
  const df = data && data.defaultFeatures;
  if (df !== undefined && df !== null) {
    if (typeof df !== 'object' || Array.isArray(df)) return { error: 'INVALID_ARGUMENT', reason: 'defaultFeatures' };
    for (const [k, v] of Object.entries(df)) {
      if (!/^[A-Za-z][A-Za-z0-9]{0,39}$/.test(k) || typeof v !== 'boolean') return { error: 'INVALID_ARGUMENT', reason: 'defaultFeatures' };
      featureSet[k] = v;
    }
  }
  const pid = planIdOf(data && data.planId);
  if (pid.error) return pid;
  const id = pid.id;
  const ref = id ? planRef(ctx.db, id) : ctx.db.collection('platformPlans').doc();
  const existing = id ? (await ref.get()).data() : null;
  if (id && !existing) return { error: 'NOT_FOUND' };
  await ref.set({
    name, periodType, active, defaultFeatures: featureSet,
    createdAt: existing ? existing.createdAt : ctx.now, createdBy: existing ? existing.createdBy : callerUid,
    updatedAt: ctx.now, updatedBy: callerUid,
  });
  const a = auditRecord(ctx, { action: 'PLAN_SAVED', actorUid: callerUid, actorEmail: caller.profile.email, actorPlatformRole: caller.platformRole, meta: { planId: ref.id, name, periodType, active } });
  await a.ref.set(a.rec);
  return { ok: true, planId: ref.id };
}

async function listPlans(ctx, callerUid, token) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT', 'COMPLIANCE', 'VIEWER']);
  if (caller.error) return { error: caller.error };
  const snap = await ctx.db.collection('platformPlans').limit(200).get();
  const plans = snap.docs
    .map((d) => ({ id: d.id, name: d.data().name || '', periodType: d.data().periodType || 'CUSTOM', active: d.data().active !== false, defaultFeatures: d.data().defaultFeatures || {} }))
    .sort((a, b) => a.name.localeCompare(b.name));
  return { plans };
}

// ---- views --------------------------------------------------------------------------

function subscriptionView(sub, school, now) {
  if (!sub) return null;
  const live = statusAt(sub, now, zoneOf(school));
  return {
    planId: sub.planId || null,
    planName: sub.planName || null,
    classification: sub.classification || 'PAID',
    startDate: sub.startDate,
    endDate: sub.endDate,
    gracePeriodDays: sub.gracePeriodDays || 0,
    status: live || sub.status || 'EXPIRED',
    storedStatus: sub.status || null,
    cancelled: sub.cancelled === true,
    cancellationReason: sub.cancellationReason || null,
    remarks: sub.remarks || null,
    internalNotes: sub.internalNotes || null,
    version: sub.version || 0,
    updatedAtMs: toMs(sub.updatedAt),
  };
}

const historyView = (id, h) => ({
  id, event: h.event, atMs: toMs(h.at), actorEmail: h.actorEmail || null, actorKind: h.actorKind || 'OWNER',
  reason: h.reason || null, fromStatus: h.fromStatus || null, toStatus: h.toStatus || null,
  before: h.before || null, after: h.after || null,
});

async function getSubscriptionHistory(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT', 'COMPLIANCE', 'VIEWER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  const snap = await ctx.db.collection('schoolSubscriptionHistory').where('schoolId', '==', schoolId).limit(200).get();
  const entries = snap.docs.map((d) => historyView(d.id, d.data())).sort((a, b) => (b.atMs || 0) - (a.atMs || 0));
  return { entries };
}

// ---- writes -------------------------------------------------------------------------

const snapshotOf = (s) => (s ? { planId: s.planId || null, classification: s.classification, startDate: s.startDate, endDate: s.endDate, gracePeriodDays: s.gracePeriodDays || 0, status: s.status, cancelled: s.cancelled === true } : null);

/**
 * Writes [next] (or the change [patch] to the current one) with one history entry and one audit
 * record in a single transaction, and keeps `schools.subscriptionStatus` in step (that field
 * drives the access mirror; see mirrorFor). Returns { ok, status, previous, subscription }.
 */
async function commitChange(ctx, caller, callerUid, { schoolId, event, build, reason, key }) {
  const hid = key ? hashKey(schoolId, key) : null;
  const out = await ctx.db.runTransaction(async (tx) => {
    const schoolRefDoc = ctx.db.collection('schools').doc(schoolId);
    const school = (await tx.get(schoolRefDoc)).data();
    if (!school) return { error: 'NOT_FOUND' };
    const prior = hid ? (await tx.get(histRef(ctx.db, hid))).data() : null;
    if (prior) return { replayed: true, status: prior.toStatus };
    const cur = (await tx.get(subRef(ctx.db, schoolId))).data() || null;
    const built = await build({ cur, school, tx });
    if (built.error) return built;
    const nextRaw = { ...built.next, schoolId };
    const status = statusAt(nextRaw, ctx.nowDate(), zoneOf(school));
    const next = { ...nextRaw, status, version: (cur ? cur.version || 0 : 0) + 1, updatedAt: ctx.now, updatedBy: callerUid, createdAt: cur ? cur.createdAt : ctx.now, createdBy: cur ? cur.createdBy : callerUid };
    tx.set(subRef(ctx.db, schoolId), next);
    tx.update(schoolRefDoc, { subscriptionStatus: status, subscriptionEndDate: next.endDate, updatedAt: ctx.now });
    tx.set(histRef(ctx.db, hid), {
      schoolId, event, at: ctx.now, actorUid: callerUid, actorEmail: caller.profile.email, actorKind: 'OWNER',
      reason: reason || null, fromStatus: cur ? cur.status : null, toStatus: status, before: snapshotOf(cur), after: snapshotOf(next),
    });
    const a = auditRecord(ctx, { action: event, actorUid: callerUid, actorEmail: caller.profile.email, actorPlatformRole: caller.platformRole, schoolId, reason: reason || null, meta: { from: cur ? cur.status : null, to: status } });
    tx.set(a.ref, a.rec);
    return { ok: true, status, previous: cur ? cur.status : null, subscription: next };
  });
  return out;
}

async function ownerGate(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  return { caller, schoolId, key: text(data && data.idempotencyKey, 100) };
}

async function planFor(ctx, planId, required) {
  if (!planId) return required ? { error: 'INVALID_ARGUMENT', reason: 'planId' } : { plan: null };
  const plan = (await planRef(ctx.db, planId).get()).data();
  if (!plan) return { error: 'NOT_FOUND' };
  if (plan.active === false) return { error: 'FAILED_PRECONDITION', reason: 'PLAN_INACTIVE' };
  return { plan };
}

/** Owner: gives a school a subscription, or replaces its current one (a reason is needed to replace). */
async function setSubscription(ctx, callerUid, token, data) {
  const g = await ownerGate(ctx, callerUid, token, data);
  if (g.error) return g;
  const classification = data && data.classification;
  if (!CLASSES.includes(classification)) return { error: 'INVALID_ARGUMENT', reason: 'classification' };
  const period = parsePeriod(data);
  if (period.error) return period;
  const grace = parseGrace(data && data.gracePeriodDays);
  if (grace === null) return { error: 'INVALID_ARGUMENT', reason: 'gracePeriodDays' };
  const pid = planIdOf(data && data.planId);
  if (pid.error) return pid;
  const planId = pid.id;
  const p = await planFor(ctx, planId, classification === 'PAID');
  if (p.error) return p;
  const reason = text(data && data.reason, 500);
  const out = await commitChange(ctx, g.caller, callerUid, {
    schoolId: g.schoolId, key: g.key, reason,
    event: 'SUBSCRIPTION_SET',
    build: async ({ cur }) => {
      if (cur && reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: 'reason' };
      return { next: { planId: planId || null, planName: p.plan ? p.plan.name : null, classification, ...period, gracePeriodDays: grace, cancelled: false, cancellationReason: null, remarks: text(data && data.remarks, 500) || null, internalNotes: text(data && data.internalNotes, 1000) || null, renewalDate: period.endDate } };
    },
  });
  return out;
}

/** Owner: moves the end date forward (never back). */
async function extendSubscription(ctx, callerUid, token, data) {
  const g = await ownerGate(ctx, callerUid, token, data);
  if (g.error) return g;
  const endDate = text(data && data.endDate, 10);
  if (!validDate(endDate)) return { error: 'INVALID_ARGUMENT', reason: 'endDate' };
  const reason = text(data && data.reason, 500);
  if (reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: 'reason' };
  return commitChange(ctx, g.caller, callerUid, {
    schoolId: g.schoolId, key: g.key, reason, event: 'SUBSCRIPTION_EXTENDED',
    build: async ({ cur }) => {
      if (!cur) return { error: 'FAILED_PRECONDITION', reason: 'NO_SUBSCRIPTION' };
      if (cur.cancelled === true) return { error: 'FAILED_PRECONDITION', reason: 'CANCELLED' };
      if (endDate <= cur.endDate) return { error: 'INVALID_ARGUMENT', reason: 'notForward' };
      return { next: { ...cur, endDate, renewalDate: endDate } };
    },
  });
}

/** Owner: a new period (after expiry or ahead of it). Starts the day after the current end unless given. */
async function renewSubscription(ctx, callerUid, token, data) {
  const g = await ownerGate(ctx, callerUid, token, data);
  if (g.error) return g;
  const endDate = text(data && data.endDate, 10);
  if (!validDate(endDate)) return { error: 'INVALID_ARGUMENT', reason: 'endDate' };
  const startIn = text(data && data.startDate, 10);
  if (startIn && !validDate(startIn)) return { error: 'INVALID_ARGUMENT', reason: 'startDate' };
  const pid = planIdOf(data && data.planId);
  if (pid.error) return pid;
  const planId = pid.id;
  const p = planId ? await planFor(ctx, planId, false) : { plan: null };
  if (p.error) return p;
  const reason = text(data && data.reason, 500);
  return commitChange(ctx, g.caller, callerUid, {
    schoolId: g.schoolId, key: g.key, reason, event: 'SUBSCRIPTION_RENEWED',
    build: async ({ cur }) => {
      if (!cur) return { error: 'FAILED_PRECONDITION', reason: 'NO_SUBSCRIPTION' };
      const startDate = startIn || addDays(cur.endDate, 1);
      const period = parsePeriod({ startDate, endDate });
      if (period.error) return period;
      return {
        next: {
          ...cur, ...period, classification: 'PAID', cancelled: false, cancellationReason: null, renewalDate: period.endDate,
          ...(planId ? { planId, planName: p.plan.name } : {}),
        },
      };
    },
  });
}

/** Owner: ends the subscription now (a written reason is required); renew to bring it back. */
async function cancelSubscription(ctx, callerUid, token, data) {
  const g = await ownerGate(ctx, callerUid, token, data);
  if (g.error) return g;
  const reason = text(data && data.reason, 500);
  if (reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: 'reason' };
  return commitChange(ctx, g.caller, callerUid, {
    schoolId: g.schoolId, key: g.key, reason, event: 'SUBSCRIPTION_CANCELLED',
    build: async ({ cur }) => {
      if (!cur) return { error: 'FAILED_PRECONDITION', reason: 'NO_SUBSCRIPTION' };
      if (cur.cancelled === true) return { error: 'FAILED_PRECONDITION', reason: 'CANCELLED' };
      return { next: { ...cur, cancelled: true, cancellationReason: reason } };
    },
  });
}

/** Owner: a trial that starts today (in the school's zone) and lasts [days]. */
async function grantTrial(ctx, callerUid, token, data) {
  const g = await ownerGate(ctx, callerUid, token, data);
  if (g.error) return g;
  const days = data && data.days;
  if (!Number.isInteger(days) || days < 1 || days > MAX_TRIAL_DAYS) return { error: 'INVALID_ARGUMENT', reason: 'days' };
  const pid = planIdOf(data && data.planId);
  if (pid.error) return pid;
  const planId = pid.id;
  const p = planId ? await planFor(ctx, planId, false) : { plan: null };
  if (p.error) return p;
  const reason = text(data && data.reason, 500);
  return commitChange(ctx, g.caller, callerUid, {
    schoolId: g.schoolId, key: g.key, reason, event: 'SUBSCRIPTION_TRIAL_GRANTED',
    build: async ({ cur, school }) => {
      if (cur && !isBlocking(statusAt(cur, ctx.nowDate(), zoneOf(school)))) return { error: 'FAILED_PRECONDITION', reason: 'HAS_SUBSCRIPTION' };
      const startDate = civilToday(ctx.nowDate(), zoneOf(school));
      return { next: { planId: planId || null, planName: p.plan ? p.plan.name : null, classification: 'TRIAL', startDate, endDate: addDays(startDate, days - 1), gracePeriodDays: 0, cancelled: false, cancellationReason: null, remarks: text(data && data.remarks, 500) || null, internalNotes: null, renewalDate: addDays(startDate, days - 1) } };
    },
  });
}

module.exports = {
  PERIODS, CLASSES, BLOCKING, MAX_GRACE, MAX_TRIAL_DAYS,
  validDate, zoneOf, statusAt, mirrorFor, isBlocking, subscriptionView, historyView,
  savePlan, listPlans, getSubscriptionHistory, setSubscription, extendSubscription, renewSubscription, cancelSubscription, grantTrial,
  subRef, histRef,
};

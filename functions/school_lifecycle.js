'use strict';

// School lifecycle for Avail404 (platform admin Phase 3): suspend/reactivate
// (ENFORCED), create a school with its first admin, add/reset school admins,
// per-school feature switches and the offboarding workflow.
// See docs/platform-admin/PLATFORM_ADMIN_PLAN.md.
//
// Suspension: the school document carries `status`; every user profile of the
// school carries a mirrored `schoolAccess` ('SUSPENDED' or absent). The rules,
// Storage rules and callables already read the caller's profile, so they check
// that field with no extra lookup (see access.methodAllowed).

const { idOf, own } = require('./ids');
const crypto = require('node:crypto');
const { platformCaller, auditRecord } = require('./platform_admin');
const notifications = require('./school_notifications');
const subscriptions = require('./subscriptions');

// Lifecycle states of a school (see docs/platform-governance/SCHOOL_LIFECYCLE_DESIGN.md).
const ALL_STATUSES = ['INACTIVE', 'ACTIVE', 'SUSPENDED', 'EXPIRED', 'CLOSED'];
const STATUSES = ALL_STATUSES;
// Allowed transitions: who may do it and what it needs. Anything else is refused.
// `reason`: a written reason of 10+ characters; `closure`: an approved offboarding.
const TRANSITIONS = {
  'INACTIVE>ACTIVE': { actors: ['OWNER'], event: 'SCHOOL_ACTIVATED' },
  'INACTIVE>CLOSED': { actors: ['OWNER'], reason: true, closure: true, event: 'SCHOOL_CLOSED' },
  'ACTIVE>INACTIVE': { actors: ['OWNER'], reason: true, event: 'SCHOOL_DEACTIVATED' },
  'ACTIVE>SUSPENDED': { actors: ['OWNER'], reason: true, event: 'SCHOOL_SUSPENDED' },
  'ACTIVE>EXPIRED': { actors: ['SYSTEM'], event: 'SCHOOL_EXPIRED' },
  'ACTIVE>CLOSED': { actors: ['OWNER'], reason: true, closure: true, event: 'SCHOOL_CLOSED' },
  'SUSPENDED>ACTIVE': { actors: ['OWNER'], event: 'SCHOOL_REACTIVATED' },
  'SUSPENDED>INACTIVE': { actors: ['OWNER'], reason: true, event: 'SCHOOL_DEACTIVATED' },
  'SUSPENDED>CLOSED': { actors: ['OWNER'], reason: true, closure: true, event: 'SCHOOL_CLOSED' },
  'EXPIRED>ACTIVE': { actors: ['OWNER', 'SYSTEM'], event: 'SCHOOL_REACTIVATED' },
  'EXPIRED>SUSPENDED': { actors: ['OWNER'], reason: true, event: 'SCHOOL_SUSPENDED' },
  'EXPIRED>CLOSED': { actors: ['OWNER'], reason: true, closure: true, event: 'SCHOOL_CLOSED' },
  // CLOSED is terminal for the normal table. The only way out is the two-owner recovery below.
  'CLOSED>INACTIVE': { actors: ['RECOVERY'], reason: true, event: 'SCHOOL_RECOVERED' },
};
// Fields only the server may set. A school document created by a CLIENT (self-registration) can carry any
// field the rules do not forbid, so the creation trigger resets these (see newSchoolFixes).
const SERVER_OWNED_ON_CREATE = [
  'subscriptionStatus', 'subscriptionEndDate', 'accessMirror', 'statusReason', 'statusChangedAt', 'statusChangedBy',
  'activatedAt', 'activatedBy', 'activationRemarks', 'suspendedAt', 'suspendedBy', 'closedAt', 'closedBy',
  'lifecycleUpdatedAt', 'lifecycleUpdatedBy',
];

/**
 * What to correct on a freshly created school: module switches come from the platform defaults (a
 * client cannot pre-set its own, so a default-off module stays off), lifecycle counters restart, and
 * server-owned bookkeeping a client may have planted is removed. Returns { set, remove } (both may be empty).
 */
function newSchoolFixes(school, defaults) {
  const set = {};
  if (JSON.stringify(school.features || null) !== JSON.stringify(defaults)) set.features = defaults;
  if (school.featuresVersion !== 1) set.featuresVersion = 1;
  if (school.lifecycleVersion !== 1) set.lifecycleVersion = 1;
  return { set, remove: SERVER_OWNED_ON_CREATE.filter((k) => school[k] !== undefined) };
}

/** A missing status is a school from before lifecycle states: ACTIVE. */
const statusOf = (school) => (ALL_STATUSES.includes(school && school.status) ? school.status : 'ACTIVE');
/** The rule for from -> to by [actor], or null when that transition is not allowed. */
function transitionRule(from, to, actor) {
  const r = TRANSITIONS[`${from}>${to}`];
  return r && r.actors.includes(actor) ? r : null;
}
const FEATURES = ['admission', 'publicAdmission'];
const REASON_MIN = 10;
const OFFBOARD_REASON_MIN = 15;
const GRACE_DAYS = 30;
const PAGE = 400;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const notFound = (e) => e && (e.code === 'auth/user-not-found' || e.code === 'not-found');

/**
 * Mirrors the school's status onto the profiles of its users (any state but ACTIVE sets
 * `schoolAccess` to that state, ACTIVE removes it). Idempotent and resumable: only profiles
 * that differ are written, in pages, until [deadlineMs] (if given).
 */
async function applySchoolAccess(ctx, schoolId, status, deadlineMs) {
  const suspended = status !== 'ACTIVE';
  let after = null;
  let updated = 0;
  let scanned = 0;
  for (;;) {
    let q = ctx.db.collection('users').where('schoolId', '==', schoolId).orderBy('__name__').limit(PAGE);
    if (after) q = q.startAfter(after);
    const snap = await q.get();
    if (!snap.docs.length) return { updated, scanned, done: true };
    const batch = ctx.db.batch();
    let n = 0;
    for (const d of snap.docs) {
      const u = d.data();
      if (u.role === 'PLATFORM_ADMIN') continue;
      // The mirror carries the state itself (INACTIVE, SUSPENDED, EXPIRED, CLOSED) so the app
      // can say which; the rules only check that the field is present.
      const want = suspended ? status : undefined;
      if (u.schoolAccess !== want) {
        batch.update(d.ref, want ? { schoolAccess: want } : { schoolAccess: ctx.deleteField });
        n++;
      }
    }
    if (n) await batch.commit();
    updated += n;
    scanned += snap.docs.length;
    after = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < PAGE) return { updated, scanned, done: true };
    if (deadlineMs && ctx.nowDate().getTime() > deadlineMs) return { updated, scanned, done: false };
  }
}

async function schoolOf(db, schoolId) {
  if (!schoolId) return null;
  const snap = await db.collection('schools').doc(schoolId).get();
  return snap.exists ? snap.data() : null;
}

function audit(ctx, caller, callerUid, action, extra) {
  return auditRecord(ctx, {
    action,
    actorUid: callerUid,
    actorEmail: caller.profile.email,
    actorPlatformRole: caller.platformRole,
    ...extra,
  });
}

const hashKey = (schoolId, key) => crypto.createHash('sha256').update(`${schoolId}|${key}`).digest('hex').slice(0, 32);
const histRef = (db, id) => db.collection('schoolLifecycleHistory').doc(id);

/** One append-only lifecycle history entry (also used for creation). */
function historyEntry(ctx, e) {
  return {
    schoolId: e.schoolId,
    from: e.from || null,
    to: e.to,
    event: e.event,
    actorUid: e.actorUid || null,
    actorEmail: e.actorEmail || null,
    actorKind: e.actorKind || 'OWNER',
    reason: e.reason || null,
    remarks: e.remarks || null,
    internalNotes: e.internalNotes || null,
    message: e.message || null,
    correlationId: e.correlationId || null,
    at: ctx.now,
  };
}

/**
 * Owner-only: moves a school to another lifecycle state through the validated table, writes
 * the school, one history entry and one audit record together, then mirrors the state onto
 * every user. `idempotencyKey` makes a retry return the first result instead of acting twice.
 */
async function transitionSchool(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const to = data && data.to;
  const reason = text(data && data.reason, 500);
  const remarks = text(data && data.remarks, 500);
  const internalNotes = text(data && data.internalNotes, 1000);
  const message = text(data && data.message, 500);
  const key = text(data && data.idempotencyKey, 100);
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  if (!ALL_STATUSES.includes(to)) return { error: 'INVALID_ARGUMENT', reason: 'status' };

  const histId = key ? hashKey(schoolId, key) : null;
  const out = await ctx.db.runTransaction(async (tx) => {
    const schoolRef = ctx.db.collection('schools').doc(schoolId);
    const school = (await tx.get(schoolRef)).data();
    const prior = histId ? (await tx.get(histRef(ctx.db, histId))).data() : null;
    const offRef = ctx.db.collection('platformOffboarding').doc(schoolId);
    const off = (await tx.get(offRef)).data();
    const subDoc = to === 'ACTIVE' ? (await tx.get(subscriptions.subRef(ctx.db, schoolId))).data() : null;
    if (prior) return { replayed: true, from: prior.from, to: prior.to };
    if (!school) return { error: 'NOT_FOUND' };
    const from = statusOf(school);
    if (from === to) return { unchanged: true, from, to };
    const rule = transitionRule(from, to, 'OWNER');
    if (!rule) return { error: 'INVALID_TRANSITION', reason: `${from}>${to}` };
    if (rule.reason && reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: 'reason' };
    const offOpen = off && ['REQUESTED', 'APPROVED'].includes(off.state);
    // While offboarding, the school stays paused until the offboarding is cancelled.
    if (to === 'ACTIVE' && offOpen) return { error: 'FAILED_PRECONDITION', reason: 'OFFBOARDING' };
    // A school whose subscription has ended cannot be switched on by hand: renew it first.
    if (to === 'ACTIVE' && subDoc && subscriptions.isBlocking(subscriptions.statusAt(subDoc, ctx.nowDate(), subscriptions.zoneOf(school)))) return { error: 'FAILED_PRECONDITION', reason: 'SUBSCRIPTION_EXPIRED' };
    if (rule.closure && !(off && off.state === 'APPROVED')) return { error: 'FAILED_PRECONDITION', reason: 'CLOSURE_NOT_APPROVED' };

    const update = {
      status: to,
      statusReason: to === 'ACTIVE' ? null : reason || null,
      statusChangedAt: ctx.now,
      statusChangedBy: callerUid,
      lifecycleUpdatedAt: ctx.now,
      lifecycleUpdatedBy: callerUid,
      lifecycleVersion: (school.lifecycleVersion || 0) + 1,
      updatedAt: ctx.now,
      updatedBy: callerUid,
    };
    if (to === 'ACTIVE') Object.assign(update, { activatedAt: ctx.now, activatedBy: callerUid, activationRemarks: remarks || null });
    if (to === 'SUSPENDED') Object.assign(update, { suspendedAt: ctx.now, suspendedBy: callerUid });
    if (to === 'CLOSED') Object.assign(update, { closedAt: ctx.now, closedBy: callerUid });
    tx.update(schoolRef, update);
    const hid = histId || histRef(ctx.db, undefined).id;
    tx.set(
      histRef(ctx.db, hid),
      historyEntry(ctx, {
        schoolId, from, to, event: rule.event, actorUid: callerUid, actorEmail: caller.profile.email,
        reason, remarks, internalNotes, message, correlationId: key || null,
      }),
    );
    if (rule.closure) tx.update(offRef, { state: 'COMPLETED', closedBy: callerUid, closedAt: ctx.now });
    const a = audit(ctx, caller, callerUid, rule.event, { schoolId, reason: reason || remarks || null, meta: { from, to } });
    tx.set(a.ref, a.rec);
    return { ok: true, from, to, hid, event: rule.event };
  });
  if (out.error || out.unchanged || out.replayed) {
    return out.error ? out : { ok: true, ...out };
  }
  const after = await schoolOf(ctx.db, schoolId);
  const applied = await applySchoolAccess(ctx, schoolId, subscriptions.mirrorFor(after), ctx.nowDate().getTime() + 30000);
  if (applied.done) await ctx.db.collection('schools').doc(schoolId).update({ accessMirror: subscriptions.mirrorFor(after) });
  // Tell the school's administrators (idempotent per change). A failure here never undoes the change.
  let notified = null;
  try {
    const n = notifications.lifecycleNotification(out.event, message);
    if (n) notified = await notifications.notifySchoolAdmins(ctx, { schoolId, sourceEventId: `lifecycle:${out.hid}`, type: out.event, ...n });
  } catch (e) {
    notified = { failed: true };
  }
  return { ok: true, from: out.from, status: out.to, to: out.to, usersUpdated: applied.updated, complete: applied.done, notified };
}

/**
 * The scheduler's lifecycle change (actor SYSTEM, e.g. ACTIVE -> EXPIRED when a subscription
 * ends, EXPIRED -> ACTIVE when it is renewed). Same table, history, audit, mirror and
 * notification as an owner's change; `key` makes a retry a no-op. Returns { ok } or { skipped }.
 */
async function systemTransition(ctx, schoolId, to, { expectedFrom, reason, key }) {
  const hid = hashKey(schoolId, `system|${key}`);
  const out = await ctx.db.runTransaction(async (tx) => {
    const schoolRef = ctx.db.collection('schools').doc(schoolId);
    const school = (await tx.get(schoolRef)).data();
    const prior = (await tx.get(histRef(ctx.db, hid))).data();
    if (prior) return { skipped: 'REPLAYED' };
    if (!school) return { skipped: 'NOT_FOUND' };
    const from = statusOf(school);
    if (from !== expectedFrom) return { skipped: 'STATE_CHANGED' };
    const rule = transitionRule(from, to, 'SYSTEM');
    if (!rule) return { skipped: 'NOT_ALLOWED' };
    tx.update(schoolRef, {
      status: to, statusReason: to === 'ACTIVE' ? null : reason || null, statusChangedAt: ctx.now, statusChangedBy: 'system',
      lifecycleUpdatedAt: ctx.now, lifecycleUpdatedBy: 'system', lifecycleVersion: (school.lifecycleVersion || 0) + 1, updatedAt: ctx.now,
    });
    tx.set(histRef(ctx.db, hid), historyEntry(ctx, { schoolId, from, to, event: rule.event, actorKind: 'SYSTEM', reason, correlationId: key }));
    const a = auditRecord(ctx, { action: rule.event, actorUid: 'system', actorEmail: 'system', actorPlatformRole: 'SYSTEM', schoolId, reason: reason || null, meta: { from, to }, source: 'SCHEDULER' });
    tx.set(a.ref, a.rec);
    return { ok: true, from, to, hid, event: rule.event, school: { ...school, status: to } };
  });
  if (!out.ok) return out;
  const mirror = subscriptions.mirrorFor(out.school);
  const applied = await applySchoolAccess(ctx, schoolId, mirror, ctx.nowDate().getTime() + 30000);
  if (applied.done) await ctx.db.collection('schools').doc(schoolId).update({ accessMirror: mirror });
  let notified = null;
  try {
    const n = notifications.lifecycleNotification(out.event, '');
    if (n) notified = await notifications.notifySchoolAdmins(ctx, { schoolId, sourceEventId: `lifecycle:${out.hid}`, type: out.event, ...n });
  } catch (e) {
    notified = { failed: true };
  }
  return { ok: true, from: out.from, to: out.to, complete: applied.done, notified };
}

/**
 * Owner-only: the original suspend / reactivate entry point (kept for the deployed app). It is
 * `transitionSchool` with the reason used as the activation remark when reactivating.
 */
async function setSchoolStatus(ctx, callerUid, token, data) {
  const to = data && data.status;
  if (!['ACTIVE', 'SUSPENDED'].includes(to)) return { error: 'INVALID_ARGUMENT', reason: 'status' };
  const reason = text(data && data.reason, 500);
  const out = await transitionSchool(ctx, callerUid, token, {
    schoolId: data.schoolId,
    to,
    reason: to === 'SUSPENDED' ? reason : undefined,
    remarks: to === 'ACTIVE' ? reason : undefined,
  });
  return out.error ? out : { ...out, status: out.status || out.to };
}

/** Owner/support: re-applies the school's current status to its users (repair). */
async function refreshSchoolAccess(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const school = await schoolOf(ctx.db, schoolId);
  if (!school) return { error: schoolId ? 'NOT_FOUND' : 'INVALID_ARGUMENT' };
  const applied = await applySchoolAccess(ctx, schoolId, subscriptions.mirrorFor(school), ctx.nowDate().getTime() + 30000);
  const a = audit(ctx, caller, callerUid, 'SCHOOL_ACCESS_REFRESHED', { schoolId, meta: { updated: applied.updated } });
  await a.ref.set(a.rec);
  return { ok: true, usersUpdated: applied.updated, complete: applied.done };
}

// ---- creating schools and school admins -----------------------------------------

function validateSchool(d) {
  const name = text(d && d.schoolName, 120);
  const adminName = text(d && d.adminName, 100);
  const adminEmail = text(d && d.adminEmail, 254).toLowerCase();
  const schoolEmail = text(d && d.schoolEmail, 254).toLowerCase() || adminEmail;
  const r = (d && d.regional) || {};
  // Strict (no truncation): "India" is not a country code and "rupees" is not a currency.
  const strict = (v) => (typeof v === 'string' ? v.trim().toUpperCase() : '');
  const countryCode = strict(r.countryCode);
  const currency = strict(r.currency);
  const timezone = text(r.timezone, 64);
  const dateFormat = text(r.dateFormat, 20);
  if (name.length < 2) return { error: 'INVALID_ARGUMENT', reason: 'schoolName' };
  if (adminName.length < 2) return { error: 'INVALID_ARGUMENT', reason: 'adminName' };
  if (!EMAIL.test(adminEmail)) return { error: 'INVALID_ARGUMENT', reason: 'adminEmail' };
  if (!EMAIL.test(schoolEmail)) return { error: 'INVALID_ARGUMENT', reason: 'schoolEmail' };
  if (!/^[A-Z]{2}$/.test(countryCode)) return { error: 'INVALID_ARGUMENT', reason: 'country' };
  if (!/^[A-Z]{3}$/.test(currency)) return { error: 'INVALID_ARGUMENT', reason: 'currency' };
  if (!timezone) return { error: 'INVALID_ARGUMENT', reason: 'timezone' };
  if (!dateFormat) return { error: 'INVALID_ARGUMENT', reason: 'dateFormat' };
  return {
    value: {
      name,
      adminName,
      adminEmail,
      schoolEmail,
      phone: text(d.phone, 30) || null,
      country: text(d.countryName, 80) || null,
      regional: { countryCode, currency, timezone, dateFormat },
    },
  };
}

const adminLogin = (now, by) => ({
  enabled: true,
  methods: ['PASSWORD', 'GOOGLE'],
  effective: ['PASSWORD', 'GOOGLE'],
  phone: null,
  updatedAt: now,
  updatedBy: by,
});

/** Creates the Auth user (random password nobody knows) and returns its uid. */
async function newAuthUser(auth, email, name) {
  try {
    await auth.getUserByEmail(email);
    return { error: 'EMAIL_IN_USE' };
  } catch (e) {
    if (!notFound(e)) throw e;
  }
  const u = await auth.createUser({ email, displayName: name, emailVerified: false, password: crypto.randomBytes(32).toString('base64url') });
  return { uid: u.uid };
}

function adminProfile(now, by, schoolId, name, email) {
  return {
    schoolId,
    branchId: 'main',
    name,
    email,
    phone: null,
    photoUrl: null,
    role: 'SCHOOL_ADMIN',
    status: 'ACTIVE',
    linkedParentId: null,
    login: adminLogin(now, by),
    createdAt: now,
    updatedAt: now,
    createdBy: by,
    updatedBy: by,
  };
}

/** Owner-only: a new school, its Main Branch and its first administrator. */
async function createSchoolWithAdmin(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const v = validateSchool(data);
  if (v.error) return v;
  const s = v.value;
  const user = await newAuthUser(ctx.auth, s.adminEmail, s.adminName);
  if (user.error) return user;

  const schoolRef = ctx.db.collection('schools').doc();
  const schoolId = schoolRef.id;
  const now = ctx.now;
  const batch = ctx.db.batch();
  batch.set(schoolRef, {
    name: s.name,
    shortName: null,
    code: null,
    logoUrl: null,
    email: s.schoolEmail,
    phone: s.phone,
    alternatePhone: null,
    website: null,
    addressLine1: null,
    addressLine2: null,
    city: null,
    state: null,
    country: s.country,
    postalCode: null,
    defaultBranchId: null,
    ...s.regional,
    // Every new school starts INACTIVE; activating it is a separate, owner-only step.
    status: 'INACTIVE',
    lifecycleVersion: 1,
    // The global defaults as they are today, copied in: later changes to the defaults never touch this school.
    features: await require('./features').snapshotDefaults(ctx.db),
    featuresVersion: 1,
    createdAt: now,
    updatedAt: now,
    createdBy: callerUid,
    updatedBy: callerUid,
  });
  batch.set(schoolRef.collection('branches').doc('main'), {
    schoolId,
    name: 'Main Branch',
    code: null,
    email: null,
    phone: null,
    addressLine1: null,
    addressLine2: null,
    city: null,
    state: null,
    country: null,
    postalCode: null,
    status: 'ACTIVE',
    createdAt: now,
    updatedAt: now,
    createdBy: callerUid,
    updatedBy: callerUid,
  });
  // The first admin is paused from the start (the school is INACTIVE).
  batch.set(ctx.db.collection('users').doc(user.uid), { ...adminProfile(now, callerUid, schoolId, s.adminName, s.adminEmail), schoolAccess: 'INACTIVE' });
  const h = historyEntry(ctx, { schoolId, from: null, to: 'INACTIVE', event: 'SCHOOL_CREATED', actorUid: callerUid, actorEmail: caller.profile.email });
  batch.set(histRef(ctx.db, undefined), h);
  const a = audit(ctx, caller, callerUid, 'SCHOOL_CREATED', {
    schoolId,
    targetUid: user.uid,
    targetEmail: s.adminEmail,
    meta: { schoolName: s.name, currency: s.regional.currency },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, schoolId, adminUid: user.uid, adminEmail: s.adminEmail };
}

/** Owner-only: another administrator for an existing school (e.g. a replacement). */
async function addSchoolAdmin(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const name = text(data && data.name, 100);
  const email = text(data && data.email, 254).toLowerCase();
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  if (name.length < 2) return { error: 'INVALID_ARGUMENT', reason: 'adminName' };
  if (!EMAIL.test(email)) return { error: 'INVALID_ARGUMENT', reason: 'adminEmail' };
  const school = await schoolOf(ctx.db, schoolId);
  if (!school) return { error: 'NOT_FOUND' };
  const user = await newAuthUser(ctx.auth, email, name);
  if (user.error) return user;
  const batch = ctx.db.batch();
  const profile = adminProfile(ctx.now, callerUid, schoolId, name, email);
  // A new admin of a school that is not active is paused like everyone else there.
  if (statusOf(school) !== 'ACTIVE') profile.schoolAccess = statusOf(school);
  batch.set(ctx.db.collection('users').doc(user.uid), profile);
  const a = audit(ctx, caller, callerUid, 'SCHOOL_ADMIN_ADDED', { schoolId, targetUid: user.uid, targetEmail: email });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, adminUid: user.uid, adminEmail: email };
}

/** Owner/support: signs a school admin out everywhere (the app then emails a reset link). */
async function resetSchoolAdminAccess(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const uid = text(data && data.uid, 128);
  const u = uid ? (await ctx.db.collection('users').doc(uid).get()).data() : null;
  if (!schoolId || !uid) return { error: 'INVALID_ARGUMENT', reason: 'uid' };
  if (!u || u.role !== 'SCHOOL_ADMIN' || u.schoolId !== schoolId) return { error: 'NOT_FOUND' };
  await ctx.auth.revokeRefreshTokens(uid);
  const a = audit(ctx, caller, callerUid, 'SCHOOL_ADMIN_ACCESS_RESET', { schoolId, targetUid: uid, targetEmail: u.email });
  await a.ref.set(a.rec);
  return { ok: true, email: u.email };
}

// ---- recovery of a CLOSED school (break-glass, two owners) -------------------------------

const RECOVERY_REASON_MIN = 15;

/** Owner: asks to recover a CLOSED school. Nothing changes until a DIFFERENT owner approves. */
async function requestSchoolRecovery(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const reason = text(data && data.reason, 500);
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  if (reason.length < RECOVERY_REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: 'reason' };
  const school = await schoolOf(ctx.db, schoolId);
  if (!school) return { error: 'NOT_FOUND' };
  if (statusOf(school) !== 'CLOSED') return { error: 'FAILED_PRECONDITION', reason: 'NOT_CLOSED' };
  const ref = ctx.db.collection('schoolRecovery').doc(schoolId);
  const cur = (await ref.get()).data();
  if (cur && cur.state === 'REQUESTED') return { error: 'FAILED_PRECONDITION', reason: 'ALREADY_OPEN' };
  const batch = ctx.db.batch();
  batch.set(ref, {
    schoolId, schoolName: school.name || '', state: 'REQUESTED', reason,
    requestedBy: callerUid, requestedByEmail: caller.profile.email, requestedAt: ctx.now,
    approvedBy: null, approvedAt: null, closedBy: null, closedAt: null,
  });
  const a = audit(ctx, caller, callerUid, 'SCHOOL_RECOVERY_REQUESTED', { schoolId, reason });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true };
}

/** A DIFFERENT owner approves: the school goes CLOSED -> INACTIVE (it still needs activating). */
async function approveSchoolRecovery(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const ref = ctx.db.collection('schoolRecovery').doc(schoolId || '-');
  const out = await ctx.db.runTransaction(async (tx) => {
    const rec = (await tx.get(ref)).data();
    const schoolRef = ctx.db.collection('schools').doc(schoolId || '-');
    const school = (await tx.get(schoolRef)).data();
    if (!rec || !school) return { error: 'NOT_FOUND' };
    if (rec.state !== 'REQUESTED') return { error: 'FAILED_PRECONDITION', reason: 'NOT_REQUESTED' };
    if (rec.requestedBy === callerUid) return { error: 'FAILED_PRECONDITION', reason: 'SAME_PERSON' };
    if (statusOf(school) !== 'CLOSED' || !transitionRule('CLOSED', 'INACTIVE', 'RECOVERY')) return { error: 'FAILED_PRECONDITION', reason: 'NOT_CLOSED' };
    tx.update(schoolRef, {
      status: 'INACTIVE', statusReason: `Recovered: ${rec.reason}`, statusChangedAt: ctx.now, statusChangedBy: callerUid,
      lifecycleUpdatedAt: ctx.now, lifecycleUpdatedBy: callerUid, lifecycleVersion: (school.lifecycleVersion || 0) + 1,
      updatedAt: ctx.now, updatedBy: callerUid,
    });
    tx.update(ref, { state: 'APPROVED', approvedBy: callerUid, approvedAt: ctx.now });
    tx.set(
      histRef(ctx.db, undefined),
      historyEntry(ctx, {
        schoolId, from: 'CLOSED', to: 'INACTIVE', event: 'SCHOOL_RECOVERED', actorUid: callerUid, actorEmail: caller.profile.email,
        reason: rec.reason, remarks: `Requested by ${rec.requestedByEmail}`,
      }),
    );
    const a = audit(ctx, caller, callerUid, 'SCHOOL_RECOVERED', { schoolId, reason: rec.reason, meta: { requestedBy: rec.requestedBy } });
    tx.set(a.ref, a.rec);
    return { ok: true };
  });
  if (out.error) return out;
  await applySchoolAccess(ctx, schoolId, 'INACTIVE', ctx.nowDate().getTime() + 30000);
  return { ok: true, status: 'INACTIVE' };
}

/** The requester (or any owner) withdraws a recovery request. */
async function cancelSchoolRecovery(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const ref = ctx.db.collection('schoolRecovery').doc(schoolId || '-');
  const rec = (await ref.get()).data();
  if (!rec) return { error: 'NOT_FOUND' };
  if (rec.state !== 'REQUESTED') return { error: 'FAILED_PRECONDITION', reason: 'NOT_REQUESTED' };
  const batch = ctx.db.batch();
  batch.update(ref, { state: 'CANCELLED', closedBy: callerUid, closedAt: ctx.now });
  const a = audit(ctx, caller, callerUid, 'SCHOOL_RECOVERY_CANCELLED', { schoolId });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true };
}

// ---- feature switches ---------------------------------------------------------------

/** Owner-only: module switches (see features.js). Kept here so existing imports keep working. */
const setSchoolFeatures = (...args) => require('./features').setSchoolFeatures(...args);

/** True unless the school's switch for [feature] is off. Missing = on. */
async function featureEnabled(db, schoolId, feature) {
  const s = await schoolOf(db, schoolId);
  if (!s) return false;
  return require('./features').usable(s.features, feature);
}

// ---- offboarding (workflow only: nothing is purged automatically) ------------------

/** Owner-only: starts offboarding; the school is suspended right away. */
async function requestSchoolOffboarding(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const reason = text(data && data.reason, 500);
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  if (reason.length < OFFBOARD_REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: 'reason' };
  const school = await schoolOf(ctx.db, schoolId);
  if (!school) return { error: 'NOT_FOUND' };
  const ref = ctx.db.collection('platformOffboarding').doc(schoolId);
  const cur = (await ref.get()).data();
  if (cur && ['REQUESTED', 'APPROVED'].includes(cur.state)) return { error: 'FAILED_PRECONDITION', reason: 'ALREADY_OPEN' };
  const graceUntil = new Date(ctx.nowDate().getTime() + GRACE_DAYS * 86400000);
  const wasActive = !school.status || school.status === 'ACTIVE';
  const batch = ctx.db.batch();
  batch.set(ref, {
    schoolId,
    schoolName: school.name || '',
    state: 'REQUESTED',
    reason,
    requestedBy: callerUid,
    requestedByEmail: caller.profile.email,
    requestedAt: ctx.now,
    graceUntil,
    suspendedByOffboarding: wasActive,
    approvedBy: null,
    approvedAt: null,
    closedBy: null,
    closedAt: null,
  });
  if (wasActive) {
    batch.update(ctx.db.collection('schools').doc(schoolId), {
      status: 'SUSPENDED',
      statusReason: 'School is being offboarded',
      statusChangedAt: ctx.now,
      statusChangedBy: callerUid,
      updatedAt: ctx.now,
      updatedBy: callerUid,
    });
  }
  const a = audit(ctx, caller, callerUid, 'SCHOOL_OFFBOARDING_REQUESTED', { schoolId, reason, meta: { graceDays: GRACE_DAYS } });
  batch.set(a.ref, a.rec);
  await batch.commit();
  if (wasActive) await applySchoolAccess(ctx, schoolId, 'SUSPENDED', ctx.nowDate().getTime() + 30000);
  return { ok: true, graceUntilMs: graceUntil.getTime() };
}

/** A SECOND owner approves (two-person rule). Still deletes nothing by itself. */
async function approveSchoolOffboarding(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const ref = ctx.db.collection('platformOffboarding').doc(schoolId || '-');
  const cur = (await ref.get()).data();
  if (!cur) return { error: 'NOT_FOUND' };
  if (cur.state !== 'REQUESTED') return { error: 'FAILED_PRECONDITION', reason: 'NOT_REQUESTED' };
  if (cur.requestedBy === callerUid) return { error: 'FAILED_PRECONDITION', reason: 'SAME_PERSON' };
  const batch = ctx.db.batch();
  batch.update(ref, { state: 'APPROVED', approvedBy: callerUid, approvedAt: ctx.now });
  const a = audit(ctx, caller, callerUid, 'SCHOOL_OFFBOARDING_APPROVED', { schoolId });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true };
}

/** Owner-only: stops offboarding and, if offboarding suspended it, reactivates the school. */
async function cancelSchoolOffboarding(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const ref = ctx.db.collection('platformOffboarding').doc(schoolId || '-');
  const cur = (await ref.get()).data();
  if (!cur) return { error: 'NOT_FOUND' };
  if (!['REQUESTED', 'APPROVED'].includes(cur.state)) return { error: 'FAILED_PRECONDITION', reason: 'NOT_OPEN' };
  const batch = ctx.db.batch();
  batch.update(ref, { state: 'CANCELLED', closedBy: callerUid, closedAt: ctx.now });
  if (cur.suspendedByOffboarding) {
    batch.update(ctx.db.collection('schools').doc(schoolId), {
      status: 'ACTIVE',
      statusReason: null,
      statusChangedAt: ctx.now,
      statusChangedBy: callerUid,
      updatedAt: ctx.now,
      updatedBy: callerUid,
    });
  }
  const a = audit(ctx, caller, callerUid, 'SCHOOL_OFFBOARDING_CANCELLED', { schoolId });
  batch.set(a.ref, a.rec);
  await batch.commit();
  if (cur.suspendedByOffboarding) await applySchoolAccess(ctx, schoolId, 'ACTIVE', ctx.nowDate().getTime() + 30000);
  return { ok: true };
}

module.exports = {
  ALL_STATUSES,
  TRANSITIONS,
  statusOf,
  transitionRule,
  transitionSchool,
  newSchoolFixes,
  SERVER_OWNED_ON_CREATE,
  systemTransition,
  requestSchoolRecovery,
  approveSchoolRecovery,
  cancelSchoolRecovery,
  STATUSES,
  FEATURES,
  GRACE_DAYS,
  applySchoolAccess,
  setSchoolStatus,
  refreshSchoolAccess,
  createSchoolWithAdmin,
  addSchoolAdmin,
  resetSchoolAdminAccess,
  setSchoolFeatures,
  featureEnabled,
  requestSchoolOffboarding,
  approveSchoolOffboarding,
  cancelSchoolOffboarding,
};

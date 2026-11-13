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

const crypto = require('node:crypto');
const { platformCaller, auditRecord } = require('./platform_admin');

const STATUSES = ['ACTIVE', 'SUSPENDED'];
const FEATURES = ['admission', 'publicAdmission'];
const REASON_MIN = 10;
const OFFBOARD_REASON_MIN = 15;
const GRACE_DAYS = 30;
const PAGE = 400;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const notFound = (e) => e && (e.code === 'auth/user-not-found' || e.code === 'not-found');

/**
 * Mirrors the school's status onto the profiles of its users (SUSPENDED sets
 * `schoolAccess`, ACTIVE removes it). Idempotent and resumable: only profiles
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
      const has = u.schoolAccess === 'SUSPENDED';
      if (suspended !== has) {
        batch.update(d.ref, suspended ? { schoolAccess: 'SUSPENDED' } : { schoolAccess: ctx.deleteField });
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

/** Owner-only: suspends or reactivates a school and applies it to every user. */
async function setSchoolStatus(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = text(data && data.schoolId, 128);
  const status = data && data.status;
  const reason = text(data && data.reason, 500);
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  if (!STATUSES.includes(status)) return { error: 'INVALID_ARGUMENT', reason: 'status' };
  if (status === 'SUSPENDED' && reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: 'reason' };
  const school = await schoolOf(ctx.db, schoolId);
  if (!school) return { error: 'NOT_FOUND' };
  // A school being offboarded stays suspended until the workflow is cancelled.
  const off = (await ctx.db.collection('platformOffboarding').doc(schoolId).get()).data();
  if (status === 'ACTIVE' && off && ['REQUESTED', 'APPROVED'].includes(off.state)) {
    return { error: 'FAILED_PRECONDITION', reason: 'OFFBOARDING' };
  }
  if (school.status === status) return { ok: true, unchanged: true, status };

  const batch = ctx.db.batch();
  batch.update(ctx.db.collection('schools').doc(schoolId), {
    status,
    statusReason: status === 'SUSPENDED' ? reason : null,
    statusChangedAt: ctx.now,
    statusChangedBy: callerUid,
    updatedAt: ctx.now,
    updatedBy: callerUid,
  });
  const a = audit(ctx, caller, callerUid, status === 'SUSPENDED' ? 'SCHOOL_SUSPENDED' : 'SCHOOL_REACTIVATED', {
    schoolId,
    reason: reason || null,
    meta: { from: school.status || null },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  const applied = await applySchoolAccess(ctx, schoolId, status, ctx.nowDate().getTime() + 30000);
  return { ok: true, status, usersUpdated: applied.updated, complete: applied.done };
}

/** Owner/support: re-applies the school's current status to its users (repair). */
async function refreshSchoolAccess(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT']);
  if (caller.error) return { error: caller.error };
  const schoolId = text(data && data.schoolId, 128);
  const school = await schoolOf(ctx.db, schoolId);
  if (!school) return { error: schoolId ? 'NOT_FOUND' : 'INVALID_ARGUMENT' };
  const applied = await applySchoolAccess(ctx, schoolId, school.status || 'ACTIVE', ctx.nowDate().getTime() + 30000);
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
    status: 'ACTIVE',
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
  batch.set(ctx.db.collection('users').doc(user.uid), adminProfile(now, callerUid, schoolId, s.adminName, s.adminEmail));
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
  const schoolId = text(data && data.schoolId, 128);
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
  // A new admin of a suspended school is paused like everyone else there.
  if (school.status && school.status !== 'ACTIVE') profile.schoolAccess = 'SUSPENDED';
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
  const schoolId = text(data && data.schoolId, 128);
  const uid = text(data && data.uid, 128);
  const u = uid ? (await ctx.db.collection('users').doc(uid).get()).data() : null;
  if (!schoolId || !uid) return { error: 'INVALID_ARGUMENT', reason: 'uid' };
  if (!u || u.role !== 'SCHOOL_ADMIN' || u.schoolId !== schoolId) return { error: 'NOT_FOUND' };
  await ctx.auth.revokeRefreshTokens(uid);
  const a = audit(ctx, caller, callerUid, 'SCHOOL_ADMIN_ACCESS_RESET', { schoolId, targetUid: uid, targetEmail: u.email });
  await a.ref.set(a.rec);
  return { ok: true, email: u.email };
}

// ---- feature switches ---------------------------------------------------------------

/** Owner-only: turns platform-controlled modules on or off for one school. */
async function setSchoolFeatures(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = text(data && data.schoolId, 128);
  const incoming = data && data.features;
  if (!schoolId || !incoming || typeof incoming !== 'object') return { error: 'INVALID_ARGUMENT', reason: 'features' };
  const school = await schoolOf(ctx.db, schoolId);
  if (!school) return { error: 'NOT_FOUND' };
  const next = { ...(school.features || {}) };
  for (const [k, v] of Object.entries(incoming)) {
    if (!FEATURES.includes(k) || typeof v !== 'boolean') return { error: 'INVALID_ARGUMENT', reason: 'features' };
    next[k] = v;
  }
  const batch = ctx.db.batch();
  batch.update(ctx.db.collection('schools').doc(schoolId), { features: next, updatedAt: ctx.now, updatedBy: callerUid });
  const a = audit(ctx, caller, callerUid, 'SCHOOL_FEATURES_CHANGED', { schoolId, meta: { features: next } });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, features: next };
}

/** True unless the school's switch for [feature] is off. Missing = on. */
async function featureEnabled(db, schoolId, feature) {
  const s = await schoolOf(db, schoolId);
  if (!s) return false;
  return !(s.features && s.features[feature] === false);
}

// ---- offboarding (workflow only: nothing is purged automatically) ------------------

/** Owner-only: starts offboarding; the school is suspended right away. */
async function requestSchoolOffboarding(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = text(data && data.schoolId, 128);
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
  const schoolId = text(data && data.schoolId, 128);
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
  const schoolId = text(data && data.schoolId, 128);
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

'use strict';

// Platform administrators (Avail404 staff): who they are, how they are created
// and what they may do. See docs/platform-admin/PLATFORM_ADMIN_PLAN.md.
//
// Rules of this module:
//  * every action is a server action that checks the caller (active
//    PLATFORM_ADMIN profile, allowed sign-in method, SECOND FACTOR present,
//    platformRole), validates input and writes an audit record;
//  * platform admins are dedicated accounts: an email that already has an
//    Auth user or a profile is never reused;
//  * no password is ever returned, stored or logged. The new person sets their
//    own through a password-reset email (sent by the app) or, for the bootstrap
//    script, a one-time reset link printed to the operator's terminal.

const crypto = require('node:crypto');
const { methodAllowed, hasSecondFactor } = require('./access');

const PLATFORM_ROLES = ['OWNER', 'SUPPORT', 'COMPLIANCE', 'VIEWER'];
// Profiles written before platformRole existed keep their full power until an
// owner assigns a role (the only platform admin that existed could do it all).
const LEGACY_ROLE = 'OWNER';
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const DEFAULT_DOMAINS = ['avail404.com'];
// Accounts a platform admin may be moved between.
const STATUSES = ['ACTIVE', 'DISABLED'];

/** The platform role of a profile; an unknown value grants nothing. */
function platformRoleOf(profile) {
  if (!profile || profile.role !== 'PLATFORM_ADMIN') return null;
  if (profile.platformRole === undefined || profile.platformRole === null) return LEGACY_ROLE;
  return PLATFORM_ROLES.includes(profile.platformRole) ? profile.platformRole : null;
}

/**
 * The caller as an ACTIVE platform admin who signed in with a second factor
 * and holds one of [roles]. Returns { profile, platformRole } or
 * { error: 'PERMISSION_DENIED' | 'MFA_REQUIRED' }.
 */
async function platformCaller(db, uid, token, roles) {
  const profile = (await db.collection('users').doc(uid).get()).data();
  const platformRole = platformRoleOf(profile);
  if (!platformRole || !methodAllowed(profile, token)) return { error: 'PERMISSION_DENIED' };
  if (!hasSecondFactor(token)) return { error: 'MFA_REQUIRED' };
  if (!roles.includes(platformRole)) return { error: 'PERMISSION_DENIED' };
  return { profile: { ...profile, uid }, platformRole };
}

/**
 * One create-only audit record. Never put secrets, passwords, links or tokens
 * in `meta`. The collection is written only here (rules forbid clients).
 */
function auditRecord(ctx, e) {
  const ref = ctx.db.collection('platformAuditLog').doc();
  return {
    ref,
    rec: {
      action: e.action,
      actorUid: e.actorUid || null,
      actorEmail: e.actorEmail || null,
      actorPlatformRole: e.actorPlatformRole || null,
      targetUid: e.targetUid || null,
      targetEmail: e.targetEmail || null,
      schoolId: e.schoolId || null,
      reason: e.reason || null,
      result: e.result || 'OK',
      meta: e.meta || {},
      source: e.source || 'CALLABLE',
      createdAt: ctx.now,
    },
  };
}

function allowedDomains(env) {
  const raw = (env && env.PLATFORM_ADMIN_EMAIL_DOMAINS) || '';
  const list = raw
    .split(',')
    .map((d) => d.trim().toLowerCase())
    .filter(Boolean);
  return list.length ? list : DEFAULT_DOMAINS;
}

const notFound = (e) => e && (e.code === 'auth/user-not-found' || e.code === 'not-found');

function validateNew(data, domains) {
  const name = typeof (data && data.name) === 'string' ? data.name.trim() : '';
  const email = typeof (data && data.email) === 'string' ? data.email.trim().toLowerCase() : '';
  const platformRole = data && data.platformRole;
  if (name.length < 2 || name.length > 100) return { error: 'INVALID_ARGUMENT', reason: 'name' };
  if (!EMAIL.test(email) || email.length > 254) return { error: 'INVALID_ARGUMENT', reason: 'email' };
  if (!PLATFORM_ROLES.includes(platformRole)) return { error: 'INVALID_ARGUMENT', reason: 'platformRole' };
  if (!domains.includes(email.split('@')[1])) return { error: 'INVALID_ARGUMENT', reason: 'emailDomain' };
  return { value: { name, email, platformRole } };
}

/**
 * Creates the Auth user (email verified, so a second factor can be enrolled;
 * password unknown to everyone until the person sets it) and the profile.
 * Shared by the owner-only callable and the bootstrap script.
 */
async function createAccount(ctx, actor, v, source) {
  const { db, auth, now } = ctx;
  let existing = null;
  try {
    existing = await auth.getUserByEmail(v.email);
  } catch (e) {
    if (!notFound(e)) throw e;
  }
  if (existing) return { error: 'EMAIL_IN_USE' };

  const created = await auth.createUser({
    email: v.email,
    displayName: v.name,
    emailVerified: true,
    password: crypto.randomBytes(32).toString('base64url'),
  });
  const uid = created.uid;
  const by = actor.uid || 'bootstrap-script';
  const batch = db.batch();
  batch.set(db.collection('users').doc(uid), {
    schoolId: null,
    branchId: null,
    name: v.name,
    email: v.email,
    phone: null,
    photoUrl: null,
    role: 'PLATFORM_ADMIN',
    platformRole: v.platformRole,
    status: 'ACTIVE',
    linkedParentId: null,
    // Password plus a second factor only (the second factor itself is enforced
    // by firestore.rules, storage.rules and callables).
    login: { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'], phone: null, updatedAt: now, updatedBy: by },
    createdAt: now,
    updatedAt: now,
    createdBy: by,
    updatedBy: by,
  });
  const a = auditRecord(ctx, {
    action: 'PLATFORM_ADMIN_CREATED',
    actorUid: actor.uid || null,
    actorEmail: actor.email || null,
    actorPlatformRole: actor.platformRole || null,
    targetUid: uid,
    targetEmail: v.email,
    meta: { platformRole: v.platformRole },
    source,
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { uid, email: v.email, platformRole: v.platformRole };
}

/** Owner-only callable: adds a platform admin. */
async function createPlatformAdmin(ctx, callerUid, token, data, env) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const v = validateNew(data, allowedDomains(env));
  if (v.error) return v;
  const out = await createAccount(
    ctx,
    { uid: callerUid, email: caller.profile.email, platformRole: caller.platformRole },
    v.value,
    'CALLABLE',
  );
  return out;
}

/**
 * Script path (no signed-in caller): creates the first or a recovery platform
 * admin. Run by an operator with project credentials, never exposed as a
 * callable. Returns a one-time password-reset link for the new person.
 */
async function bootstrapPlatformAdmin(ctx, data, env, operator) {
  const v = validateNew(data, allowedDomains(env));
  if (v.error) return v;
  const out = await createAccount(ctx, { uid: null, email: operator || null, platformRole: null }, v.value, 'SCRIPT');
  if (out.error) return out;
  const resetLink = await ctx.auth.generatePasswordResetLink(v.value.email);
  return { ...out, resetLink };
}

async function enrolledFactors(auth, uid) {
  try {
    const u = await auth.getUser(uid);
    const f = u.multiFactor && u.multiFactor.enrolledFactors;
    return { mfaEnrolled: Array.isArray(f) && f.length > 0, lastSignIn: (u.metadata && u.metadata.lastSignInTime) || null };
  } catch (e) {
    if (notFound(e)) return { mfaEnrolled: false, lastSignIn: null, missingAuth: true };
    throw e;
  }
}

/** Owner-only: every platform admin with their role, status and MFA state. */
async function listPlatformAdmins(ctx, callerUid, token) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const snap = await ctx.db.collection('users').where('role', '==', 'PLATFORM_ADMIN').get();
  const admins = [];
  for (const d of snap.docs) {
    const u = d.data();
    const f = await enrolledFactors(ctx.auth, d.id);
    admins.push({
      uid: d.id,
      name: u.name || '',
      email: u.email || '',
      platformRole: platformRoleOf(u) || 'NONE',
      roleAssigned: u.platformRole !== undefined && u.platformRole !== null,
      status: u.status,
      mfaEnrolled: f.mfaEnrolled,
      lastSignIn: f.lastSignIn,
      isSelf: d.id === callerUid,
    });
  }
  admins.sort((a, b) => a.email.localeCompare(b.email));
  return { admins };
}

async function targetAdmin(db, uid) {
  if (typeof uid !== 'string' || !uid) return null;
  const u = (await db.collection('users').doc(uid).get()).data();
  return u && u.role === 'PLATFORM_ADMIN' ? u : null;
}

/** Owner-only: changes another platform admin's role. Never your own. */
async function setPlatformRole(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const uid = data && data.uid;
  const platformRole = data && data.platformRole;
  if (!PLATFORM_ROLES.includes(platformRole)) return { error: 'INVALID_ARGUMENT', reason: 'platformRole' };
  if (uid === callerUid) return { error: 'FAILED_PRECONDITION', reason: 'SELF_CHANGE' };
  const target = await targetAdmin(ctx.db, uid);
  if (!target) return { error: 'NOT_FOUND' };
  // The caller is an active OWNER and is not the target, so at least one
  // owner always remains after this change.
  const before = platformRoleOf(target);
  const batch = ctx.db.batch();
  batch.update(ctx.db.collection('users').doc(uid), { platformRole, updatedAt: ctx.now, updatedBy: callerUid });
  const a = auditRecord(ctx, {
    action: 'PLATFORM_ROLE_CHANGED',
    actorUid: callerUid,
    actorEmail: caller.profile.email,
    actorPlatformRole: caller.platformRole,
    targetUid: uid,
    targetEmail: target.email,
    meta: { from: before, to: platformRole },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  // The role is read from the profile on every call, so it takes effect at
  // once; no token needs revoking.
  return { ok: true, platformRole };
}

/** Owner-only: disables or re-enables another platform admin. */
async function setPlatformAdminStatus(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const uid = data && data.uid;
  const status = data && data.status;
  if (!STATUSES.includes(status)) return { error: 'INVALID_ARGUMENT', reason: 'status' };
  if (uid === callerUid) return { error: 'FAILED_PRECONDITION', reason: 'SELF_CHANGE' };
  const target = await targetAdmin(ctx.db, uid);
  if (!target) return { error: 'NOT_FOUND' };

  const disabled = status === 'DISABLED';
  await ctx.auth.updateUser(uid, { disabled });
  if (disabled) await ctx.auth.revokeRefreshTokens(uid);
  const batch = ctx.db.batch();
  batch.update(ctx.db.collection('users').doc(uid), { status, updatedAt: ctx.now, updatedBy: callerUid });
  const a = auditRecord(ctx, {
    action: disabled ? 'PLATFORM_ADMIN_DISABLED' : 'PLATFORM_ADMIN_ENABLED',
    actorUid: callerUid,
    actorEmail: caller.profile.email,
    actorPlatformRole: caller.platformRole,
    targetUid: uid,
    targetEmail: target.email,
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, status };
}

module.exports = {
  PLATFORM_ROLES,
  LEGACY_ROLE,
  platformRoleOf,
  platformCaller,
  auditRecord,
  allowedDomains,
  createPlatformAdmin,
  bootstrapPlatformAdmin,
  listPlatformAdmins,
  setPlatformRole,
  setPlatformAdminStatus,
};

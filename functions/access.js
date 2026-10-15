'use strict';

// Login access management: which sign-in methods a school enables, which a
// user may use, and the server-written `login` map on /users/{uid} that
// firestore.rules / storage.rules enforce on every request.
//
//   users/{uid}.login = {
//     enabled:   bool,        // master switch (false => cannot use the app)
//     methods:   string[],    // what the admin granted this user
//     effective: string[],    // methods ∩ school-enabled (what rules check)
//     phone:     string|null, // E.164, only when PHONE_OTP is granted
//     phoneVerifiedAt?, updatedAt, updatedBy
//   }
//   schools/{s}/authSettings/methods = { methods: string[], updatedAt, updatedBy }
//   schools/{s}/authAudit/{id}       = security audit trail (no secrets)
//
// A profile without `login` is a legacy account: allowed as before.

const crypto = require('node:crypto');

const METHODS = ['PASSWORD', 'GOOGLE', 'PHONE_OTP'];
// What accounts could use before this feature existed. Materialised for
// legacy users only when a school changes its settings.
const LEGACY_METHODS = ['PASSWORD', 'GOOGLE'];
const DEFAULT_SCHOOL_METHODS = ['PASSWORD', 'GOOGLE'];
const SCHOOL_KEYS = { emailPassword: 'PASSWORD', google: 'GOOGLE', phoneOtp: 'PHONE_OTP' };
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const MAX_LOGIN_ADMIN_BATCH = 400;

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);
const methodsDoc = (db, s) => db.collection('schools').doc(s).collection('authSettings').doc('methods');

const sortMethods = (m) => METHODS.filter((x) => m.includes(x));
const intersect = (a, b) => sortMethods(a.filter((x) => b.includes(x)));

// E.164 normalisation. A bare 10-digit number gets the default country code.
function normalizePhone(raw, defaultCountryCode = process.env.DEFAULT_PHONE_COUNTRY_CODE || '91') {
  if (typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  if (!/^[+\d][\d\s\-().]*$/.test(trimmed)) return null;
  const digits = trimmed.replace(/\D/g, '');
  let e164;
  if (trimmed.startsWith('+')) e164 = `+${digits}`;
  else if (digits.length === 10) e164 = `+${defaultCountryCode}${digits}`;
  else if (digits.length === 11 && digits.startsWith('0')) e164 = `+${defaultCountryCode}${digits.slice(1)}`;
  else if (digits.length >= 11 && digits.length <= 15) e164 = `+${digits}`;
  else return null;
  return /^\+[1-9]\d{7,14}$/.test(e164) ? e164 : null;
}

function normalizeEmail(raw) {
  if (typeof raw !== 'string') return null;
  const e = raw.trim().toLowerCase();
  return EMAIL.test(e) ? e : null;
}

// JS mirror of loginAllowed() in firestore.rules, for server-side checks in
// callables. `token` is request.auth.token.
function signInMethod(token) {
  const p = token && token.firebase && token.firebase.sign_in_provider;
  if (p === 'password') return 'PASSWORD';
  if (p === 'google.com') return 'GOOGLE';
  if (p === 'custom' && token.via === 'PHONE_OTP') return 'PHONE_OTP';
  return 'OTHER';
}

function loginAllowed(profile, token) {
  if (!profile || profile.status !== 'ACTIVE') return false;
  const l = profile.login;
  if (l == null) return true;
  return l.enabled === true && Array.isArray(l.effective) && l.effective.includes(signInMethod(token));
}

async function schoolMethods(db, schoolId) {
  const snap = await methodsDoc(db, schoolId).get();
  const m = snap.exists ? snap.data().methods : null;
  return Array.isArray(m) ? sortMethods(m) : [...DEFAULT_SCHOOL_METHODS];
}

// The caller must be an ACTIVE school admin of the school, or an ACTIVE
// branch admin of the branch, and must themselves be allowed to sign in.
async function assertAdmin(db, uid, schoolId, branchId, token) {
  const snap = await db.collection('users').doc(uid).get();
  const u = snap.data();
  if (!u || u.schoolId !== schoolId || !loginAllowed(u, token)) return null;
  if (u.role === 'SCHOOL_ADMIN') return u;
  if (u.role === 'BRANCH_ADMIN' && branchId && u.branchId === branchId) return u;
  return null;
}

function audit(ctx, schoolId, event) {
  const ref = ctx.db.collection('schools').doc(schoolId).collection('authAudit').doc();
  const rec = { schoolId, ...event, createdAt: ctx.now };
  return { ref, rec };
}

// ---- record resolution ---------------------------------------------------

function displayName(d) {
  return [d.firstName, d.middleName, d.lastName].filter(Boolean).join(' ');
}

async function loadRecord(db, { schoolId, branchId, kind, id }) {
  const coll = kind === 'STAFF' ? 'staff' : 'parents';
  const ref = branchRef(db, schoolId, branchId).collection(coll).doc(id);
  const snap = await ref.get();
  if (!snap.exists) return null;
  const d = snap.data();
  return {
    ref,
    data: d,
    uid: (kind === 'STAFF' ? d.userId : d.linkedUserId) || null,
    name: displayName(d),
    email: normalizeEmail(d.email || ''),
    phone: normalizePhone(d.phone || ''),
  };
}

function validTarget(kind, schoolId, branchId, id) {
  return (
    (kind === 'STAFF' || kind === 'PARENT') &&
    [schoolId, branchId, id].every((v) => typeof v === 'string' && v.length > 0 && v.length <= 128)
  );
}

// A branch admin may only manage non-admin users; nobody manages admins of
// the platform or another school admin through this path.
function mayManageRole(caller, targetRole) {
  if (targetRole === 'PLATFORM_ADMIN' || targetRole === 'SCHOOL_ADMIN') return false;
  if (targetRole === 'BRANCH_ADMIN') return caller.role === 'SCHOOL_ADMIN';
  return ['TEACHER', 'FINANCE', 'PARENT'].includes(targetRole);
}

function activation(authUser) {
  if (!authUser) return 'NO_ACCOUNT';
  return authUser.metadata && authUser.metadata.lastSignInTime ? 'ACTIVE' : 'PENDING_ACTIVATION';
}

// ---- getLoginAccess ------------------------------------------------------

async function getLoginAccess({ db, auth }, callerUid, token, data) {
  const { schoolId, branchId, kind, id } = data || {};
  if (!validTarget(kind, schoolId, branchId, id)) return { error: 'INVALID_ARGUMENT' };
  const caller = await assertAdmin(db, callerUid, schoolId, branchId, token);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const rec = await loadRecord(db, { schoolId, branchId, kind, id });
  if (!rec) return { error: 'NOT_FOUND' };
  const school = await schoolMethods(db, schoolId);
  const out = {
    id,
    kind,
    name: rec.name,
    userType: kind === 'PARENT' ? 'PARENT' : rec.data.isTeacher ? 'TEACHER' : 'STAFF',
    registeredEmail: rec.email,
    registeredPhone: rec.phone,
    schoolMethods: school,
    hasAccount: false,
    enabled: false,
    methods: [],
    effective: [],
    activation: 'NO_ACCOUNT',
    emailVerified: false,
    lastLogin: null,
    phoneVerified: false,
    manageable: true,
  };
  if (!rec.uid) return { result: out };
  const u = (await db.collection('users').doc(rec.uid).get()).data();
  if (!u || u.schoolId !== schoolId) return { result: out };
  out.hasAccount = true;
  out.role = u.role;
  out.manageable = mayManageRole(caller, u.role) && rec.uid !== callerUid;
  const l = u.login;
  out.legacy = l == null;
  out.enabled = u.status === 'ACTIVE' && (l == null || l.enabled === true);
  out.methods = l ? l.methods || [] : intersect(LEGACY_METHODS, school).length ? [...LEGACY_METHODS] : [];
  out.effective = l ? l.effective || [] : intersect(LEGACY_METHODS, school);
  out.phoneVerified = !!(l && l.phoneVerifiedAt);
  try {
    const a = await auth.getUser(rec.uid);
    out.activation = activation(a);
    out.emailVerified = a.emailVerified === true;
    out.lastLogin = (a.metadata && a.metadata.lastSignInTime) || null;
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
    out.activation = 'NO_ACCOUNT';
  }
  return { result: out };
}

// ---- setLoginAccess ------------------------------------------------------

function validateGrant({ enabled, methods, school, email, phone }) {
  if (enabled && methods.length === 0) return 'NO_METHOD';
  for (const m of methods) {
    if (!school.includes(m)) return 'METHOD_NOT_ENABLED';
    if ((m === 'PASSWORD' || m === 'GOOGLE') && !email) return 'EMAIL_REQUIRED';
    if (m === 'PHONE_OTP' && !phone) return 'PHONE_REQUIRED';
  }
  return null;
}

/**
 * Enables/disables login for a staff or parent record and sets the methods
 * they may use. If the record has no account yet, one is created (email
 * optional when only PHONE_OTP is granted). Never deletes the account, the
 * record or any history.
 */
async function setLoginAccess(ctx, callerUid, token, data) {
  const { db, auth, now } = ctx;
  const { schoolId, branchId, kind, id } = data || {};
  if (!validTarget(kind, schoolId, branchId, id)) return { error: 'INVALID_ARGUMENT' };
  if (typeof data.enabled !== 'boolean') return { error: 'INVALID_ARGUMENT' };
  const requested = Array.isArray(data.methods) ? data.methods : [];
  if (requested.some((m) => !METHODS.includes(m))) return { error: 'INVALID_ARGUMENT' };
  const methods = sortMethods([...new Set(requested)]);

  const caller = await assertAdmin(db, callerUid, schoolId, branchId, token);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const rec = await loadRecord(db, { schoolId, branchId, kind, id });
  if (!rec) return { error: 'NOT_FOUND' };
  if (rec.data.status && rec.data.status !== 'ACTIVE' && data.enabled) return { error: 'RECORD_INACTIVE' };
  const school = await schoolMethods(db, schoolId);

  // The phone to bind to PHONE_OTP: an explicit override from the admin, else
  // the record's registered mobile.
  let phone = null;
  if (methods.includes('PHONE_OTP')) {
    phone = data.phone != null && data.phone !== '' ? normalizePhone(data.phone) : rec.phone;
    if (data.phone != null && data.phone !== '' && !phone) return { error: 'INVALID_PHONE' };
  }
  const problem = validateGrant({ enabled: data.enabled, methods, school, email: rec.email, phone });
  if (problem) return { error: problem };

  if (phone) {
    const clash = await db.collection('users').where('login.phone', '==', phone).limit(5).get();
    if (clash.docs.some((d) => d.id !== rec.uid)) return { error: 'PHONE_IN_USE' };
  }

  let uid = rec.uid;
  let created = false;
  if (!uid) {
    if (!data.enabled) return { error: 'NO_ACCOUNT' };
    const made = await createAccountFor(ctx, { rec, kind, schoolId, branchId, callerUid, caller, data });
    if (made.error) return made;
    uid = made.uid;
    created = true;
  }

  const userRef = db.collection('users').doc(uid);
  const txn = await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const u = snap.data();
    if (!u || u.schoolId !== schoolId || (u.branchId && u.branchId !== branchId)) {
      throw Object.assign(new Error('mismatch'), { code: 'TARGET_MISMATCH' });
    }
    if (uid === callerUid || !mayManageRole(caller, u.role)) {
      throw Object.assign(new Error('forbidden'), { code: 'FORBIDDEN_TARGET' });
    }
    const prev = u.login || null;
    const login = {
      enabled: data.enabled,
      methods,
      effective: data.enabled ? intersect(methods, school) : [],
      phone: phone || null,
      ...(prev && prev.phoneVerifiedAt && prev.phone === phone ? { phoneVerifiedAt: prev.phoneVerifiedAt } : {}),
      updatedAt: now,
      updatedBy: callerUid,
    };
    tx.update(userRef, { login });
    const a = audit(ctx, schoolId, {
      type: data.enabled ? (prev && prev.enabled === false ? 'LOGIN_ENABLED' : 'LOGIN_UPDATED') : 'LOGIN_DISABLED',
      actorUid: callerUid,
      targetUid: uid,
      targetKind: kind,
      targetId: id,
      before: prev ? { enabled: prev.enabled, methods: prev.methods || [] } : { enabled: true, legacy: true },
      after: { enabled: login.enabled, methods },
      accountCreated: created,
    });
    tx.set(a.ref, a.rec);
    return { before: prev, user: login };
  }).catch((e) => {
    if (TARGET_ERRORS[e.code]) return { fail: TARGET_ERRORS[e.code] };
    throw e;
  });
  if (txn.fail) return { error: txn.fail };
  const { before, user } = txn;

  // Prompt revocation of existing sessions. Rules already refuse the old
  // tokens' Firestore/Storage access; this also stops silent ID-token
  // refresh. Revoking when only widening access is unnecessary.
  const prevEff = before ? before.effective || [] : intersect(LEGACY_METHODS, school);
  const narrowed = !data.enabled || prevEff.some((m) => !user.effective.includes(m));
  let revoked = false;
  if (narrowed || data.revokeSessions === true) {
    await auth.revokeRefreshTokens(uid);
    revoked = true;
  }
  // A family's class/section-scoped screens (homework, leave, results,
  // timetable) are authorised by the `parentAccess` index, which is only built
  // when a link is portal-enabled. Granting access therefore (re)builds it, so
  // a parent who already had an account is not left with screens that fail.
  let portalLinked = false;
  if (kind === 'PARENT' && data.enabled && !created && data.enablePortal !== false && ctx.enablePortalLinks) {
    await ctx.enablePortalLinks({ db, schoolId, branchId, by: callerUid, now }, id);
    portalLinked = true;
  }
  return { result: { uid, created, enabled: user.enabled, methods, effective: user.effective, revoked, portalLinked } };
}

const TARGET_ERRORS = { TARGET_MISMATCH: 'PERMISSION_DENIED', FORBIDDEN_TARGET: 'PERMISSION_DENIED' };

async function createAccountFor(ctx, { rec, kind, schoolId, branchId, callerUid, caller, data }) {
  const { db, auth, now } = ctx;
  if (kind === 'STAFF' && rec.data.userId) return { error: 'ALREADY_LINKED' };
  const role = kind === 'PARENT' ? 'PARENT' : rec.data.isTeacher ? 'TEACHER' : 'FINANCE';
  if (!mayManageRole(caller, role)) return { error: 'PERMISSION_DENIED' };
  const a = await ctx.ensureAuthUser(auth, db, {
    email: rec.email,
    name: rec.name,
    phone: rec.phone,
    schoolId,
    branchId,
    kind,
    recordId: rec.ref.id,
    allowedRoles:
      kind === 'PARENT'
        ? ['PARENT']
        : caller.role === 'SCHOOL_ADMIN'
          ? ['TEACHER', 'FINANCE', 'BRANCH_ADMIN']
          : ['TEACHER', 'FINANCE'],
  });
  if (a.problem) return { error: a.problem };
  const batch = db.batch();
  const userRef = db.collection('users').doc(a.uid);
  if (a.existingProfile) {
    // An existing /users profile for this person: map it, keep role/status and
    // any existing grant (setLoginAccess then writes the requested one).
    batch.update(userRef, {
      ...(kind === 'PARENT' ? { linkedParentId: rec.ref.id } : {}),
      updatedAt: now,
      updatedBy: callerUid,
    });
  } else {
    batch.set(userRef, {
      schoolId,
      branchId,
      name: rec.name,
      email: rec.email,
      phone: rec.phone,
      photoUrl: null,
      role,
      status: 'ACTIVE',
      linkedParentId: kind === 'PARENT' ? rec.ref.id : null,
      // Created locked: setLoginAccess immediately writes the real grant.
      login: { enabled: false, methods: [], effective: [], phone: null, updatedAt: now, updatedBy: callerUid },
      createdAt: now,
      updatedAt: now,
      createdBy: callerUid,
      updatedBy: callerUid,
    });
  }
  batch.update(rec.ref, { [kind === 'STAFF' ? 'userId' : 'linkedUserId']: a.uid, updatedAt: now, updatedBy: callerUid });
  await batch.commit();
  // A parent's portal shows nothing until their children's links allow it.
  if (kind === 'PARENT' && data.enablePortal !== false && ctx.enablePortalLinks) {
    await ctx.enablePortalLinks({ db, schoolId, branchId, by: callerUid, now }, rec.ref.id);
  }
  return { uid: a.uid };
}

// ---- school-level settings ----------------------------------------------

function parseSchoolInput(data) {
  const out = [];
  for (const [k, m] of Object.entries(SCHOOL_KEYS)) {
    if (typeof data[k] !== 'boolean') return null;
    if (data[k]) out.push(m);
  }
  return sortMethods(out);
}

// At least one ACTIVE school admin (incl. the caller) must keep a usable
// method, otherwise nobody could sign in to repair the setting.
async function lockoutRisk(db, schoolId, callerUid, next) {
  const admins = await db
    .collection('users')
    .where('schoolId', '==', schoolId)
    .where('role', '==', 'SCHOOL_ADMIN')
    .get();
  const usable = (u) => {
    if (u.status !== 'ACTIVE') return false;
    const l = u.login;
    if (l == null) return intersect(LEGACY_METHODS, next).length > 0;
    return l.enabled === true && intersect(l.methods || [], next).length > 0;
  };
  const rows = admins.docs.map((d) => ({ uid: d.id, u: d.data() }));
  const caller = rows.find((r) => r.uid === callerUid);
  if (!caller || !usable(caller.u)) return 'CALLER_LOCKOUT';
  return rows.some((r) => usable(r.u)) ? null : 'ADMIN_LOCKOUT';
}

/**
 * Recomputes `login.effective` for every user of the school after a school
 * level change. Legacy users (no `login`) are only materialised when the new
 * settings would actually restrict them.
 */
async function recomputeSchool({ db, auth, now }, schoolId, school, by) {
  let last = null;
  const narrowed = [];
  let touched = 0;
  for (;;) {
    let q = db.collection('users').where('schoolId', '==', schoolId).orderBy('__name__').limit(MAX_LOGIN_ADMIN_BATCH);
    if (last) q = q.startAfter(last);
    const page = await q.get();
    if (page.docs.length === 0) break;
    const batch = db.batch();
    let n = 0;
    for (const d of page.docs) {
      const u = d.data();
      last = d;
      if (u.role === 'PLATFORM_ADMIN') continue;
      const l = u.login;
      if (l == null) {
        const eff = intersect(LEGACY_METHODS, school);
        if (eff.length === LEGACY_METHODS.length) continue;
        batch.update(d.ref, {
          login: { enabled: true, methods: [...LEGACY_METHODS], effective: eff, phone: null, legacy: true, updatedAt: now, updatedBy: by },
        });
        n++;
        narrowed.push(d.id);
      } else {
        const eff = l.enabled === true ? intersect(l.methods || [], school) : [];
        if (JSON.stringify(eff) === JSON.stringify(l.effective || [])) continue;
        batch.update(d.ref, { 'login.effective': eff, 'login.updatedAt': now, 'login.updatedBy': by });
        n++;
        if ((l.effective || []).some((m) => !eff.includes(m))) narrowed.push(d.id);
      }
    }
    if (n) await batch.commit();
    touched += n;
    for (const uid of narrowed.splice(0)) await auth.revokeRefreshTokens(uid);
    if (page.docs.length < MAX_LOGIN_ADMIN_BATCH) break;
  }
  return touched;
}

async function getSchoolAuthSettings({ db, configured }, callerUid, token, data) {
  const { schoolId } = data || {};
  if (typeof schoolId !== 'string' || !schoolId) return { error: 'INVALID_ARGUMENT' };
  const caller = await assertAdmin(db, callerUid, schoolId, null, token);
  if (!caller || caller.role !== 'SCHOOL_ADMIN') return { error: 'PERMISSION_DENIED' };
  const m = await schoolMethods(db, schoolId);
  return {
    result: {
      emailPassword: m.includes('PASSWORD'),
      google: m.includes('GOOGLE'),
      phoneOtp: m.includes('PHONE_OTP'),
      // Provider-side readiness. Email/password and Google are enabled in the
      // Firebase console and cannot be introspected from here.
      configured: { emailPassword: true, google: true, phoneOtp: configured.phoneOtp === true },
    },
  };
}

async function updateSchoolAuthSettings(ctx, callerUid, token, data) {
  const { db, now, configured } = ctx;
  const { schoolId } = data || {};
  if (typeof schoolId !== 'string' || !schoolId) return { error: 'INVALID_ARGUMENT' };
  const next = parseSchoolInput(data);
  if (!next) return { error: 'INVALID_ARGUMENT' };
  const caller = await assertAdmin(db, callerUid, schoolId, null, token);
  if (!caller || caller.role !== 'SCHOOL_ADMIN') return { error: 'PERMISSION_DENIED' };
  if (next.length === 0) return { error: 'NO_METHOD' };
  if (next.includes('PHONE_OTP') && configured.phoneOtp !== true) return { error: 'PHONE_OTP_NOT_CONFIGURED' };
  const risk = await lockoutRisk(db, schoolId, callerUid, next);
  if (risk) return { error: risk };
  const prev = await schoolMethods(db, schoolId);
  const a = audit(ctx, schoolId, {
    type: 'SCHOOL_AUTH_SETTINGS_CHANGED',
    actorUid: callerUid,
    before: { methods: prev },
    after: { methods: next },
  });
  const batch = db.batch();
  batch.set(methodsDoc(db, schoolId), { schoolId, methods: next, updatedAt: now, updatedBy: callerUid });
  batch.set(a.ref, a.rec);
  await batch.commit();
  const updated = await recomputeSchool(ctx, schoolId, next, callerUid);
  return { result: { methods: next, usersUpdated: updated } };
}

module.exports = {
  METHODS,
  LEGACY_METHODS,
  DEFAULT_SCHOOL_METHODS,
  TARGET_ERRORS,
  normalizePhone,
  normalizeEmail,
  signInMethod,
  loginAllowed,
  schoolMethods,
  assertAdmin,
  intersect,
  getLoginAccess,
  setLoginAccess,
  getSchoolAuthSettings,
  updateSchoolAuthSettings,
  recomputeSchool,
  audit,
  newId: () => crypto.randomBytes(16).toString('hex'),
};

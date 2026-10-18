'use strict';

const crypto = require('node:crypto');
const { schoolMethods, intersect, LEGACY_METHODS, loginAllowed } = require('./access');

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const STAFF_ROLES = ['TEACHER', 'FINANCE', 'BRANCH_ADMIN'];
const MAX_BATCH = 50;

// How the first password is set when a login is created. RESET_LINK and
// ACTIVATION_EMAIL set no password the admin can know (the person sets their
// own through the emailed link); the other three set one on the server.
// Nothing here ever stores or logs a password.
const PASSWORD_OPTIONS = ['NAME_MOBILE', 'RANDOM_TEMP', 'ACTIVATION_EMAIL', 'RESET_LINK', 'ADMIN_DEFINED'];
const MIN_PASSWORD = 8;
const MAX_PASSWORD = 64;
const SERVER_SET = ['NAME_MOBILE', 'RANDOM_TEMP', 'ADMIN_DEFINED'];

const passwordPolicyOk = (p) =>
  typeof p === 'string' && p.length >= MIN_PASSWORD && p.length <= MAX_PASSWORD && /[A-Za-z]/.test(p) && /\d/.test(p);

// First four letters of the name (upper case) + last five digits of the mobile.
// Missing letters/digits is a refusal, never a weaker password.
function nameMobilePassword(name, phone) {
  const letters = String(name || '')
    .normalize('NFKD')
    .replace(/[^A-Za-z]/g, '')
    .toUpperCase();
  const digits = String(phone || '').replace(/\D/g, '');
  if (letters.length < 4 || digits.length < 5) return null;
  return letters.slice(0, 4) + digits.slice(-5);
}

// Cryptographically random, always satisfying the policy (letters + digits).
function randomTempPassword() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  const pick = (set) => set[crypto.randomInt(set.length)];
  const chars = [pick('ABCDEFGHJKLMNPQRSTUVWXYZ'), pick('abcdefghijkmnopqrstuvwxyz'), pick('23456789')];
  while (chars.length < 12) chars.push(pick(alphabet));
  for (let i = chars.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

// { password } to set on the new account, { password: null } when the person
// sets their own, or { problem } when this row cannot get the chosen option.
function initialPassword(setup, name, phone) {
  if (!setup || !SERVER_SET.includes(setup.option)) return { password: null };
  if (setup.option === 'RANDOM_TEMP') return { password: randomTempPassword(), reveal: true };
  if (setup.option === 'ADMIN_DEFINED') return { password: setup.password };
  const pw = nameMobilePassword(name, phone);
  return pw ? { password: pw } : { problem: 'PASSWORD_INPUT_MISSING' };
}

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);

// Who may provision: an ACTIVE school admin of the school, or branch admin of
// the branch. Mirrors canManageStaff in firestore.rules.
async function assertAdmin(db, uid, schoolId, branchId, token) {
  const snap = await db.collection('users').doc(uid).get();
  const u = snap.data();
  // Same gate as the rules: a disabled login or method cannot administer.
  if (!u || u.schoolId !== schoolId || !loginAllowed(u, token)) return null;
  if (u.role === 'SCHOOL_ADMIN') return u;
  if (branchId) {
    // A branch admin of this branch: by home role, or by a per-branch role
    // (users.branchRoles). The returned caller carries the role held HERE.
    if (u.role === 'BRANCH_ADMIN' && u.branchId === branchId) return u;
    if (u.branchId !== branchId && (u.branchRoles || {})[branchId] === 'BRANCH_ADMIN') return { ...u, role: 'BRANCH_ADMIN' };
  }
  return null;
}

// Finds or creates the Authentication account for [email]. Returns
// { uid, created } or { problem }. [email] may be null for a phone-only login
// (the account is then reachable only through the verified phone OTP flow).
//
// When the email already has an Auth account AND a /users profile, the profile
// is *mapped* to the record (`existingProfile: true`) only if it belongs to the
// same school/branch, has a role this record may hold (`allowedRoles`), and is
// not claimed by another person. Otherwise it is EMAIL_IN_USE: re-using it
// would silently merge two people (or two schools).
async function ensureAuthUser(auth, db, { email, name, schoolId, branchId, kind, recordId, allowedRoles, allowCrossBranch, password }) {
  if (email) {
    try {
      const existing = await auth.getUserByEmail(email);
      const profile = await db.collection('users').doc(existing.uid).get();
      if (profile.exists) {
        const u = profile.data();
        const sameSchool = !!schoolId && u.schoolId === schoolId;
        const sameBranch = !u.branchId || !branchId || u.branchId === branchId;
        // A staff member who already works in another branch of the SAME school
        // is not a clash: the record in this branch gets a per-branch role
        // (users.branchRoles) instead of a second account. School admins and
        // non-staff profiles are never merged this way.
        const crossBranch = allowCrossBranch === true && kind === 'STAFF' && sameSchool && !sameBranch && STAFF_ROLES.includes(u.role);
        const roleOk = Array.isArray(allowedRoles) && allowedRoles.includes(u.role);
        if (!sameSchool || (!sameBranch && !crossBranch) || !roleOk) return { problem: 'EMAIL_IN_USE' };
        if (kind === 'PARENT') {
          if (u.linkedParentId && u.linkedParentId !== recordId) return { problem: 'EMAIL_IN_USE' };
          const other = await db
            .collection('schools').doc(schoolId).collection('branches').doc(u.branchId || branchId)
            .collection('parents').where('linkedUserId', '==', existing.uid).limit(2).get();
          if (other.docs.some((d) => d.id !== recordId)) return { problem: 'EMAIL_IN_USE' };
        } else if (kind === 'STAFF') {
          // The record being linked is in [branchId]; another record of the same
          // person there (or, for a same-branch map, in their home branch)
          // would make two people share one login.
          const other = await db
            .collection('schools').doc(schoolId).collection('branches').doc(crossBranch ? branchId : (u.branchId || branchId))
            .collection('staff').where('userId', '==', existing.uid).limit(2).get();
          if (other.docs.some((d) => d.id !== recordId)) return { problem: 'EMAIL_IN_USE' };
        } else {
          return { problem: 'EMAIL_IN_USE' };
        }
        return { uid: existing.uid, created: false, existingProfile: true, crossBranch, profile: u };
      }
      // An Auth account with this email but no profile was created outside
      // the app (e.g. someone pre-registered the address). Whoever set its
      // password is not known to be the mailbox owner, so the password is
      // replaced and all sessions revoked before we adopt it. The real owner
      // then sets their own via password reset or signs in with Google.
      await auth.updateUser(existing.uid, { password: password || crypto.randomBytes(24).toString('base64url') });
      await auth.revokeRefreshTokens(existing.uid);
      return { uid: existing.uid, created: false, ...(password ? { passwordApplied: true } : {}) };
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
    }
  }
  const created = await auth.createUser({
    ...(email ? { email, password: password || crypto.randomBytes(24).toString('base64url') } : {}),
    displayName: name,
    emailVerified: false,
  });
  return { uid: created.uid, created: true, ...(password ? { passwordApplied: true } : {}) };
}

function profileDoc({ schoolId, branchId, name, email, phone, role, linkedParentId, login, by, now }) {
  return {
    schoolId,
    branchId,
    name,
    email,
    phone: phone || null,
    photoUrl: null,
    role,
    status: 'ACTIVE',
    linkedParentId: linkedParentId || null,
    login,
    createdAt: now,
    updatedAt: now,
    createdBy: by,
    updatedBy: by,
  };
}

// Bulk-provisioned accounts get the same email+Google access they always had,
// limited to what the school enables.
async function defaultLogin(ctx, mustChangePassword) {
  // Read once per request (set in provisionLogins), not once per person.
  const school = ctx.school || (await schoolMethods(ctx.db, ctx.schoolId));
  const eff = intersect(LEGACY_METHODS, school);
  return {
    enabled: eff.length > 0,
    methods: [...LEGACY_METHODS],
    effective: eff,
    phone: null,
    // Set only when the first password was chosen by the admin or derived
    // from the record; the app sends the person to change it at first sign-in.
    ...(mustChangePassword ? { mustChangePassword: true } : {}),
    updatedAt: ctx.now,
    updatedBy: ctx.by,
  };
}

// Moves a linked person's login to a new email: the NEW address becomes the
// active sign-in, the OLD one stops working (same account, so no second
// login and no lost history), every session is revoked, and the previous
// address is kept on the profile for audit. Never touches a different
// person's account.
async function changeLinkedEmail(ctx, { recordRef, uid, newEmail, allowedRoles, id, name }) {
  const { db, auth, by, now } = ctx;
  const profileSnap = await db.collection('users').doc(uid).get();
  const profile = profileSnap.exists ? profileSnap.data() : null;
  if (!profile || profile.schoolId !== ctx.schoolId || !allowedRoles.includes(profile.role)) {
    return { id, name, email: newEmail, outcome: 'EMAIL_IN_USE' };
  }
  const oldEmail = (profile.email || '').toLowerCase();
  if (oldEmail === newEmail) return { id, name, email: newEmail, outcome: 'ALREADY_LINKED' };
  try {
    const other = await auth.getUserByEmail(newEmail);
    if (other.uid !== uid) return { id, name, email: newEmail, outcome: 'EMAIL_IN_USE' };
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
  await auth.updateUser(uid, { email: newEmail, emailVerified: false });
  await auth.revokeRefreshTokens(uid);
  const history = [...(profile.previousEmails || []), { email: oldEmail, replacedAt: new Date().toISOString(), by }].slice(-10);
  const batch = db.batch();
  batch.update(db.collection('users').doc(uid), { email: newEmail, previousEmails: history, updatedAt: now, updatedBy: by });
  batch.update(recordRef, { email: newEmail, updatedAt: now, updatedBy: by });
  await batch.commit();
  return { id, name, email: newEmail, outcome: 'EMAIL_UPDATED', uid, newAccount: false, previousEmail: oldEmail };
}

async function provisionStaff(ctx, id, opts) {
  const { db, auth, schoolId, branchId, by, now } = ctx;
  const ref = branchRef(db, schoolId, branchId).collection('staff').doc(id);
  const snap = await ref.get();
  if (!snap.exists) return { id, outcome: 'NOT_FOUND' };
  const s = snap.data();
  const name = [s.firstName, s.middleName, s.lastName].filter(Boolean).join(' ');
  if (s.status !== 'ACTIVE') return { id, name, outcome: s.userId ? 'ALREADY_LINKED' : 'INACTIVE' };
  const typed = (opts.emails[id] || '').trim().toLowerCase();
  if (s.userId) {
    if (!typed || typed === (s.email || '').toLowerCase()) return { id, name, outcome: 'ALREADY_LINKED' };
    if (!EMAIL.test(typed)) return { id, name, email: typed, outcome: 'INVALID_EMAIL' };
    return changeLinkedEmail(ctx, { recordRef: ref, uid: s.userId, newEmail: typed, allowedRoles: opts.mappableRoles, id, name });
  }
  const email = (typed || s.email || '').trim().toLowerCase();
  if (!email) return { id, name, outcome: 'NO_EMAIL' };
  if (!EMAIL.test(email)) return { id, name, email, outcome: 'INVALID_EMAIL' };
  const pw = opts.passwordApplies ? initialPassword(opts.passwordSetup, name, s.phone) : { password: null };
  if (pw.problem) return { id, name, email, outcome: pw.problem };
  const role = s.isTeacher ? 'TEACHER' : opts.role;
  const a = await ensureAuthUser(auth, db, {
    email,
    name,
    schoolId,
    branchId,
    kind: 'STAFF',
    recordId: id,
    allowedRoles: opts.mappableRoles,
    // Only a school admin may attach a person from another branch.
    allowCrossBranch: opts.allowCrossBranch,
    password: pw.password,
  });
  if (a.problem) return { id, name, email, outcome: a.problem };
  const mustChange = a.passwordApplied === true;
  const batch = db.batch();
  const userRef = db.collection('users').doc(a.uid);
  if (a.existingProfile) {
    // Keep the profile's role/status; only fill the gaps and map the record.
    const patch = { updatedAt: now, updatedBy: by };
    if (a.crossBranch) {
      // Same person, another branch: add the per-branch role, never touch the
      // home branch/role. (Cloud Functions are the only writer of branchRoles.)
      patch.branchRoles = { ...(a.profile.branchRoles || {}), [branchId]: role };
    }
    if (!a.profile.login) patch.login = await defaultLogin(ctx);
    batch.update(userRef, patch);
  } else {
    batch.set(
      userRef,
      profileDoc({ schoolId, branchId, name, email, phone: s.phone, role, login: await defaultLogin(ctx, mustChange), by, now }),
    );
  }
  batch.update(ref, { userId: a.uid, ...(s.email === email ? {} : { email }), updatedAt: now, updatedBy: by });
  await batch.commit();
  return {
    id,
    name,
    email,
    outcome: 'CREATED',
    uid: a.uid,
    role: a.existingProfile ? (a.crossBranch ? role : a.profile.role) : role,
    crossBranch: a.crossBranch === true,
    newAccount: a.created,
    mapped: a.existingProfile === true,
    passwordSet: mustChange,
    ...(mustChange && pw.reveal ? { tempPassword: pw.password } : {}),
  };
}

// Recomputes parentAccess/{parentId} exactly as ParentAccessSync does in the
// app (ACTIVE, placed children behind an ACTIVE portal-enabled link).
async function refreshParentAccess(ctx, parentId) {
  const { db, schoolId, branchId, by, now } = ctx;
  const links = await db
    .collectionGroup('parentLinks')
    .where('schoolId', '==', schoolId)
    .where('branchId', '==', branchId)
    .where('parentId', '==', parentId)
    .get();
  const classes = new Set();
  const sections = new Set();
  for (const l of links.docs) {
    const d = l.data();
    if (d.canAccessPortal !== true || d.status !== 'ACTIVE') continue;
    const st = await branchRef(db, schoolId, branchId).collection('students').doc(d.studentId).get();
    const sd = st.data();
    if (!sd || sd.status !== 'ACTIVE' || !sd.currentClassId) continue;
    classes.add(sd.currentClassId);
    if (sd.currentSectionId) sections.add(`${sd.currentClassId}__${sd.currentSectionId}`);
  }
  await branchRef(db, schoolId, branchId)
    .collection('parentAccess')
    .doc(parentId)
    .set({
      schoolId,
      branchId,
      parentId,
      classKeys: [...classes].sort(),
      sectionKeys: [...sections].sort(),
      updatedAt: now,
      updatedBy: by,
    });
}

async function enablePortalLinks(ctx, parentId) {
  const { db, schoolId, branchId, by, now } = ctx;
  const links = await db
    .collectionGroup('parentLinks')
    .where('schoolId', '==', schoolId)
    .where('branchId', '==', branchId)
    .where('parentId', '==', parentId)
    .get();
  for (const l of links.docs) {
    if (l.data().status === 'ACTIVE' && l.data().canAccessPortal !== true) {
      await l.ref.update({ canAccessPortal: true, updatedAt: now, updatedBy: by });
    }
  }
  await refreshParentAccess(ctx, parentId);
}

async function provisionParent(ctx, id, opts) {
  const { db, auth, schoolId, branchId, by, now } = ctx;
  const ref = branchRef(db, schoolId, branchId).collection('parents').doc(id);
  const snap = await ref.get();
  if (!snap.exists) return { id, outcome: 'NOT_FOUND' };
  const p = snap.data();
  const name = [p.firstName, p.middleName, p.lastName].filter(Boolean).join(' ');
  if (p.status !== 'ACTIVE') return { id, name, outcome: p.linkedUserId ? 'ALREADY_LINKED' : 'INACTIVE' };
  const typed = (opts.emails[id] || '').trim().toLowerCase();
  if (p.linkedUserId) {
    if (!typed || typed === (p.email || '').toLowerCase()) return { id, name, outcome: 'ALREADY_LINKED' };
    if (!EMAIL.test(typed)) return { id, name, email: typed, outcome: 'INVALID_EMAIL' };
    return changeLinkedEmail(ctx, { recordRef: ref, uid: p.linkedUserId, newEmail: typed, allowedRoles: ['PARENT'], id, name });
  }
  const email = (typed || p.email || '').trim().toLowerCase();
  if (!email) return { id, name, outcome: 'NO_EMAIL' };
  if (!EMAIL.test(email)) return { id, name, email, outcome: 'INVALID_EMAIL' };
  const pw = opts.passwordApplies ? initialPassword(opts.passwordSetup, name, p.phone) : { password: null };
  if (pw.problem) return { id, name, email, outcome: pw.problem };
  const a = await ensureAuthUser(auth, db, {
    email,
    name,
    schoolId,
    branchId,
    kind: 'PARENT',
    recordId: id,
    allowedRoles: ['PARENT'],
    password: pw.password,
  });
  if (a.problem) return { id, name, email, outcome: a.problem };
  const mustChange = a.passwordApplied === true;
  const batch = db.batch();
  const userRef = db.collection('users').doc(a.uid);
  if (a.existingProfile) {
    const patch = { linkedParentId: id, updatedAt: now, updatedBy: by };
    if (!a.profile.login) patch.login = await defaultLogin(ctx);
    batch.update(userRef, patch);
  } else {
    batch.set(
      userRef,
      profileDoc({
        schoolId,
        branchId,
        name,
        email,
        phone: p.phone,
        role: 'PARENT',
        linkedParentId: id,
        login: await defaultLogin(ctx, mustChange),
        by,
        now,
      }),
    );
  }
  batch.update(ref, { linkedUserId: a.uid, ...(p.email === email ? {} : { email }), updatedAt: now, updatedBy: by });
  await batch.commit();
  if (opts.enablePortal) await enablePortalLinks(ctx, id);
  return {
    id,
    name,
    email,
    outcome: 'CREATED',
    uid: a.uid,
    role: 'PARENT',
    newAccount: a.created,
    mapped: a.existingProfile === true,
    passwordSet: mustChange,
    ...(mustChange && pw.reveal ? { tempPassword: pw.password } : {}),
  };
}

// Core of the callable, separated from the Firebase wrapper so it can be
// tested with fakes. Never throws for one bad record: each gets an outcome.
async function provisionLogins({ db, auth, now }, callerUid, data, token) {
  const { schoolId, branchId, kind, ids } = data || {};
  if (typeof schoolId !== 'string' || typeof branchId !== 'string') return { error: 'INVALID_ARGUMENT' };
  if (kind !== 'STAFF' && kind !== 'PARENT') return { error: 'INVALID_ARGUMENT' };
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > MAX_BATCH || ids.some((i) => typeof i !== 'string')) {
    return { error: 'INVALID_ARGUMENT' };
  }
  const caller = await assertAdmin(db, callerUid, schoolId, branchId, token);
  if (!caller) return { error: 'PERMISSION_DENIED' };

  let role = 'FINANCE';
  if (data.role !== undefined) {
    if (!STAFF_ROLES.includes(data.role)) return { error: 'INVALID_ARGUMENT' };
    // Only a school admin may mint a branch admin.
    if (data.role === 'BRANCH_ADMIN' && caller.role !== 'SCHOOL_ADMIN') return { error: 'PERMISSION_DENIED' };
    role = data.role;
  }
  // Emails typed in by the admin for records that have none.
  const emails = {};
  if (data.emails && typeof data.emails === 'object') {
    for (const [k, v] of Object.entries(data.emails)) if (typeof v === 'string') emails[k] = v;
  }
  // Password setup: validated up front so a bad request changes nothing.
  let passwordSetup = { option: 'RESET_LINK' };
  if (data.passwordSetup !== undefined) {
    const ps = data.passwordSetup;
    if (!ps || typeof ps !== 'object' || !PASSWORD_OPTIONS.includes(ps.option)) return { error: 'INVALID_ARGUMENT' };
    if (ps.option === 'ADMIN_DEFINED' && !passwordPolicyOk(ps.password)) return { error: 'INVALID_ARGUMENT' };
    passwordSetup = { option: ps.option, ...(ps.option === 'ADMIN_DEFINED' ? { password: ps.password } : {}) };
  }
  // A password only means something where password sign-in is allowed;
  // OTP-only / Google-only schools get accounts without one.
  const school = await schoolMethods(db, schoolId);
  const passwordApplies = intersect(LEGACY_METHODS, school).includes('PASSWORD');
  const mappableRoles = caller.role === 'SCHOOL_ADMIN' ? ['TEACHER', 'FINANCE', 'BRANCH_ADMIN'] : ['TEACHER', 'FINANCE'];
  const ctx = { db, auth, schoolId, branchId, by: callerUid, now, school };
  const results = [];
  for (const id of [...new Set(ids)]) {
    try {
      results.push(
        kind === 'STAFF'
          ? await provisionStaff(ctx, id, { role, emails, mappableRoles, allowCrossBranch: caller.role === 'SCHOOL_ADMIN', passwordSetup, passwordApplies })
          : await provisionParent(ctx, id, { enablePortal: data.enablePortal === true, emails, passwordSetup, passwordApplies }),
      );
    } catch (e) {
      results.push({ id, outcome: 'FAILED', message: String(e.code || e.message || e) });
    }
  }
  return { results };
}

// The signed-in person replaces the initial password an admin set or derived.
// Allowed only while the profile is flagged, so it cannot be used as a
// general "set password" path. The password is never stored or logged.
async function changeInitialPassword({ db, auth, now }, uid, data) {
  const pw = data && data.newPassword;
  if (!passwordPolicyOk(pw)) return { error: 'INVALID_ARGUMENT' };
  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
  const u = snap.exists ? snap.data() : null;
  if (!u || !u.login || u.login.mustChangePassword !== true) return { error: 'NOT_REQUIRED' };
  await auth.updateUser(uid, { password: pw });
  await auth.revokeRefreshTokens(uid);
  const { mustChangePassword, ...login } = u.login;
  await ref.update({ login: { ...login, updatedAt: now }, updatedAt: now });
  return { ok: true };
}

// Admin sets a new password for people who already have a login, using the
// same server-set options as when logins are created (the two link options
// are emails the app sends, so they never reach here). Each person must change
// it at next sign-in and all their sessions are revoked. Nothing about the
// password is stored or logged; a random one is returned once to the admin.
//
// `id` resets one person ({ ok, tempPassword? }); `ids` (up to MAX_BATCH)
// resets several and reports every person's outcome ({ results }). One bad
// record never stops the others.
async function resetLoginPassword(ctx0, callerUid, data, token) {
  const { db } = ctx0;
  const { schoolId, branchId, kind, passwordSetup } = data || {};
  const ok = (v) => typeof v === 'string' && v.length > 0 && v.length <= 128;
  const bulk = Array.isArray(data && data.ids);
  const ids = bulk ? [...new Set(data.ids)] : [data && data.id];
  if (!ok(schoolId) || !ok(branchId) || (kind !== 'STAFF' && kind !== 'PARENT')) return { error: 'INVALID_ARGUMENT' };
  if (ids.length === 0 || ids.length > MAX_BATCH || !ids.every(ok)) return { error: 'INVALID_ARGUMENT' };
  if (!passwordSetup || typeof passwordSetup !== 'object' || !SERVER_SET.includes(passwordSetup.option)) return { error: 'INVALID_ARGUMENT' };
  if (passwordSetup.option === 'ADMIN_DEFINED' && !passwordPolicyOk(passwordSetup.password)) return { error: 'INVALID_ARGUMENT' };
  const caller = await assertAdmin(db, callerUid, schoolId, branchId, token);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const school = await schoolMethods(db, schoolId);
  if (!intersect(LEGACY_METHODS, school).includes('PASSWORD')) return { error: 'PASSWORD_NOT_ALLOWED' };

  const ctx = { ...ctx0, callerUid, caller, schoolId, branchId, kind, passwordSetup };
  const results = [];
  for (const id of ids) {
    try {
      results.push(await resetOne(ctx, id));
    } catch (e) {
      results.push({ id, outcome: 'FAILED', message: String(e.code || e.message || e) });
    }
  }
  if (bulk) return { result: { results } };
  const r = results[0];
  if (r.outcome === 'FAILED') throw new Error(r.message);
  if (r.outcome !== 'RESET') return { error: r.outcome };
  return { result: { ok: true, ...(r.tempPassword ? { tempPassword: r.tempPassword } : {}) } };
}

// One person. outcome is 'RESET' or the reason nothing changed (the same
// codes a single reset returns as its error).
async function resetOne(ctx, id) {
  const { db, auth, now, callerUid, caller, schoolId, branchId, kind, passwordSetup } = ctx;
  const snap = await branchRef(db, schoolId, branchId).collection(kind === 'STAFF' ? 'staff' : 'parents').doc(id).get();
  if (!snap.exists) return { id, outcome: 'NOT_FOUND' };
  const rec = snap.data();
  const name = [rec.firstName, rec.middleName, rec.lastName].filter(Boolean).join(' ');
  const uid = kind === 'STAFF' ? rec.userId : rec.linkedUserId;
  if (!uid) return { id, name, outcome: 'NO_ACCOUNT' };
  const userRef = db.collection('users').doc(uid);
  const uSnap = await userRef.get();
  const u = uSnap.exists ? uSnap.data() : null;
  const roles = caller.role === 'SCHOOL_ADMIN' ? ['TEACHER', 'FINANCE', 'BRANCH_ADMIN', 'PARENT'] : ['TEACHER', 'FINANCE', 'PARENT'];
  const worksHere = u && u.branchId !== branchId && (u.branchRoles || {})[branchId];
  if (!u || u.schoolId !== schoolId || (u.branchId && u.branchId !== branchId && !worksHere) || uid === callerUid || !roles.includes(u.role)) {
    return { id, name, outcome: 'PERMISSION_DENIED' };
  }
  const pw = initialPassword(passwordSetup, name, rec.phone);
  if (pw.problem) return { id, name, outcome: pw.problem };
  await auth.updateUser(uid, { password: pw.password });
  await auth.revokeRefreshTokens(uid);
  await userRef.update({ login: { ...(u.login || {}), mustChangePassword: true, updatedAt: now, updatedBy: callerUid }, updatedAt: now, updatedBy: callerUid });
  await db.collection('schools').doc(schoolId).collection('authAudit').doc().set({
    schoolId,
    type: 'PASSWORD_RESET',
    actorUid: callerUid,
    targetUid: uid,
    targetKind: kind,
    targetId: id,
    option: passwordSetup.option,
    createdAt: now,
  });
  return { id, name, outcome: 'RESET', ...(pw.reveal ? { tempPassword: pw.password } : {}) };
}

module.exports = { resetLoginPassword, changeInitialPassword, provisionLogins, nameMobilePassword, randomTempPassword, passwordPolicyOk, PASSWORD_OPTIONS, ensureAuthUser, enablePortalLinks, refreshParentAccess, MAX_BATCH };

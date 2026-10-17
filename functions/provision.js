'use strict';

const crypto = require('node:crypto');
const { schoolMethods, intersect, LEGACY_METHODS, loginAllowed } = require('./access');

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const STAFF_ROLES = ['TEACHER', 'FINANCE', 'BRANCH_ADMIN'];
const MAX_BATCH = 50;

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
async function ensureAuthUser(auth, db, { email, name, schoolId, branchId, kind, recordId, allowedRoles, allowCrossBranch }) {
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
      await auth.updateUser(existing.uid, { password: crypto.randomBytes(24).toString('base64url') });
      await auth.revokeRefreshTokens(existing.uid);
      return { uid: existing.uid, created: false };
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
    }
  }
  const created = await auth.createUser({
    ...(email ? { email, password: crypto.randomBytes(24).toString('base64url') } : {}),
    displayName: name,
    emailVerified: false,
  });
  return { uid: created.uid, created: true };
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
async function defaultLogin(ctx) {
  const school = await schoolMethods(ctx.db, ctx.schoolId);
  const eff = intersect(LEGACY_METHODS, school);
  return { enabled: eff.length > 0, methods: [...LEGACY_METHODS], effective: eff, phone: null, updatedAt: ctx.now, updatedBy: ctx.by };
}

async function provisionStaff(ctx, id, opts) {
  const { db, auth, schoolId, branchId, by, now } = ctx;
  const ref = branchRef(db, schoolId, branchId).collection('staff').doc(id);
  const snap = await ref.get();
  if (!snap.exists) return { id, outcome: 'NOT_FOUND' };
  const s = snap.data();
  const name = [s.firstName, s.middleName, s.lastName].filter(Boolean).join(' ');
  if (s.userId) return { id, name, outcome: 'ALREADY_LINKED' };
  if (s.status !== 'ACTIVE') return { id, name, outcome: 'INACTIVE' };
  const email = (s.email || opts.emails[id] || '').trim().toLowerCase();
  if (!email) return { id, name, outcome: 'NO_EMAIL' };
  if (!EMAIL.test(email)) return { id, name, email, outcome: 'INVALID_EMAIL' };
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
  });
  if (a.problem) return { id, name, email, outcome: a.problem };
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
      profileDoc({ schoolId, branchId, name, email, phone: s.phone, role, login: await defaultLogin(ctx), by, now }),
    );
  }
  batch.update(ref, { userId: a.uid, ...(s.email ? {} : { email }), updatedAt: now, updatedBy: by });
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
  if (p.linkedUserId) return { id, name, outcome: 'ALREADY_LINKED' };
  if (p.status !== 'ACTIVE') return { id, name, outcome: 'INACTIVE' };
  const email = (p.email || opts.emails[id] || '').trim().toLowerCase();
  if (!email) return { id, name, outcome: 'NO_EMAIL' };
  if (!EMAIL.test(email)) return { id, name, email, outcome: 'INVALID_EMAIL' };
  const a = await ensureAuthUser(auth, db, {
    email,
    name,
    schoolId,
    branchId,
    kind: 'PARENT',
    recordId: id,
    allowedRoles: ['PARENT'],
  });
  if (a.problem) return { id, name, email, outcome: a.problem };
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
        login: await defaultLogin(ctx),
        by,
        now,
      }),
    );
  }
  batch.update(ref, { linkedUserId: a.uid, ...(p.email ? {} : { email }), updatedAt: now, updatedBy: by });
  await batch.commit();
  if (opts.enablePortal) await enablePortalLinks(ctx, id);
  return { id, name, email, outcome: 'CREATED', uid: a.uid, role: 'PARENT', newAccount: a.created, mapped: a.existingProfile === true };
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
  const mappableRoles = caller.role === 'SCHOOL_ADMIN' ? ['TEACHER', 'FINANCE', 'BRANCH_ADMIN'] : ['TEACHER', 'FINANCE'];
  const ctx = { db, auth, schoolId, branchId, by: callerUid, now };
  const results = [];
  for (const id of [...new Set(ids)]) {
    try {
      results.push(
        kind === 'STAFF'
          ? await provisionStaff(ctx, id, { role, emails, mappableRoles, allowCrossBranch: caller.role === 'SCHOOL_ADMIN' })
          : await provisionParent(ctx, id, { enablePortal: data.enablePortal === true, emails }),
      );
    } catch (e) {
      results.push({ id, outcome: 'FAILED', message: String(e.code || e.message || e) });
    }
  }
  return { results };
}

module.exports = { provisionLogins, ensureAuthUser, enablePortalLinks, refreshParentAccess, MAX_BATCH };

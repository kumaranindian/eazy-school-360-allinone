'use strict';

const crypto = require('node:crypto');

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const STAFF_ROLES = ['TEACHER', 'FINANCE', 'BRANCH_ADMIN'];
const MAX_BATCH = 50;

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);

// Who may provision: an ACTIVE school admin of the school, or branch admin of
// the branch. Mirrors canManageStaff in firestore.rules.
async function assertAdmin(db, uid, schoolId, branchId) {
  const snap = await db.collection('users').doc(uid).get();
  const u = snap.data();
  if (!u || u.status !== 'ACTIVE' || u.schoolId !== schoolId) return null;
  if (u.role === 'SCHOOL_ADMIN') return u;
  if (u.role === 'BRANCH_ADMIN' && u.branchId === branchId) return u;
  return null;
}

// Finds or creates the Authentication account for [email]. Returns
// { uid, created } or { problem }.
async function ensureAuthUser(auth, db, { email, name, schoolId }) {
  try {
    const existing = await auth.getUserByEmail(email);
    const profile = await db.collection('users').doc(existing.uid).get();
    // An email that already belongs to a profile is never re-used: it would
    // silently merge two people (or two schools).
    if (profile.exists) return { problem: 'EMAIL_IN_USE' };
    return { uid: existing.uid, created: false };
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
  const created = await auth.createUser({
    email,
    displayName: name,
    password: crypto.randomBytes(24).toString('base64url'),
    emailVerified: false,
  });
  return { uid: created.uid, created: true };
}

function profileDoc({ schoolId, branchId, name, email, phone, role, linkedParentId, by, now }) {
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
    createdAt: now,
    updatedAt: now,
    createdBy: by,
    updatedBy: by,
  };
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
  const a = await ensureAuthUser(auth, db, { email, name, schoolId });
  if (a.problem) return { id, name, email, outcome: a.problem };
  const batch = db.batch();
  batch.set(
    db.collection('users').doc(a.uid),
    profileDoc({ schoolId, branchId, name, email, phone: s.phone, role, by, now }),
  );
  batch.update(ref, { userId: a.uid, ...(s.email ? {} : { email }), updatedAt: now, updatedBy: by });
  await batch.commit();
  return { id, name, email, outcome: 'CREATED', uid: a.uid, role, newAccount: a.created };
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
  const a = await ensureAuthUser(auth, db, { email, name, schoolId });
  if (a.problem) return { id, name, email, outcome: a.problem };
  const batch = db.batch();
  batch.set(
    db.collection('users').doc(a.uid),
    profileDoc({
      schoolId,
      branchId,
      name,
      email,
      phone: p.phone,
      role: 'PARENT',
      linkedParentId: id,
      by,
      now,
    }),
  );
  batch.update(ref, { linkedUserId: a.uid, ...(p.email ? {} : { email }), updatedAt: now, updatedBy: by });
  await batch.commit();
  if (opts.enablePortal) await enablePortalLinks(ctx, id);
  return { id, name, email, outcome: 'CREATED', uid: a.uid, role: 'PARENT', newAccount: a.created };
}

// Core of the callable, separated from the Firebase wrapper so it can be
// tested with fakes. Never throws for one bad record: each gets an outcome.
async function provisionLogins({ db, auth, now }, callerUid, data) {
  const { schoolId, branchId, kind, ids } = data || {};
  if (typeof schoolId !== 'string' || typeof branchId !== 'string') return { error: 'INVALID_ARGUMENT' };
  if (kind !== 'STAFF' && kind !== 'PARENT') return { error: 'INVALID_ARGUMENT' };
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > MAX_BATCH || ids.some((i) => typeof i !== 'string')) {
    return { error: 'INVALID_ARGUMENT' };
  }
  const caller = await assertAdmin(db, callerUid, schoolId, branchId);
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
  const ctx = { db, auth, schoolId, branchId, by: callerUid, now };
  const results = [];
  for (const id of [...new Set(ids)]) {
    try {
      results.push(
        kind === 'STAFF'
          ? await provisionStaff(ctx, id, { role, emails })
          : await provisionParent(ctx, id, { enablePortal: data.enablePortal === true, emails }),
      );
    } catch (e) {
      results.push({ id, outcome: 'FAILED', message: String(e.code || e.message || e) });
    }
  }
  return { results };
}

module.exports = { provisionLogins, MAX_BATCH };

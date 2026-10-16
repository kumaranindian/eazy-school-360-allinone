'use strict';

// Per-branch roles for staff who work in more than one branch.
//
//   users/{uid} = { ..., branchId (home), role (home role),
//                   branchRoles: { <otherBranchId>: 'TEACHER'|'FINANCE'|'BRANCH_ADMIN' } }
//
// `branchRoles` is written ONLY here (Admin SDK): firestore.rules and
// storage.rules read it (branchRoleOf) and reject any client write. Granting
// requires a school admin, an ACTIVE staff record of the same person in the
// target branch, and a branch of the same school. Every change is audited in
// schools/{s}/branchAccessAudit.

const { loginAllowed } = require('./access');

const STAFF_ROLES = ['TEACHER', 'FINANCE', 'BRANCH_ADMIN'];

const userRef = (db, uid) => db.collection('users').doc(uid);
const schoolRef = (db, s) => db.collection('schools').doc(s);
const branchRef = (db, s, b) => schoolRef(db, s).collection('branches').doc(b);

async function assertSchoolAdmin(db, uid, schoolId, token) {
  const u = (await userRef(db, uid).get()).data();
  if (!u || u.schoolId !== schoolId || u.role !== 'SCHOOL_ADMIN' || !loginAllowed(u, token)) return null;
  return u;
}

/**
 * Grants, changes or (role = null) revokes [uid]'s role in [branchId].
 * Returns { branchRoles } or { error }.
 */
async function setBranchAccess({ db, now }, callerUid, data, token) {
  const { schoolId, branchId, uid, role } = data || {};
  if ([schoolId, branchId, uid].some((x) => typeof x !== 'string' || !x)) return { error: 'INVALID_ARGUMENT' };
  if (role !== null && !STAFF_ROLES.includes(role)) return { error: 'INVALID_ARGUMENT' };
  if (!(await assertSchoolAdmin(db, callerUid, schoolId, token))) return { error: 'PERMISSION_DENIED' };

  const target = (await userRef(db, uid).get()).data();
  if (!target || target.schoolId !== schoolId) return { error: 'NOT_FOUND' };
  // Only branch-scoped staff hold per-branch roles; admins and parents never.
  if (!STAFF_ROLES.includes(target.role)) return { error: 'ROLE_NOT_ELIGIBLE' };
  if (target.branchId === branchId) return { error: 'HOME_BRANCH' };
  if (!(await branchRef(db, schoolId, branchId).get()).exists) return { error: 'NOT_FOUND' };

  const current = target.branchRoles || {};
  const next = { ...current };
  if (role === null) {
    delete next[branchId];
  } else {
    // The person must exist as ACTIVE staff in that branch (what staff-owned
    // data, e.g. teaching assignments, hangs off) and be linked to this login.
    const staff = await branchRef(db, schoolId, branchId).collection('staff').where('userId', '==', uid).limit(2).get();
    if (!staff.docs.some((d) => d.data().status === 'ACTIVE')) return { error: 'NO_STAFF_RECORD' };
    next[branchId] = role;
  }
  if (JSON.stringify(next) === JSON.stringify(current)) return { branchRoles: next, unchanged: true };

  await userRef(db, uid).update({ branchRoles: next, updatedAt: now, updatedBy: callerUid });
  await schoolRef(db, schoolId).collection('branchAccessAudit').add({
    schoolId,
    uid,
    branchId,
    from: current[branchId] || null,
    to: role,
    by: callerUid,
    at: now,
  });
  return { branchRoles: next };
}

/**
 * Trigger helper: when the staff record that grounds a per-branch role stops
 * being ACTIVE (or loses its login link), the role is removed.
 */
async function revokeIfStaffInactive({ db, now }, { schoolId, branchId, before, after }) {
  const uid = (before && before.userId) || (after && after.userId);
  if (!uid) return { changed: false };
  const stillActive = after && after.userId === uid && after.status === 'ACTIVE';
  if (stillActive) return { changed: false };
  const u = (await userRef(db, uid).get()).data();
  if (!u || u.schoolId !== schoolId || u.branchId === branchId) return { changed: false };
  const current = u.branchRoles || {};
  if (!current[branchId]) return { changed: false };
  const next = { ...current };
  delete next[branchId];
  await userRef(db, uid).update({ branchRoles: next, updatedAt: now, updatedBy: 'system:staff-inactive' });
  await schoolRef(db, schoolId).collection('branchAccessAudit').add({
    schoolId, uid, branchId, from: current[branchId], to: null, by: 'system:staff-inactive', at: now,
  });
  return { changed: true };
}

module.exports = { setBranchAccess, revokeIfStaffInactive, STAFF_ROLES };

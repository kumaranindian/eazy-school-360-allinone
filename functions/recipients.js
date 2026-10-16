'use strict';

const IN_LIMIT = 30; // Firestore `in` query limit

function chunk(list, size) {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
}

const branchRef = (db, schoolId, branchId) =>
  db.collection('schools').doc(schoolId).collection('branches').doc(branchId);

async function activeUsersWhere(db, schoolId, build) {
  const snap = await build(
    db.collection('users').where('schoolId', '==', schoolId).where('status', '==', 'ACTIVE'),
  ).get();
  return snap.docs.map((d) => d.id);
}

// Parents with an ACTIVE, placed child in the branch, optionally narrowed to a
// class or section — from the same `parentAccess` index the security rules use.
async function parentUserIds(db, schoolId, branchId, { classId, sectionId } = {}) {
  let q = branchRef(db, schoolId, branchId).collection('parentAccess');
  if (classId && sectionId) q = q.where('sectionKeys', 'array-contains', `${classId}__${sectionId}`);
  else if (classId) q = q.where('classKeys', 'array-contains', classId);
  const parentIds = (await q.get()).docs.map((d) => d.id);
  const ids = new Set();
  for (const part of chunk(parentIds, IN_LIMIT)) {
    const uids = await activeUsersWhere(db, schoolId, (u) =>
      u.where('role', '==', 'PARENT').where('linkedParentId', 'in', part),
    );
    uids.forEach((u) => ids.add(u));
  }
  return ids;
}

// Logins that hold [role] in [branchId]: those whose home branch it is, and
// staff who work there through a per-branch role (users.branchRoles).
async function usersWithRoleInBranch(db, schoolId, branchId, role) {
  const home = await activeUsersWhere(db, schoolId, (u) =>
    u.where('role', '==', role).where('branchId', '==', branchId),
  );
  const extra = await activeUsersWhere(db, schoolId, (u) => u.where(`branchRoles.${branchId}`, '==', role));
  return new Set([...home, ...extra]);
}

async function staffUserIds(db, schoolId, branchId) {
  const ids = new Set();
  for (const role of ['TEACHER', 'FINANCE']) {
    (await usersWithRoleInBranch(db, schoolId, branchId, role)).forEach((u) => ids.add(u));
  }
  return ids;
}

// Teachers with an active assignment to the class (or section).
async function teacherUserIds(db, schoolId, branchId, { classId, sectionId }) {
  let q = branchRef(db, schoolId, branchId)
    .collection('teacherAssignments')
    .where('status', '==', 'ACTIVE')
    .where('classId', '==', classId);
  if (sectionId) q = q.where('sectionId', '==', sectionId);
  const staffIds = [...new Set((await q.get()).docs.map((d) => d.data().teacherStaffId))].filter(Boolean);
  const userIds = new Set();
  if (staffIds.length === 0) return userIds;
  const staffRefs = staffIds.map((id) => branchRef(db, schoolId, branchId).collection('staff').doc(id));
  const staffDocs = await db.getAll(...staffRefs);
  const candidates = staffDocs.map((s) => s.data()?.userId).filter(Boolean);
  const userDocs = await db.getAll(...candidates.map((id) => db.collection('users').doc(id)));
  for (const u of userDocs) {
    const d = u.data();
    const roleHere = d && (d.branchId === branchId ? d.role : (d.branchRoles || {})[branchId]);
    if (d && roleHere === 'TEACHER' && d.status === 'ACTIVE' && d.schoolId === schoolId) userIds.add(u.id);
  }
  return userIds;
}

async function adminUserIds(db, schoolId, branchId) {
  const ids = new Set();
  (await activeUsersWhere(db, schoolId, (u) => u.where('role', '==', 'SCHOOL_ADMIN'))).forEach((u) => ids.add(u));
  (await usersWithRoleInBranch(db, schoolId, branchId, 'BRANCH_ADMIN')).forEach((u) => ids.add(u));
  return ids;
}

// Who an audience-addressed notice is for. Mirrors AnnouncementVisibility
// (lib/features/announcements/domain/announcement.dart).
async function broadcastRecipients(db, notice) {
  const { schoolId, branchId, audienceKind, classId, sectionId } = notice;
  const ids = await adminUserIds(db, schoolId, branchId);
  const add = (set) => set.forEach((u) => ids.add(u));
  switch (audienceKind) {
    case 'ALL':
      (await activeUsersWhere(db, schoolId, (u) => u)).forEach((u) => ids.add(u));
      break;
    case 'BRANCH':
      add(await staffUserIds(db, schoolId, branchId));
      add(await parentUserIds(db, schoolId, branchId));
      break;
    case 'STAFF':
      add(await staffUserIds(db, schoolId, branchId));
      break;
    case 'PARENTS':
      add(await parentUserIds(db, schoolId, branchId));
      break;
    case 'CLASS':
    case 'SECTION': {
      const scope = { classId, sectionId: audienceKind === 'SECTION' ? sectionId : undefined };
      if (!scope.classId) break;
      add(await parentUserIds(db, schoolId, branchId, scope));
      add(await teacherUserIds(db, schoolId, branchId, scope));
      break;
    }
    default:
      break;
  }
  return ids;
}

// Who a `notifications` document is for: one user, or the leave reviewers.
async function targetedRecipients(db, n) {
  if (n.audience === 'USER' && n.recipientUserId) return new Set([n.recipientUserId]);
  if (n.audience === 'REVIEWERS') return adminUserIds(db, n.schoolId, n.branchId);
  return new Set();
}

module.exports = { broadcastRecipients, targetedRecipients, chunk };

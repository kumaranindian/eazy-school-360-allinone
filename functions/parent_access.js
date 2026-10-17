'use strict';

// parentAccess/{parentId}: the rules-readable summary of the classes and
// sections where a family has an ACTIVE, portal-enabled child (see
// provision.js → refreshParentAccess for how one document is built).
// firestore.rules call get() on it to authorise homework, timetable, results
// and class/section announcements for a parent; a missing document grants
// nothing, which shows up as "permission denied" on exactly those screens.
//
// The app also refreshes it after some staff actions, but any path that does
// not (older data, an import, a console edit, a placement change made by
// another route) used to leave a family locked out until an admin found the
// "Refresh parent access" button. These helpers are driven by triggers on the
// source documents (index.js) so the index follows the data on its own, plus a
// backfill for data that already exists.

const { refreshParentAccess } = require('./provision');

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);

/** Fields of a student document that change what a family may read. */
const placementOf = (s) => (s ? [s.status, s.currentClassId, s.currentSectionId] : null);

function placementChanged(before, after) {
  return JSON.stringify(placementOf(before)) !== JSON.stringify(placementOf(after));
}

/** Link fields that decide whether the link counts towards the index. */
const linkOf = (l) => (l ? [l.parentId, l.status, l.canAccessPortal] : null);

function linkChanged(before, after) {
  return JSON.stringify(linkOf(before)) !== JSON.stringify(linkOf(after));
}

/** Refreshes the families named by [parentIds]; returns how many were written. */
async function refreshParents(ctx, schoolId, branchId, parentIds) {
  let n = 0;
  for (const parentId of new Set(parentIds)) {
    if (typeof parentId !== 'string' || !parentId) continue;
    await refreshParentAccess({ ...ctx, schoolId, branchId }, parentId);
    n++;
  }
  return n;
}

/** Every family linked (in any status) to a student — a switched-off link must leave its index too. */
async function refreshFamiliesOfStudent(ctx, schoolId, branchId, studentId) {
  const links = await branchRef(ctx.db, schoolId, branchId).collection('students').doc(studentId).collection('parentLinks').get();
  return refreshParents(ctx, schoolId, branchId, links.docs.map((l) => l.data().parentId || l.id));
}

/** Admin backfill / repair for a whole branch. */
async function refreshBranchParents(ctx, schoolId, branchId) {
  const parents = await branchRef(ctx.db, schoolId, branchId).collection('parents').get();
  const written = await refreshParents(ctx, schoolId, branchId, parents.docs.map((p) => p.id));
  return { parents: parents.docs.length, written };
}

/**
 * Self-heal for a signed-in parent: rebuilds the caller's OWN index in every
 * branch where their parent record has a link. The result is derived purely
 * from the link and student documents, so a parent cannot widen their own
 * access by calling it; it only repairs a missing or stale index (older data,
 * an import, a link made before the triggers existed).
 */
async function refreshOwnFamily(ctx, uid) {
  const user = (await ctx.db.collection('users').doc(uid).get()).data();
  if (!user || user.role !== 'PARENT' || user.status !== 'ACTIVE') return { error: 'PERMISSION_DENIED' };
  const { schoolId, linkedParentId } = user;
  if (typeof schoolId !== 'string' || typeof linkedParentId !== 'string' || !linkedParentId) return { error: 'PERMISSION_DENIED' };
  const links = await ctx.db
    .collectionGroup('parentLinks')
    .where('schoolId', '==', schoolId)
    .where('parentId', '==', linkedParentId)
    .get();
  const branches = new Set(links.docs.map((l) => l.data().branchId).filter((b) => typeof b === 'string' && b));
  let written = 0;
  for (const branchId of branches) {
    written += await refreshParents({ ...ctx, by: uid }, schoolId, branchId, [linkedParentId]);
  }
  return { branches: branches.size, written };
}

module.exports = { placementChanged, linkChanged, refreshParents, refreshFamiliesOfStudent, refreshBranchParents, refreshOwnFamily };

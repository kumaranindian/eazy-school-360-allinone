'use strict';

// teacherAccess/{uid}: the rules-readable summary of which sections a teacher
// is assigned to (ACTIVE assignments only), the teacher counterpart of
// parentAccess. firestore.rules call get() on it to decide which students a
// teacher may read; Firestore rules cannot query teacherAssignments, so this
// index is the relationship the rules trust. It is written ONLY here
// (Admin SDK) — never by a client — and rebuilt whenever an assignment or the
// staff↔login link changes (triggers in index.js) or on demand (backfill).
//
//   schools/{s}/branches/{b}/teacherAccess/{uid} = {
//     schoolId, branchId, staffId, userId,
//     sectionKeys: ['classId__sectionId', ...],           // what the rules check
//     scopes: [{ academicYearId, classId, sectionId }],   // what the app shows
//     updatedAt
//   }

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);

/** Pure: the document for one staff member, or null when they get no access. */
function buildTeacherAccess({ schoolId, branchId, staffId, staff, assignments, now }) {
  if (!staff || !staff.userId || staff.status !== 'ACTIVE' || staff.isTeacher !== true) return null;
  const seen = new Set();
  const scopes = [];
  for (const a of assignments) {
    if (a.status !== 'ACTIVE' || !a.classId || !a.sectionId) continue;
    const key = `${a.classId}__${a.sectionId}`;
    if (seen.has(key)) continue;
    seen.add(key);
    scopes.push({ academicYearId: a.academicYearId || null, classId: a.classId, sectionId: a.sectionId });
  }
  scopes.sort((x, y) => `${x.classId}__${x.sectionId}`.localeCompare(`${y.classId}__${y.sectionId}`));
  return {
    uid: staff.userId,
    data: {
      schoolId,
      branchId,
      staffId,
      userId: staff.userId,
      sectionKeys: scopes.map((s) => `${s.classId}__${s.sectionId}`),
      scopes,
      updatedAt: now,
    },
  };
}

/** Rebuilds (or removes) the access document of one staff member. */
async function refreshStaffAccess({ db, now }, schoolId, branchId, staffId) {
  const b = branchRef(db, schoolId, branchId);
  const staffSnap = await b.collection('staff').doc(staffId).get();
  const staff = staffSnap.exists ? staffSnap.data() : null;
  const assignments = staff
    ? (await b.collection('teacherAssignments').where('teacherStaffId', '==', staffId).where('status', '==', 'ACTIVE').get()).docs.map((d) => d.data())
    : [];
  const built = buildTeacherAccess({ schoolId, branchId, staffId, staff, assignments, now });
  if (built) {
    await b.collection('teacherAccess').doc(built.uid).set(built.data);
    return { uid: built.uid, sections: built.data.sectionKeys.length };
  }
  return { uid: null, sections: 0 };
}

/** Removes the access document of a login that no longer maps to this staff record. */
async function removeAccessFor(db, schoolId, branchId, uid, staffId) {
  const ref = branchRef(db, schoolId, branchId).collection('teacherAccess').doc(uid);
  const snap = await ref.get();
  if (snap.exists && snap.data().staffId === staffId) await ref.delete();
}

/** Admin backfill / repair for a whole branch. */
async function refreshBranchAccess(ctx, schoolId, branchId) {
  const staff = await branchRef(ctx.db, schoolId, branchId).collection('staff').where('isTeacher', '==', true).get();
  let written = 0;
  for (const s of staff.docs) {
    const r = await refreshStaffAccess(ctx, schoolId, branchId, s.id);
    if (r.uid) written++;
  }
  return { teachers: staff.docs.length, written };
}

module.exports = { buildTeacherAccess, refreshStaffAccess, removeAccessFor, refreshBranchAccess };

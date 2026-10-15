'use strict';

// "Why does this person get permission-denied?" — checks, for one user, every
// prerequisite the Firestore rules and the app rely on, and says which is
// missing. Read-only. Callable by the school's admins (see index.js).
//
// firestore.rules never match on email/phone/claims; they use the caller's
// /users/{uid} profile plus relationship records:
//   teacher: profile.schoolId/branchId + staff.userId link + teacherAssignments
//   parent : profile.linkedParentId + parents/{id} + students/*/parentLinks +
//            parentAccess/{id} (class/section index)
// A missing piece shows up as permission-denied (or an empty screen), not as
// an error naming the cause. This names it.

const { assertAdmin } = require('./access');

const ROLES = ['PLATFORM_ADMIN', 'SCHOOL_ADMIN', 'BRANCH_ADMIN', 'TEACHER', 'FINANCE', 'PARENT'];
const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);

function mk() {
  const checks = [];
  return {
    checks,
    ok: (id, message) => checks.push({ id, ok: true, severity: 'OK', message }),
    bad: (id, severity, message, fix) => checks.push({ id, ok: false, severity, message, fix }),
  };
}

async function teacherChecks(db, c, { uid, schoolId, branchId }) {
  const staff = await branchRef(db, schoolId, branchId).collection('staff').where('userId', '==', uid).limit(3).get();
  if (staff.docs.length === 0) {
    c.bad('STAFF_LINK', 'HIGH', 'No staff record in this branch is linked to this login (staff.userId).',
      'Open Staff → the person → Login access, or re-run "Give login access" so the staff record gets userId.');
    return;
  }
  if (staff.docs.length > 1) {
    c.bad('STAFF_LINK', 'HIGH', 'More than one staff record claims this login.', 'Keep one staff record linked to this user.');
    return;
  }
  const s = staff.docs[0];
  const d = s.data();
  if (d.status !== 'ACTIVE') c.bad('STAFF_ACTIVE', 'HIGH', `The linked staff record is ${d.status}, not ACTIVE.`, 'Reactivate the staff record.');
  else c.ok('STAFF_ACTIVE', 'Linked staff record is ACTIVE.');
  if (d.isTeacher !== true) c.bad('STAFF_IS_TEACHER', 'MEDIUM', 'The staff record is not marked as a teacher.', 'Set "Is teacher" on the staff record.');
  else c.ok('STAFF_IS_TEACHER', 'Staff record is marked as a teacher.');

  const as = await branchRef(db, schoolId, branchId).collection('teacherAssignments').where('teacherStaffId', '==', s.id).get();
  const active = as.docs.map((x) => x.data()).filter((x) => x.status === 'ACTIVE');
  if (active.length === 0) {
    c.bad('ASSIGNMENTS', 'MEDIUM', 'This teacher has no ACTIVE class/section assignment, so class screens will be empty.',
      'Assign the teacher under Staff → Teacher assignments.');
    return;
  }
  c.ok('ASSIGNMENTS', `${active.length} active assignment(s).`);

  // The rules decide which students a teacher may read from teacherAccess/{uid}
  // (rebuilt by functions on every assignment change). Missing or stale ⇒ the
  // teacher's student/roster screens are denied even though assignments exist.
  const want = [...new Set(active.filter((x) => x.classId && x.sectionId).map((x) => `${x.classId}__${x.sectionId}`))];
  const ta = await branchRef(db, schoolId, branchId).collection('teacherAccess').doc(uid).get();
  const have = ta.exists ? ta.data().sectionKeys || [] : null;
  if (have === null) {
    c.bad('TEACHER_ACCESS', 'HIGH', 'The teacherAccess index document is missing, so the teacher is denied every student and roster screen.',
      'Run "Refresh teacher access" (callable refreshTeacherAccess) for the branch, or re-save an assignment.');
  } else if (want.some((k) => !have.includes(k))) {
    c.bad('TEACHER_ACCESS', 'HIGH', `teacherAccess is stale: missing ${want.filter((k) => !have.includes(k)).join(', ')}.`,
      'Run "Refresh teacher access" for the branch.');
  } else c.ok('TEACHER_ACCESS', 'teacherAccess index matches the assignments.');
  // Attendance (class teacher) and marks entry (subject teacher) are judged by
  // the assignmentSlots document the assignment should have written.
  for (const a of active) {
    const key = `${a.academicYearId}__${a.classId}__${a.sectionId}__${a.isClassTeacher === true ? 'CLASS_TEACHER' : a.subjectId}`;
    const slot = await branchRef(db, schoolId, branchId).collection('assignmentSlots').doc(key).get();
    if (!slot.exists || slot.data().teacherStaffId !== s.id) {
      c.bad('ASSIGNMENT_SLOT', 'HIGH',
        `Assignment slot ${key} is missing or points at another teacher; ${a.isClassTeacher === true ? 'attendance marking' : 'marks entry'} will be denied.`,
        'End and recreate the assignment so the slot is rewritten.');
    }
  }
}

async function parentChecks(db, c, { uid, user, schoolId, branchId }) {
  const pid = user.linkedParentId;
  if (!pid) {
    c.bad('LINKED_PARENT_ID', 'CRITICAL', 'The login has no linkedParentId, so every parent query is denied.',
      'Open Parents → the person → Login access and save; this links the account to the parent record.');
    return;
  }
  const pdoc = await branchRef(db, schoolId, branchId).collection('parents').doc(pid).get();
  if (!pdoc.exists) {
    c.bad('PARENT_RECORD', 'CRITICAL', `linkedParentId ${pid} does not exist in this branch.`, 'Relink the login to an existing parent record.');
    return;
  }
  const p = pdoc.data();
  if (p.linkedUserId !== uid) c.bad('PARENT_BACKLINK', 'HIGH', 'The parent record points at a different login (linkedUserId).', 'Relink so parent.linkedUserId equals this login.');
  else c.ok('PARENT_BACKLINK', 'Parent record and login point at each other.');
  if (p.status && p.status !== 'ACTIVE') c.bad('PARENT_ACTIVE', 'HIGH', `The parent record is ${p.status}.`, 'Reactivate the parent record.');

  const links = await db.collectionGroup('parentLinks')
    .where('schoolId', '==', schoolId).where('branchId', '==', branchId).where('parentId', '==', pid).get();
  const usable = links.docs.map((l) => l.data()).filter((l) => l.status === 'ACTIVE' && l.canAccessPortal === true);
  if (links.docs.length === 0) {
    c.bad('CHILD_LINKS', 'MEDIUM', 'No child is linked to this parent.', 'Link the parent to a student from the student profile.');
    return;
  }
  if (usable.length === 0) {
    c.bad('PORTAL_ENABLED', 'HIGH', 'Children are linked but none has portal access switched on (canAccessPortal).',
      'Save Login access for this parent (it enables portal links) or edit the link to allow portal access.');
    return;
  }
  c.ok('CHILD_LINKS', `${usable.length} portal-enabled child link(s).`);

  const wantClass = new Set();
  const wantSection = new Set();
  for (const l of usable) {
    const st = (await branchRef(db, schoolId, branchId).collection('students').doc(l.studentId).get()).data();
    if (st && st.status === 'ACTIVE' && st.currentClassId) {
      wantClass.add(st.currentClassId);
      if (st.currentSectionId) wantSection.add(`${st.currentClassId}__${st.currentSectionId}`);
    }
  }
  const acc = await branchRef(db, schoolId, branchId).collection('parentAccess').doc(pid).get();
  if (!acc.exists) {
    c.bad('PARENT_ACCESS', 'HIGH', 'The parentAccess index document is missing; class-level data (homework, results, timetable) is denied.',
      'Parents → "Refresh parent access", or save Login access for this parent.');
    return;
  }
  const a = acc.data();
  const missing = [...wantClass].filter((k) => !(a.classKeys || []).includes(k))
    .concat([...wantSection].filter((k) => !(a.sectionKeys || []).includes(k)));
  if (missing.length) {
    c.bad('PARENT_ACCESS', 'HIGH', `parentAccess is stale: missing ${missing.join(', ')}.`, 'Parents → "Refresh parent access".');
  } else {
    c.ok('PARENT_ACCESS', 'parentAccess index matches the children\'s classes.');
  }
}

/** Pure(ish) core: returns { error } or { result: { uid, role, healthy, checks } }. */
async function diagnoseAccess({ db }, callerUid, token, data) {
  const { schoolId, branchId, uid } = data || {};
  if ([schoolId, branchId, uid].some((v) => typeof v !== 'string' || !v || v.length > 128)) return { error: 'INVALID_ARGUMENT' };
  const caller = await assertAdmin(db, callerUid, schoolId, branchId, token);
  if (!caller) return { error: 'PERMISSION_DENIED' };

  const c = mk();
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) {
    c.bad('PROFILE_EXISTS', 'CRITICAL', 'There is no /users profile for this login: every query is denied and the app treats it as a new account.',
      'Create the login from Staff/Parents → Login access.');
    return { result: { uid, role: null, healthy: false, checks: c.checks } };
  }
  const user = snap.data();
  if (user.schoolId !== schoolId) return { error: 'PERMISSION_DENIED' }; // never describe another school's user
  c.ok('PROFILE_EXISTS', 'Profile found.');

  if (!ROLES.includes(user.role)) c.bad('ROLE_VALID', 'CRITICAL', `Role "${user.role}" is not one the app/rules know.`, 'Set role to TEACHER, PARENT, FINANCE or BRANCH_ADMIN.');
  else c.ok('ROLE_VALID', `Role ${user.role}.`);
  if (user.status !== 'ACTIVE') c.bad('STATUS_ACTIVE', 'CRITICAL', `Profile status is ${user.status}; the rules deny non-ACTIVE accounts everything.`, 'Activate the account.');
  else c.ok('STATUS_ACTIVE', 'Profile is ACTIVE.');

  const needsBranch = user.role !== 'SCHOOL_ADMIN' && user.role !== 'PLATFORM_ADMIN';
  if (needsBranch && user.branchId !== branchId) {
    c.bad('BRANCH_MATCH', 'CRITICAL', `Profile branchId is ${user.branchId ? `"${user.branchId}"` : 'missing'}, not "${branchId}"; branch-scoped rules deny it.`,
      'Set the profile branchId to the branch the person works in.');
  } else if (needsBranch) c.ok('BRANCH_MATCH', 'Profile branch matches.');

  const l = user.login;
  if (l && !(l.enabled === true && (l.effective || []).length > 0)) {
    c.bad('LOGIN_METHODS', 'HIGH', 'Login access is switched off or has no effective sign-in method.', 'Enable access and a school-permitted method in Login access.');
  } else c.ok('LOGIN_METHODS', l ? `Methods: ${(l.effective || []).join(', ')}.` : 'Legacy account (no login map): all methods work.');

  if (user.role === 'TEACHER') await teacherChecks(db, c, { uid, schoolId, branchId });
  if (user.role === 'PARENT') await parentChecks(db, c, { uid, user, schoolId, branchId });

  return { result: { uid, role: user.role, healthy: c.checks.every((x) => x.ok), checks: c.checks } };
}

module.exports = { diagnoseAccess };

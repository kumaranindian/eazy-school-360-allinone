// RBAC audit: the queries a TEACHER and a PARENT issue between login and the
// first screens (same constraints as the Dart repositories), run against the
// real firestore.rules for healthy and for broken/legacy data. It documents
// which failures are DATA problems (missing relationship records — see
// functions/diagnose.js) and which are QUERY problems. Prefix: rb-.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, collectionGroup, doc, getDoc, getDocs, limit, orderBy, query, serverTimestamp, setDoc, where,
} from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
  await seed();
});
after(async () => env.cleanup());

const A = 'rb-a';
const Z = 'rb-z';
const N = 'north';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const nb = (s = A, b = N) => ['schools', s, 'branches', b];
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const col = (d, name, s = A) => collection(d, ...nb(s), name);
const AUD = ['ALL', 'BRANCH', 'PARENTS']; // general audiences; CLASS/SECTION are queried pinned to the parent's own class/section

async function seed() {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, Z]) {
      await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...base });
      await setDoc(doc(d, ...nb(s)), { schoolId: s, name: N, status: 'ACTIVE', ...base });
    }
    const users = {
      'rb-t-ok': { schoolId: A, branchId: N, role: 'TEACHER' },
      'rb-t-nobranch': { schoolId: A, branchId: null, role: 'TEACHER' },
      'rb-t-wrongbranch': { schoolId: A, branchId: 'other', role: 'TEACHER' },
      'rb-t2': { schoolId: A, branchId: N, role: 'TEACHER' },
      'rb-t-z': { schoolId: Z, branchId: N, role: 'TEACHER' },
      'rb-p-ok': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'pr-ok' },
      'rb-p-noaccess': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'pr-na' },
      'rb-p-unlinked': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: null },
      'rb-p-noportal': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'pr-np' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: 'x@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    const n = nb();
    await setDoc(doc(d, ...n, 'staff', 'st1'), { schoolId: A, branchId: N, userId: 'rb-t-ok', status: 'ACTIVE', isTeacher: true, ...base });
    await setDoc(doc(d, ...n, 'teacherAccess', 'rb-t-ok'), { schoolId: A, branchId: N, staffId: 'st1', userId: 'rb-t-ok', sectionKeys: ['c5__sa'], scopes: [], updatedAt: serverTimestamp() });
    await setDoc(doc(d, ...n, 'staff', 'st2'), { schoolId: A, branchId: N, userId: 'rb-t2', status: 'ACTIVE', isTeacher: true, ...base });
    for (const [id, st] of [['as1', 'st1'], ['as2', 'st2']]) {
      await setDoc(doc(d, ...n, 'teacherAssignments', id), {
        schoolId: A, branchId: N, teacherStaffId: st, status: 'ACTIVE', classId: 'c5', sectionId: 'sa', academicYearId: 'y1', isClassTeacher: false, subjectId: 'm', ...base,
      });
    }
    await setDoc(doc(d, ...n, 'students', 'stu1'), { schoolId: A, branchId: N, status: 'ACTIVE', currentClassId: 'c5', currentSectionId: 'sa', ...base });
    for (const [pid, portal, access] of [['pr-ok', true, true], ['pr-na', true, false], ['pr-np', false, true]]) {
      await setDoc(doc(d, ...n, 'parents', pid), { schoolId: A, branchId: N, status: 'ACTIVE', ...base });
      await setDoc(doc(d, ...n, 'students', 'stu1', 'parentLinks', pid), {
        schoolId: A, branchId: N, studentId: 'stu1', parentId: pid, status: 'ACTIVE', canAccessPortal: portal, ...base,
      });
      if (access) {
        await setDoc(doc(d, ...n, 'parentAccess', pid), { schoolId: A, branchId: N, parentId: pid, classKeys: ['c5'], sectionKeys: ['c5__sa'], updatedAt: serverTimestamp(), updatedBy: 'seed' });
      }
    }
    for (const [id, kind, status] of [['an1', 'ALL', 'PUBLISHED'], ['an2', 'PARENTS', 'PUBLISHED'], ['an3', 'STAFF', 'PUBLISHED']]) {
      await setDoc(doc(d, ...n, 'announcements', id), { schoolId: A, branchId: N, authorId: 'seed', status, audienceKind: kind, title: 'T', body: 'b', publishAt: serverTimestamp(), ...base });
      await setDoc(doc(d, ...n, 'broadcastNotices', id), { schoolId: A, branchId: N, audienceKind: kind, type: 'ANNOUNCEMENT_PUBLISHED', title: 'T', ...base });
    }
    await setDoc(doc(d, ...nb(), 'assignmentSlots', 'y1__c5__sa__CLASS_TEACHER'), { schoolId: A, branchId: N, teacherStaffId: 'st1', ...base });
    await setDoc(doc(d, ...nb(), 'assignmentSlots', 'y1__c5__sa__m'), { schoolId: A, branchId: N, teacherStaffId: 'st1', ...base });
    await setDoc(doc(d, ...nb(), 'academicYears', 'y1'), { schoolId: A, branchId: N, name: 'Y1', status: 'ACTIVE', ...base });
    await setDoc(doc(d, ...nb(), 'examinations', 'ex1'), { schoolId: A, branchId: N, academicYearId: 'y1', classId: 'c5', status: 'PUBLISHED', resultVersion: 1, ...base });
    await setDoc(doc(d, ...nb(), 'homework', 'hw1'), { schoolId: A, branchId: N, teacherStaffId: 'st1', classId: 'c5', sectionId: 'sa', academicYearId: 'y1', status: 'PUBLISHED', ...base });
  });
}

const staffAnnouncements = (d) => getDocs(query(col(d, 'announcements'), where('status', '==', 'PUBLISHED'), orderBy('publishAt', 'desc'), limit(100)));
const parentAnnouncements = (d, aud = AUD) =>
  getDocs(query(col(d, 'announcements'), where('status', '==', 'PUBLISHED'), where('audienceKind', 'in', aud), orderBy('publishAt', 'desc'), limit(100)));
const parentNotices = (d, aud = AUD) =>
  getDocs(query(col(d, 'broadcastNotices'), where('audienceKind', 'in', aud), orderBy('createdAt', 'desc'), limit(30)));
const parentClassAnnouncements = (d, classId = 'c5') =>
  getDocs(query(col(d, 'announcements'), where('status', '==', 'PUBLISHED'), where('audienceKind', '==', 'CLASS'), where('classId', '==', classId), orderBy('publishAt', 'desc'), limit(100)));
const parentSectionNotices = (d, classId = 'c5', sectionId = 'sa') =>
  getDocs(query(col(d, 'broadcastNotices'), where('audienceKind', '==', 'SECTION'), where('classId', '==', classId), where('sectionId', '==', sectionId), orderBy('createdAt', 'desc'), limit(30)));

// ---------------------------------------------------------------- teacher
test('teacher (healthy data): login → dashboard → class screens all succeed', async () => {
  const d = as('rb-t-ok');
  await assertSucceeds(getDoc(doc(d, 'users', 'rb-t-ok')));
  await assertSucceeds(getDoc(doc(d, 'schools', A)));
  await assertSucceeds(getDoc(doc(d, ...nb())));
  await assertSucceeds(getDocs(query(col(d, 'staff'), where('userId', '==', 'rb-t-ok'), limit(1))));
  await assertSucceeds(getDocs(query(col(d, 'teacherAssignments'), where('teacherStaffId', '==', 'st1'), where('status', '==', 'ACTIVE'))));
  await assertSucceeds(staffAnnouncements(d));
  await assertSucceeds(getDocs(query(col(d, 'broadcastNotices'), orderBy('createdAt', 'desc'), limit(30))));
  // students: only the pinned section the teacher is assigned to
  await assertSucceeds(getDocs(query(col(d, 'students'), where('currentClassId', '==', 'c5'), where('currentSectionId', '==', 'sa'), limit(50))));
  await assertFails(getDocs(query(col(d, 'students'), limit(50))));
});

test('teacher: a profile with no branchId is denied every branch read (DATA root cause)', async () => {
  const d = as('rb-t-nobranch');
  await assertSucceeds(getDoc(doc(d, 'users', 'rb-t-nobranch')));
  await assertSucceeds(getDoc(doc(d, 'schools', A)));
  await assertFails(staffAnnouncements(d));
  await assertFails(getDocs(query(col(d, 'students'), limit(50))));
});

test('teacher: a profile pointing at another branch is denied', async () => {
  const d = as('rb-t-wrongbranch');
  await assertFails(staffAnnouncements(d));
  await assertFails(getDocs(query(col(d, 'students'), limit(50))));
});

test('teacher cannot read another teacher\'s assignments, nor list them unfiltered', async () => {
  const d = as('rb-t-ok');
  await assertFails(getDocs(query(col(d, 'teacherAssignments'), where('teacherStaffId', '==', 'st2'))));
  await assertFails(getDocs(col(d, 'teacherAssignments')));
  await assertFails(getDocs(query(col(d, 'staff'), limit(10))));
});

test('teacher cannot give themselves assignments, links or roles', async () => {
  const d = as('rb-t-ok');
  await assertFails(setDoc(doc(d, ...nb(), 'teacherAssignments', 'mine'), { schoolId: A, branchId: N, teacherStaffId: 'st1', status: 'ACTIVE', ...base }));
  await assertFails(setDoc(doc(d, 'users', 'rb-t-ok'), { schoolId: A, branchId: N, role: 'SCHOOL_ADMIN', status: 'ACTIVE', name: 'T', email: 'x@example.com', ...base }));
  await assertFails(setDoc(doc(d, ...nb(), 'students', 'stu1', 'parentLinks', 'x'), { schoolId: A, branchId: N, parentId: 'x', studentId: 'stu1', ...base }));
});

test('teacher of another school sees nothing here', async () => {
  const d = as('rb-t-z');
  await assertFails(staffAnnouncements(d));
  await assertFails(getDocs(query(col(d, 'students'), limit(5))));
  await assertFails(getDoc(doc(d, 'schools', A)));
});

// ----------------------------------------------------------------- parent
test('parent (healthy data): profile, own record, linked child, announcements', async () => {
  const d = as('rb-p-ok');
  await assertSucceeds(getDoc(doc(d, 'users', 'rb-p-ok')));
  await assertSucceeds(getDoc(doc(d, 'schools', A)));
  await assertSucceeds(getDoc(doc(d, ...nb())));
  await assertSucceeds(getDoc(doc(d, ...nb(), 'parents', 'pr-ok')));
  await assertSucceeds(getDoc(doc(d, ...nb(), 'parentAccess', 'pr-ok')));
  await assertSucceeds(getDoc(doc(d, ...nb(), 'students', 'stu1')));
  await assertSucceeds(parentAnnouncements(d));
  await assertSucceeds(parentNotices(d));
  await assertSucceeds(parentClassAnnouncements(d));
  await assertSucceeds(parentSectionNotices(d));
  // another class's / section's content is refused
  await assertFails(parentClassAnnouncements(d, 'c9'));
  await assertFails(parentSectionNotices(d, 'c5', 'sz'));
  // the old single 5-kind query is no longer provable
  await assertFails(parentAnnouncements(d, ['ALL', 'BRANCH', 'PARENTS', 'CLASS', 'SECTION']));
});

test('parent cannot read an unrelated student, another parent, or list students', async () => {
  const d = as('rb-p-ok');
  await assertFails(getDoc(doc(d, ...nb(), 'parents', 'pr-na')));
  await assertFails(getDocs(query(col(d, 'students'), limit(5))));
  await assertFails(getDoc(doc(d, ...nb(), 'students', 'stu1', 'parentLinks', 'pr-na')));
});

test('parent: staff-only announcements are not readable, and an unconstrained query is refused', async () => {
  const d = as('rb-p-ok');
  await assertFails(getDoc(doc(d, ...nb(), 'announcements', 'an3')));
  await assertFails(staffAnnouncements(d));
});

test('CONFIRMED: a parent with no parentAccess index is denied the whole announcements query (DATA root cause)', async () => {
  const d = as('rb-p-noaccess');
  // the broad query the app issues cannot be proven safe without the index doc…
  await assertFails(parentAnnouncements(d));
  await assertFails(parentNotices(d));
  // …but school-wide ("ALL") announcements are still readable when asked for alone.
  await assertFails(parentClassAnnouncements(d));
  await assertSucceeds(parentAnnouncements(d, ['ALL']));
  await assertSucceeds(parentNotices(d, ['ALL']));
});

test('parent with portal access switched off cannot read the child', async () => {
  const d = as('rb-p-noportal');
  await assertFails(getDoc(doc(d, ...nb(), 'students', 'stu1')));
  await assertSucceeds(parentAnnouncements(d)); // index exists, announcements still fine
});

test('parent with no linkedParentId is denied everything beyond their own profile', async () => {
  const d = as('rb-p-unlinked');
  await assertSucceeds(getDoc(doc(d, 'users', 'rb-p-unlinked')));
  await assertFails(parentAnnouncements(d));
  await assertFails(getDoc(doc(d, ...nb(), 'students', 'stu1')));
  // school-wide announcements stay readable (the app's fallback); the broad query is not provable
  await assertSucceeds(parentAnnouncements(d, ['ALL']));
});

test('parent cannot link themselves to a child or edit protected records', async () => {
  const d = as('rb-p-ok');
  await assertFails(setDoc(doc(d, ...nb(), 'students', 'stu1', 'parentLinks', 'pr-ok'), { schoolId: A, branchId: N, studentId: 'stu1', parentId: 'pr-ok', status: 'ACTIVE', canAccessPortal: true, ...base }));
  await assertFails(setDoc(doc(d, ...nb(), 'parentAccess', 'pr-ok'), { schoolId: A, branchId: N, parentId: 'pr-ok', classKeys: ['c1', 'c2', 'c3'], sectionKeys: [], updatedAt: serverTimestamp(), updatedBy: 'rb-p-ok' }));
  await assertFails(setDoc(doc(d, ...nb(), 'students', 'stu1'), { schoolId: A, branchId: N, status: 'ACTIVE', ...base }));
});

// ------------------------------------------------ audit findings (agent T1..P5)
const yearAssignments = (d) =>
  getDocs(query(col(d, 'teacherAssignments'), where('academicYearId', '==', 'y1'), where('status', '==', 'ACTIVE'), limit(101)));

test('T1: the year-wide ACTIVE assignments list the app loads for every teacher', async () => {
  await assertSucceeds(yearAssignments(as('rb-t-ok')));
});

test('T1: …but never an unfiltered or ENDED list, nor from another branch/school', async () => {
  const d = as('rb-t-ok');
  await assertFails(getDocs(query(col(d, 'teacherAssignments'), where('academicYearId', '==', 'y1'))));
  await assertFails(getDocs(query(col(d, 'teacherAssignments'), where('status', '==', 'ENDED'))));
  await assertFails(yearAssignments(as('rb-t-z')));
  await assertFails(yearAssignments(as('rb-t-wrongbranch')));
  await assertFails(yearAssignments(as('rb-p-ok')));
});

test('T2: a teacher still cannot list colleagues\' staff records', async () => {
  await assertFails(getDocs(query(col(as('rb-t-ok'), 'staff'), where('status', '==', 'ACTIVE'), where('isTeacher', '==', true), limit(100))));
});

test('T3: a teacher cannot list a parent\'s links (parents are reached only through their own students)', async () => {
  const d = as('rb-t-ok');
  await assertFails(getDocs(query(collectionGroup(d, 'parentLinks'), where('schoolId', '==', A), where('parentId', '==', 'pr-ok'))));
  await assertFails(getDocs(query(collectionGroup(d, 'parentLinks'), where('schoolId', '==', A), where('branchId', '==', N), where('parentId', '==', 'pr-ok'))));
});

test('P4: a parent reads an invoice\'s payments only when the query is pinned to their child', async () => {
  const d = as('rb-p-ok');
  await assertFails(getDocs(query(col(d, 'payments'), where('invoiceId', '==', 'inv1'))));
  await assertSucceeds(getDocs(query(col(d, 'payments'), where('invoiceId', '==', 'inv1'), where('studentId', '==', 'stu1'))));
  await assertFails(getDocs(query(col(as('rb-p-ok'), 'payments'), where('invoiceId', '==', 'inv1'), where('studentId', '==', 'stu-other'))));
});

test('P5: a parent may read a single academic-year document of their child\'s branch, never the list', async () => {
  const d = as('rb-p-ok');
  await assertSucceeds(getDoc(doc(d, ...nb(), 'academicYears', 'y1')));
  await assertFails(getDocs(col(d, 'academicYears')));
  await assertFails(getDocs(collection(d, ...nb(), 'academicYears', 'y1', 'classes')));
  // a parent with no family index (no child here) gets nothing
  await assertFails(getDoc(doc(as('rb-p-noaccess'), ...nb(), 'academicYears', 'y1')));
  await assertFails(getDoc(doc(as('rb-p-ok'), ...nb(Z), 'academicYears', 'y1')));
});

// --- documents that do not exist yet --------------------------------------
// The app reads a register / marks sheet / submission / result with a plain
// get() and treats "missing" as "not started". A rule that dereferences
// resource.data on a missing document errors → permission-denied for every
// non-admin. These must behave like a normal miss for the people who may
// create the document, and stay denied for everyone else.
test('M1: class teacher can read a not-yet-created attendance session (a normal miss)', async () => {
  const id = '2026-10-10__y1__c5__sa';
  await assertSucceeds(getDoc(doc(as('rb-t-ok'), ...nb(), 'attendanceSessions', id)));
  await assertFails(getDoc(doc(as('rb-t2'), ...nb(), 'attendanceSessions', id))); // not the class teacher
  await assertFails(getDoc(doc(as('rb-t-z'), ...nb(), 'attendanceSessions', id)));
  await assertFails(getDoc(doc(as('rb-p-ok'), ...nb(), 'attendanceSessions', id)));
});

test('M2: the assigned subject teacher can read a not-yet-created marks sheet', async () => {
  const id = 'ex1__m__sa';
  await assertSucceeds(getDoc(doc(as('rb-t-ok'), ...nb(), 'marksSheets', id)));
  await assertFails(getDoc(doc(as('rb-t2'), ...nb(), 'marksSheets', id)));
  await assertFails(getDoc(doc(as('rb-p-ok'), ...nb(), 'marksSheets', id)));
});

test('M3: a parent can read their own child\'s not-yet-created submission; a teacher their own homework\'s', async () => {
  await assertSucceeds(getDoc(doc(as('rb-p-ok'), ...nb(), 'homeworkSubmissions', 'hw1__stu1')));
  await assertFails(getDoc(doc(as('rb-p-noportal'), ...nb(), 'homeworkSubmissions', 'hw1__stu1')));
  await assertFails(getDoc(doc(as('rb-p-ok'), ...nb(), 'homeworkSubmissions', 'hw1__stuOther')));
  await assertSucceeds(getDoc(doc(as('rb-t-ok'), ...nb(), 'homeworkSubmissions', 'hw1__stu1')));
  await assertFails(getDoc(doc(as('rb-t2'), ...nb(), 'homeworkSubmissions', 'hw1__stu1')));
});

test('M4: a parent can read a not-yet-published result as a normal miss (published exam, own child only)', async () => {
  await assertSucceeds(getDoc(doc(as('rb-p-ok'), ...nb(), 'resultSummaries', 'ex1__stu1__v1')));
  await assertFails(getDoc(doc(as('rb-p-noportal'), ...nb(), 'resultSummaries', 'ex1__stu1__v1')));
  await assertFails(getDoc(doc(as('rb-p-ok'), ...nb(), 'resultSummaries', 'ex1__stuOther__v1')));
});

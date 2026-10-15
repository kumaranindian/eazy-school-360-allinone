// RBAC audit — screen sweep. Every Firestore read a TEACHER or a PARENT screen
// issues (same collection, same where/orderBy constraints as the Dart
// repositories), run against firestore.rules with HEALTHY data. A failure here
// is either a rule gap or a query that cannot be proven safe — both are
// defects to fix, not data problems. Prefix: sw-.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, collectionGroup, doc, getCountFromServer, getDoc, getDocs, limit, orderBy, query,
  serverTimestamp, setDoc, where,
} from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await seed();
});
after(async () => env.cleanup());

const A = 'sw-a';
const N = 'north';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const nb = () => ['schools', A, 'branches', N];
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const col = (d, name) => collection(d, ...nb(), name);
const bdoc = (d, name, id) => doc(d, ...nb(), name, id);
const Y = 'y1', C = 'c5', S = 'sa', SUBJ = 'math';

async function seed() {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    await setDoc(doc(d, 'schools', A), { name: A, status: 'ACTIVE', ...base });
    await setDoc(doc(d, ...nb()), { schoolId: A, name: N, status: 'ACTIVE', ...base });
    const users = {
      'sw-t': { role: 'TEACHER' }, 'sw-t2': { role: 'TEACHER' },
      'sw-p': { role: 'PARENT', linkedParentId: 'pr1' },
      'sw-admin': { role: 'SCHOOL_ADMIN', branchId: null },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { schoolId: A, branchId: N, name: 'T', email: 'x@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    const n = nb();
    await setDoc(doc(d, ...n, 'staff', 'st1'), { schoolId: A, branchId: N, userId: 'sw-t', status: 'ACTIVE', isTeacher: true, ...base });
    await setDoc(doc(d, ...n, 'teacherAccess', 'sw-t'), { schoolId: A, branchId: N, staffId: 'st1', userId: 'sw-t', sectionKeys: [`${C}__${S}`], scopes: [{ academicYearId: Y, classId: C, sectionId: S }], updatedAt: serverTimestamp() });
    await setDoc(doc(d, ...n, 'staff', 'st2'), { schoolId: A, branchId: N, userId: 'sw-t2', status: 'ACTIVE', isTeacher: true, ...base });
    await setDoc(doc(d, ...n, 'teacherAssignments', 'as1'), { schoolId: A, branchId: N, teacherStaffId: 'st1', status: 'ACTIVE', academicYearId: Y, classId: C, sectionId: S, subjectId: null, isClassTeacher: true, startDate: new Date(), ...base });
    await setDoc(doc(d, ...n, 'assignmentSlots', `${Y}__${C}__${S}__CLASS_TEACHER`), { schoolId: A, branchId: N, teacherStaffId: 'st1', ...base });
    await setDoc(doc(d, ...n, 'assignmentSlots', `${Y}__${C}__${S}__${SUBJ}`), { schoolId: A, branchId: N, teacherStaffId: 'st1', ...base });
    await setDoc(doc(d, ...n, 'students', 'stu1'), { schoolId: A, branchId: N, status: 'ACTIVE', currentAcademicYearId: Y, currentClassId: C, currentSectionId: S, ...base });
    await setDoc(doc(d, ...n, 'parents', 'pr1'), { schoolId: A, branchId: N, status: 'ACTIVE', linkedUserId: 'sw-p', ...base });
    await setDoc(doc(d, ...n, 'students', 'stu1', 'parentLinks', 'pr1'), { schoolId: A, branchId: N, studentId: 'stu1', parentId: 'pr1', status: 'ACTIVE', canAccessPortal: true, ...base });
    await setDoc(doc(d, ...n, 'parentAccess', 'pr1'), { schoolId: A, branchId: N, parentId: 'pr1', classKeys: [C], sectionKeys: [`${C}__${S}`], updatedAt: serverTimestamp(), updatedBy: 'seed' });
    await setDoc(doc(d, ...n, 'homework', 'hw1'), { schoolId: A, branchId: N, teacherStaffId: 'st1', classId: C, sectionId: S, academicYearId: Y, status: 'PUBLISHED', ...base });
    await setDoc(doc(d, ...n, 'timetables', 'tt1'), { schoolId: A, branchId: N, academicYearId: Y, classId: C, sectionId: S, status: 'PUBLISHED', ...base });
    await setDoc(doc(d, ...n, 'examinations', 'ex1'), { schoolId: A, branchId: N, academicYearId: Y, classId: C, sectionId: null, status: 'PUBLISHED', resultVersion: 1, ...base });
    await setDoc(doc(d, ...n, 'conversations', 'conv1'), { schoolId: A, branchId: N, participants: ['sw-t', 'sw-p'], parentUserId: 'sw-p', ...base });
    await setDoc(doc(d, ...n, 'messageContacts', 'st1'), { schoolId: A, branchId: N, staffId: 'st1', userId: 'sw-t', enabled: true, name: 'T', sectionKeys: [`${C}__${S}`], ...base });
    await setDoc(doc(d, ...n, 'invoices', 'inv1'), { schoolId: A, branchId: N, studentId: 'stu1', ...base });
    await setDoc(doc(d, ...n, 'receipts', 'rc1'), { schoolId: A, branchId: N, studentId: 'stu1', ...base });
    await setDoc(doc(d, ...n, 'leaveApplications', 'la1'), { schoolId: A, branchId: N, subjectKind: 'STUDENT', subjectId: 'stu1', applicantUserId: 'sw-p', status: 'PENDING', ...base });
    await setDoc(doc(d, 'users', 'sw-t', 'noticeReads', 'state'), { ids: [] });
    await setDoc(doc(d, 'users', 'sw-t', 'preferences', 'notifications'), { pushEnabled: true });
  });
}

const rows = [];
const T = (label, fn, role = 'sw-t') => rows.push({ role, label, fn });

// ---- common ---------------------------------------------------------------
for (const [role, who] of [['sw-t', 'teacher'], ['sw-p', 'parent']]) {
  const nr = (d) => query(col(d, 'notifications'), where('audience', '==', 'USER'), where('recipientUserId', '==', role), orderBy('createdAt', 'desc'), limit(30));
  T(`${who}: own profile, school, branch`, async (d) => { await getDoc(doc(d, 'users', role)); await getDoc(doc(d, 'schools', A)); await getDoc(doc(d, ...nb())); }, role);
  T(`${who}: my notifications (feed + bell count)`, async (d) => { await getDocs(nr(d)); await getCountFromServer(query(col(d, 'notifications'), where('audience', '==', 'USER'), where('recipientUserId', '==', role), where('readAt', '==', null))); }, role);
  T(`${who}: announcements (school-wide, published)`, (d) => getDocs(query(col(d, 'announcements'), where('status', '==', 'PUBLISHED'), ...(role === 'sw-p' ? [where('audienceKind', 'in', ['ALL', 'BRANCH', 'PARENTS'])] : []), orderBy('publishAt', 'desc'), limit(100))), role);
  T(`${who}: broadcast notices`, (d) => getDocs(query(col(d, 'broadcastNotices'), ...(role === 'sw-p' ? [where('audienceKind', 'in', ['ALL', 'BRANCH', 'PARENTS'])] : []), orderBy('createdAt', 'desc'), limit(30))), role);
  T(`${who}: conversations list + thread`, async (d) => { await getDocs(query(col(d, 'conversations'), where('participants', 'array-contains', role), orderBy('lastMessageAt', 'desc'), limit(50))); await getDocs(query(collection(d, ...nb(), 'conversations', 'conv1', 'messages'), orderBy('createdAt'))); }, role);
}
T('teacher: notice reads + preferences', async (d) => { await getDoc(doc(d, 'users', 'sw-t', 'noticeReads', 'state')); await getDoc(doc(d, 'users', 'sw-t', 'preferences', 'notifications')); });

// ---- TEACHER --------------------------------------------------------------
T('teacher: academic structure (years, classes, sections, subjects, holidays, settings)', async (d) => {
  await getDocs(query(col(d, 'academicYears'), orderBy('startDate', 'desc')));
  await getDocs(collection(d, ...nb(), 'academicYears', Y, 'classes'));
  await getDocs(collection(d, ...nb(), 'academicYears', Y, 'classes', C, 'sections'));
  await getDocs(collection(d, ...nb(), 'academicYears', Y, 'subjects'));
  await getDocs(collection(d, ...nb(), 'academicYears', Y, 'holidays'));
  await getDocs(collection(d, ...nb(), 'settings'));
});
T('teacher: my class roster (assigned section pinned), count, student profile panels', async (d) => {
  await getDocs(query(col(d, 'students'), where('currentAcademicYearId', '==', Y), where('currentClassId', '==', C), where('currentSectionId', '==', S), orderBy('displayNameLower')));
  await getCountFromServer(query(col(d, 'students'), where('currentClassId', '==', C), where('currentSectionId', '==', S)));
  await getDoc(bdoc(d, 'students', 'stu1'));
  await getDocs(collection(d, ...nb(), 'students', 'stu1', 'academicRecords'));
  await getDocs(collection(d, ...nb(), 'students', 'stu1', 'parentLinks'));
});
T('teacher: a parent of my student (profile panel, single document)', async (d) => { await getDoc(bdoc(d, 'parents', 'pr1')); });
T('teacher: my staff profile + assignments + departments/designations', async (d) => {
  await getDocs(query(col(d, 'staff'), where('userId', '==', 'sw-t'), limit(1)));
  await getDocs(col(d, 'departments')); await getDocs(col(d, 'designations'));
  await getDocs(query(col(d, 'teacherAssignments'), where('teacherStaffId', '==', 'st1'), orderBy('startDate', 'desc')));
});
T('teacher: attendance (register, sessions, roster, reports)', async (d) => {
  await getDoc(bdoc(d, 'attendanceSessions', `2026-10-10__${Y}__${C}__${S}`));
  await getDocs(query(col(d, 'attendanceSessions'), where('dateKey', '==', '2026-10-10'), where('academicYearId', '==', Y), where('classId', '==', C), where('sectionId', '==', S)));
  await getDocs(query(col(d, 'studentAttendance'), where('academicYearId', '==', Y), where('classId', '==', C), where('sectionId', '==', S), where('dateKey', '==', '2026-10-10')));
  await getDocs(query(col(d, 'studentAttendance'), where('academicYearId', '==', Y), where('classId', '==', C), where('sectionId', '==', S), where('dateKey', '>=', '2026-10-01'), where('dateKey', '<=', '2026-10-31'), orderBy('dateKey')));
  await getDocs(query(collectionGroup(d, 'academicRecords'), where('schoolId', '==', A), where('branchId', '==', N), where('academicYearId', '==', Y), where('classId', '==', C), where('sectionId', '==', S)));
});
T('teacher: my leave (applications, balances, types, history, student calendar)', async (d) => {
  await getDocs(query(col(d, 'leaveApplications'), where('subjectKind', '==', 'STAFF'), where('subjectId', '==', 'st1'), orderBy('createdAt', 'desc'), limit(100)));
  await getDocs(query(col(d, 'leaveBalances'), where('staffId', '==', 'st1'), where('academicYearId', '==', Y)));
  await getDocs(query(col(d, 'leaveTypes'), where('kind', '==', 'STAFF'), limit(200)));
  await getDocs(query(col(d, 'leaveHistory'), where('subjectKind', '==', 'STAFF'), where('subjectId', '==', 'st1'), where('applicationId', '==', 'la9'), orderBy('revision')));
  await getDocs(query(col(d, 'leaveCalendar'), where('subjectKind', '==', 'STUDENT'), where('classId', '==', C), where('sectionId', '==', S), where('endDateKey', '>=', '2026-10-01'), orderBy('endDateKey'), limit(300)));
});
T('teacher: my timetable (entries, timetable docs, substitutions)', async (d) => {
  await getDocs(query(col(d, 'timetableEntries'), where('academicYearId', '==', Y), where('teacherStaffId', '==', 'st1'), where('live', '==', true)));
  await getDoc(bdoc(d, 'timetables', 'tt1'));
  await getDocs(query(col(d, 'substitutions'), where('substituteTeacherId', '==', 'st1'), where('dateKey', '>=', '2026-10-01'), where('dateKey', '<=', '2026-10-31')));
  await getDocs(query(col(d, 'substitutions'), where('originalTeacherId', '==', 'st1'), where('dateKey', '>=', '2026-10-01'), where('dateKey', '<=', '2026-10-31')));
});
T('teacher: homework list, count, submissions, revisions', async (d) => {
  await getDocs(query(col(d, 'homework'), where('academicYearId', '==', Y), where('teacherStaffId', '==', 'st1'), orderBy('dueDateKey', 'desc'), limit(26)));
  await getCountFromServer(query(col(d, 'homework'), where('academicYearId', '==', Y), where('status', '==', 'PUBLISHED'), where('teacherStaffId', '==', 'st1')));
  await getDocs(query(col(d, 'homeworkSubmissions'), where('homeworkId', '==', 'hw1'), orderBy('studentName')));
  await getDocs(query(col(d, 'homeworkRevisions'), where('homeworkId', '==', 'hw1'), where('studentId', '==', 'stu1')));
});
T('teacher: announcement authoring (own drafts) and year assignments', async (d) => {
  await getDocs(query(col(d, 'announcements'), where('authorId', '==', 'sw-t'), orderBy('createdAt', 'desc'), limit(100)));
  await getDocs(query(col(d, 'teacherAssignments'), where('academicYearId', '==', Y), where('status', '==', 'ACTIVE'), limit(101)));
});
T('teacher: exams list + subjects', async (d) => {
  await getDocs(query(col(d, 'examinations'), where('academicYearId', '==', Y), orderBy('startDateKey', 'desc')));
  await getDocs(query(col(d, 'examinationSubjects'), where('examId', '==', 'ex1')));
});
T('teacher: marks sheet (one, as the marks-entry screen reads it)', async (d) => { await getDoc(bdoc(d, 'marksSheets', `ex1__${SUBJ}__${S}`)); });
T('teacher: marks entries of one section+subject', async (d) => {
  await getDocs(query(col(d, 'marksEntries'), where('examId', '==', 'ex1'), where('subjectId', '==', SUBJ), where('sectionId', '==', S), where('classId', '==', C), where('academicYearId', '==', Y)));
});
T('teacher: published results + remarks', async (d) => {
  await getDocs(query(col(d, 'resultSummaries'), where('examId', '==', 'ex1'), where('version', '==', 1), orderBy('studentName')));
  await getDocs(query(col(d, 'examRemarks'), where('examId', '==', 'ex1')));
});
T('teacher: parent-message contact setting', async (d) => { await getDoc(bdoc(d, 'messageContacts', 'st1')); });

// ---- PARENT ---------------------------------------------------------------
const P = 'sw-p';
T('parent: children (links lookup + child docs)', async (d) => {
  await getDocs(query(collectionGroup(d, 'parentLinks'), where('schoolId', '==', A), where('parentId', '==', 'pr1')));
  await getDoc(bdoc(d, 'students', 'stu1')); await getDoc(bdoc(d, 'parents', 'pr1')); await getDoc(bdoc(d, 'parentAccess', 'pr1'));
}, P);
T('parent: fees (invoices, payments, assignments, invoice payments, receipt)', async (d) => {
  await getDocs(query(col(d, 'invoices'), where('studentId', '==', 'stu1'), orderBy('dueDateKey', 'desc'), limit(200)));
  await getDocs(query(col(d, 'payments'), where('studentId', '==', 'stu1'), orderBy('paymentDateKey', 'desc')));
  await getDocs(query(col(d, 'studentFeeAssignments'), where('studentId', '==', 'stu1'), where('academicYearId', '==', Y)));
  await getDocs(query(col(d, 'payments'), where('invoiceId', '==', 'inv1'), where('studentId', '==', 'stu1')));
  await getDoc(bdoc(d, 'invoices', 'inv1')); await getDoc(bdoc(d, 'receipts', 'rc1'));
}, P);
T('parent: leave (list, detail history, types, apply form year)', async (d) => {
  await getDocs(query(col(d, 'leaveApplications'), where('subjectKind', '==', 'STUDENT'), where('subjectId', '==', 'stu1'), orderBy('createdAt', 'desc'), limit(100)));
  await getDoc(bdoc(d, 'leaveApplications', 'la1'));
  await getDocs(query(col(d, 'leaveHistory'), where('subjectKind', '==', 'STUDENT'), where('subjectId', '==', 'stu1'), where('applicationId', '==', 'la1'), orderBy('revision')));
  await getDocs(query(col(d, 'leaveTypes'), where('kind', '==', 'STUDENT'), limit(200)));
  await getDoc(bdoc(d, 'academicYears', Y));
}, P);
T('parent: timetable (timetables, entries, substitutions)', async (d) => {
  await getDocs(query(col(d, 'timetables'), where('academicYearId', '==', Y), where('classId', '==', C), where('sectionId', '==', S), where('status', '==', 'PUBLISHED')));
  await getDocs(query(col(d, 'timetableEntries'), where('academicYearId', '==', Y), where('classId', '==', C), where('sectionId', '==', S), where('live', '==', true)));
  await getDocs(query(col(d, 'substitutions'), where('classId', '==', C), where('sectionId', '==', S), where('status', '==', 'ACTIVE'), where('dateKey', '>=', '2026-10-01'), where('dateKey', '<=', '2026-10-31')));
}, P);
T('parent: homework (list, submissions, revisions, detail docs)', async (d) => {
  await getDocs(query(col(d, 'homework'), where('academicYearId', '==', Y), where('classId', '==', C), where('sectionId', '==', S), where('status', 'in', ['PUBLISHED', 'CLOSED']), orderBy('dueDateKey', 'desc')));
  await getDoc(bdoc(d, 'homework', 'hw1'));
  await getDocs(query(col(d, 'homeworkSubmissions'), where('studentId', '==', 'stu1'), where('academicYearId', '==', Y)));
  await getDoc(bdoc(d, 'homeworkSubmissions', 'hw1__stu1'));
  await getDocs(query(col(d, 'homeworkRevisions'), where('homeworkId', '==', 'hw1'), where('studentId', '==', 'stu1')));
}, P);
T('parent: results (exams, subjects, result doc)', async (d) => {
  await getDocs(query(col(d, 'examinations'), where('academicYearId', '==', Y), where('classId', '==', C), where('status', '==', 'PUBLISHED'), where('sectionId', '==', null)));
  await getDocs(query(col(d, 'examinations'), where('academicYearId', '==', Y), where('classId', '==', C), where('status', '==', 'PUBLISHED'), where('sectionId', '==', S)));
  await getDoc(bdoc(d, 'examinations', 'ex1'));
  await getDocs(query(col(d, 'examinationSubjects'), where('examId', '==', 'ex1')));
  await getDoc(bdoc(d, 'resultSummaries', 'ex1__stu1__v1'));
}, P);
T('parent: messages (contacts for my child\'s section, contact doc)', async (d) => {
  await getDocs(query(col(d, 'messageContacts'), where('enabled', '==', true), where('sectionKeys', 'array-contains', `${C}__${S}`)));
  await getDoc(bdoc(d, 'messageContacts', 'st1'));
}, P);

for (const r of rows) {
  test(`${r.label}`, async () => {
    await assertSucceeds(r.fn(as(r.role)));
  });
}

// ---- the same reads must stay denied for an outsider -------------------------
test('negative: a teacher of nowhere / unrelated parent get none of the above', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'users', 'sw-out'), { schoolId: 'sw-other', branchId: 'x', name: 'O', email: 'o@x.com', role: 'TEACHER', status: 'ACTIVE', linkedParentId: null, ...base });
    await setDoc(doc(c.firestore(), 'users', 'sw-p2'), { schoolId: A, branchId: N, name: 'P2', email: 'p2@x.com', role: 'PARENT', status: 'ACTIVE', linkedParentId: 'pr2', ...base });
  });
  const o = as('sw-out');
  await assertFails(getDocs(query(col(o, 'students'), where('status', '==', 'ACTIVE'), limit(5))));
  await assertFails(getDocs(query(col(o, 'announcements'), where('status', '==', 'PUBLISHED'), limit(5))));
  const p2 = as('sw-p2');
  await assertFails(getDoc(bdoc(p2, 'students', 'stu1')));
  await assertFails(getDocs(query(col(p2, 'invoices'), where('studentId', '==', 'stu1'), limit(5))));
  await assertFails(getDocs(query(col(p2, 'homework'), where('academicYearId', '==', Y), where('classId', '==', C), where('sectionId', '==', S), where('status', 'in', ['PUBLISHED', 'CLOSED']))));
  await assertFails(getDoc(bdoc(p2, 'homeworkSubmissions', 'hw1__stu1')));
});

// Marks review lists every sheet of an exam; that is an approver screen
// (`approveResults`, not a teacher permission), so a teacher is — correctly —
// refused the unconstrained list and can only open the sheets they are assigned.
test('negative: a teacher cannot list all marks sheets of an exam', async () => {
  await assertFails(getDocs(query(col(as('sw-t'), 'marksSheets'), where('examId', '==', 'ex1'))));
  await assertSucceeds(getDocs(query(col(as('sw-admin'), 'marksSheets'), where('examId', '==', 'ex1'))));
});

// ---- teacher scope (assigned sections only) -----------------------------------
test('negative: a teacher is refused every branch-wide student/parent read', async () => {
  const d = as('sw-t');
  await assertFails(getDocs(query(col(d, 'students'), where('status', '==', 'ACTIVE'), orderBy('displayNameLower'), limit(26))));
  await assertFails(getCountFromServer(query(col(d, 'students'), where('status', '==', 'ACTIVE'))));
  await assertFails(getDocs(query(col(d, 'students'), where('currentClassId', '==', C)))); // class without section
  await assertFails(getDocs(query(col(d, 'students'), where('currentClassId', '==', 'c9'), where('currentSectionId', '==', 'sz')))); // not assigned
  await assertFails(getDocs(query(col(d, 'parents'), orderBy('displayNameLower'), limit(26))));
  await assertFails(getDocs(query(collectionGroup(d, 'parentLinks'), where('schoolId', '==', A), where('branchId', '==', N), where('parentId', '==', 'pr1'))));
  await assertFails(getDocs(query(collectionGroup(d, 'academicRecords'), where('schoolId', '==', A), where('branchId', '==', N), where('academicYearId', '==', Y))));
  await assertFails(getDocs(query(col(d, 'leaveCalendar'), where('subjectKind', '==', 'STUDENT'), where('endDateKey', '>=', '2026-10-01'))));
  await assertFails(getDocs(col(d, 'parentAccess')));
});

test('negative: another teacher (no assignment, or another section) reads none of my students', async () => {
  const d = as('sw-t2'); // has a staff record but no teacherAccess
  await assertFails(getDoc(bdoc(d, 'students', 'stu1')));
  await assertFails(getDocs(query(col(d, 'students'), where('currentClassId', '==', C), where('currentSectionId', '==', S))));
  await assertFails(getDoc(bdoc(d, 'parents', 'pr1')));
  await assertFails(getDocs(collection(d, ...nb(), 'students', 'stu1', 'parentLinks')));
  await assertFails(getDoc(bdoc(d, 'teacherAccess', 'sw-t'))); // not someone else's index
});

test('a teacher cannot write their own teacherAccess (server only), nor can an admin client', async () => {
  const body = { schoolId: A, branchId: N, staffId: 'st1', userId: 'sw-t', sectionKeys: [`${C}__${S}`, 'c9__sz'], scopes: [], updatedAt: serverTimestamp() };
  await assertFails(setDoc(bdoc(as('sw-t'), 'teacherAccess', 'sw-t'), body));
  await assertFails(setDoc(bdoc(as('sw-admin'), 'teacherAccess', 'sw-t'), body));
  await assertSucceeds(getDoc(bdoc(as('sw-t'), 'teacherAccess', 'sw-t'))); // own index is readable
  await assertSucceeds(getDoc(bdoc(as('sw-admin'), 'teacherAccess', 'sw-t')));
});

test('finance and admins keep branch-wide student/parent reads', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'users', 'sw-fin'), { schoolId: A, branchId: N, name: 'F', email: 'f@x.com', role: 'FINANCE', status: 'ACTIVE', linkedParentId: null, ...base });
  });
  for (const uid of ['sw-admin', 'sw-fin']) {
    const d = as(uid);
    await assertSucceeds(getDocs(query(col(d, 'students'), where('status', '==', 'ACTIVE'), orderBy('displayNameLower'), limit(26))));
    await assertSucceeds(getDocs(query(col(d, 'parents'), orderBy('displayNameLower'), limit(26))));
  }
});

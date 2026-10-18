// Firestore security-rules tests for Milestone 10 — examinations, marks and
// results (see ../firestore.rules and
// ../docs/milestone-10-examinations-results-report-cards.md).
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, increment, query, orderBy, limit, serverTimestamp, setDoc, updateDoc, deleteDoc, where, writeBatch,
} from 'firebase/firestore';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

let A = 'ex-a';
let B = 'ex-b';
let counter = 0;
const NORTH = 'north';
const SOUTH = 'south';
const YEAR = 'y1';
const EXAM = `${YEAR}__c5__sa__half-yearly`;

const branch = (s, b) => ['schools', s, 'branches', b];
const seed = (fn) => testEnv.withSecurityRulesDisabled(async (c) => fn(c.firestore()));
const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: uid });
const col = (db, name, b = NORTH, s = A) => collection(db, ...branch(s, b), name);
const ref = (db, name, id, b = NORTH, s = A) => doc(db, ...branch(s, b), name, id);

// -------------------------------------------------------------- builders
function examDoc({ uid = 'ex-admin', status = 'DRAFT', overrides = {} } = {}) {
  const d = {
    schoolId: A, branchId: NORTH, academicYearId: YEAR, classId: 'c5', sectionId: 'sa', classLabel: 'Class 5 – A',
    name: 'Half-yearly', nameSlug: 'half-yearly', description: '', type: 'HALF_YEARLY', schemeId: 'gs1',
    startDateKey: '2026-09-01', endDateKey: '2026-09-10', instructions: '', status, revision: 1, lastEvent: 'CREATED',
    subjectCount: 0, sheetCount: 0, approvedSheets: 0, resultVersion: 0, resultCount: 0, resultsWritten: 0,
    schemeSnapshot: null, finalizedBy: null, publishedBy: null, publishedAt: null, ...audit(uid), ...overrides,
  };
  // sectionScope is the section id, or 'ALL' for a class-wide examination.
  return { ...d, sectionScope: overrides.sectionScope ?? d.sectionId ?? 'ALL' };
}
const hist = ({ id = EXAM, rev, event, toStatus, uid, note = null }) => ({
  schoolId: A, branchId: NORTH, academicYearId: YEAR, examId: id, classId: 'c5', revision: rev, event, toStatus,
  actorId: uid, actorName: 'X', note, at: serverTimestamp(),
});
function subjectDoc({ subject = 'math', uid = 'ex-admin', overrides = {} } = {}) {
  return {
    schoolId: A, branchId: NORTH, examId: EXAM, subjectId: subject, academicYearId: YEAR, classId: 'c5', subjectName: subject,
    maxMarks: 100, passMarks: 35, weightage: 1, dateKey: '2026-09-02', startMin: 540, endMin: 600,
    theoryMax: null, practicalMax: null, revision: 1, ...audit(uid), ...overrides,
  };
}
const sheetId = (subject = 'math', section = 'sa') => `${EXAM}__${subject}__${section}`;
const sheetDoc = ({ subject = 'math', section = 'sa', uid = 't1', overrides = {} } = {}) => ({
  schoolId: A, branchId: NORTH, examId: EXAM, subjectId: subject, sectionId: section, classId: 'c5', academicYearId: YEAR,
  status: 'DRAFT', revision: 1, lastEvent: 'SAVED', rosterCount: 2, submittedBy: null, submittedAt: null,
  approvedBy: null, approvedAt: null, reviewNote: null, ...audit(uid), ...overrides,
});
const sheetHist = ({ sid, rev, event, toStatus, uid }) => ({
  schoolId: A, branchId: NORTH, examId: EXAM, sheetId: sid, revision: rev, event, toStatus, actorId: uid, actorName: 'X', note: null, at: serverTimestamp(),
});
const entryDoc = ({ subject = 'math', student = 's1', section = 'sa', uid = 't1', status = 'ENTERED', marks = 50, overrides = {} } = {}) => ({
  schoolId: A, branchId: NORTH, examId: EXAM, subjectId: subject, sheetId: sheetId(subject, section), sectionId: section,
  classId: 'c5', academicYearId: YEAR, studentId: student, studentName: student, rollNumber: null,
  status, marks: status === 'ENTERED' ? marks : null, theory: null, practical: null, remark: '', revision: 1, ...audit(uid), ...overrides,
});
const revDoc = ({ entryId, rev = 1, status = 'ENTERED', marks = 50, uid = 't1' }) => ({
  schoolId: A, branchId: NORTH, examId: EXAM, subjectId: 'math', entryId, studentId: 's1', revision: rev, status, marks, remark: '',
  actorId: uid, actorName: 'X', at: serverTimestamp(),
});

/** Create the sheet (if `withSheet`) and the entries, each with its revision record. */
function saveEntries(db, uid, entries, { withSheet = true, subject = 'math', section = 'sa' } = {}) {
  const b = writeBatch(db);
  const sid = sheetId(subject, section);
  if (withSheet) {
    b.set(ref(db, 'marksSheets', sid), sheetDoc({ subject, section, uid }));
    b.set(ref(db, 'marksSheetHistory', `${sid}__1`), sheetHist({ sid, rev: 1, event: 'SAVED', toStatus: 'DRAFT', uid }));
  }
  for (const e of entries) {
    const id = `${sid}__${e.studentId}`;
    b.set(ref(db, 'marksEntries', id), e);
    b.set(ref(db, 'marksRevisions', `${id}__1`), revDoc({ entryId: id, status: e.status, marks: e.marks, uid }));
  }
  return b;
}

function examStatus(db, uid, patch, { rev, event, toStatus, note = null, extra = [] }) {
  const b = writeBatch(db);
  b.update(ref(db, 'examinations', EXAM), { revision: rev, lastEvent: event, status: toStatus, ...stamp(uid), ...patch });
  b.set(ref(db, 'examHistory', `${EXAM}__${rev}`), hist({ rev, event, toStatus, uid, note }));
  for (const [coll, id, data] of extra) b.set(ref(db, coll, id), data);
  return b;
}

async function seedWorld({ status = 'IN_PROGRESS', exam = {}, sheets = true } = {}) {
  counter += 1;
  A = `ex-a-${counter}`;
  B = `ex-b-${counter}`;
  await seed(async (db) => {
    for (const s of [A, B]) {
      await setDoc(doc(db, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      for (const b of s === A ? [NORTH, SOUTH] : [NORTH]) await setDoc(doc(db, ...branch(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'ex-admin': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'ex-admin-b': { schoolId: B, branchId: NORTH, role: 'SCHOOL_ADMIN' },
      'ex-br-north': { schoolId: A, branchId: NORTH, role: 'BRANCH_ADMIN' },
      'ex-br-south': { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' },
      't1': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      't2': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      't3': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      't-south': { schoolId: A, branchId: SOUTH, role: 'TEACHER' },
      'ex-fin': { schoolId: A, branchId: NORTH, role: 'FINANCE' },
      'p1': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'par1' },
      'p2': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'par2' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, 'users', uid), { branchId: null, name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    const n = branch(A, NORTH);
    for (const [staffId, uid] of [['st1', 't1'], ['st2', 't2'], ['st3', 't3']]) {
      await setDoc(doc(db, ...n, 'staff', staffId), { schoolId: A, branchId: NORTH, userId: uid, status: 'ACTIVE', isTeacher: true, ...audit('seed') });
    }
    for (const sec of ['sa', 'sb']) {
      await setDoc(doc(db, ...n, 'academicYears', YEAR, 'classes', 'c5', 'sections', sec), { schoolId: A, branchId: NORTH, name: sec, status: 'ACTIVE', ...audit('seed') });
    }
    for (const sub of ['math', 'sci']) {
      await setDoc(doc(db, ...n, 'academicYears', YEAR, 'classes', 'c5', 'classSubjects', sub), { schoolId: A, branchId: NORTH, subjectId: sub, status: 'ACTIVE', ...audit('seed') });
    }
    const slot = (key, teacher) => setDoc(doc(db, ...n, 'assignmentSlots', key), {
      schoolId: A, branchId: NORTH, assignmentId: `a-${key}`, teacherStaffId: teacher, createdBy: 'seed', createdAt: serverTimestamp(),
    });
    await slot(`${YEAR}__c5__sa__math`, 'st1');
    await slot(`${YEAR}__c5__sa__sci`, 'st2');
    await slot(`${YEAR}__c5__sa__CLASS_TEACHER`, 'st3');
    const student = (id, section, st = 'ACTIVE') => setDoc(doc(db, ...n, 'students', id), {
      schoolId: A, branchId: NORTH, status: st, currentAcademicYearId: YEAR, currentClassId: 'c5', currentSectionId: section, ...audit('seed'),
    });
    await student('s1', 'sa');
    await student('s2', 'sa');
    await student('s3', 'sb');
    await student('s-left', 'sa', 'LEFT');
    const link = (studentId, parentId) => setDoc(doc(db, ...n, 'students', studentId, 'parentLinks', parentId), {
      schoolId: A, branchId: NORTH, studentId, parentId, canAccessPortal: true, status: 'ACTIVE', ...audit('seed'),
    });
    await link('s1', 'par1');
    await link('s2', 'par2');

    // Milestone 12A: the family-access index the rules read for class-specific content.
    const access = (parentId, sections) => setDoc(doc(db, ...n, 'parentAccess', parentId), {
      schoolId: A, branchId: NORTH, parentId, classKeys: ['c5'], sectionKeys: sections.map((s) => `c5__${s}`),
      updatedAt: serverTimestamp(), updatedBy: 'seed',
    });
    await access('par1', ['sa']);
    await access('par2', ['sa']);

    const sub = ['DRAFT', 'SCHEDULED'].includes(status) ? 0 : 2;
    await setDoc(ref(db, 'examinations', EXAM), examDoc({ status, overrides: { subjectCount: sub, sheetCount: sub ? 2 : 0, ...exam } }));
    if (sub) {
      await setDoc(ref(db, 'examinationSubjects', `${EXAM}__math`), subjectDoc({ subject: 'math' }));
      await setDoc(ref(db, 'examinationSubjects', `${EXAM}__sci`), subjectDoc({ subject: 'sci', overrides: { theoryMax: 70, practicalMax: 30 } }));
    }
    if (sheets && status === 'IN_PROGRESS') {
      await setDoc(ref(db, 'marksSheets', sheetId('math')), sheetDoc({ subject: 'math' }));
    }
  });
}

const denied = (n, p) => assertFails(p).catch((e) => { throw new Error("denial case " + n + " was allowed: " + e.message); });

// ===================================================================== TESTS

test('Tenant and branch isolation: other school, other branch and finance cannot read or write', async () => {
  await seedWorld();
  for (const uid of ['ex-admin-b', 'ex-br-south', 't-south', 'ex-fin']) {
    const db = asUser(uid);
    await assertFails(getDoc(ref(db, 'examinations', EXAM)));
    await assertFails(getDocs(col(db, 'examinations')));
    await assertFails(updateDoc(ref(db, 'examinations', EXAM), { name: 'hijack', ...stamp(uid) }));
    await assertFails(getDocs(query(col(db, 'marksEntries'), where('examId', '==', EXAM))));
  }
});

test('Examination configuration: managers only, valid, deterministic id so no duplicates', async () => {
  await seedWorld();
  const make = (db, uid, o = {}, id = `${YEAR}__c5__sb__unit-test-1`) => {
    const b = writeBatch(db);
    b.set(ref(db, 'examinations', id), examDoc({ uid, overrides: { sectionId: 'sb', name: 'Unit test 1', nameSlug: 'unit-test-1', ...o } }));
    b.set(ref(db, 'examHistory', `${id}__1`), { ...hist({ id, rev: 1, event: 'CREATED', toStatus: 'DRAFT', uid }) });
    return b;
  };
  for (const uid of ['t1', 'p1', 'ex-fin', 'ex-admin-b']) await assertFails(make(asUser(uid), uid).commit());
  const admin = asUser('ex-br-north');
  await assertFails(make(admin, 'ex-br-north', { endDateKey: '2026-08-01' }).commit()); // ends before it starts
  await assertFails(make(admin, 'ex-br-north', { name: 'ab' }).commit());
  await assertFails(make(admin, 'ex-br-north', { type: 'ONLINE' }).commit());
  await assertFails(make(admin, 'ex-br-north', { status: 'PUBLISHED' }).commit());
  await assertFails(make(admin, 'ex-br-north', { subjectCount: 3 }).commit());
  await assertFails(make(admin, 'ex-br-north', { sectionId: 'nope' }).commit()); // section does not exist
  await assertFails(make(admin, 'ex-br-north', {}, `${YEAR}__c5__sb__made-up-id`).commit()); // id does not match scope+name
  await assertSucceeds(make(admin, 'ex-br-north').commit());
  // the same scope and name again is a duplicate
  await assertFails(make(admin, 'ex-br-north').commit());
});

test('Subject configuration: bounds, components, class relationship and the counter move together', async () => {
  await seedWorld({ status: 'DRAFT' });
  const admin = asUser('ex-admin');
  const add = (subject, o = {}, bump = 1) => {
    const b = writeBatch(admin);
    b.set(ref(admin, 'examinationSubjects', `${EXAM}__${subject}`), subjectDoc({ subject, overrides: o }));
    b.update(ref(admin, 'examinations', EXAM), { subjectCount: bump, ...stamp('ex-admin') });
    return b;
  };
  await denied(1, add('hist', {}, 1).commit()); // not a subject of the class
  await denied(2, add('math', { maxMarks: 0 }).commit());
  await denied(3, add('math', { maxMarks: 100, passMarks: 101 }).commit());
  await denied(4, add('math', { weightage: 0 }).commit());
  await denied(5, add('math', { theoryMax: 60, practicalMax: 30 }).commit()); // 90 != 100
  await denied(6, add('math', { startMin: 600, endMin: 540 }).commit());
  await denied(7, add('math', {}, 5).commit()); // counter jump
  for (const uid of ['t1', 'p1']) {
    const udb = asUser(uid);
    const b = writeBatch(udb);
    b.set(ref(udb, 'examinationSubjects', `${EXAM}__math`), subjectDoc({ uid }));
    await assertFails(b.commit());
  }
  await assertSucceeds(add('math', { theoryMax: 70, practicalMax: 30 }).commit());
});

test('Workflow transitions: order, preconditions, reasons, and who may', async () => {
  await seedWorld({ status: 'DRAFT' });
  const admin = asUser('ex-admin');
  // cannot schedule with no subjects, nor jump states
  await assertFails(examStatus(admin, 'ex-admin', {}, { rev: 2, event: 'SCHEDULED', toStatus: 'SCHEDULED' }).commit());
  await assertFails(examStatus(admin, 'ex-admin', { sheetCount: 2 }, { rev: 2, event: 'STARTED', toStatus: 'IN_PROGRESS' }).commit());
  await assertFails(examStatus(admin, 'ex-admin', {}, { rev: 2, event: 'PUBLISHED', toStatus: 'PUBLISHED' }).commit());
  // cancellation needs a reason
  await assertFails(examStatus(admin, 'ex-admin', {}, { rev: 2, event: 'CANCELLED', toStatus: 'CANCELLED' }).commit());
  await assertSucceeds(examStatus(admin, 'ex-admin', {}, { rev: 2, event: 'CANCELLED', toStatus: 'CANCELLED', note: 'Held next term' }).commit());
  // a cancelled examination goes nowhere
  await assertFails(examStatus(admin, 'ex-admin', {}, { rev: 3, event: 'SCHEDULED', toStatus: 'SCHEDULED' }).commit());
  for (const uid of ['t1', 'p1']) {
    await assertFails(examStatus(asUser(uid), uid, {}, { rev: 3, event: 'EDITED', toStatus: 'CANCELLED', note: 'x y z' }).commit());
  }
});

test('Finalisation needs every sheet approved; publication needs every result written and its notice; published cannot be cancelled', async () => {
  await seedWorld({ status: 'IN_PROGRESS', exam: { approvedSheets: 1 } });
  const admin = asUser('ex-admin');
  const finalize = (patch = {}) => examStatus(admin, 'ex-admin', {
    resultVersion: 1, resultCount: 2, resultsWritten: 0, schemeSnapshot: { schemeId: 'gs1' }, finalizedBy: 'ex-admin', ...patch,
  }, { rev: 2, event: 'FINALIZED', toStatus: 'COMPLETED' });
  await assertFails(finalize().commit()); // 1 of 2 sheets approved
  await seed(async (db) => updateDoc(ref(db, 'examinations', EXAM), { approvedSheets: 2 }));
  await assertFails(finalize({ resultVersion: 5 }).commit()); // version must advance by one
  await assertFails(finalize({ schemeSnapshot: null }).commit()); // snapshot required
  await assertFails(finalize({ resultCount: 0 }).commit());
  await assertFails(finalize({ resultsWritten: 1 }).commit());
  await assertFails(examStatus(asUser('ex-br-south'), 'ex-br-south', {}, { rev: 2, event: 'FINALIZED', toStatus: 'COMPLETED' }).commit());
  await assertSucceeds(finalize().commit());

  const publish = (notice = true) => examStatus(admin, 'ex-admin', { publishedBy: 'ex-admin', publishedAt: serverTimestamp() },
    {
      rev: 3, event: 'PUBLISHED', toStatus: 'PUBLISHED',
      extra: notice ? [['broadcastNotices', `${EXAM}__PUBLISHED__1`, {
        schoolId: A, branchId: NORTH, type: 'RESULT_PUBLISHED', audienceKind: 'SECTION', classId: 'c5', sectionId: 'sa',
        title: 'Results published', body: 'Half-yearly', refType: 'EXAM', refId: EXAM, revision: 1, createdBy: 'ex-admin', createdAt: serverTimestamp(),
      }]] : [],
    });
  await assertFails(publish().commit()); // results not written yet (0 of 2)
  await assertFails(updateDoc(ref(admin, 'examinations', EXAM), { resultsWritten: 3, ...stamp('ex-admin') })); // beyond the count
  await assertSucceeds(updateDoc(ref(admin, 'examinations', EXAM), { resultsWritten: 2, ...stamp('ex-admin') }));
  await assertFails(publish(false).commit()); // no notice
  await assertSucceeds(publish().commit());
  // a published examination: no cancellation, no config edits, no result edits
  await assertFails(examStatus(admin, 'ex-admin', {}, { rev: 4, event: 'CANCELLED', toStatus: 'CANCELLED', note: 'oops oops' }).commit());
  await assertFails(updateDoc(ref(admin, 'examinations', EXAM), { name: 'Renamed', revision: 4, lastEvent: 'EDITED', ...stamp('ex-admin') }));
  // withdrawing needs a reason, then reopening needs one too
  await assertFails(examStatus(admin, 'ex-admin', {}, { rev: 4, event: 'WITHDRAWN', toStatus: 'WITHDRAWN' }).commit());
  await assertSucceeds(examStatus(admin, 'ex-admin', {}, { rev: 4, event: 'WITHDRAWN', toStatus: 'WITHDRAWN', note: 'Marks misread' }).commit());
});

test('Marks entry authority: only the assigned teacher (or an admin), only enrolled students, only in marks entry', async () => {
  await seedWorld();
  const e = (o = {}) => entryDoc({ uid: 't1', ...o });
  // not the maths teacher / no assignment / another branch
  for (const uid of ['t2', 't3', 't-south', 'p1', 'ex-fin', 'ex-admin-b']) {
    await assertFails(saveEntries(asUser(uid), uid, [entryDoc({ uid })], { withSheet: false }).commit());
  }
  const t1 = asUser('t1');
  // a subject they do not teach
  await assertFails(saveEntries(t1, 't1', [e({ subject: 'sci' })], { subject: 'sci' }).commit());
  // students that are not enrolled in this class+section / left school
  await assertFails(saveEntries(t1, 't1', [e({ student: 's3' })], { withSheet: false }).commit());
  await assertFails(saveEntries(t1, 't1', [e({ student: 's-left' })], { withSheet: false }).commit());
  await assertFails(saveEntries(t1, 't1', [e({ student: 'nobody' })], { withSheet: false }).commit());
  // a section the exam does not cover
  await assertFails(saveEntries(t1, 't1', [e({ section: 'sb', student: 's3' })], { section: 'sb' }).commit());
  // the maths teacher, an enrolled student
  await assertSucceeds(saveEntries(t1, 't1', [e({ student: 's1', marks: 0 })], { withSheet: false }).commit());
  // an admin may enter on the teacher's behalf
  await assertSucceeds(saveEntries(asUser('ex-br-north'), 'ex-br-north', [entryDoc({ uid: 'ex-br-north', student: 's2' })], { withSheet: false }).commit());
});

test('Marks values: bounds, zero vs absent vs exempted vs pending, components, remarks', async () => {
  await seedWorld();
  const t1 = asUser('t1');
  const put = (o) => saveEntries(t1, 't1', [entryDoc({ uid: 't1', ...o })], { withSheet: false });
  await assertFails(put({ marks: 101 }).commit());
  await assertFails(put({ marks: -1 }).commit());
  await assertFails(put({ marks: null }).commit()); // ENTERED needs marks
  await assertFails(put({ status: 'ABSENT', overrides: { marks: 10 } }).commit()); // absent carries no marks
  await assertFails(put({ status: 'EXEMPTED', overrides: { marks: 0 } }).commit());
  await assertFails(put({ status: 'LATE' }).commit());
  await assertFails(put({ overrides: { remark: 'x'.repeat(201) } }).commit());
  await assertFails(put({ overrides: { theory: 10, practical: 5 } }).commit()); // maths has no components
  await assertSucceeds(put({ marks: 0 }).commit()); // zero is a real score
  await assertSucceeds(put({ student: 's2', status: 'ABSENT' }).commit());
  // components: theory + practical must equal marks and respect their maxima
  const t2 = asUser('t2');
  const sci = (o) => saveEntries(t2, 't2', [entryDoc({ uid: 't2', subject: 'sci', ...o })], { subject: 'sci' });
  await assertFails(sci({ marks: 85, overrides: { theory: 60, practical: 25, marks: 90 } }).commit());
  await assertFails(sci({ marks: 85, overrides: { theory: 75, practical: 10, marks: 85 } }).commit());
  await assertFails(sci({ marks: 85, overrides: { theory: null, practical: null } }).commit());
  await assertSucceeds(sci({ marks: 85, overrides: { theory: 60, practical: 25, marks: 85 } }).commit());
});

test('Five entries in one commit fit the rules\' evaluation budget', async () => {
  await seedWorld();
  await seed(async (db) => {
    for (const id of ['s4', 's5', 's6']) {
      await setDoc(ref(db, 'students', id), { schoolId: A, branchId: NORTH, status: 'ACTIVE', currentAcademicYearId: YEAR, currentClassId: 'c5', currentSectionId: 'sa', ...audit('seed') });
    }
  });
  const entries = ['s1', 's2', 's4', 's5', 's6'].map((s, i) => entryDoc({ uid: 't1', student: s, marks: 10 * (i + 1) }));
  await assertSucceeds(saveEntries(asUser('t1'), 't1', entries, { withSheet: false }).commit());
});

test('Review workflow: submit locks entry; approval by someone else; counter moves with it; teachers cannot approve', async () => {
  await seedWorld();
  const t1 = asUser('t1');
  await assertSucceeds(saveEntries(t1, 't1', [entryDoc({ uid: 't1' })], { withSheet: false }).commit());
  const sid = sheetId('math');
  const step = (db, uid, patch, rev, event, toStatus, extra = null) => {
    const b = writeBatch(db);
    b.update(ref(db, 'marksSheets', sid), { status: toStatus, revision: rev, lastEvent: event, ...stamp(uid), ...patch });
    if (extra) b.update(ref(db, 'examinations', EXAM), { ...extra, ...stamp(uid) });
    b.set(ref(db, 'marksSheetHistory', `${sid}__${rev}`), sheetHist({ sid, rev, event, toStatus, uid }));
    return b;
  };
  // another teacher cannot submit this sheet
  await assertFails(step(asUser('t2'), 't2', { submittedBy: 't2', submittedAt: serverTimestamp() }, 2, 'SUBMITTED', 'SUBMITTED').commit());
  await assertSucceeds(step(t1, 't1', { submittedBy: 't1', submittedAt: serverTimestamp() }, 2, 'SUBMITTED', 'SUBMITTED').commit());
  // submitted: further entry edits are refused
  const edit = writeBatch(t1);
  edit.update(ref(t1, 'marksEntries', `${sid}__s1`), { marks: 99, revision: 2, ...stamp('t1') });
  edit.set(ref(t1, 'marksRevisions', `${sid}__s1__2`), revDoc({ entryId: `${sid}__s1`, rev: 2, marks: 99 }));
  await assertFails(edit.commit());
  // the teacher cannot approve; approval must move the counter
  await assertFails(step(t1, 't1', { approvedBy: 't1', approvedAt: serverTimestamp() }, 3, 'APPROVED', 'APPROVED', { approvedSheets: 1 }).commit());
  const badmin = asUser('ex-br-north');
  await assertFails(step(badmin, 'ex-br-north', { approvedBy: 'ex-br-north', approvedAt: serverTimestamp() }, 3, 'APPROVED', 'APPROVED').commit());
  await assertFails(step(asUser('ex-br-south'), 'ex-br-south', { approvedBy: 'ex-br-south', approvedAt: serverTimestamp() }, 3, 'APPROVED', 'APPROVED', { approvedSheets: 1 }).commit());
  await assertSucceeds(step(badmin, 'ex-br-north', { approvedBy: 'ex-br-north', approvedAt: serverTimestamp() }, 3, 'APPROVED', 'APPROVED', { approvedSheets: 1 }).commit());
  // returning needs a note and undoes the counter
  await assertFails(step(badmin, 'ex-br-north', { reviewNote: null, approvedBy: null, approvedAt: null }, 4, 'RETURNED', 'RETURNED', { approvedSheets: 0 }).commit());
  await assertFails(step(badmin, 'ex-br-north', { reviewNote: 'Check Q4', approvedBy: null, approvedAt: null }, 4, 'RETURNED', 'RETURNED').commit());
  await assertSucceeds(step(badmin, 'ex-br-north', { reviewNote: 'Check Q4', approvedBy: null, approvedAt: null }, 4, 'RETURNED', 'RETURNED', { approvedSheets: 0 }).commit());
});

test('A branch administrator who entered marks cannot approve them; a school administrator can', async () => {
  await seedWorld();
  const badmin = asUser('ex-br-north');
  await assertSucceeds(saveEntries(badmin, 'ex-br-north', [entryDoc({ uid: 'ex-br-north' })], { withSheet: false }).commit());
  const sid = sheetId('math');
  const go = (db, uid, patch, rev, event, toStatus, extra) => {
    const b = writeBatch(db);
    b.update(ref(db, 'marksSheets', sid), { status: toStatus, revision: rev, lastEvent: event, ...stamp(uid), ...patch });
    if (extra) b.update(ref(db, 'examinations', EXAM), { ...extra, ...stamp(uid) });
    b.set(ref(db, 'marksSheetHistory', `${sid}__${rev}`), sheetHist({ sid, rev, event, toStatus, uid }));
    return b;
  };
  await assertSucceeds(go(badmin, 'ex-br-north', { submittedBy: 'ex-br-north', submittedAt: serverTimestamp() }, 2, 'SUBMITTED', 'SUBMITTED').commit());
  await assertFails(go(badmin, 'ex-br-north', { approvedBy: 'ex-br-north', approvedAt: serverTimestamp() }, 3, 'APPROVED', 'APPROVED', { approvedSheets: 1 }).commit());
  const admin = asUser('ex-admin');
  await assertSucceeds(go(admin, 'ex-admin', { approvedBy: 'ex-admin', approvedAt: serverTimestamp() }, 3, 'APPROVED', 'APPROVED', { approvedSheets: 1 }).commit());
});

test('Results are create-only, version-matched and never edited or deleted', async () => {
  await seedWorld({ status: 'COMPLETED', exam: { resultVersion: 1, resultCount: 2, resultsWritten: 0, approvedSheets: 2, schemeSnapshot: { x: 1 } } });
  const admin = asUser('ex-admin');
  const result = (student, version = 1, o = {}) => ({
    schoolId: A, branchId: NORTH, examId: EXAM, examName: 'Half-yearly', studentId: student, studentName: student, version,
    academicYearId: YEAR, classId: 'c5', sectionId: 'sa', classLabel: 'Class 5 – A', status: 'FINAL',
    summary: { result: 'PASS' }, schemeSnapshot: { x: 1 }, attendance: null, teacherRemark: '', principalRemark: '',
    calculatedBy: 'ex-admin', calculatedAt: serverTimestamp(), ...o,
  });
  const put = (db, student, version, o) => setDoc(ref(db, 'resultSummaries', `${EXAM}__${student}__v${version}`), result(student, version, o));
  await assertFails(put(asUser('t1'), 's1', 1, { calculatedBy: 't1' }));
  await assertFails(put(asUser('p1'), 's1', 1, { calculatedBy: 'p1' }));
  await assertFails(put(admin, 's1', 2)); // not the version in force
  await assertFails(put(admin, 's1', 1, { summary: 'PASS' }));
  await assertSucceeds(put(admin, 's1', 1));
  // no replacement, no edit, no delete (even by the school admin)
  await assertFails(put(admin, 's1', 1, { summary: { result: 'FAIL' } }));
  await assertFails(updateDoc(ref(admin, 'resultSummaries', `${EXAM}__s1__v1`), { summary: { result: 'FAIL' } }));
  await assertFails(deleteDoc(ref(admin, 'resultSummaries', `${EXAM}__s1__v1`)));
  // not while the examination is back in marks entry
  await seed(async (db) => updateDoc(ref(db, 'examinations', EXAM), { status: 'IN_PROGRESS' }));
  await assertFails(put(admin, 's2', 1));
});

test('Parent access: only published results of a linked child, the version in force, by id', async () => {
  await seedWorld({ status: 'COMPLETED', exam: { resultVersion: 1, resultCount: 2, resultsWritten: 2, approvedSheets: 2, schemeSnapshot: { x: 1 } } });
  const mk = (student, version = 1) => ({
    schoolId: A, branchId: NORTH, examId: EXAM, examName: 'Half-yearly', studentId: student, studentName: student, version,
    academicYearId: YEAR, classId: 'c5', sectionId: 'sa', classLabel: 'Class 5 – A', status: 'FINAL',
    summary: { result: 'PASS' }, schemeSnapshot: { x: 1 }, attendance: null, teacherRemark: '', principalRemark: '',
    calculatedBy: 'ex-admin', calculatedAt: serverTimestamp(),
  });
  await seed(async (db) => {
    await setDoc(ref(db, 'resultSummaries', `${EXAM}__s1__v1`), mk('s1'));
    await setDoc(ref(db, 'resultSummaries', `${EXAM}__s2__v1`), mk('s2'));
    await setDoc(ref(db, 'resultSummaries', `${EXAM}__s1__v0`), mk('s1', 0));
  });
  const p1 = asUser('p1');
  const id = (s, v = 1) => `${EXAM}__${s}__v${v}`;
  // finalised but not published: nothing for families
  await assertFails(getDoc(ref(p1, 'resultSummaries', id('s1'))));
  await assertFails(getDoc(ref(p1, 'examinations', EXAM)));
  await seed(async (db) => updateDoc(ref(db, 'examinations', EXAM), { status: 'PUBLISHED' }));
  await assertSucceeds(getDoc(ref(p1, 'resultSummaries', id('s1'))));
  await assertSucceeds(getDoc(ref(p1, 'examinations', EXAM)));
  // the two query shapes the app issues: class-wide, and the child's own section
  const examQ = (db, section) => getDocs(query(col(db, 'examinations'), where('academicYearId', '==', YEAR), where('classId', '==', 'c5'),
    where('status', '==', 'PUBLISHED'), where('sectionScope', '==', section ?? 'ALL')));
  await assertSucceeds(examQ(p1, 'sa'));
  await assertSucceeds(examQ(p1, null));
  // M12A: another section of the class is not this family's, and the unpinned shape is unprovable
  await assertFails(examQ(p1, 'sb'));
  await assertFails(getDocs(query(col(p1, 'examinations'), where('academicYearId', '==', YEAR), where('classId', '==', 'c5'), where('status', '==', 'PUBLISHED'))));
  // another family's child, another version, a list, unrelated parents/roles
  await assertFails(getDoc(ref(p1, 'resultSummaries', id('s2'))));
  await assertFails(getDoc(ref(p1, 'resultSummaries', id('s1', 0))));
  await assertFails(getDocs(query(col(p1, 'resultSummaries'), where('examId', '==', EXAM), where('version', '==', 1))));
  await assertFails(getDocs(query(col(p1, 'examinations'), where('academicYearId', '==', YEAR))));
  await assertFails(getDoc(ref(asUser('ex-fin'), 'resultSummaries', id('s1'))));
  await assertSucceeds(getDoc(ref(asUser('p2'), 'resultSummaries', id('s2'))));
  await assertFails(getDoc(ref(asUser('p2'), 'resultSummaries', id('s1'))));
  // withdrawn: access stops at once
  await seed(async (db) => updateDoc(ref(db, 'examinations', EXAM), { status: 'WITHDRAWN' }));
  await assertFails(getDoc(ref(p1, 'resultSummaries', id('s1'))));
  // a parent can never see marks, sheets, remarks or history, and never writes
  for (const name of ['marksEntries', 'marksSheets', 'examRemarks', 'examHistory', 'marksRevisions', 'gradingSchemes']) {
    await assertFails(getDocs(col(p1, name)));
  }
  await assertFails(updateDoc(ref(p1, 'examinations', EXAM), { name: 'x', ...stamp('p1') }));
});

test('Teachers read only their own marks sheets; the app\'s query shapes are provable', async () => {
  await seedWorld();
  await assertSucceeds(saveEntries(asUser('t1'), 't1', [entryDoc({ uid: 't1' })], { withSheet: false }).commit());
  const pinned = (db) => getDocs(query(col(db, 'marksEntries'), where('examId', '==', EXAM), where('subjectId', '==', 'math'),
    where('sectionId', '==', 'sa'), where('classId', '==', 'c5'), where('academicYearId', '==', YEAR)));
  await assertSucceeds(pinned(asUser('t1')));
  await assertSucceeds(pinned(asUser('ex-br-north')));
  await assertFails(pinned(asUser('t2'))); // teaches science, not maths
  await assertFails(pinned(asUser('t3')));
  await assertFails(getDocs(query(col(asUser('t1'), 'marksEntries'), where('examId', '==', EXAM)))); // unpinned
  await assertSucceeds(getDocs(query(col(asUser('ex-admin'), 'marksEntries'), where('examId', '==', EXAM), orderBy('__name__'), limit(300))));
  await assertSucceeds(getDoc(ref(asUser('t1'), 'marksSheets', sheetId('math'))));
  await assertFails(getDoc(ref(asUser('t2'), 'marksSheets', sheetId('math'))));
  await assertSucceeds(getDocs(query(col(asUser('ex-admin'), 'marksSheets'), where('examId', '==', EXAM))));
  // examinations for the branch's teachers and managers
  const lists = query(col(asUser('t1'), 'examinations'), where('academicYearId', '==', YEAR), orderBy('startDateKey', 'desc'), limit(25));
  await assertSucceeds(getDocs(lists));
  await assertSucceeds(getDocs(query(col(asUser('ex-admin'), 'examinations'), where('academicYearId', '==', YEAR), where('classId', '==', 'c5'),
    where('status', '==', 'IN_PROGRESS'), orderBy('startDateKey', 'desc'), limit(25))));
  await assertSucceeds(getDocs(query(col(asUser('ex-admin'), 'examHistory'), where('examId', '==', EXAM))));
  await assertFails(getDocs(query(col(asUser('t1'), 'examHistory'), where('examId', '==', EXAM))));
});

test('Remarks: class teacher writes the teacher remark only; admins both; only during marks entry', async () => {
  await seedWorld();
  const remark = (uid, o = {}) => ({
    schoolId: A, branchId: NORTH, examId: EXAM, academicYearId: YEAR, classId: 'c5', sectionId: 'sa', studentId: 's1',
    teacherRemark: 'Hard working', principalRemark: '', ...stamp(uid), ...o,
  });
  const put = (uid, o) => setDoc(ref(asUser(uid), 'examRemarks', `${EXAM}__s1`), remark(uid, o));
  await assertSucceeds(put('t3', {})); // class teacher of sa
  await assertFails(put('t3', { principalRemark: 'Promoted' }));
  await assertFails(put('t1', {})); // subject teacher, not the class teacher
  await assertFails(put('p1', {}));
  await assertSucceeds(put('ex-br-north', { principalRemark: 'Well done' }));
  await assertSucceeds(put('t3', { principalRemark: 'Well done' })); // unchanged principal remark is fine
  await assertFails(put('t3', { principalRemark: 'Changed' }));
  await seed(async (db) => updateDoc(ref(db, 'examinations', EXAM), { status: 'COMPLETED', resultVersion: 1, resultCount: 1 }));
  await assertFails(put('ex-br-north', { principalRemark: 'Late edit' }));
});

test('Result notices are tied to the publish commit', async () => {
  await seedWorld({ status: 'COMPLETED', exam: { resultVersion: 1, resultCount: 2, resultsWritten: 2, approvedSheets: 2, schemeSnapshot: { x: 1 } } });
  const admin = asUser('ex-admin');
  const notice = (o = {}) => ({
    schoolId: A, branchId: NORTH, type: 'RESULT_PUBLISHED', audienceKind: 'SECTION', classId: 'c5', sectionId: 'sa',
    title: 'Results published', body: 'Half-yearly', refType: 'EXAM', refId: EXAM, revision: 1, createdBy: 'ex-admin', createdAt: serverTimestamp(), ...o,
  });
  const nid = `${EXAM}__PUBLISHED__1`;
  // a notice on its own (the examination is not published) is refused
  await assertFails(setDoc(ref(admin, 'broadcastNotices', nid), notice()));
  // wrong class / wrong revision inside the publish commit is refused
  const publish = (n) => examStatus(admin, 'ex-admin', { publishedBy: 'ex-admin', publishedAt: serverTimestamp() },
    { rev: 2, event: 'PUBLISHED', toStatus: 'PUBLISHED', extra: [['broadcastNotices', nid, n]] });
  await assertFails(publish(notice({ classId: 'c6' })).commit());
  await assertFails(publish(notice({ revision: 7 })).commit());
  await assertSucceeds(publish(notice()).commit());
  // a retry cannot write the same notice again (no duplicate notification)
  await assertFails(setDoc(ref(admin, 'broadcastNotices', nid), notice()));
  // families of the class can read it; a teacher forging one cannot create it
  await assertSucceeds(getDoc(ref(asUser('p1'), 'broadcastNotices', nid)));
  await assertFails(setDoc(ref(asUser('t1'), 'broadcastNotices', `${EXAM}__PUBLISHED__2`), notice({ createdBy: 't1', revision: 2 })));
});

test('Grading schemes: managers write; teachers read; parents and finance see nothing', async () => {
  await seedWorld();
  const scheme = (uid, o = {}) => ({
    schoolId: A, branchId: NORTH, name: 'Standard', description: '', bands: [{ grade: 'A', label: '', minPercent: 0, gradePoint: null }],
    passPercent: 33, overallPassPercent: null, decimals: 2, rounding: 'HALF_UP', absentPolicy: 'EXCLUDE', aggregate: 'TOTAL',
    rankingEnabled: false, status: 'ACTIVE', revision: 1, ...audit(uid), ...o,
  });
  await assertFails(setDoc(ref(asUser('t1'), 'gradingSchemes', 'g1'), scheme('t1')));
  await assertFails(setDoc(ref(asUser('ex-admin'), 'gradingSchemes', 'g1'), scheme('ex-admin', { decimals: 5 })));
  await assertFails(setDoc(ref(asUser('ex-admin'), 'gradingSchemes', 'g1'), scheme('ex-admin', { bands: [] })));
  await assertSucceeds(setDoc(ref(asUser('ex-admin'), 'gradingSchemes', 'g1'), scheme('ex-admin')));
  await assertSucceeds(getDoc(ref(asUser('t1'), 'gradingSchemes', 'g1')));
  for (const uid of ['p1', 'ex-fin', 'ex-admin-b']) await assertFails(getDoc(ref(asUser(uid), 'gradingSchemes', 'g1')));
  await assertFails(deleteDoc(ref(asUser('ex-admin'), 'gradingSchemes', 'g1')));
});

test('Once finalised or published, marks cannot be changed, replaced or re-approved', async () => {
  await seedWorld();
  const t1 = asUser('t1');
  await assertSucceeds(saveEntries(t1, 't1', [entryDoc({ uid: 't1' })], { withSheet: false }).commit());
  const sid = sheetId('math');
  const edit = () => {
    const b = writeBatch(t1);
    b.update(ref(t1, 'marksEntries', `${sid}__s1`), { marks: 99, revision: 2, ...stamp('t1') });
    b.set(ref(t1, 'marksRevisions', `${sid}__s1__2`), revDoc({ entryId: `${sid}__s1`, rev: 2, marks: 99 }));
    return b;
  };
  for (const status of ['COMPLETED', 'PUBLISHED', 'WITHDRAWN', 'CANCELLED']) {
    await seed(async (db) => updateDoc(ref(db, 'examinations', EXAM), { status }));
    await assertFails(edit().commit());
    // not even an administrator
    const admin = asUser('ex-admin');
    const b = writeBatch(admin);
    b.update(ref(admin, 'marksEntries', `${sid}__s1`), { marks: 99, revision: 2, ...stamp('ex-admin') });
    b.set(ref(admin, 'marksRevisions', `${sid}__s1__2`), revDoc({ entryId: `${sid}__s1`, rev: 2, marks: 99, uid: 'ex-admin' }));
    await assertFails(b.commit());
  }
  // entries can never be deleted
  await seed(async (db) => updateDoc(ref(db, 'examinations', EXAM), { status: 'IN_PROGRESS' }));
  await assertFails(deleteDoc(ref(asUser('ex-admin'), 'marksEntries', `${sid}__s1`)));
  await assertFails(deleteDoc(ref(asUser('ex-admin'), 'marksRevisions', `${sid}__s1__1`)));
  await assertSucceeds(edit().commit());
});

test('Gaps found by the mutation check: class, state, authority, counters, bounds, remarks', async () => {
  // a student of another class in a section that happens to share the id
  await seedWorld();
  await seed(async (db) => {
    await setDoc(ref(db, 'students', 's-c6'), { schoolId: A, branchId: NORTH, status: 'ACTIVE', currentAcademicYearId: YEAR, currentClassId: 'c6', currentSectionId: 'sa', ...audit('seed') });
  });
  await assertFails(saveEntries(asUser('t1'), 't1', [entryDoc({ uid: 't1', student: 's-c6' })], { withSheet: false }).commit());

  // sheet changes stop with marks entry: a teacher cannot submit after finalisation
  const t1 = asUser('t1');
  await assertSucceeds(saveEntries(t1, 't1', [entryDoc({ uid: 't1' })], { withSheet: false }).commit());
  await seed(async (db) => updateDoc(ref(db, 'examinations', EXAM), { status: 'PUBLISHED', resultVersion: 1, resultCount: 1, resultsWritten: 1 }));
  const sid = sheetId('math');
  const submit = writeBatch(t1);
  submit.update(ref(t1, 'marksSheets', sid), { status: 'SUBMITTED', revision: 2, lastEvent: 'SUBMITTED', submittedBy: 't1', submittedAt: serverTimestamp(), ...stamp('t1') });
  submit.set(ref(t1, 'marksSheetHistory', `${sid}__2`), sheetHist({ sid, rev: 2, event: 'SUBMITTED', toStatus: 'SUBMITTED', uid: 't1' }));
  await assertFails(submit.commit());
});

test('Only administrators change an examination, even with a correct history record', async () => {
  await seedWorld({ status: 'DRAFT', exam: { subjectCount: 1 } });
  for (const uid of ['t1', 't3', 'p1', 'ex-fin']) {
    await assertFails(examStatus(asUser(uid), uid, {}, { rev: 2, event: 'SCHEDULED', toStatus: 'SCHEDULED' }).commit());
  }
  await assertSucceeds(examStatus(asUser('ex-br-north'), 'ex-br-north', {}, { rev: 2, event: 'SCHEDULED', toStatus: 'SCHEDULED' }).commit());
});

test('A subject cannot be added without its counter, nor with a zero maximum', async () => {
  await seedWorld({ status: 'DRAFT' });
  const admin = asUser('ex-admin');
  const alone = writeBatch(admin);
  alone.set(ref(admin, 'examinationSubjects', `${EXAM}__math`), subjectDoc({ subject: 'math' }));
  await assertFails(alone.commit()); // no counter bump in the commit
  const zero = writeBatch(admin);
  zero.set(ref(admin, 'examinationSubjects', `${EXAM}__math`), subjectDoc({ subject: 'math', overrides: { maxMarks: 0, passMarks: null } }));
  zero.update(ref(admin, 'examinations', EXAM), { subjectCount: 1, ...stamp('ex-admin') });
  await assertFails(zero.commit());
  const neg = writeBatch(admin);
  neg.set(ref(admin, 'examinationSubjects', `${EXAM}__math`), subjectDoc({ subject: 'math', overrides: { maxMarks: -5, passMarks: null } }));
  neg.update(ref(admin, 'examinations', EXAM), { subjectCount: 1, ...stamp('ex-admin') });
  await assertFails(neg.commit());
});

test('A first remark by the class teacher cannot carry a principal remark', async () => {
  await seedWorld();
  const mk = (student, o = {}) => ({
    schoolId: A, branchId: NORTH, examId: EXAM, academicYearId: YEAR, classId: 'c5', sectionId: 'sa', studentId: student,
    teacherRemark: 'Hard working', principalRemark: '', ...stamp('t3'), ...o,
  });
  const t3 = asUser('t3');
  await assertFails(setDoc(ref(t3, 'examRemarks', `${EXAM}__s2`), mk('s2', { principalRemark: 'Promoted' })));
  await assertSucceeds(setDoc(ref(t3, 'examRemarks', `${EXAM}__s2`), mk('s2')));
});

test('Examination sectionScope must agree with sectionId, so a family filter can be trusted', async () => {
  await seedWorld();
  const make = (o) => {
    const admin = asUser('ex-br-north');
    const id = `${YEAR}__c5__sb__scope-check`;
    const b = writeBatch(admin);
    b.set(ref(admin, 'examinations', id), examDoc({ uid: 'ex-br-north', overrides: { sectionId: 'sb', name: 'Scope check', nameSlug: 'scope-check', ...o } }));
    b.set(ref(admin, 'examHistory', `${id}__1`), { ...hist({ id, rev: 1, event: 'CREATED', toStatus: 'DRAFT', uid: 'ex-br-north' }) });
    return b;
  };
  await assertFails(make({ sectionScope: 'ALL' }).commit()); // a section exam claiming to be class-wide
  await assertFails(make({ sectionScope: 'sa' }).commit()); // another section's scope
  await assertSucceeds(make({}).commit());
});

test('ACAD-4: two sheets approved at the same time both count (relative counter)', async () => {
  await seedWorld({ exam: { sheetCount: 2 } });
  const t1 = asUser('t1');
  const t2 = asUser('t2');
  await assertSucceeds(saveEntries(t1, 't1', [entryDoc({ uid: 't1' })], { withSheet: false }).commit());
  await assertSucceeds(saveEntries(t2, 't2', [entryDoc({ uid: 't2', subject: 'sci', marks: 85, overrides: { theory: 60, practical: 25, marks: 85 } })], { subject: 'sci' }).commit());
  const step = (db, uid, sid, patch, rev, event, toStatus, extra = null) => {
    const b = writeBatch(db);
    b.update(ref(db, 'marksSheets', sid), { status: toStatus, revision: rev, lastEvent: event, ...stamp(uid), ...patch });
    if (extra) b.update(ref(db, 'examinations', EXAM), { ...extra, ...stamp(uid) });
    b.set(ref(db, 'marksSheetHistory', `${sid}__${rev}`), sheetHist({ sid, rev, event, toStatus, uid }));
    return b;
  };
  const math = sheetId('math');
  const sci = sheetId('sci');
  await assertSucceeds(step(t1, 't1', math, { submittedBy: 't1', submittedAt: serverTimestamp() }, 2, 'SUBMITTED', 'SUBMITTED').commit());
  await assertSucceeds(step(t2, 't2', sci, { submittedBy: 't2', submittedAt: serverTimestamp() }, 2, 'SUBMITTED', 'SUBMITTED').commit());
  const admin = asUser('ex-admin');
  const approve = (sid) => step(admin, 'ex-admin', sid, { approvedBy: 'ex-admin', approvedAt: serverTimestamp() }, 3, 'APPROVED', 'APPROVED', { approvedSheets: increment(1) });
  const results = await Promise.allSettled([approve(math).commit(), approve(sci).commit()]);
  if (results.some((r) => r.status === 'rejected')) throw new Error(`a concurrent approval was refused: ${results.map((r) => r.reason?.message).join('; ')}`);
  let exam;
  await seed(async (db) => { exam = (await getDoc(ref(db, 'examinations', EXAM))).data(); });
  if (exam.approvedSheets !== 2) throw new Error(`counter is ${exam.approvedSheets}, expected 2`);
});

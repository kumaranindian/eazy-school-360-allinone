// Firestore security-rules tests for Milestone 9 — Homework, submissions and
// announcements (see ../firestore.rules and
// ../docs/milestone-9-homework-assignments-announcements.md).
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, getCountFromServer, query, orderBy, limit, serverTimestamp, setDoc, updateDoc, deleteDoc, where, writeBatch, Timestamp,
} from 'firebase/firestore';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

let A = 'hw-a';
let B = 'hw-b';
let counter = 0;
const NORTH = 'north';
const SOUTH = 'south';
const YEAR = 'y1';
const FUTURE = Timestamp.fromDate(new Date('2099-06-01T17:00:00Z'));
const FUTURE2 = Timestamp.fromDate(new Date('2099-06-08T17:00:00Z'));
const PAST = Timestamp.fromDate(new Date('2020-06-01T17:00:00Z'));

const branch = (s, b) => ['schools', s, 'branches', b];
const seed = (fn) => testEnv.withSecurityRulesDisabled(async (c) => fn(c.firestore()));
const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const col = (db, name, b = NORTH, s = A) => collection(db, ...branch(s, b), name);
const ref = (db, name, id, b = NORTH, s = A) => doc(db, ...branch(s, b), name, id);
const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: uid });

// ---------------------------------------------------------------- builders
function hwDoc({ batch = 'b1', section = 'sa', subject = 'math', teacher = 'st1', uid, dueAt = FUTURE, overrides = {} }) {
  return {
    schoolId: A, branchId: NORTH, academicYearId: YEAR, batchId: batch, classId: 'c5', sectionId: section, classLabel: 'Class 5',
    subjectId: subject, subjectName: subject, teacherStaffId: teacher, teacherName: teacher,
    title: 'Chapter 4 exercises', description: 'Do all questions', assignedDateKey: '2026-08-01', dueDateKey: '2099-06-01', dueTimeMin: null, dueAt,
    attachments: [], maxMarks: 10, requiresSubmission: true, allowFiles: true, allowLate: false, allowResubmission: true,
    status: 'DRAFT', revision: 1, lastEvent: 'CREATED', publishedBy: null, publishedAt: null, ...audit(uid), ...overrides,
  };
}
const hwId = (batch = 'b1', section = 'sa') => `${batch}__${section}`;
const hwHistory = ({ id, rev, event, toStatus, uid }) => ({
  schoolId: A, branchId: NORTH, academicYearId: YEAR, homeworkId: id, classId: 'c5', sectionId: 'sa', revision: rev, event, toStatus,
  actorId: uid, actorName: 'T', note: null, at: serverTimestamp(),
});
const notice = ({ id, event, rev, uid, type, section = 'sa' }) => ({
  schoolId: A, branchId: NORTH, type, audienceKind: 'SECTION', classId: 'c5', sectionId: section, title: 't', body: 'b',
  refType: 'HOMEWORK', refId: id, revision: rev, createdBy: uid, createdAt: serverTimestamp(),
});

function createHw(db, uid, o = {}) {
  const batch = o.batch ?? 'b1';
  const section = o.section ?? 'sa';
  const id = hwId(batch, section);
  const b = writeBatch(db);
  b.set(ref(db, 'homework', id), hwDoc({ uid, ...o }));
  if (!o.skipHistory) b.set(ref(db, 'homeworkHistory', `${id}__1`), hwHistory({ id, rev: 1, event: 'CREATED', toStatus: 'DRAFT', uid }));
  return b;
}

function publishHw(db, uid, { id = hwId(), rev = 2, skipNotice = false, skipHistory = false, patch = {} } = {}) {
  const b = writeBatch(db);
  b.update(ref(db, 'homework', id), {
    status: 'PUBLISHED', revision: rev, lastEvent: 'PUBLISHED', publishedBy: uid, publishedAt: serverTimestamp(), ...stamp(uid), ...patch,
  });
  if (!skipHistory) b.set(ref(db, 'homeworkHistory', `${id}__${rev}`), hwHistory({ id, rev, event: 'PUBLISHED', toStatus: 'PUBLISHED', uid }));
  if (!skipNotice) b.set(ref(db, 'broadcastNotices', `${id}__PUBLISHED__${rev}`), notice({ id, event: 'PUBLISHED', rev, uid, type: 'HOMEWORK_PUBLISHED' }));
  return b;
}

const subId = (hw, student) => `${hw}__${student}`;
const subDoc = ({ hw, student, uid, status = 'SUBMITTED', late = false, text = 'My answer', attachments = [], section = 'sa', overrides = {} }) => ({
  schoolId: A, branchId: NORTH, academicYearId: YEAR, homeworkId: hw, studentId: student, studentName: student, classId: 'c5', sectionId: section,
  status, late, textAnswer: text, attachments, revision: 1, lastEvent: 'SUBMIT', submittedBy: uid, submittedAt: serverTimestamp(),
  feedback: null, marks: null, gradedBy: null, gradedByName: null, gradedAt: null, reviewedBy: null, reviewedAt: null, ...audit(uid), ...overrides,
});
const revDoc = ({ sub, hw, student, rev, event, status, uid, text = 'My answer' }) => ({
  schoolId: A, branchId: NORTH, submissionId: sub, homeworkId: hw, studentId: student, revision: rev, event, status, textAnswer: text,
  attachments: [], feedback: null, marks: null, actorId: uid, actorName: 'X', actorRole: 'PARENT', at: serverTimestamp(),
});

function submitBatch(db, uid, { hw = hwId(), student = 'stu-1', skipRevision = false, ...o } = {}) {
  const id = subId(hw, student);
  const b = writeBatch(db);
  b.set(ref(db, 'homeworkSubmissions', id), subDoc({ hw, student, uid, ...o }));
  if (!skipRevision) b.set(ref(db, 'homeworkRevisions', `${id}__1`), revDoc({ sub: id, hw, student, rev: 1, event: 'SUBMIT', status: o.status ?? 'SUBMITTED', uid }));
  return b;
}

function changeSubmission(db, uid, { hw = hwId(), student = 'stu-1', rev, event, status, patch, skipRevision = false, text }) {
  const id = subId(hw, student);
  const b = writeBatch(db);
  b.update(ref(db, 'homeworkSubmissions', id), { status, revision: rev, lastEvent: event, ...stamp(uid), ...patch });
  if (!skipRevision) b.set(ref(db, 'homeworkRevisions', `${id}__${rev}`), revDoc({ sub: id, hw, student, rev, event, status, uid, text }));
  return b;
}

async function seedWorld() {
  counter += 1;
  A = `hw-a-${counter}`;
  B = `hw-b-${counter}`;
  await seed(async (db) => {
    for (const s of [A, B]) {
      await setDoc(doc(db, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      for (const b of s === A ? [NORTH, SOUTH] : [NORTH]) await setDoc(doc(db, ...branch(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'hw-admin': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'hw-admin-b': { schoolId: B, branchId: NORTH, role: 'SCHOOL_ADMIN' },
      'hw-br-north': { schoolId: A, branchId: NORTH, role: 'BRANCH_ADMIN' },
      'hw-br-south': { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' },
      'hw-t1': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'hw-t2': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'hw-t3': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'hw-t-south': { schoolId: A, branchId: SOUTH, role: 'TEACHER' },
      'hw-fin': { schoolId: A, branchId: NORTH, role: 'FINANCE' },
      'hw-p1': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'parent-1' },
      'hw-p2': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'parent-2' },
      'hw-p-off': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'parent-off' },
      'hw-p-np': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'parent-np' },
      'hw-t-linked': { schoolId: A, branchId: NORTH, role: 'TEACHER', linkedParentId: 'parent-1' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, 'users', uid), { branchId: null, name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    const n = branch(A, NORTH);
    for (const [staffId, uid] of [['st1', 'hw-t1'], ['st2', 'hw-t2'], ['st3', 'hw-t3']]) {
      await setDoc(doc(db, ...n, 'staff', staffId), { schoolId: A, branchId: NORTH, userId: uid, status: 'ACTIVE', isTeacher: true, ...audit('seed') });
    }
    for (const sec of ['sa', 'sb']) {
      await setDoc(doc(db, ...n, 'academicYears', YEAR, 'classes', 'c5', 'sections', sec), { schoolId: A, branchId: NORTH, name: sec, status: 'ACTIVE', ...audit('seed') });
    }
    const slot = (section, subject, teacher) => setDoc(doc(db, ...n, 'assignmentSlots', `${YEAR}__c5__${section}__${subject}`), {
      schoolId: A, branchId: NORTH, assignmentId: `a-${section}-${subject}`, teacherStaffId: teacher, createdBy: 'seed', createdAt: serverTimestamp(),
    });
    await slot('sa', 'math', 'st1');
    await slot('sa', 'eng', 'st2');
    await slot('sb', 'sci', 'st3');
    // class teacher of sa is st2
    await setDoc(doc(db, ...n, 'assignmentSlots', `${YEAR}__c5__sa__CLASS_TEACHER`), {
      schoolId: A, branchId: NORTH, assignmentId: 'a-ct', teacherStaffId: 'st2', createdBy: 'seed', createdAt: serverTimestamp(),
    });
    const student = (id, section, status = 'ACTIVE') => setDoc(doc(db, ...n, 'students', id), {
      schoolId: A, branchId: NORTH, status, currentAcademicYearId: YEAR, currentClassId: 'c5', currentSectionId: section, ...audit('seed'),
    });
    await student('stu-1', 'sa');
    await student('stu-2', 'sb');
    await student('stu-moved', 'sb'); // was in sa, transferred to sb
    await student('stu-left', 'sa', 'LEFT');
    const link = (studentId, parentId) => setDoc(doc(db, ...n, 'students', studentId, 'parentLinks', parentId), {
      schoolId: A, branchId: NORTH, studentId, parentId, canAccessPortal: true, status: 'ACTIVE', ...audit('seed'),
    });
    await link('stu-1', 'parent-1');
    await link('stu-moved', 'parent-1');
    await link('stu-left', 'parent-1');
    await link('stu-2', 'parent-2');

    // Milestone 12A: the family-access index the rules read for class-specific content.
    const access = (parentId, sections) => setDoc(doc(db, ...n, 'parentAccess', parentId), {
      schoolId: A, branchId: NORTH, parentId, classKeys: ['c5'], sectionKeys: sections.map((s) => `c5__${s}`),
      updatedAt: serverTimestamp(), updatedBy: 'seed',
    });
    await access('parent-1', ['sa', 'sb']);
    await access('parent-2', ['sb']);
    await setDoc(doc(db, ...n, 'students', 'stu-1', 'parentLinks', 'parent-off'), {
      schoolId: A, branchId: NORTH, studentId: 'stu-1', parentId: 'parent-off', canAccessPortal: true, status: 'INACTIVE', ...audit('seed'),
    });
    await setDoc(doc(db, ...n, 'students', 'stu-1', 'parentLinks', 'parent-np'), {
      schoolId: A, branchId: NORTH, studentId: 'stu-1', parentId: 'parent-np', canAccessPortal: false, status: 'ACTIVE', ...audit('seed'),
    });
  });
}

/** A published homework (open) for section sa. */
async function seedOpenHomework({ dueAt = FUTURE, overrides = {} } = {}) {
  await seed(async (db) => {
    await setDoc(ref(db, 'homework', hwId()), hwDoc({ uid: 'hw-t1', dueAt, overrides: { status: 'PUBLISHED', revision: 2, lastEvent: 'PUBLISHED', publishedBy: 'hw-t1', publishedAt: serverTimestamp(), ...overrides } }));
  });
  return hwId();
}

// ===================================================================== TESTS

test('Tenant isolation: School B admin and South branch staff cannot read or write North homework', async () => {
  await seedWorld();
  const id = await seedOpenHomework();
  for (const uid of ['hw-admin-b', 'hw-br-south', 'hw-t-south']) {
    const db = asUser(uid);
    await assertFails(getDoc(ref(db, 'homework', id)));
    await assertFails(getDocs(col(db, 'homework')));
    await assertFails(createHw(db, uid, { batch: 'x1' }).commit());
    await assertFails(updateDoc(ref(db, 'homework', id), { title: 'hijack', ...stamp(uid) }));
  }
});

test('Creation: only the assigned teacher (or an admin for that teacher), for their own section and subject', async () => {
  await seedWorld();
  const t1 = asUser('hw-t1');
  await assertSucceeds(createHw(t1, 'hw-t1', { batch: 'b1' }).commit());
  // another teacher's subject, another section, a made-up subject
  await assertFails(createHw(t1, 'hw-t1', { batch: 'b2', subject: 'eng', teacher: 'st1' }).commit());
  await assertFails(createHw(t1, 'hw-t1', { batch: 'b3', section: 'sb', subject: 'math', teacher: 'st1' }).commit());
  await assertFails(createHw(t1, 'hw-t1', { batch: 'b4', subject: 'art' }).commit());
  // claiming to be another teacher
  await assertFails(createHw(t1, 'hw-t1', { batch: 'b5', subject: 'eng', teacher: 'st2' }).commit());
  // t3 teaches sci in sb only
  await assertFails(createHw(asUser('hw-t3'), 'hw-t3', { batch: 'b6', subject: 'math', teacher: 'st1' }).commit());
  // a parent, finance, and another school cannot
  for (const uid of ['hw-p1', 'hw-fin', 'hw-admin-b']) await assertFails(createHw(asUser(uid), uid, { batch: 'b7' }).commit());
  // an admin creates for the slot's teacher
  await assertSucceeds(createHw(asUser('hw-br-north'), 'hw-br-north', { batch: 'b8', subject: 'eng', teacher: 'st2' }).commit());
  // required: history record; valid fields; status DRAFT
  await assertFails(createHw(t1, 'hw-t1', { batch: 'b9', skipHistory: true }).commit());
  await assertFails(createHw(t1, 'hw-t1', { batch: 'b10', overrides: { title: 'x' } }).commit());
  await assertFails(createHw(t1, 'hw-t1', { batch: 'b11', overrides: { dueDateKey: '2026-07-01' } }).commit());
  await assertFails(createHw(t1, 'hw-t1', { batch: 'b12', overrides: { maxMarks: 0 } }).commit());
  await assertFails(createHw(t1, 'hw-t1', { batch: 'b13', overrides: { status: 'PUBLISHED' } }).commit());
});

test('Assigning to several sections is idempotent: the id is batch + section, a retry cannot duplicate', async () => {
  await seedWorld();
  const admin = asUser('hw-admin');
  await assertSucceeds(createHw(admin, 'hw-admin', { batch: 'multi', section: 'sa', subject: 'math', teacher: 'st1' }).commit());
  // the same batch + section again is an update, not a create: refused as a replay
  await assertFails(createHw(admin, 'hw-admin', { batch: 'multi', section: 'sa', subject: 'math', teacher: 'st1' }).commit());
  // a free-text id is refused
  const b = writeBatch(admin);
  b.set(ref(admin, 'homework', 'whatever'), hwDoc({ uid: 'hw-admin', batch: 'multi' }));
  await assertFails(b.commit());
});

test('Publish needs the history, the broadcast notice, a future deadline, and the author\'s authority', async () => {
  await seedWorld();
  const t1 = asUser('hw-t1');
  await assertSucceeds(createHw(t1, 'hw-t1').commit());
  await assertFails(publishHw(t1, 'hw-t1', { skipNotice: true }).commit());
  await assertFails(publishHw(t1, 'hw-t1', { skipHistory: true }).commit());
  await assertFails(publishHw(asUser('hw-t2'), 'hw-t2').commit());
  await assertFails(publishHw(asUser('hw-p1'), 'hw-p1').commit());
  await assertSucceeds(publishHw(t1, 'hw-t1').commit());
  // a deadline already in the past cannot be published
  await assertSucceeds(createHw(t1, 'hw-t1', { batch: 'old', dueAt: PAST }).commit());
  await assertFails(publishHw(t1, 'hw-t1', { id: hwId('old') }).commit());
});

test('Published homework: only extension of the deadline, instructions, close; marks and policy are fixed', async () => {
  await seedWorld();
  const t1 = asUser('hw-t1');
  const id = await seedOpenHomework();
  const change = (patch, { rev = 3, event = 'DUE_CHANGED', notice = true } = {}) => {
    const b = writeBatch(t1);
    b.update(ref(t1, 'homework', id), { revision: rev, lastEvent: event, ...stamp('hw-t1'), ...patch });
    b.set(ref(t1, 'homeworkHistory', `${id}__${rev}`), hwHistory({ id, rev, event, toStatus: patch.status ?? 'PUBLISHED', uid: 'hw-t1' }));
    if (notice) b.set(ref(t1, 'broadcastNotices', `${id}__${event}__${rev}`), notice_({ id, event, rev }));
    return b;
  };
  const notice_ = ({ id, event, rev }) => notice({ id, event, rev, uid: 'hw-t1', type: 'HOMEWORK_DUE_CHANGED' });
  // shortening is refused; extending needs its notice
  await assertFails(change({ dueDateKey: '2099-05-01', dueAt: Timestamp.fromDate(new Date('2099-05-01T17:00:00Z')) }).commit());
  await assertFails(change({ dueDateKey: '2099-06-08', dueAt: FUTURE2 }, { notice: false }).commit());
  await assertSucceeds(change({ dueDateKey: '2099-06-08', dueAt: FUTURE2 }).commit());
  // marks, subject, section, policy cannot change after publication
  for (const patch of [{ maxMarks: 100 }, { subjectId: 'eng' }, { sectionId: 'sb' }, { teacherStaffId: 'st2' }, { allowLate: true }, { classId: 'c9' }]) {
    await assertFails(change(patch, { rev: 4, event: 'EDITED', notice: false }).commit());
  }
  // a student's family cannot edit it
  await assertFails(updateDoc(ref(asUser('hw-p1'), 'homework', id), { description: 'x', ...stamp('hw-p1') }));
  // close, then no more edits to the deadline
  await assertSucceeds(change({ status: 'CLOSED' }, { rev: 4, event: 'CLOSED', notice: false }).commit());
  await assertFails(change({ dueDateKey: '2099-07-08', dueAt: FUTURE2 }, { rev: 5 }).commit());
});

test('Visibility: drafts are for the author and admins; published work for branch teachers and parents; never other tenants', async () => {
  await seedWorld();
  const t1 = asUser('hw-t1');
  await assertSucceeds(createHw(t1, 'hw-t1', { batch: 'draft' }).commit());
  const open = await seedOpenHomework();
  const draft = hwId('draft');
  await assertSucceeds(getDoc(ref(t1, 'homework', draft)));
  await assertSucceeds(getDoc(ref(asUser('hw-admin'), 'homework', draft)));
  for (const uid of ['hw-t2', 'hw-p1', 'hw-fin']) await assertFails(getDoc(ref(asUser(uid), 'homework', draft)));
  for (const uid of ['hw-t2', 'hw-p1']) {
    await assertSucceeds(getDoc(ref(asUser(uid), 'homework', open)));
    // the app's shape pins class and section, which is what lets the rules prove it
    await assertSucceeds(getDocs(query(col(asUser(uid), 'homework'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), where('status', 'in', ['PUBLISHED', 'CLOSED']))));
    await assertFails(getDocs(col(asUser(uid), 'homework')));
  }
  // M12A: a family reads homework only for sections where they have a child
  await assertFails(getDoc(ref(asUser('hw-p2'), 'homework', open))); // parent-2's child is in sb
  await assertFails(getDocs(query(col(asUser('hw-p2'), 'homework'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), where('status', 'in', ['PUBLISHED', 'CLOSED']))));
  await assertFails(getDocs(query(col(asUser('hw-p1'), 'homework'), where('sectionId', '==', 'sa'), where('status', 'in', ['PUBLISHED', 'CLOSED'])))); // unpinned class
  // an inactive link or one without portal access has no index, so nothing
  for (const uid of ['hw-p-off', 'hw-p-np']) await assertFails(getDoc(ref(asUser(uid), 'homework', open)));
  await assertFails(getDoc(ref(asUser('hw-fin'), 'homework', open)));
  await assertFails(getDoc(ref(asUser('hw-t-south'), 'homework', open)));
});

// --------------------------------------------------------------- submissions

test('Submission: a LINKED parent for a child in this section; one per student; before the deadline', async () => {
  await seedWorld();
  const id = await seedOpenHomework();
  const p1 = asUser('hw-p1');
  // not their child: tried FIRST, so the refusal is the link check and not
  // "the document already exists"
  await assertFails(submitBatch(asUser('hw-p2'), 'hw-p2', { student: 'stu-1' }).commit());
  await assertSucceeds(submitBatch(p1, 'hw-p1').commit());
  // again (retry / double tap): the document exists, so create is refused
  await assertFails(submitBatch(p1, 'hw-p1').commit());
  await assertFails(submitBatch(p1, 'hw-p1', { student: 'stu-2', section: 'sb' }).commit());
  // child transferred to another section / left school
  await assertFails(submitBatch(p1, 'hw-p1', { student: 'stu-moved' }).commit());
  await assertFails(submitBatch(p1, 'hw-p1', { student: 'stu-left' }).commit());
  // a teacher, admin or finance cannot submit as a student
  for (const uid of ['hw-t1', 'hw-admin', 'hw-fin']) await assertFails(submitBatch(asUser(uid), uid, { student: 'stu-1' }).commit());
  assertTruthy(id);
});

function assertTruthy(v) {
  if (!v) throw new Error('expected a value');
}

test('Submission validation: status must match the server clock; revision history required; no protected fields', async () => {
  await seedWorld();
  await seedOpenHomework();
  const p1 = asUser('hw-p1');
  // claiming LATE while on time, or a client-chosen status
  await assertFails(submitBatch(p1, 'hw-p1', { status: 'LATE_SUBMITTED', late: true }).commit());
  await assertFails(submitBatch(p1, 'hw-p1', { status: 'GRADED' }).commit());
  await assertFails(submitBatch(p1, 'hw-p1', { skipRevision: true }).commit());
  // a student cannot plant marks or feedback
  await assertFails(submitBatch(p1, 'hw-p1', { overrides: { marks: 10 } }).commit());
  await assertFails(submitBatch(p1, 'hw-p1', { overrides: { feedback: 'great' } }).commit());
  // empty answer; too many files
  await assertFails(submitBatch(p1, 'hw-p1', { text: '' }).commit());
  const f = { path: 'p', name: 'n.pdf', contentType: 'application/pdf', sizeBytes: 5, uploadedBy: 'hw-p1', uploadedAt: null };
  await assertFails(submitBatch(p1, 'hw-p1', { attachments: [f, f, f, f] }).commit());
  await assertSucceeds(submitBatch(p1, 'hw-p1', { attachments: [f] }).commit());
});

test('DEADLINE is judged on the server: after it, late work is accepted only when the homework allows it', async () => {
  await seedWorld();
  await seedOpenHomework({ dueAt: PAST });
  const p1 = asUser('hw-p1');
  // marking itself on time after the deadline is refused
  await assertFails(submitBatch(p1, 'hw-p1', { status: 'SUBMITTED', late: false }).commit());
  // late is not accepted when the homework does not allow it
  await assertFails(submitBatch(p1, 'hw-p1', { status: 'LATE_SUBMITTED', late: true }).commit());

  await seed(async (db) => updateDoc(ref(db, 'homework', hwId()), { allowLate: true }));
  await assertSucceeds(submitBatch(p1, 'hw-p1', { status: 'LATE_SUBMITTED', late: true }).commit());
});

test('Closed or unpublished homework takes no submissions', async () => {
  await seedWorld();
  const t1 = asUser('hw-t1');
  await assertSucceeds(createHw(t1, 'hw-t1', { batch: 'd' }).commit());
  await assertFails(submitBatch(asUser('hw-p1'), 'hw-p1', { hw: hwId('d') }).commit());
  await seedOpenHomework({ overrides: { status: 'CLOSED' } });
  await assertFails(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
  // and a homework that takes no submissions
  await seedWorld();
  await seedOpenHomework({ overrides: { requiresSubmission: false } });
  await assertFails(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
});

test('Resubmission: allowed before the deadline when permitted; a trace revision is required; graded work is locked', async () => {
  await seedWorld();
  await seedOpenHomework();
  const p1 = asUser('hw-p1');
  await assertSucceeds(submitBatch(p1, 'hw-p1').commit());
  const resubmit = (db, uid, o = {}) => changeSubmission(db, uid, {
    rev: 2, event: 'RESUBMIT', status: 'RESUBMITTED', text: 'Better answer',
    patch: { textAnswer: 'Better answer', attachments: [], late: false, submittedBy: uid, submittedAt: serverTimestamp(), ...(o.patch ?? {}) },
    skipRevision: o.skipRevision,
  });
  await assertFails(resubmit(p1, 'hw-p1', { skipRevision: true }).commit()); // no trace
  await assertFails(resubmit(p1, 'hw-p1', { patch: { marks: 10 } }).commit());
  await assertFails(resubmit(p1, 'hw-p1', { patch: { feedback: 'x' } }).commit());
  await assertFails(resubmit(asUser('hw-p2'), 'hw-p2').commit());
  await assertSucceeds(resubmit(p1, 'hw-p1').commit());
  // the first answer is still on record
  const first = await getDoc(ref(asUser('hw-admin'), 'homeworkRevisions', `${subId(hwId(), 'stu-1')}__1`));
  if (first.data().textAnswer !== 'My answer') throw new Error('revision 1 lost');

  // the teacher grades: now the family can no longer change it
  const t1 = asUser('hw-t1');
  await assertSucceeds(changeSubmission(t1, 'hw-t1', {
    rev: 3, event: 'GRADE', status: 'GRADED',
    patch: { marks: 8, feedback: 'Well done', gradedBy: 'hw-t1', gradedByName: 'T', gradedAt: serverTimestamp() },
  }).commit());
  await assertFails(changeSubmission(p1, 'hw-p1', {
    rev: 4, event: 'RESUBMIT', status: 'RESUBMITTED',
    patch: { textAnswer: 'sneaky', late: false, submittedBy: 'hw-p1', submittedAt: serverTimestamp() },
  }).commit());
});

test('Resubmission is refused when the homework forbids it, or after the deadline without late allowance', async () => {
  await seedWorld();
  await seedOpenHomework({ overrides: { allowResubmission: false } });
  const p1 = asUser('hw-p1');
  await assertSucceeds(submitBatch(p1, 'hw-p1').commit());
  await assertFails(changeSubmission(p1, 'hw-p1', {
    rev: 2, event: 'RESUBMIT', status: 'RESUBMITTED',
    patch: { textAnswer: 'again', late: false, submittedBy: 'hw-p1', submittedAt: serverTimestamp() },
  }).commit());

  await seedWorld();
  await seedOpenHomework();
  await assertSucceeds(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
  // the deadline passes (set by the school, not the client)
  await seed(async (db) => updateDoc(ref(db, 'homework', hwId()), { dueAt: PAST }));
  await assertFails(changeSubmission(asUser('hw-p1'), 'hw-p1', {
    rev: 2, event: 'RESUBMIT', status: 'RESUBMITTED',
    patch: { textAnswer: 'too late', late: true, submittedBy: 'hw-p1', submittedAt: serverTimestamp() },
  }).commit());
});

test('GRADING: only the homework\'s teacher or an admin; marks within the maximum; a trace is required', async () => {
  await seedWorld();
  await seedOpenHomework(); // max 10
  await assertSucceeds(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
  const grade = (uid, marks, o = {}) => changeSubmission(asUser(uid), uid, {
    rev: 2, event: 'GRADE', status: 'GRADED', skipRevision: o.skipRevision,
    patch: { marks, feedback: 'ok', gradedBy: uid, gradedByName: 'T', gradedAt: serverTimestamp() },
  });
  // unrelated teacher (teaches another subject of the same section), another section's teacher, parent, finance
  for (const uid of ['hw-t2', 'hw-t3', 'hw-p1', 'hw-fin', 'hw-t-south']) await assertFails(grade(uid, 5).commit());
  // out-of-range
  await assertFails(grade('hw-t1', 11).commit());
  await assertFails(grade('hw-t1', -1).commit());
  await assertFails(grade('hw-t1', 5, { skipRevision: true }).commit());
  await assertSucceeds(grade('hw-t1', 10).commit());
  // an admin may regrade; the earlier grade stays in the revisions
  await assertSucceeds(changeSubmission(asUser('hw-admin'), 'hw-admin', {
    rev: 3, event: 'GRADE', status: 'GRADED',
    patch: { marks: 7, feedback: 'regraded', gradedBy: 'hw-admin', gradedByName: 'A', gradedAt: serverTimestamp() },
  }).commit());
  const r2 = await getDoc(ref(asUser('hw-admin'), 'homeworkRevisions', `${subId(hwId(), 'stu-1')}__2`));
  if (!r2.exists()) throw new Error('grading history lost');
});

test('A homework without marks cannot be given marks; return for revision needs a reason and unlocks resubmission after the deadline', async () => {
  await seedWorld();
  await seedOpenHomework({ overrides: { maxMarks: null } });
  await assertSucceeds(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
  const t1 = asUser('hw-t1');
  await assertFails(changeSubmission(t1, 'hw-t1', {
    rev: 2, event: 'GRADE', status: 'GRADED', patch: { marks: 3, feedback: 'x', gradedBy: 'hw-t1', gradedByName: 'T', gradedAt: serverTimestamp() },
  }).commit());
  await assertFails(changeSubmission(t1, 'hw-t1', {
    rev: 2, event: 'RETURN', status: 'RETURNED_FOR_REVISION',
    patch: { feedback: '', marks: null, gradedBy: null, gradedByName: null, gradedAt: null, reviewedBy: 'hw-t1', reviewedAt: serverTimestamp() },
  }).commit());
  await assertSucceeds(changeSubmission(t1, 'hw-t1', {
    rev: 2, event: 'RETURN', status: 'RETURNED_FOR_REVISION',
    patch: { feedback: 'Show your working', marks: null, gradedBy: null, gradedByName: null, gradedAt: null, reviewedBy: 'hw-t1', reviewedAt: serverTimestamp() },
  }).commit());
  // even after the deadline, the family may answer a returned submission
  await seed(async (db) => updateDoc(ref(db, 'homework', hwId()), { dueAt: PAST }));
  await assertSucceeds(changeSubmission(asUser('hw-p1'), 'hw-p1', {
    rev: 3, event: 'RESUBMIT', status: 'RESUBMITTED',
    patch: { textAnswer: 'With working', late: true, submittedBy: 'hw-p1', submittedAt: serverTimestamp() },
  }).commit());
});

test('Reviewing marks a submission reviewed without changing its state', async () => {
  await seedWorld();
  await seedOpenHomework();
  await assertSucceeds(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
  await assertFails(changeSubmission(asUser('hw-t2'), 'hw-t2', {
    rev: 2, event: 'REVIEW', status: 'SUBMITTED', patch: { reviewedBy: 'hw-t2', reviewedAt: serverTimestamp() },
  }).commit());
  await assertSucceeds(changeSubmission(asUser('hw-t1'), 'hw-t1', {
    rev: 2, event: 'REVIEW', status: 'SUBMITTED', patch: { reviewedBy: 'hw-t1', reviewedAt: serverTimestamp() },
  }).commit());
});

test('Parent-child isolation: a parent reads only their linked child\'s submissions and revisions', async () => {
  await seedWorld();
  await seedOpenHomework();
  await assertSucceeds(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
  const id = subId(hwId(), 'stu-1');
  await assertSucceeds(getDoc(ref(asUser('hw-p1'), 'homeworkSubmissions', id)));
  await assertSucceeds(getDocs(query(col(asUser('hw-p1'), 'homeworkSubmissions'), where('studentId', '==', 'stu-1'))));
  await assertSucceeds(getDocs(query(col(asUser('hw-p1'), 'homeworkRevisions'), where('studentId', '==', 'stu-1'))));
  // another parent, an unrelated teacher, finance, other tenant
  for (const uid of ['hw-p2', 'hw-t2', 'hw-t3', 'hw-fin', 'hw-admin-b', 'hw-t-south']) {
    await assertFails(getDoc(ref(asUser(uid), 'homeworkSubmissions', id)));
  }
  await assertFails(getDocs(query(col(asUser('hw-p2'), 'homeworkSubmissions'), where('studentId', '==', 'stu-1'))));
  await assertFails(getDocs(col(asUser('hw-p1'), 'homeworkSubmissions')));
  // the homework's teacher lists its submissions with the pinned query
  await assertSucceeds(getDocs(query(col(asUser('hw-t1'), 'homeworkSubmissions'), where('homeworkId', '==', hwId()))));
  await assertFails(getDocs(query(col(asUser('hw-t2'), 'homeworkSubmissions'), where('homeworkId', '==', hwId()))));
  // (the query pins the homework too: rules can only prove the teacher owns
  // the results when the homework is named)
  await assertSucceeds(getDocs(query(col(asUser('hw-t1'), 'homeworkRevisions'), where('homeworkId', '==', hwId()), where('submissionId', '==', id))));
  await assertFails(getDocs(query(col(asUser('hw-t1'), 'homeworkRevisions'), where('submissionId', '==', id))));
  // never deletable; revisions append-only
  await assertFails(deleteDoc(ref(asUser('hw-admin'), 'homeworkSubmissions', id)));
  await assertFails(updateDoc(ref(asUser('hw-admin'), 'homeworkRevisions', `${id}__1`), { textAnswer: 'rewritten' }));
  await assertFails(deleteDoc(ref(asUser('hw-admin'), 'homeworkRevisions', `${id}__1`)));
});

// ------------------------------------------------------------ announcements

const annDoc = ({ id = 'an-1', uid, kind = 'SECTION', section = 'sa', overrides = {} }) => ({
  schoolId: A, branchId: NORTH, academicYearId: YEAR, audienceKind: kind, classId: kind === 'CLASS' || kind === 'SECTION' ? 'c5' : null,
  sectionId: kind === 'SECTION' ? section : null, audienceLabel: 'x', title: 'Sports day', body: 'On Friday', attachments: [],
  publishAt: null, expiresAt: null, status: 'DRAFT', revision: 1, lastEvent: 'CREATED', authorId: uid, authorName: 'A', authorRole: 'TEACHER',
  publishedBy: null, publishedAt: null, ...audit(uid), ...overrides,
});
const annHistory = ({ id, rev, event, toStatus, uid }) => ({
  schoolId: A, branchId: NORTH, announcementId: id, revision: rev, event, toStatus, actorId: uid, actorName: 'A', at: serverTimestamp(),
});
const createAnn = (db, uid, o = {}) => {
  const id = o.id ?? 'an-1';
  const b = writeBatch(db);
  b.set(ref(db, 'announcements', id), annDoc({ uid, ...o }));
  if (!o.skipHistory) b.set(ref(db, 'announcementHistory', `${id}__1`), annHistory({ id, rev: 1, event: 'CREATED', toStatus: 'DRAFT', uid }));
  return b;
};
const publishAnn = (db, uid, { id = 'an-1', rev = 2, kind = 'SECTION', skipNotice = false, expiresAt = null, publishAt = Timestamp.fromDate(new Date('2020-01-01T00:00:00Z')) } = {}) => {
  const b = writeBatch(db);
  b.update(ref(db, 'announcements', id), {
    status: 'PUBLISHED', publishAt, expiresAt, publishedBy: uid, publishedAt: serverTimestamp(), revision: rev, lastEvent: 'PUBLISHED', ...stamp(uid),
  });
  b.set(ref(db, 'announcementHistory', `${id}__${rev}`), annHistory({ id, rev, event: 'PUBLISHED', toStatus: 'PUBLISHED', uid }));
  if (!skipNotice) {
    b.set(ref(db, 'broadcastNotices', `${id}__PUBLISHED__${rev}`), {
      schoolId: A, branchId: NORTH, type: 'ANNOUNCEMENT_PUBLISHED', audienceKind: kind, classId: kind === 'SECTION' ? 'c5' : null,
      sectionId: kind === 'SECTION' ? 'sa' : null, title: 't', body: 'b', refType: 'ANNOUNCEMENT', refId: id, revision: rev,
      createdBy: uid, createdAt: serverTimestamp(),
    });
  }
  return b;
};

test('Announcements: who may address which audience', async () => {
  await seedWorld();
  // st2 is the class teacher of sa => hw-t2
  await assertSucceeds(createAnn(asUser('hw-t2'), 'hw-t2', { id: 'a1', kind: 'SECTION', section: 'sa' }).commit());
  // not the class teacher, wrong section, whole-school / staff / class audiences
  await assertFails(createAnn(asUser('hw-t1'), 'hw-t1', { id: 'a2', kind: 'SECTION', section: 'sa' }).commit());
  await assertFails(createAnn(asUser('hw-t2'), 'hw-t2', { id: 'a3', kind: 'SECTION', section: 'sb' }).commit());
  for (const kind of ['ALL', 'BRANCH', 'STAFF', 'PARENTS', 'CLASS']) {
    await assertFails(createAnn(asUser('hw-t2'), 'hw-t2', { id: `t-${kind}`, kind }).commit());
  }
  // branch admin: anything in the branch except the whole school
  await assertSucceeds(createAnn(asUser('hw-br-north'), 'hw-br-north', { id: 'b1', kind: 'PARENTS' }).commit());
  await assertSucceeds(createAnn(asUser('hw-br-north'), 'hw-br-north', { id: 'b2', kind: 'CLASS' }).commit());
  await assertFails(createAnn(asUser('hw-br-north'), 'hw-br-north', { id: 'b3', kind: 'ALL' }).commit());
  await assertSucceeds(createAnn(asUser('hw-admin'), 'hw-admin', { id: 's1', kind: 'ALL' }).commit());
  // another branch's admin, parent, finance
  for (const uid of ['hw-br-south', 'hw-p1', 'hw-fin', 'hw-admin-b']) await assertFails(createAnn(asUser(uid), uid, { id: `x-${uid}`, kind: 'BRANCH' }).commit());
  // impersonating an author
  await assertFails(createAnn(asUser('hw-admin'), 'hw-admin', { id: 'imp', kind: 'ALL', overrides: { authorId: 'hw-t1' } }).commit());
  await assertFails(createAnn(asUser('hw-admin'), 'hw-admin', { id: 'nohist', kind: 'ALL', skipHistory: true }).commit());
});

test('Announcements: up to 10 attachments on create and on edit, 11 refused', async () => {
  await seedWorld();
  const admin = asUser('hw-admin');
  const files = (n) => Array.from({ length: n }, (_, i) => ({
    path: `schools/${A}/branches/${NORTH}/announcements/ac1/files/att_${i}.pdf`, name: `f${i}.pdf`, contentType: 'application/pdf',
    sizeBytes: 10, uploadedBy: 'hw-admin', uploadedAt: null,
  }));
  await assertFails(createAnn(admin, 'hw-admin', { id: 'ac0', kind: 'ALL', overrides: { attachments: files(11) } }).commit());
  await assertSucceeds(createAnn(admin, 'hw-admin', { id: 'ac1', kind: 'ALL', overrides: { attachments: files(10) } }).commit());
  const edit = (n, rev) => {
    const b = writeBatch(admin);
    b.update(ref(admin, 'announcements', 'ac1'), { attachments: files(n), revision: rev, lastEvent: 'EDITED', ...stamp('hw-admin') });
    b.set(ref(admin, 'announcementHistory', `ac1__${rev}`), annHistory({ id: 'ac1', rev, event: 'EDITED', toStatus: 'DRAFT', uid: 'hw-admin' }));
    return b;
  };
  await assertFails(edit(11, 2).commit());
  await assertSucceeds(edit(3, 2).commit());
});

test('Announcements: publish needs the notice and history; the audience of a published one is fixed; archive keeps it', async () => {
  await seedWorld();
  const admin = asUser('hw-admin');
  await assertSucceeds(createAnn(admin, 'hw-admin', { id: 'p1', kind: 'PARENTS', overrides: { authorRole: 'SCHOOL_ADMIN' } }).commit());
  await assertFails(publishAnn(admin, 'hw-admin', { id: 'p1', kind: 'PARENTS', skipNotice: true }).commit());
  await assertFails(publishAnn(asUser('hw-p1'), 'hw-p1', { id: 'p1', kind: 'PARENTS' }).commit());
  // expiry before the start is refused
  await assertFails(publishAnn(admin, 'hw-admin', {
    id: 'p1', kind: 'PARENTS', expiresAt: Timestamp.fromDate(new Date('2019-01-01T00:00:00Z')),
  }).commit());
  await assertSucceeds(publishAnn(admin, 'hw-admin', { id: 'p1', kind: 'PARENTS' }).commit());

  // the audience cannot be widened after publication
  const widen = writeBatch(admin);
  widen.update(ref(admin, 'announcements', 'p1'), { audienceKind: 'ALL', revision: 3, lastEvent: 'UPDATED', ...stamp('hw-admin') });
  widen.set(ref(admin, 'announcementHistory', 'p1__3'), annHistory({ id: 'p1', rev: 3, event: 'UPDATED', toStatus: 'PUBLISHED', uid: 'hw-admin' }));
  await assertFails(widen.commit());
  // text may be updated; archive keeps the record
  const edit = writeBatch(admin);
  edit.update(ref(admin, 'announcements', 'p1'), { title: 'Sports day (moved)', revision: 3, lastEvent: 'UPDATED', ...stamp('hw-admin') });
  edit.set(ref(admin, 'announcementHistory', 'p1__3'), annHistory({ id: 'p1', rev: 3, event: 'UPDATED', toStatus: 'PUBLISHED', uid: 'hw-admin' }));
  await assertSucceeds(edit.commit());
  const arch = writeBatch(admin);
  arch.update(ref(admin, 'announcements', 'p1'), { status: 'ARCHIVED', revision: 4, lastEvent: 'ARCHIVED', ...stamp('hw-admin') });
  arch.set(ref(admin, 'announcementHistory', 'p1__4'), annHistory({ id: 'p1', rev: 4, event: 'ARCHIVED', toStatus: 'ARCHIVED', uid: 'hw-admin' }));
  await assertSucceeds(arch.commit());
  await assertFails(deleteDoc(ref(admin, 'announcements', 'p1')));
  await assertFails(updateDoc(ref(asUser('hw-p1'), 'announcements', 'p1'), { title: 'hacked', ...stamp('hw-p1') }));
});

test('Announcement visibility: drafts for author/admins; published to the right roles; STAFF ones never to parents', async () => {
  await seedWorld();
  const admin = asUser('hw-admin');
  await assertSucceeds(createAnn(admin, 'hw-admin', { id: 'draft', kind: 'ALL' }).commit());
  await assertSucceeds(createAnn(admin, 'hw-admin', { id: 'staff', kind: 'STAFF' }).commit());
  await assertSucceeds(publishAnn(admin, 'hw-admin', { id: 'staff', kind: 'STAFF' }).commit());
  await assertSucceeds(createAnn(admin, 'hw-admin', { id: 'all', kind: 'ALL' }).commit());
  await assertSucceeds(publishAnn(admin, 'hw-admin', { id: 'all', kind: 'ALL' }).commit());

  for (const uid of ['hw-p1', 'hw-t1', 'hw-fin']) await assertFails(getDoc(ref(asUser(uid), 'announcements', 'draft')));
  await assertSucceeds(getDoc(ref(asUser('hw-p1'), 'announcements', 'all')));
  await assertSucceeds(getDoc(ref(asUser('hw-t1'), 'announcements', 'staff')));
  await assertSucceeds(getDoc(ref(asUser('hw-fin'), 'announcements', 'staff')));
  await assertFails(getDoc(ref(asUser('hw-p1'), 'announcements', 'staff')));
  // other branch's staff / other tenants
  for (const uid of ['hw-t-south', 'hw-admin-b']) await assertFails(getDoc(ref(asUser(uid), 'announcements', 'all')));
  // the parent's list query
  await assertSucceeds(getDocs(query(col(asUser('hw-p1'), 'announcements'), where('status', '==', 'PUBLISHED'), where('audienceKind', 'in', ['ALL', 'BRANCH', 'PARENTS']))));
  await assertFails(getDocs(query(col(asUser('hw-p1'), 'announcements'), where('status', '==', 'PUBLISHED'), where('audienceKind', 'in', ['ALL', 'BRANCH', 'PARENTS', 'CLASS', 'SECTION']))));
  await assertFails(getDocs(query(col(asUser('hw-p1'), 'announcements'), where('status', '==', 'PUBLISHED'))));
});

// ------------------------------------------------------------------ notices

test('Notices: written with their event; forged or mismatched ones refused; readable by the right people', async () => {
  await seedWorld();
  const t1 = asUser('hw-t1');
  await assertSucceeds(createHw(t1, 'hw-t1').commit());
  // wrong type for the event / wrong section / planted by someone else
  const bad = (n) => {
    const b = publishHw(t1, 'hw-t1', { skipNotice: true });
    b.set(ref(t1, 'broadcastNotices', `${hwId()}__PUBLISHED__2`), n);
    return b;
  };
  const good = notice({ id: hwId(), event: 'PUBLISHED', rev: 2, uid: 'hw-t1', type: 'HOMEWORK_PUBLISHED' });
  await assertFails(bad({ ...good, type: 'ANNOUNCEMENT_PUBLISHED' }).commit());
  await assertFails(bad({ ...good, sectionId: 'sb' }).commit());
  await assertFails(bad({ ...good, revision: 9 }).commit());
  await assertSucceeds(bad(good).commit());

  const nid = `${hwId()}__PUBLISHED__2`;
  for (const uid of ['hw-p1', 'hw-t2', 'hw-admin']) await assertSucceeds(getDoc(ref(asUser(uid), 'broadcastNotices', nid)));
  for (const uid of ['hw-admin-b', 'hw-t-south']) await assertFails(getDoc(ref(asUser(uid), 'broadcastNotices', nid)));
  // nobody edits or deletes a notice; a parent cannot plant one
  await assertFails(updateDoc(ref(t1, 'broadcastNotices', nid), { title: 'x' }));
  await assertFails(deleteDoc(ref(t1, 'broadcastNotices', nid)));
  await assertFails(setDoc(ref(asUser('hw-p1'), 'broadcastNotices', 'forged'), { ...good, createdBy: 'hw-p1' }));
});

test('Targeted notifications (returned / graded) go to the submitter, in the commit of the change, with no marks or feedback text', async () => {
  await seedWorld();
  await seedOpenHomework();
  await assertSucceeds(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
  const t1 = asUser('hw-t1');
  const id = subId(hwId(), 'stu-1');
  const note = (uid, o = {}) => ({
    schoolId: A, branchId: NORTH, audience: 'USER', recipientUserId: 'hw-p1', type: 'HOMEWORK_GRADED', applicationId: null,
    submissionId: id, homeworkId: hwId(), revision: 2, title: 'Homework graded', body: 'math', createdBy: uid, createdAt: serverTimestamp(), readAt: null, ...o,
  });
  const gradeWith = (n) => {
    const b = changeSubmission(t1, 'hw-t1', {
      rev: 2, event: 'GRADE', status: 'GRADED',
      patch: { marks: 9, feedback: 'ok', gradedBy: 'hw-t1', gradedByName: 'T', gradedAt: serverTimestamp() },
    });
    b.set(ref(t1, 'notifications', `${id}__GRADE__2`), n);
    return b;
  };
  await assertFails(gradeWith(note('hw-t1', { recipientUserId: 'hw-p2' })).commit()); // someone else
  await assertFails(gradeWith(note('hw-t1', { type: 'HOMEWORK_RETURNED' })).commit()); // wrong event
  await assertFails(gradeWith(note('hw-t1', { revision: 7 })).commit());
  await assertSucceeds(gradeWith(note('hw-t1')).commit());
  await assertSucceeds(getDoc(ref(asUser('hw-p1'), 'notifications', `${id}__GRADE__2`)));
  await assertFails(getDoc(ref(asUser('hw-p2'), 'notifications', `${id}__GRADE__2`)));
});

test('Read state is the user\'s own document', async () => {
  await seedWorld();
  await assertSucceeds(setDoc(doc(asUser('hw-p1'), 'users', 'hw-p1', 'noticeReads', 'state'), { ids: ['a', 'b'] }));
  await assertFails(setDoc(doc(asUser('hw-p2'), 'users', 'hw-p1', 'noticeReads', 'state'), { ids: [] }));
  await assertFails(getDoc(doc(asUser('hw-p2'), 'users', 'hw-p1', 'noticeReads', 'state')));
});

// ------------------------------------------------------------ query shapes

test('The exact queries the app issues are provable by the rules (and unpinned variants are not)', async () => {
  await seedWorld();
  await seedOpenHomework();
  await assertSucceeds(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
  const t1 = asUser('hw-t1');
  const p1 = asUser('hw-p1');
  const admin = asUser('hw-br-north');

  // homework: a teacher's own list (any status), the family's section list
  await assertSucceeds(getDocs(query(col(t1, 'homework'), where('academicYearId', '==', YEAR), where('teacherStaffId', '==', 'st1'), orderBy('dueDateKey', 'desc'), limit(25))));
  await assertSucceeds(getDocs(query(col(t1, 'homework'), where('academicYearId', '==', YEAR), where('teacherStaffId', '==', 'st1'), where('status', '==', 'DRAFT'), orderBy('dueDateKey', 'desc'), limit(25))));
  await assertFails(getDocs(query(col(asUser('hw-t2'), 'homework'), where('academicYearId', '==', YEAR), where('teacherStaffId', '==', 'st1'), orderBy('dueDateKey', 'desc'))));
  await assertSucceeds(getDocs(query(col(admin, 'homework'), where('academicYearId', '==', YEAR), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), orderBy('dueDateKey', 'desc'), limit(25))));
  for (const who of [p1, asUser('hw-t2')]) {
    await assertSucceeds(getDocs(query(col(who, 'homework'), where('academicYearId', '==', YEAR), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), where('status', 'in', ['PUBLISHED', 'CLOSED']), orderBy('dueDateKey', 'desc'), limit(100))));
  }
  // a parent cannot list drafts by omitting the status
  await assertFails(getDocs(query(col(p1, 'homework'), where('academicYearId', '==', YEAR), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), orderBy('dueDateKey', 'desc'))));

  // submissions: review list, per-student lookup, counts
  await assertSucceeds(getDocs(query(col(t1, 'homeworkSubmissions'), where('homeworkId', '==', hwId()), where('status', '==', 'SUBMITTED'), orderBy('studentName'), limit(25))));
  await assertSucceeds(getDocs(query(col(t1, 'homeworkSubmissions'), where('homeworkId', '==', hwId()), where('studentId', 'in', ['stu-1', 'stu-2']))));
  await assertSucceeds(getDocs(query(col(p1, 'homeworkSubmissions'), where('studentId', '==', 'stu-1'), where('academicYearId', '==', YEAR))));
  const base = [where('homeworkId', '==', hwId())];
  const agg = await assertSucceeds(getCountFromServer(query(col(t1, 'homeworkSubmissions'), ...base, where('status', 'in', ['SUBMITTED', 'LATE_SUBMITTED']), where('reviewedBy', '==', null))));
  if (agg.data().count !== 1) throw new Error('expected 1 awaiting review, got ' + agg.data().count);
  await assertFails(getCountFromServer(query(col(asUser('hw-t2'), 'homeworkSubmissions'), ...base)));
  // revisions: both pinned
  await assertSucceeds(getDocs(query(col(p1, 'homeworkRevisions'), where('homeworkId', '==', hwId()), where('studentId', '==', 'stu-1'))));
  await assertSucceeds(getDocs(query(col(t1, 'homeworkRevisions'), where('homeworkId', '==', hwId()), where('studentId', '==', 'stu-1'))));
  await assertFails(getDocs(query(col(asUser('hw-p2'), 'homeworkRevisions'), where('homeworkId', '==', hwId()), where('studentId', '==', 'stu-1'))));
});

test('Announcement and notice queries the app issues', async () => {
  await seedWorld();
  const admin = asUser('hw-admin');
  await assertSucceeds(createAnn(admin, 'hw-admin', { id: 'q1', kind: 'PARENTS' }).commit());
  await assertSucceeds(publishAnn(admin, 'hw-admin', { id: 'q1', kind: 'PARENTS' }).commit());
  await assertSucceeds(createAnn(asUser('hw-t2'), 'hw-t2', { id: 'q2', kind: 'SECTION', section: 'sa' }).commit());
  const audiences = ['ALL', 'BRANCH', 'PARENTS'];
  // manager: everything of the branch
  await assertSucceeds(getDocs(query(col(asUser('hw-br-north'), 'announcements'), orderBy('createdAt', 'desc'), limit(100))));
  // parent: published and parent-addressable only; class/section audiences are asked for one scope at a time
  await assertSucceeds(getDocs(query(col(asUser('hw-p1'), 'announcements'), where('status', '==', 'PUBLISHED'), where('audienceKind', 'in', audiences), orderBy('publishAt', 'desc'), limit(100))));
  await assertSucceeds(getDocs(query(col(asUser('hw-p1'), 'announcements'), where('status', '==', 'PUBLISHED'), where('audienceKind', '==', 'SECTION'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), orderBy('publishAt', 'desc'), limit(100))));
  await assertSucceeds(getDocs(query(col(asUser('hw-p1'), 'announcements'), where('status', '==', 'PUBLISHED'), where('audienceKind', '==', 'CLASS'), where('classId', '==', 'c5'), orderBy('publishAt', 'desc'), limit(100))));
  // teacher: published ones, plus their own drafts by author
  await assertSucceeds(getDocs(query(col(asUser('hw-t1'), 'announcements'), where('status', '==', 'PUBLISHED'), orderBy('publishAt', 'desc'), limit(100))));
  await assertSucceeds(getDocs(query(col(asUser('hw-t2'), 'announcements'), where('authorId', '==', 'hw-t2'), orderBy('createdAt', 'desc'), limit(100))));
  await assertFails(getDocs(query(col(asUser('hw-t1'), 'announcements'), where('authorId', '==', 'hw-t2'))));
  await assertFails(getDocs(query(col(asUser('hw-p1'), 'announcements'), orderBy('createdAt', 'desc'))));
  // notices
  await assertSucceeds(getDocs(query(col(asUser('hw-p1'), 'broadcastNotices'), where('audienceKind', 'in', audiences), orderBy('createdAt', 'desc'), limit(50))));
  await assertSucceeds(getDocs(query(col(asUser('hw-t1'), 'broadcastNotices'), orderBy('createdAt', 'desc'), limit(50))));
  await assertFails(getDocs(query(col(asUser('hw-p1'), 'broadcastNotices'), orderBy('createdAt', 'desc'))));
  await assertFails(getDocs(query(col(asUser('hw-admin-b'), 'broadcastNotices'), orderBy('createdAt', 'desc'))));
});

test('Announcement edits: only the author or an admin; the revision advances by exactly one', async () => {
  await seedWorld();
  // hw-t2 is class teacher of sa and the author
  await assertSucceeds(createAnn(asUser('hw-t2'), 'hw-t2', { id: 'e1', kind: 'SECTION', section: 'sa' }).commit());
  const edit = (db, uid, { rev = 2, title = 'Edited title' } = {}) => {
    const b = writeBatch(db);
    b.update(ref(db, 'announcements', 'e1'), { title, revision: rev, lastEvent: 'EDITED', ...stamp(uid) });
    b.set(ref(db, 'announcementHistory', `e1__${rev}`), annHistory({ id: 'e1', rev, event: 'EDITED', toStatus: 'DRAFT', uid }));
    return b;
  };
  // another teacher, a parent, finance, another branch's admin: not the author
  for (const uid of ['hw-t1', 'hw-p1', 'hw-fin', 'hw-br-south', 'hw-admin-b']) {
    await assertFails(edit(asUser(uid), uid).commit());
  }
  // skipping revisions is refused even with a matching history record
  await assertFails(edit(asUser('hw-t2'), 'hw-t2', { rev: 3 }).commit());
  await assertSucceeds(edit(asUser('hw-t2'), 'hw-t2', { rev: 2 }).commit());
  // an admin of the branch may edit someone else's draft
  await assertSucceeds(edit(asUser('hw-br-north'), 'hw-br-north', { rev: 3, title: 'Admin edit' }).commit());
});

test('A child who has moved sections or left can no longer change work set for the old section', async () => {
  await seedWorld();
  await seedOpenHomework();
  const p1 = asUser('hw-p1');
  await assertSucceeds(submitBatch(p1, 'hw-p1').commit());
  const resubmit = () => changeSubmission(p1, 'hw-p1', {
    rev: 2, event: 'RESUBMIT', status: 'RESUBMITTED',
    patch: { textAnswer: 'second try', late: false, submittedBy: 'hw-p1', submittedAt: serverTimestamp() },
  });
  // transferred to another section: refused (the submission itself stays readable)
  await seed(async (db) => updateDoc(ref(db, 'students', 'stu-1'), { currentSectionId: 'sb' }));
  await assertFails(resubmit().commit());
  await assertSucceeds(getDoc(ref(p1, 'homeworkSubmissions', subId(hwId(), 'stu-1'))));
  // back in the section but withdrawn from school: refused
  await seed(async (db) => updateDoc(ref(db, 'students', 'stu-1'), { currentSectionId: 'sa', status: 'LEFT' }));
  await assertFails(resubmit().commit());
  // enrolled again: allowed
  await seed(async (db) => updateDoc(ref(db, 'students', 'stu-1'), { status: 'ACTIVE' }));
  await assertSucceeds(resubmit().commit());
});

test('Only an ACTIVE, portal-enabled link of a PARENT account may act for a child', async () => {
  await seedWorld();
  await seedOpenHomework();
  // ended link, portal switched off, and a non-parent account that merely
  // carries a linked parent id: none may submit for the child
  for (const uid of ['hw-p-off', 'hw-p-np', 'hw-t-linked']) {
    await assertFails(submitBatch(asUser(uid), uid, { student: 'stu-1' }).commit());
  }
  await assertSucceeds(submitBatch(asUser('hw-p1'), 'hw-p1').commit());
  // ...nor read the submission or change it
  for (const uid of ['hw-p-off', 'hw-p-np']) {
    await assertFails(getDoc(ref(asUser(uid), 'homeworkSubmissions', subId(hwId(), 'stu-1'))));
    await assertFails(changeSubmission(asUser(uid), uid, {
      rev: 2, event: 'RESUBMIT', status: 'RESUBMITTED',
      patch: { textAnswer: 'x', late: false, submittedBy: uid, submittedAt: serverTimestamp() },
    }).commit());
  }
  await assertFails(changeSubmission(asUser('hw-t-linked'), 'hw-t-linked', {
    rev: 2, event: 'RESUBMIT', status: 'RESUBMITTED',
    patch: { textAnswer: 'x', late: false, submittedBy: 'hw-t-linked', submittedAt: serverTimestamp() },
  }).commit());
});

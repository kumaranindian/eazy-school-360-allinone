// Firestore security-rules tests for Milestone 7 — Leave (see ../firestore.rules
// and ../docs/milestone-7-leave-management.md). Own school ids (`lv-a-<n>`) and
// uid prefix (`lv-`) so it can run beside the other files on the shared emulator.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, where, writeBatch,
} from 'firebase/firestore';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

let A = 'lv-a';
let B = 'lv-b';
let counter = 0;
const NORTH = 'north';
const SOUTH = 'south';
const YEAR = 'y1';

const branch = (s, b) => ['schools', s, 'branches', b];
const seed = (fn) => testEnv.withSecurityRulesDisabled(async (c) => fn(c.firestore()));
const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const col = (db, name, b = NORTH, s = A) => collection(db, ...branch(s, b), name);
const ref = (db, name, id, b = NORTH, s = A) => doc(db, ...branch(s, b), name, id);

const userDoc = ({ schoolId, branchId = null, role, linkedParentId = null }) => ({
  schoolId, branchId, name: 'T', email: 't@example.com', role, status: 'ACTIVE', linkedParentId, ...audit('seed'),
});

// ---------------------------------------------------------------- builders

const DAYS = ['2026-08-03', '2026-08-04']; // Mon, Tue

function typeDoc({ kind, code, name, payType, requiresDocument = false, requiresReason = true, entitlement = null, exceed = 'BLOCK', status = 'ACTIVE', maxDays = null, carryMax = 0, uid = 'seed' }) {
  return {
    schoolId: A, branchId: NORTH, kind, code, name, payType, requiresDocument, requiresReason, allowHalfDay: true,
    countNonWorkingDays: false, maxDaysPerRequest: maxDays, applicableRoles: [], applicableEmploymentTypes: [],
    annualEntitlementUnits: entitlement, accrual: 'UPFRONT', carryForwardMaxUnits: carryMax, exceedPolicy: exceed, status, ...audit(uid),
  };
}

const lockIds = (kind, subjectId, dates, half = 'NONE') =>
  dates.flatMap((d) => (half === 'NONE' ? ['FIRST', 'SECOND'] : [half]).map((s) => `${kind}_${subjectId}__${d}__${s}`));

function appDoc({
  id, uid, kind = 'STUDENT', subjectId = 'stu-1', relation = 'PARENT', typeId = 'STUDENT__sick', typeName = 'Sick leave', payType = 'NA',
  dates = DAYS, half = 'NONE', units, reason = 'Fever', attachments = [], balanceId = null, overrides = {},
}) {
  const counted = dates;
  return {
    schoolId: A, branchId: NORTH, subjectKind: kind, subjectId, subjectName: 'Anil', subjectCode: 'ADM-1', academicYearId: YEAR,
    classId: 'c5', className: 'Class 5', sectionId: 'sa', sectionName: 'A',
    applicantUserId: uid, applicantName: 'P', relation, typeId, typeName, payType,
    startDateKey: dates[0], endDateKey: dates[dates.length - 1], halfDay: half,
    units: units ?? (half === 'NONE' ? counted.length * 2 : 1), countedDateKeys: counted, reason, attachments, balanceId,
    status: 'PENDING', revision: 1, lastEvent: 'SUBMIT', decidedBy: null, ...audit(uid), ...overrides,
  };
}

const historyDoc = ({ id, rev, from, to, event, actor, kind = 'STUDENT', subjectId = 'stu-1', applicant, remarks = null, overrides = {} }) => ({
  schoolId: A, branchId: NORTH, applicationId: id, revision: rev, fromStatus: from, toStatus: to, event, actorId: actor, actorName: 'X',
  remarks, at: serverTimestamp(), applicantUserId: applicant ?? actor, subjectKind: kind, subjectId, ...overrides,
});

const lockDoc = ({ id, uid, kind = 'STUDENT', subjectId = 'stu-1', dateKey, slot }) => ({
  schoolId: A, branchId: NORTH, lockedBy: uid, applicationId: id, subjectKind: kind, subjectId, dateKey, slot,
});

const notifDoc = ({ id, rev, audience, recipient = null, type, uid }) => ({
  schoolId: A, branchId: NORTH, audience, recipientUserId: recipient, type, applicationId: id, revision: rev, title: 't',
  createdBy: uid, createdAt: serverTimestamp(), readAt: null,
});

/** Submission, exactly as the app writes it: application + history + locks + reviewer notice. */
function submitBatch(db, uid, o) {
  const { id } = o;
  const app = appDoc({ uid, ...o });
  const batch = writeBatch(db);
  batch.set(ref(db, 'leaveApplications', id), app);
  batch.set(ref(db, 'leaveHistory', `${id}__1`), historyDoc({ id, rev: 1, from: null, to: 'PENDING', event: 'SUBMIT', actor: uid, kind: app.subjectKind, subjectId: app.subjectId, applicant: uid }));
  if (!o.skipLocks) {
    for (const l of lockIds(app.subjectKind, app.subjectId, app.countedDateKeys, app.halfDay)) {
      batch.set(ref(db, 'leaveDayLocks', l), lockDoc({ id, uid, kind: app.subjectKind, subjectId: app.subjectId, dateKey: l.split('__')[1], slot: l.split('__')[2] }));
    }
  }
  batch.set(ref(db, 'notifications', `${id}__SUBMIT__1__REVIEWERS`), notifDoc({ id, rev: 1, audience: 'REVIEWERS', type: 'LEAVE_SUBMITTED', uid }));
  return batch;
}

/** A decision on a PENDING application (APPROVED / REJECTED / RETURNED). */
function decideBatch(db, uid, { id, to, kind = 'STUDENT', subjectId = 'stu-1', applicant = 'lv-parent', remarks = null, units = 4, dates = DAYS, half = 'NONE', balance = null, skip = [], appOverrides = {} }) {
  const event = { APPROVED: 'APPROVE', REJECTED: 'REJECT', RETURNED: 'RETURN' }[to];
  const batch = writeBatch(db);
  if (!skip.includes('app')) {
    batch.update(ref(db, 'leaveApplications', id), {
      status: to, revision: 2, lastEvent: event, decidedBy: uid, decidedByName: 'Admin', decidedAt: serverTimestamp(), decisionRemarks: remarks,
      updatedAt: serverTimestamp(), updatedBy: uid, ...appOverrides,
    });
  }
  if (!skip.includes('history')) {
    batch.set(ref(db, 'leaveHistory', `${id}__2`), historyDoc({ id, rev: 2, from: 'PENDING', to, event, actor: uid, kind, subjectId, applicant, remarks }));
  }
  if (to === 'APPROVED') {
    if (!skip.includes('calendar')) {
      batch.set(ref(db, 'leaveCalendar', id), {
        schoolId: A, branchId: NORTH, subjectKind: kind, subjectId, subjectName: 'Anil', academicYearId: YEAR, classId: 'c5', sectionId: 'sa',
        startDateKey: dates[0], endDateKey: dates[dates.length - 1], halfDay: half, countedDateKeys: dates, status: 'ACTIVE',
      });
    }
    if (balance && !skip.includes('ledger')) {
      batch.set(ref(db, 'leaveLedger', `${id}__consume`), {
        schoolId: A, branchId: NORTH, staffId: subjectId, typeId: balance.typeId, academicYearId: YEAR, balanceId: balance.id,
        entryType: 'CONSUME', units: balance.units ?? units, applicationId: id, actorId: uid, actorName: 'Admin', at: serverTimestamp(),
      });
      if (!skip.includes('balance')) {
        if (balance.exists) {
          batch.update(ref(db, 'leaveBalances', balance.id), {
            consumedUnits: (balance.consumed ?? 0) + (balance.units ?? units), lastLedgerId: `${id}__consume`, updatedAt: serverTimestamp(), updatedBy: uid,
          });
        } else {
          batch.set(ref(db, 'leaveBalances', balance.id), {
            schoolId: A, branchId: NORTH, staffId: subjectId, typeId: balance.typeId, academicYearId: YEAR, leaveYearStartKey: '2026-06-01',
            entitlementUnits: balance.entitlement ?? 24, accrual: 'UPFRONT', exceedPolicy: balance.exceed ?? 'BLOCK', carryForwardUnits: 0,
            adjustmentUnits: 0, consumedUnits: balance.units ?? units, lastLedgerId: `${id}__consume`, ...audit(uid),
          });
        }
      }
    }
  } else {
    for (const l of lockIds(kind, subjectId, dates, half)) batch.delete(ref(db, 'leaveDayLocks', l));
  }
  const recipient = applicant;
  batch.set(ref(db, 'notifications', `${id}__${event}__2__${recipient}`), notifDoc({ id, rev: 2, audience: 'USER', recipient, type: `LEAVE_${to === 'RETURNED' ? 'RETURNED' : to}`, uid }));
  return batch;
}

function cancelBatch(db, uid, { id, kind = 'STUDENT', subjectId = 'stu-1', applicant = 'lv-parent', dates = DAYS, half = 'NONE', remarks = 'Child will attend', balance = null, skip = [] }) {
  const batch = writeBatch(db);
  batch.update(ref(db, 'leaveApplications', id), {
    status: 'CANCELLED', revision: 3, lastEvent: 'CANCEL', decidedBy: uid, decidedByName: 'Admin', decidedAt: serverTimestamp(), decisionRemarks: remarks,
    updatedAt: serverTimestamp(), updatedBy: uid,
  });
  batch.set(ref(db, 'leaveHistory', `${id}__3`), historyDoc({ id, rev: 3, from: 'APPROVED', to: 'CANCELLED', event: 'CANCEL', actor: uid, kind, subjectId, applicant, remarks }));
  if (!skip.includes('calendar')) batch.update(ref(db, 'leaveCalendar', id), { status: 'CANCELLED' });
  if (balance && !skip.includes('ledger')) {
    batch.set(ref(db, 'leaveLedger', `${id}__restore`), {
      schoolId: A, branchId: NORTH, staffId: subjectId, typeId: balance.typeId, academicYearId: YEAR, balanceId: balance.id,
      entryType: 'RESTORE', units: balance.units, applicationId: id, actorId: uid, actorName: 'Admin', at: serverTimestamp(),
    });
    batch.update(ref(db, 'leaveBalances', balance.id), {
      consumedUnits: balance.consumed - balance.units, lastLedgerId: `${id}__restore`, updatedAt: serverTimestamp(), updatedBy: uid,
    });
  }
  for (const l of lockIds(kind, subjectId, dates, half)) batch.delete(ref(db, 'leaveDayLocks', l));
  return batch;
}

async function seedWorld() {
  counter += 1;
  A = `lv-a-${counter}`;
  B = `lv-b-${counter}`;
  await seed(async (db) => {
    for (const s of [A, B]) {
      await setDoc(doc(db, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      for (const b of s === A ? [NORTH, SOUTH] : [NORTH]) await setDoc(doc(db, ...branch(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'lv-admin': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'lv-admin2': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'lv-admin-b': { schoolId: B, branchId: NORTH, role: 'SCHOOL_ADMIN' },
      'lv-br-north': { schoolId: A, branchId: NORTH, role: 'BRANCH_ADMIN' },
      'lv-br-south': { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' },
      'lv-teacher': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'lv-teacher2': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'lv-fin': { schoolId: A, branchId: NORTH, role: 'FINANCE' },
      'lv-parent': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'parent-1' },
      'lv-parent2': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'parent-2' },
    };
    for (const [uid, u] of Object.entries(users)) await setDoc(doc(db, 'users', uid), userDoc(u));
    const n = branch(A, NORTH);
    for (const [sid, name] of [['stu-1', 'Anil'], ['stu-2', 'Bina']]) {
      await setDoc(doc(db, ...n, 'students', sid), { schoolId: A, branchId: NORTH, status: 'ACTIVE', displayName: name, ...audit('seed') });
    }
    await setDoc(doc(db, ...n, 'students', 'stu-1', 'parentLinks', 'parent-1'), { schoolId: A, branchId: NORTH, studentId: 'stu-1', parentId: 'parent-1', canAccessPortal: true, status: 'ACTIVE', ...audit('seed') });
    await setDoc(doc(db, ...n, 'students', 'stu-2', 'parentLinks', 'parent-2'), { schoolId: A, branchId: NORTH, studentId: 'stu-2', parentId: 'parent-2', canAccessPortal: true, status: 'ACTIVE', ...audit('seed') });
    for (const [sid, uid] of [['staff-t', 'lv-teacher'], ['staff-t2', 'lv-teacher2'], ['staff-f', 'lv-fin']]) {
      await setDoc(doc(db, ...n, 'staff', sid), { schoolId: A, branchId: NORTH, userId: uid, status: 'ACTIVE', ...audit('seed') });
    }
    // teacherAccess (server-written in production): lv-teacher teaches Class 5-A, lv-teacher2 nothing.
    await setDoc(doc(db, ...n, 'teacherAccess', 'lv-teacher'), { schoolId: A, branchId: NORTH, staffId: 'staff-t', userId: 'lv-teacher', sectionKeys: ['c5__sa'], scopes: [], updatedAt: serverTimestamp() });
    const t = (id, d) => setDoc(ref(db, 'leaveTypes', id), d);
    await t('STUDENT__sick', typeDoc({ kind: 'STUDENT', code: 'SICK', name: 'Sick leave', payType: 'NA' }));
    await t('STUDENT__medical', typeDoc({ kind: 'STUDENT', code: 'MEDICAL', name: 'Medical', payType: 'NA', requiresDocument: true }));
    await t('STUDENT__old', typeDoc({ kind: 'STUDENT', code: 'OLD', name: 'Old', payType: 'NA', status: 'INACTIVE' }));
    await t('STUDENT__short', typeDoc({ kind: 'STUDENT', code: 'SHORT', name: 'Short', payType: 'NA', maxDays: 1 }));
    await t('STAFF__cl', typeDoc({ kind: 'STAFF', code: 'CL', name: 'Casual leave', payType: 'PAID', entitlement: 24 }));
    await t('STAFF__warn', typeDoc({ kind: 'STAFF', code: 'WARN', name: 'Warn leave', payType: 'PAID', entitlement: 2, exceed: 'WARN' }));
    await t('STAFF__ul', typeDoc({ kind: 'STAFF', code: 'UL', name: 'Unpaid', payType: 'UNPAID' }));
  });
}

const LEAVE_BAL = (staff = 'staff-t', type = 'STAFF__cl') => `${staff}__${type}__${YEAR}`;
const staffApp = (id, o = {}) => ({
  id, kind: 'STAFF', subjectId: 'staff-t', relation: 'SELF', typeId: 'STAFF__cl', typeName: 'Casual leave', payType: 'PAID',
  balanceId: LEAVE_BAL(), ...o,
});
const submitStudent = async (id = 'l-1', uid = 'lv-parent', o = {}) => assertSucceeds(submitBatch(asUser(uid), uid, { id, ...o }).commit());
const submitStaff = async (id = 'l-s1', uid = 'lv-teacher', o = {}) => assertSucceeds(submitBatch(asUser(uid), uid, staffApp(id, o)).commit());

// ===================================================================== TESTS

test('Tenant isolation: School B users cannot read or write any School A leave data', async () => {
  await seedWorld();
  await submitStudent();
  const db = asUser('lv-admin-b');
  await assertFails(getDoc(ref(db, 'leaveApplications', 'l-1')));
  await assertFails(getDocs(col(db, 'leaveApplications')));
  await assertFails(getDocs(col(db, 'leaveCalendar')));
  await assertFails(getDoc(ref(db, 'leaveTypes', 'STUDENT__sick')));
  await assertFails(decideBatch(db, 'lv-admin-b', { id: 'l-1', to: 'APPROVED' }).commit());
  await assertFails(setDoc(ref(db, 'leaveTypes', 'STUDENT__evil'), typeDoc({ kind: 'STUDENT', code: 'EVIL', name: 'Evil', payType: 'NA', uid: 'lv-admin-b' })));
});

test('Branch isolation: South branch admin cannot read or decide North leave; the school admin spans branches', async () => {
  await seedWorld();
  await submitStudent();
  const south = asUser('lv-br-south');
  await assertFails(getDoc(ref(south, 'leaveApplications', 'l-1')));
  await assertFails(decideBatch(south, 'lv-br-south', { id: 'l-1', to: 'APPROVED' }).commit());
  await assertSucceeds(getDoc(ref(asUser('lv-admin'), 'leaveApplications', 'l-1')));
  await assertSucceeds(getDoc(ref(asUser('lv-br-north'), 'leaveApplications', 'l-1')));
});

test('Parent submits for the LINKED child only; cannot file for another child, as ADMIN, or as someone else', async () => {
  await seedWorld();
  await submitStudent('l-ok');
  const db = asUser('lv-parent');
  // another parent's child
  await assertFails(submitBatch(db, 'lv-parent', { id: 'l-x1', subjectId: 'stu-2' }).commit());
  // claiming to be an admin filing on behalf
  await assertFails(submitBatch(db, 'lv-parent', { id: 'l-x2', relation: 'ADMIN' }).commit());
  // spoofing the applicant
  await assertFails(submitBatch(db, 'lv-parent', { id: 'l-x3', overrides: { applicantUserId: 'lv-parent2' } }).commit());
  // a parent cannot file STAFF leave
  await assertFails(submitBatch(db, 'lv-parent', staffApp('l-x4', { relation: 'SELF' })).commit());
  // a withdrawn portal link is not enough
  await seed((d) => updateDoc(doc(d, ...branch(A, NORTH), 'students', 'stu-1', 'parentLinks', 'parent-1'), { canAccessPortal: false }));
  await assertFails(submitBatch(db, 'lv-parent', { id: 'l-x5', dates: ['2026-08-10'] }).commit());
});

test('Applications are private: the applicant, the linked parent and reviewers read; teachers, finance and other parents cannot', async () => {
  await seedWorld();
  await submitStudent();
  await assertSucceeds(getDoc(ref(asUser('lv-parent'), 'leaveApplications', 'l-1')));
  await assertSucceeds(getDocs(query(col(asUser('lv-parent'), 'leaveApplications'), where('subjectKind', '==', 'STUDENT'), where('subjectId', '==', 'stu-1'))));
  for (const uid of ['lv-teacher', 'lv-fin', 'lv-parent2']) {
    await assertFails(getDoc(ref(asUser(uid), 'leaveApplications', 'l-1')));
    await assertFails(getDocs(col(asUser(uid), 'leaveApplications')));
  }
  await assertFails(getDocs(query(col(asUser('lv-parent2'), 'leaveApplications'), where('subjectKind', '==', 'STUDENT'), where('subjectId', '==', 'stu-1'))));
});

test('Submission validation: reason, document, type state, units, dates, half days', async () => {
  await seedWorld();
  const db = asUser('lv-parent');
  const bad = async (id, o) => assertFails(submitBatch(db, 'lv-parent', { id, dates: ['2026-09-07'], ...o }).commit());
  await bad('v1', { reason: '' });
  await bad('v2', { typeId: 'STUDENT__medical', typeName: 'Medical', attachments: [] });
  await bad('v3', { typeId: 'STUDENT__old', typeName: 'Old' });
  await bad('v4', { units: 4 }); // 1 day, claims 2 days
  await bad('v5', { typeName: 'Renamed' }); // snapshot must match the type
  await bad('v6', { overrides: { endDateKey: '2026-09-01' } });
  await bad('v7', { half: 'FIRST', dates: ['2026-09-07', '2026-09-08'] });
  await bad('v8', { typeId: 'STUDENT__short', typeName: 'Short', dates: ['2026-09-07', '2026-09-08'] });
  await bad('v9', { typeId: 'STUDENT__nope', typeName: 'x' });
  await bad('v10', { overrides: { status: 'APPROVED' } });
  await bad('v11', { overrides: { decidedBy: 'lv-admin' } });
  await bad('v12', { attachments: [1, 2, 3, 4] });
  // valid ones
  await assertSucceeds(submitBatch(db, 'lv-parent', { id: 'good1', dates: ['2026-09-07'], half: 'FIRST' }).commit());
  await assertSucceeds(submitBatch(db, 'lv-parent', {
    id: 'good2', dates: ['2026-09-08'], typeId: 'STUDENT__medical', typeName: 'Medical',
    attachments: [{ path: 'p', name: 'n.pdf', contentType: 'application/pdf', sizeBytes: 10 }],
  }).commit());
});

test('A submission needs its history record; an application cannot be created already decided', async () => {
  await seedWorld();
  const db = asUser('lv-parent');
  const batch = writeBatch(db);
  batch.set(ref(db, 'leaveApplications', 'nohist'), appDoc({ id: 'nohist', uid: 'lv-parent' }));
  await assertFails(batch.commit());
});

test('OVERLAP: a second application for the same dates is impossible, even when submitted concurrently', async () => {
  await seedWorld();
  await submitStudent('first');
  // second application, overlapping Tuesday
  await assertFails(submitBatch(asUser('lv-parent'), 'lv-parent', { id: 'second', dates: ['2026-08-04', '2026-08-05'] }).commit());
  // non-overlapping is fine
  await assertSucceeds(submitBatch(asUser('lv-parent'), 'lv-parent', { id: 'third', dates: ['2026-08-05'] }).commit());
});

test('Half days: two sessions of one date coexist; a half and a full day do not', async () => {
  await seedWorld();
  const db = asUser('lv-parent');
  await assertSucceeds(submitBatch(db, 'lv-parent', { id: 'h1', dates: ['2026-08-10'], half: 'FIRST' }).commit());
  await assertSucceeds(submitBatch(db, 'lv-parent', { id: 'h2', dates: ['2026-08-10'], half: 'SECOND' }).commit());
  await assertFails(submitBatch(db, 'lv-parent', { id: 'h3', dates: ['2026-08-10'], half: 'FIRST' }).commit());
  await assertFails(submitBatch(db, 'lv-parent', { id: 'h4', dates: ['2026-08-10'] }).commit());
});

test('A lock cannot be forged without an application of the caller for that subject', async () => {
  await seedWorld();
  const db = asUser('lv-parent');
  await assertFails(setDoc(ref(db, 'leaveDayLocks', 'STUDENT_stu-2__2026-08-20__FIRST'), lockDoc({ id: 'ghost', uid: 'lv-parent', subjectId: 'stu-2', dateKey: '2026-08-20', slot: 'FIRST' })));
  // a lock cannot be deleted by its owner while the application still holds days
  await submitStudent('own');
  await assertFails(deleteDoc(ref(db, 'leaveDayLocks', 'STUDENT_stu-1__2026-08-03__FIRST')));
});

test('Staff self-service: own leave only; another staff member and parent-style filings are refused', async () => {
  await seedWorld();
  await submitStaff('s-ok');
  await assertFails(submitBatch(asUser('lv-teacher'), 'lv-teacher', staffApp('s-other', { subjectId: 'staff-t2', balanceId: LEAVE_BAL('staff-t2'), dates: ['2026-09-07'] })).commit());
  await assertFails(submitBatch(asUser('lv-teacher'), 'lv-teacher', staffApp('s-adm', { relation: 'ADMIN', dates: ['2026-09-07'] })).commit());
  // another teacher cannot read it; finance cannot; the owner and admins can
  await assertFails(getDoc(ref(asUser('lv-teacher2'), 'leaveApplications', 's-ok')));
  await assertFails(getDoc(ref(asUser('lv-fin'), 'leaveApplications', 's-ok')));
  await assertSucceeds(getDoc(ref(asUser('lv-teacher'), 'leaveApplications', 's-ok')));
  await assertSucceeds(getDoc(ref(asUser('lv-br-north'), 'leaveApplications', 's-ok')));
});

test('Staff balance ceiling: BLOCK refuses a request over the entitlement; WARN allows it; unpaid is untracked', async () => {
  await seedWorld();
  const many = ['2026-08-03', '2026-08-04', '2026-08-05', '2026-08-06', '2026-08-07', '2026-08-10', '2026-08-11', '2026-08-12', '2026-08-13', '2026-08-14', '2026-08-17', '2026-08-18', '2026-08-19'];
  // 13 days = 26 units > 24 entitlement
  await assertFails(submitBatch(asUser('lv-teacher'), 'lv-teacher', staffApp('big', { dates: many })).commit());
  // WARN type: 2 units entitlement, 4 requested is allowed (the client warns)
  await assertSucceeds(submitBatch(asUser('lv-teacher'), 'lv-teacher', staffApp('warn', { typeId: 'STAFF__warn', typeName: 'Warn leave', balanceId: LEAVE_BAL('staff-t', 'STAFF__warn'), dates: ['2026-09-07', '2026-09-08'] })).commit());
  // unpaid leave: no balance check, balanceId stays null
  await assertSucceeds(submitBatch(asUser('lv-teacher'), 'lv-teacher', staffApp('unpaid', { typeId: 'STAFF__ul', typeName: 'Unpaid', payType: 'UNPAID', balanceId: null, dates: many })).commit());
});

test('Admin on behalf: refused unless the branch policy allows it', async () => {
  await seedWorld();
  const db = asUser('lv-admin');
  await assertFails(submitBatch(db, 'lv-admin', { id: 'ob1', relation: 'ADMIN' }).commit());
  await seed((d) => setDoc(ref(d, 'leaveSettings', 'policy'), { schoolId: A, branchId: NORTH, allowAdminOnBehalf: true, updatedBy: 'seed' }));
  await assertSucceeds(submitBatch(db, 'lv-admin', { id: 'ob2', relation: 'ADMIN' }).commit());
  // a teacher still cannot use it
  await assertFails(submitBatch(asUser('lv-teacher'), 'lv-teacher', { id: 'ob3', relation: 'ADMIN', dates: ['2026-09-07'] }).commit());
});

test('Calendar entries are minimal: teachers read student entries (no reason), never staff entries', async () => {
  await seedWorld();
  await submitStudent();
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'l-1', to: 'APPROVED' }).commit());
  const cal = (await getDoc(ref(asUser('lv-teacher'), 'leaveCalendar', 'l-1'))).data();
  assert_no_sensitive(cal);
  // A teacher reads student entries only for a section they teach (class + section pinned).
  await assertSucceeds(getDoc(ref(asUser('lv-teacher'), 'leaveCalendar', 'l-1')));
  await assertSucceeds(getDocs(query(col(asUser('lv-teacher'), 'leaveCalendar'), where('subjectKind', '==', 'STUDENT'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'))));
  await assertFails(getDocs(query(col(asUser('lv-teacher'), 'leaveCalendar'), where('subjectKind', '==', 'STUDENT'))));
  await assertFails(getDoc(ref(asUser('lv-teacher2'), 'leaveCalendar', 'l-1')));
  await assertSucceeds(getDoc(ref(asUser('lv-parent'), 'leaveCalendar', 'l-1')));
  await assertFails(getDoc(ref(asUser('lv-parent2'), 'leaveCalendar', 'l-1')));
  await assertFails(getDoc(ref(asUser('lv-admin-b'), 'leaveCalendar', 'l-1')));

  await submitStaff('s-1');
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 's-1', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', units: 4, balance: { id: LEAVE_BAL(), typeId: 'STAFF__cl' } }).commit());
  await assertFails(getDoc(ref(asUser('lv-teacher2'), 'leaveCalendar', 's-1')));
  await assertFails(getDoc(ref(asUser('lv-fin'), 'leaveCalendar', 's-1')));
  await assertSucceeds(getDoc(ref(asUser('lv-teacher'), 'leaveCalendar', 's-1')));
});

function assert_no_sensitive(cal) {
  for (const k of ['reason', 'attachments', 'typeId', 'typeName', 'applicantUserId']) {
    if (k in cal) throw new Error(`calendar entry leaks ${k}`);
  }
}

test('Approval: a reviewer approves; the calendar entry must come in the same commit', async () => {
  await seedWorld();
  await submitStudent();
  const admin = asUser('lv-admin');
  await assertFails(decideBatch(admin, 'lv-admin', { id: 'l-1', to: 'APPROVED', skip: ['calendar'] }).commit());
  await assertFails(decideBatch(admin, 'lv-admin', { id: 'l-1', to: 'APPROVED', skip: ['history'] }).commit());
  await assertSucceeds(decideBatch(admin, 'lv-admin', { id: 'l-1', to: 'APPROVED' }).commit());
});

test('Only authorized reviewers decide: parent, teacher, finance and the applicant cannot', async () => {
  await seedWorld();
  await submitStudent();
  for (const uid of ['lv-parent', 'lv-teacher', 'lv-fin', 'lv-parent2']) {
    await assertFails(decideBatch(asUser(uid), uid, { id: 'l-1', to: 'APPROVED' }).commit());
  }
  await assertSucceeds(decideBatch(asUser('lv-br-north'), 'lv-br-north', { id: 'l-1', to: 'APPROVED' }).commit());
});

test('SELF-APPROVAL: an admin who filed on behalf cannot decide it; neither can a reviewer deciding their own staff leave', async () => {
  await seedWorld();
  await seed((d) => setDoc(ref(d, 'leaveSettings', 'policy'), { schoolId: A, branchId: NORTH, allowAdminOnBehalf: true, updatedBy: 'seed' }));
  await assertSucceeds(submitBatch(asUser('lv-admin'), 'lv-admin', { id: 'ob', relation: 'ADMIN' }).commit());
  await assertFails(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'ob', to: 'APPROVED', applicant: 'lv-admin' }).commit());
  await assertSucceeds(decideBatch(asUser('lv-admin2'), 'lv-admin2', { id: 'ob', to: 'APPROVED', applicant: 'lv-admin' }).commit());

  // a branch admin who has a staff record and applies for their own leave
  await seed((d) => setDoc(doc(d, ...branch(A, NORTH), 'staff', 'staff-br'), { schoolId: A, branchId: NORTH, userId: 'lv-br-north', status: 'ACTIVE', ...audit('seed') }));
  await assertSucceeds(submitBatch(asUser('lv-br-north'), 'lv-br-north', staffApp('self', { subjectId: 'staff-br', balanceId: LEAVE_BAL('staff-br') })).commit());
  await assertFails(decideBatch(asUser('lv-br-north'), 'lv-br-north', {
    id: 'self', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-br', applicant: 'lv-br-north', balance: { id: LEAVE_BAL('staff-br'), typeId: 'STAFF__cl' },
  }).commit());
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', {
    id: 'self', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-br', applicant: 'lv-br-north', balance: { id: LEAVE_BAL('staff-br'), typeId: 'STAFF__cl' },
  }).commit());
});

test('CONCURRENCY: two reviewers decide the same pending application — exactly one commit wins', async () => {
  await seedWorld();
  await submitStudent();
  const a = decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'l-1', to: 'APPROVED' });
  const b = decideBatch(asUser('lv-admin2'), 'lv-admin2', { id: 'l-1', to: 'REJECTED', remarks: 'No' });
  const results = await Promise.allSettled([a.commit(), b.commit()]);
  assertEq(results.filter((r) => r.status === 'fulfilled').length, 1);
  // and a repeated click of the winner changes nothing
  await assertFails(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'l-1', to: 'APPROVED' }).commit());
});

function assertEq(a, b) {
  if (a !== b) throw new Error(`expected ${b}, got ${a}`);
}

test('Rejection and return need a reason, release the day-locks, and cannot be decided again', async () => {
  await seedWorld();
  await submitStudent();
  const admin = asUser('lv-admin');
  await assertFails(decideBatch(admin, 'lv-admin', { id: 'l-1', to: 'REJECTED', remarks: '' }).commit());
  await assertSucceeds(decideBatch(admin, 'lv-admin', { id: 'l-1', to: 'REJECTED', remarks: 'Exams that week' }).commit());
  // dates are free again
  await assertSucceeds(submitBatch(asUser('lv-parent'), 'lv-parent', { id: 'again' }).commit());
  // the rejected application is final
  await assertFails(decideBatch(admin, 'lv-admin', { id: 'l-1', to: 'APPROVED' }).commit());
});

test('Locks cannot be deleted while the application is still pending or approved (no bypass of the overlap guard)', async () => {
  await seedWorld();
  await submitStudent();
  await assertFails(deleteDoc(ref(asUser('lv-admin'), 'leaveDayLocks', 'STUDENT_stu-1__2026-08-03__FIRST')));
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'l-1', to: 'APPROVED' }).commit());
  await assertFails(deleteDoc(ref(asUser('lv-parent'), 'leaveDayLocks', 'STUDENT_stu-1__2026-08-03__FIRST')));
});

test('Return for correction, then resubmit; a resubmission must stay valid', async () => {
  await seedWorld();
  await submitStudent();
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'l-1', to: 'RETURNED', remarks: 'Add the doctor note' }).commit());
  const parent = asUser('lv-parent');
  const resubmit = (units = 4, dates = DAYS, extra = {}) => {
    const b = writeBatch(parent);
    b.update(ref(parent, 'leaveApplications', 'l-1'), {
      status: 'PENDING', revision: 3, lastEvent: 'RESUBMIT', reason: 'Fever and rest', units, countedDateKeys: dates,
      startDateKey: dates[0], endDateKey: dates[dates.length - 1], decidedBy: null, decisionRemarks: null,
      updatedAt: serverTimestamp(), updatedBy: 'lv-parent', ...extra,
    });
    b.set(ref(parent, 'leaveHistory', 'l-1__3'), historyDoc({ id: 'l-1', rev: 3, from: 'RETURNED', to: 'PENDING', event: 'RESUBMIT', actor: 'lv-parent', applicant: 'lv-parent' }));
    for (const l of lockIds('STUDENT', 'stu-1', dates)) b.set(ref(parent, 'leaveDayLocks', l), lockDoc({ id: 'l-1', uid: 'lv-parent', dateKey: l.split('__')[1], slot: l.split('__')[2] }));
    return b;
  };
  await assertFails(resubmit(2).commit()); // units no longer match the days
  await assertSucceeds(resubmit(4).commit());
});

test('Withdrawal: only the applicant, only pending/returned; approved leave cannot be withdrawn', async () => {
  await seedWorld();
  await submitStudent();
  const withdraw = (db, uid) => {
    const b = writeBatch(db);
    b.update(ref(db, 'leaveApplications', 'l-1'), { status: 'WITHDRAWN', revision: 2, lastEvent: 'WITHDRAW', updatedAt: serverTimestamp(), updatedBy: uid });
    b.set(ref(db, 'leaveHistory', 'l-1__2'), historyDoc({ id: 'l-1', rev: 2, from: 'PENDING', to: 'WITHDRAWN', event: 'WITHDRAW', actor: uid, applicant: 'lv-parent' }));
    for (const l of lockIds('STUDENT', 'stu-1', DAYS)) b.delete(ref(db, 'leaveDayLocks', l));
    return b;
  };
  await assertFails(withdraw(asUser('lv-parent2'), 'lv-parent2').commit());
  await assertFails(withdraw(asUser('lv-teacher'), 'lv-teacher').commit());
  await assertSucceeds(withdraw(asUser('lv-parent'), 'lv-parent').commit());

  await submitStudent('l-2', 'lv-parent', { dates: ['2026-09-07'] });
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'l-2', to: 'APPROVED', dates: ['2026-09-07'], units: 2 }).commit());
  const pdb = asUser('lv-parent');
  const b = writeBatch(pdb);
  b.update(ref(pdb, 'leaveApplications', 'l-2'), { status: 'WITHDRAWN', revision: 3, lastEvent: 'WITHDRAW', updatedAt: serverTimestamp(), updatedBy: 'lv-parent' });
  b.set(ref(pdb, 'leaveHistory', 'l-2__3'), historyDoc({ id: 'l-2', rev: 3, from: 'APPROVED', to: 'WITHDRAWN', event: 'WITHDRAW', actor: 'lv-parent', applicant: 'lv-parent' }));
  await assertFails(b.commit());
});

test('An applicant cannot edit decision fields, status, units or anything on a pending application directly', async () => {
  await seedWorld();
  await submitStudent();
  const db = asUser('lv-parent');
  for (const patch of [
    { status: 'APPROVED' }, { decidedBy: 'lv-admin' }, { decisionRemarks: 'ok' }, { units: 2 }, { reason: 'changed' }, { subjectId: 'stu-2' },
    { applicantUserId: 'lv-parent2' }, { schoolId: B },
  ]) {
    await assertFails(updateDoc(ref(db, 'leaveApplications', 'l-1'), { ...patch, updatedAt: serverTimestamp(), updatedBy: 'lv-parent' }));
  }
  await assertFails(deleteDoc(ref(db, 'leaveApplications', 'l-1')));
  await assertFails(deleteDoc(ref(asUser('lv-admin'), 'leaveApplications', 'l-1')));
});

test('History is append-only and readable by the right people', async () => {
  await seedWorld();
  await submitStudent();
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'l-1', to: 'APPROVED' }).commit());
  const h = ref(asUser('lv-admin'), 'leaveHistory', 'l-1__2');
  await assertFails(updateDoc(h, { remarks: 'rewritten' }));
  await assertFails(deleteDoc(h));
  await assertSucceeds(getDoc(ref(asUser('lv-parent'), 'leaveHistory', 'l-1__2')));
  await assertFails(getDoc(ref(asUser('lv-parent2'), 'leaveHistory', 'l-1__2')));
  await assertFails(getDoc(ref(asUser('lv-teacher'), 'leaveHistory', 'l-1__2')));
  // a forged history entry for no real change
  await assertFails(setDoc(ref(asUser('lv-admin'), 'leaveHistory', 'l-1__9'), historyDoc({ id: 'l-1', rev: 9, from: 'APPROVED', to: 'CANCELLED', event: 'CANCEL', actor: 'lv-admin', applicant: 'lv-parent' })));
});

test('Staff leave consumption: approval consumes the balance once; a retry cannot deduct twice', async () => {
  await seedWorld();
  await submitStaff('s-1');
  const admin = asUser('lv-admin');
  const bal = { id: LEAVE_BAL(), typeId: 'STAFF__cl' };
  // without its ledger entry, or its balance, approval is refused
  await assertFails(decideBatch(admin, 'lv-admin', { id: 's-1', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', balance: bal, skip: ['ledger'] }).commit());
  await assertFails(decideBatch(admin, 'lv-admin', { id: 's-1', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', balance: bal, skip: ['balance'] }).commit());
  // ledger units must equal the application's
  await assertFails(decideBatch(admin, 'lv-admin', { id: 's-1', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', balance: { ...bal, units: 2 } }).commit());
  await assertSucceeds(decideBatch(admin, 'lv-admin', { id: 's-1', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', balance: bal }).commit());

  const b = (await getDoc(ref(admin, 'leaveBalances', bal.id))).data();
  assertEq(b.consumedUnits, 4);
  // retry the same approval: refused (not pending, ledger id taken)
  await assertFails(decideBatch(admin, 'lv-admin', { id: 's-1', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', balance: { ...bal, exists: true, consumed: 4 } }).commit());
  assertEq((await getDoc(ref(admin, 'leaveBalances', bal.id))).data().consumedUnits, 4);
  // the ledger entry cannot be rewritten
  await assertFails(updateDoc(ref(admin, 'leaveLedger', 's-1__consume'), { units: 0 }));
  await assertFails(deleteDoc(ref(admin, 'leaveLedger', 's-1__consume')));
});

test('The year ceiling holds under BLOCK: on submit, and again when a reviewer approves against a changed balance', async () => {
  await seedWorld();
  // two applications submitted while the balance is untouched
  await submitStaff('s-a', 'lv-teacher', { dates: ['2026-08-03', '2026-08-04'] });
  await submitStaff('s-b', 'lv-teacher', { dates: ['2026-08-10', '2026-08-11'] });
  // meanwhile 22 of 24 units get used
  await seed(async (d) => {
    await setDoc(ref(d, 'leaveBalances', LEAVE_BAL()), {
      schoolId: A, branchId: NORTH, staffId: 'staff-t', typeId: 'STAFF__cl', academicYearId: YEAR, leaveYearStartKey: '2026-06-01',
      entitlementUnits: 24, accrual: 'UPFRONT', exceedPolicy: 'BLOCK', carryForwardUnits: 0, adjustmentUnits: 0, consumedUnits: 22, lastLedgerId: 'seed', ...audit('seed'),
    });
  });
  const bal = { id: LEAVE_BAL(), typeId: 'STAFF__cl', exists: true, consumed: 22 };
  const admin = asUser('lv-admin');
  // 22 + 4 = 26 > 24: refused at approval
  await assertFails(decideBatch(admin, 'lv-admin', { id: 's-a', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', balance: bal }).commit());
  // and a new application over what is left is refused at submission
  await assertFails(submitBatch(asUser('lv-teacher'), 'lv-teacher', staffApp('s-c', { dates: ['2026-08-17', '2026-08-18'] })).commit());
  // a half day (1 unit) still fits
  await assertSucceeds(submitBatch(asUser('lv-teacher'), 'lv-teacher', staffApp('s-d', { dates: ['2026-08-19'], half: 'FIRST' })).commit());
  // a balance cannot be edited directly, by anyone
  for (const uid of ['lv-admin', 'lv-teacher']) {
    await assertFails(updateDoc(ref(asUser(uid), 'leaveBalances', LEAVE_BAL()), { consumedUnits: 0, updatedAt: serverTimestamp(), updatedBy: uid }));
  }
});

test('Cancelling approved leave restores the balance once; applicants cannot cancel; double restore refused', async () => {
  await seedWorld();
  await submitStaff('s-1');
  const bal = { id: LEAVE_BAL(), typeId: 'STAFF__cl' };
  const admin = asUser('lv-admin');
  await assertSucceeds(decideBatch(admin, 'lv-admin', { id: 's-1', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', balance: bal }).commit());
  const args = { id: 's-1', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', balance: { ...bal, units: 4, consumed: 4 } };

  await assertFails(cancelBatch(asUser('lv-teacher'), 'lv-teacher', args).commit());
  await assertFails(cancelBatch(admin, 'lv-admin', { ...args, remarks: '' }).commit());
  await assertFails(cancelBatch(admin, 'lv-admin', { ...args, skip: ['ledger'] }).commit());
  await assertFails(cancelBatch(admin, 'lv-admin', { ...args, skip: ['calendar'] }).commit());
  await assertSucceeds(cancelBatch(admin, 'lv-admin', args).commit());
  assertEq((await getDoc(ref(admin, 'leaveBalances', bal.id))).data().consumedUnits, 0);
  assertEq((await getDoc(ref(admin, 'leaveCalendar', 's-1'))).data().status, 'CANCELLED');
  // a second cancellation / restore is impossible
  await assertFails(cancelBatch(admin, 'lv-admin', { ...args, balance: { ...args.balance, consumed: 0 } }).commit());
  // the days are free again
  await assertSucceeds(submitBatch(asUser('lv-teacher'), 'lv-teacher', staffApp('s-2')).commit());
});

test('Manual adjustments: admin only, with a reason and a ledger entry; staff cannot adjust their own', async () => {
  await seedWorld();
  await seed(async (d) => {
    await setDoc(ref(d, 'leaveBalances', LEAVE_BAL()), {
      schoolId: A, branchId: NORTH, staffId: 'staff-t', typeId: 'STAFF__cl', academicYearId: YEAR, leaveYearStartKey: '2026-06-01',
      entitlementUnits: 24, accrual: 'UPFRONT', exceedPolicy: 'BLOCK', carryForwardUnits: 0, adjustmentUnits: 0, consumedUnits: 0, lastLedgerId: 'seed', ...audit('seed'),
    });
  });
  const adjust = (db, uid, { units = 4, reason = 'Granted for exam duty', id = 'adj-1', adjTotal = units } = {}) => {
    const b = writeBatch(db);
    b.set(ref(db, 'leaveLedger', id), {
      schoolId: A, branchId: NORTH, staffId: 'staff-t', typeId: 'STAFF__cl', academicYearId: YEAR, balanceId: LEAVE_BAL(),
      entryType: 'ADJUSTMENT', units, reason, actorId: uid, actorName: 'X', at: serverTimestamp(),
    });
    b.update(ref(db, 'leaveBalances', LEAVE_BAL()), { adjustmentUnits: adjTotal, lastLedgerId: id, updatedAt: serverTimestamp(), updatedBy: uid });
    return b;
  };
  await assertFails(adjust(asUser('lv-teacher'), 'lv-teacher').commit());
  await assertFails(adjust(asUser('lv-fin'), 'lv-fin').commit());
  await assertFails(adjust(asUser('lv-admin'), 'lv-admin', { reason: '' }).commit());
  await assertFails(adjust(asUser('lv-admin'), 'lv-admin', { adjTotal: 40 }).commit()); // balance moved more than the ledger says
  await assertSucceeds(adjust(asUser('lv-admin'), 'lv-admin').commit());
  // the staff member reads their own balance and ledger, not a colleague's
  await assertSucceeds(getDoc(ref(asUser('lv-teacher'), 'leaveBalances', LEAVE_BAL())));
  await assertSucceeds(getDoc(ref(asUser('lv-teacher'), 'leaveLedger', 'adj-1')));
  await assertFails(getDoc(ref(asUser('lv-teacher2'), 'leaveBalances', LEAVE_BAL())));
  await assertFails(updateDoc(ref(asUser('lv-teacher'), 'leaveBalances', LEAVE_BAL()), { adjustmentUnits: 100 }));
});

test('Leave types: everyone in the school reads; only admins write; shape and id are enforced; never deleted', async () => {
  await seedWorld();
  for (const uid of ['lv-parent', 'lv-teacher', 'lv-fin']) await assertSucceeds(getDoc(ref(asUser(uid), 'leaveTypes', 'STUDENT__sick')));
  await assertFails(getDoc(ref(asUser('lv-admin-b'), 'leaveTypes', 'STUDENT__sick')));
  for (const uid of ['lv-parent', 'lv-teacher', 'lv-fin']) {
    await assertFails(setDoc(ref(asUser(uid), 'leaveTypes', 'STUDENT__x'), typeDoc({ kind: 'STUDENT', code: 'X', name: 'Xx', payType: 'NA', uid })));
  }
  const admin = asUser('lv-admin');
  await assertSucceeds(setDoc(ref(admin, 'leaveTypes', 'STUDENT__trip'), typeDoc({ kind: 'STUDENT', code: 'TRIP', name: 'School trip', payType: 'NA', uid: 'lv-admin' })));
  await assertFails(setDoc(ref(admin, 'leaveTypes', 'STUDENT__wrongid'), typeDoc({ kind: 'STUDENT', code: 'TRIP2', name: 'Trip', payType: 'NA', uid: 'lv-admin' })));
  await assertFails(setDoc(ref(admin, 'leaveTypes', 'STUDENT__ent'), typeDoc({ kind: 'STUDENT', code: 'ENT', name: 'Ent', payType: 'NA', entitlement: 10, uid: 'lv-admin' })));
  await assertFails(setDoc(ref(admin, 'leaveTypes', 'STAFF__na'), typeDoc({ kind: 'STAFF', code: 'NA', name: 'Na', payType: 'NA', uid: 'lv-admin' })));
  await assertFails(deleteDoc(ref(admin, 'leaveTypes', 'STUDENT__sick')));
  // deactivating keeps history intact; an existing application is unaffected
  await assertSucceeds(updateDoc(ref(admin, 'leaveTypes', 'STUDENT__sick'), { status: 'INACTIVE', updatedAt: serverTimestamp(), updatedBy: 'lv-admin' }));
  // cannot change kind or code of an existing type
  await assertFails(updateDoc(ref(admin, 'leaveTypes', 'STUDENT__trip'), { code: 'OTHER', updatedAt: serverTimestamp(), updatedBy: 'lv-admin' }));
  await assertFails(updateDoc(ref(asUser('lv-br-south'), 'leaveTypes', 'STUDENT__trip'), { name: 'Hijack', updatedAt: serverTimestamp(), updatedBy: 'lv-br-south' }));
});

test('Notifications: written with their event; only the recipient reads them; forging recipients is refused', async () => {
  await seedWorld();
  await submitStudent();
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'l-1', to: 'APPROVED' }).commit());
  const nid = 'l-1__APPROVE__2__lv-parent';
  await assertSucceeds(getDoc(ref(asUser('lv-parent'), 'notifications', nid)));
  await assertFails(getDoc(ref(asUser('lv-parent2'), 'notifications', nid)));
  await assertFails(getDoc(ref(asUser('lv-teacher'), 'notifications', nid)));
  // reviewer notices: reviewers only
  await assertSucceeds(getDoc(ref(asUser('lv-admin'), 'notifications', 'l-1__SUBMIT__1__REVIEWERS')));
  await assertFails(getDoc(ref(asUser('lv-parent'), 'notifications', 'l-1__SUBMIT__1__REVIEWERS')));
  await assertFails(getDoc(ref(asUser('lv-teacher'), 'notifications', 'l-1__SUBMIT__1__REVIEWERS')));
  // the recipient may only mark it read
  await assertSucceeds(updateDoc(ref(asUser('lv-parent'), 'notifications', nid), { readAt: serverTimestamp() }));
  await assertFails(updateDoc(ref(asUser('lv-parent'), 'notifications', nid), { title: 'edited' }));
  await assertFails(deleteDoc(ref(asUser('lv-parent'), 'notifications', nid)));
  // a notification cannot be planted for someone else without a matching event
  await assertFails(setDoc(ref(asUser('lv-parent2'), 'notifications', 'forged'), notifDoc({ id: 'l-1', rev: 2, audience: 'USER', recipient: 'lv-parent', type: 'LEAVE_REJECTED', uid: 'lv-parent2' })));
  await assertFails(setDoc(ref(asUser('lv-teacher'), 'notifications', 'forged2'), notifDoc({ id: 'nope', rev: 1, audience: 'USER', recipient: 'lv-teacher', type: 'LEAVE_APPROVED', uid: 'lv-teacher' })));
});

test('A 60-day application stays inside the platform limits (120 locks in one commit)', async () => {
  await seedWorld();
  const days = [];
  for (let i = 0; i < 60; i += 1) {
    const d = new Date(Date.UTC(2026, 7, 3 + i));
    days.push(d.toISOString().slice(0, 10));
  }
  await assertSucceeds(submitBatch(asUser('lv-parent'), 'lv-parent', { id: 'long', dates: days }).commit());
});

test('A bystander cannot plant a notification even with the right type for the current event', async () => {
  await seedWorld();
  await submitStudent();
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'l-1', to: 'APPROVED' }).commit());
  // event is APPROVE, rev 2: this is exactly the legitimate type/recipient, but written by a stranger
  await assertFails(setDoc(ref(asUser('lv-parent2'), 'notifications', 'plant'), notifDoc({ id: 'l-1', rev: 2, audience: 'USER', recipient: 'lv-parent', type: 'LEAVE_APPROVED', uid: 'lv-parent2' })));
  await assertFails(setDoc(ref(asUser('lv-teacher'), 'notifications', 'plant2'), notifDoc({ id: 'l-1', rev: 2, audience: 'REVIEWERS', type: 'LEAVE_APPROVED', uid: 'lv-teacher' })));
});

test('Restoring leave that was never consumed is impossible (cannot mint balance through a cancellation)', async () => {
  await seedWorld();
  // unpaid leave is untracked: no balanceId, no consume entry
  await submitBatch(asUser('lv-teacher'), 'lv-teacher', staffApp('u-1', { typeId: 'STAFF__ul', typeName: 'Unpaid', payType: 'UNPAID', balanceId: null }))
    .commit();
  await seed(async (d) => {
    await setDoc(ref(d, 'leaveBalances', LEAVE_BAL()), {
      schoolId: A, branchId: NORTH, staffId: 'staff-t', typeId: 'STAFF__cl', academicYearId: YEAR, leaveYearStartKey: '2026-06-01',
      entitlementUnits: 24, accrual: 'UPFRONT', exceedPolicy: 'BLOCK', carryForwardUnits: 0, adjustmentUnits: 0, consumedUnits: 10, lastLedgerId: 'seed', ...audit('seed'),
    });
  });
  const admin = asUser('lv-admin');
  await assertSucceeds(decideBatch(admin, 'lv-admin', { id: 'u-1', to: 'APPROVED', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher' }).commit());
  // cancel and try to refund 4 units into the CL balance through a restore entry
  await assertFails(cancelBatch(admin, 'lv-admin', {
    id: 'u-1', kind: 'STAFF', subjectId: 'staff-t', applicant: 'lv-teacher', balance: { id: LEAVE_BAL(), typeId: 'STAFF__cl', units: 4, consumed: 10 },
  }).commit());
  assertEq((await getDoc(ref(admin, 'leaveBalances', LEAVE_BAL()))).data().consumedUnits, 10);
});

test('The queries the app uses work for the right person and fail for everyone else', async () => {
  await seedWorld();
  await submitStaff('s-q');
  await submitStudent('stu-q', 'lv-parent', { dates: ['2026-09-14'] });

  // staff: their own history by (subjectKind, subjectId); the page's own query shape
  const own = query(col(asUser('lv-teacher'), 'leaveApplications'), where('subjectKind', '==', 'STAFF'), where('subjectId', '==', 'staff-t'));
  await assertSucceeds(getDocs(own));
  // another teacher asking for that staff member's history, or for everyone's
  await assertFails(getDocs(query(col(asUser('lv-teacher2'), 'leaveApplications'), where('subjectKind', '==', 'STAFF'), where('subjectId', '==', 'staff-t'))));
  await assertFails(getDocs(query(col(asUser('lv-teacher2'), 'leaveApplications'), where('subjectKind', '==', 'STAFF'))));
  await assertFails(getDocs(col(asUser('lv-teacher'), 'leaveApplications')));

  // reviewers' queue query: kind + status, ordered
  await assertSucceeds(getDocs(query(col(asUser('lv-admin'), 'leaveApplications'), where('subjectKind', '==', 'STUDENT'), where('status', '==', 'PENDING'))));
  await assertFails(getDocs(query(col(asUser('lv-parent'), 'leaveApplications'), where('subjectKind', '==', 'STUDENT'), where('status', '==', 'PENDING'))));

  // history of one application, for the people who may read it
  // (the app pins the subject too: rules can only prove access for a person
  // who is not a reviewer when the query names the subject)
  const h = (uid) => getDocs(query(
    col(asUser(uid), 'leaveHistory'),
    where('subjectKind', '==', 'STAFF'), where('subjectId', '==', 'staff-t'), where('applicationId', '==', 's-q'),
  ));
  await assertSucceeds(h('lv-teacher'));
  await assertSucceeds(h('lv-admin'));
  await assertFails(h('lv-teacher2'));
  await assertFails(h('lv-fin'));
  // and the parent's view of a child's history
  await assertSucceeds(getDocs(query(
    col(asUser('lv-parent'), 'leaveHistory'),
    where('subjectKind', '==', 'STUDENT'), where('subjectId', '==', 'stu-1'), where('applicationId', '==', 'stu-q'),
  )));
  await assertFails(getDocs(query(
    col(asUser('lv-parent2'), 'leaveHistory'),
    where('subjectKind', '==', 'STUDENT'), where('subjectId', '==', 'stu-1'), where('applicationId', '==', 'stu-q'),
  )));

  // a teacher's calendar window (students only) and a parent's own child
  await assertSucceeds(decideBatch(asUser('lv-admin'), 'lv-admin', { id: 'stu-q', to: 'APPROVED', dates: ['2026-09-14'], units: 2 }).commit());
  await assertSucceeds(getDocs(query(col(asUser('lv-teacher'), 'leaveCalendar'), where('subjectKind', '==', 'STUDENT'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), where('endDateKey', '>=', '2026-09-01'))));
  // a teacher's window must name a section they teach; the branch-wide window is refused
  await assertFails(getDocs(query(col(asUser('lv-teacher'), 'leaveCalendar'), where('subjectKind', '==', 'STUDENT'), where('endDateKey', '>=', '2026-09-01'))));
  await assertFails(getDocs(query(col(asUser('lv-teacher2'), 'leaveCalendar'), where('subjectKind', '==', 'STUDENT'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), where('endDateKey', '>=', '2026-09-01'))));
  await assertFails(getDocs(query(col(asUser('lv-teacher'), 'leaveCalendar'), where('subjectKind', '==', 'STAFF'), where('endDateKey', '>=', '2026-09-01'))));
  await assertSucceeds(getDocs(query(col(asUser('lv-parent'), 'leaveCalendar'), where('subjectKind', '==', 'STUDENT'), where('subjectId', '==', 'stu-1'), where('endDateKey', '>=', '2026-09-01'))));
  await assertFails(getDocs(query(col(asUser('lv-parent'), 'leaveCalendar'), where('subjectKind', '==', 'STUDENT'), where('endDateKey', '>=', '2026-09-01'))));

  // balances and ledger by staff member: their own, never a colleague's
  await seed(async (d) => {
    await setDoc(ref(d, 'leaveBalances', LEAVE_BAL()), {
      schoolId: A, branchId: NORTH, staffId: 'staff-t', typeId: 'STAFF__cl', academicYearId: YEAR, leaveYearStartKey: '2026-06-01',
      entitlementUnits: 24, accrual: 'UPFRONT', exceedPolicy: 'BLOCK', carryForwardUnits: 0, adjustmentUnits: 0, consumedUnits: 0, lastLedgerId: 'seed', ...audit('seed'),
    });
  });
  const bal = (uid) => getDocs(query(col(asUser(uid), 'leaveBalances'), where('staffId', '==', 'staff-t'), where('academicYearId', '==', YEAR)));
  await assertSucceeds(bal('lv-teacher'));
  await assertSucceeds(bal('lv-admin'));
  await assertFails(bal('lv-teacher2'));
  await assertFails(bal('lv-fin'));
  await assertSucceeds(getDocs(query(col(asUser('lv-admin'), 'leaveBalances'), where('academicYearId', '==', YEAR), where('typeId', '==', 'STAFF__cl'))));
  await assertFails(getDocs(query(col(asUser('lv-teacher'), 'leaveBalances'), where('academicYearId', '==', YEAR), where('typeId', '==', 'STAFF__cl'))));

  // notifications inbox: own only
  await assertSucceeds(getDocs(query(col(asUser('lv-parent'), 'notifications'), where('audience', '==', 'USER'), where('recipientUserId', '==', 'lv-parent'))));
  await assertFails(getDocs(query(col(asUser('lv-parent'), 'notifications'), where('audience', '==', 'USER'), where('recipientUserId', '==', 'lv-parent2'))));
  await assertFails(getDocs(query(col(asUser('lv-parent'), 'notifications'), where('audience', '==', 'REVIEWERS'))));
  await assertSucceeds(getDocs(query(col(asUser('lv-admin'), 'notifications'), where('audience', '==', 'REVIEWERS'))));
});

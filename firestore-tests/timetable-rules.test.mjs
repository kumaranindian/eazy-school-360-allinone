// Firestore security-rules tests for Milestone 8 — Timetable & Substitution
// (see ../firestore.rules and ../docs/milestone-8-timetable-substitution.md).
// Own school ids (`tt-a-<n>`) and uid prefix (`tt-`) so it can run beside the
// other files on the shared emulator.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, deleteDoc, where, writeBatch,
} from 'firebase/firestore';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

let A = 'tt-a';
let B = 'tt-b';
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
const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: uid });

const ttId = (section = 'sa', v = 1) => `${YEAR}__c5__${section}__v${v}`;
const entryId = (tt, weekday = 'MONDAY', slot = 'p1') => `${tt}__${weekday}__${slot}`;

// ---------------------------------------------------------------- builders

function timetableDoc({ section = 'sa', version = 1, uid, from = '2026-06-01', to = null, overrides = {} }) {
  return {
    schoolId: A, branchId: NORTH, academicYearId: YEAR, classId: 'c5', sectionId: section, className: 'Class 5', sectionName: section.toUpperCase(),
    version, status: 'DRAFT', name: 'Term 1', dayPeriodSets: { MONDAY: 'y1__regular', TUESDAY: 'y1__regular' },
    effectiveFromKey: from, effectiveToKey: to, entryCount: 0, teacherIds: [], copiedFrom: null, revision: 1, lastEvent: 'CREATED',
    publishedBy: null, publishedAt: null, ...audit(uid), ...overrides,
  };
}

const historyDoc = ({ tt, rev, toStatus, event, uid, version = 1 }) => ({
  schoolId: A, branchId: NORTH, academicYearId: YEAR, timetableId: tt, version, title: 'Class 5 SA', revision: rev, toStatus, event,
  actorId: uid, actorName: 'Admin', note: null, at: serverTimestamp(),
});

const entryDoc = ({ tt, section = 'sa', weekday = 'MONDAY', slot = 'p1', period = 1, start = 540, end = 580, subject = 'math', teacher = 'st1', room = null, overrides = {} }) => ({
  timetableId: tt, schoolId: A, branchId: NORTH, academicYearId: YEAR, classId: 'c5', sectionId: section, weekday, slotId: slot,
  periodNumber: period, startMin: start, endMin: end, subjectId: subject, subjectName: subject, teacherStaffId: teacher, teacherName: teacher,
  room, live: false, ...overrides,
});

/** Create a draft exactly as the app does: counter + timetable + history (+ entries). */
function createBatch(db, uid, { section = 'sa', version = 1, counterExists = false, entries = [], overrides = {}, skip = [] } = {}) {
  const tt = ttId(section, version);
  const b = writeBatch(db);
  const key = `${YEAR}__c5__${section}`;
  if (!skip.includes('counter')) {
    if (counterExists) b.update(ref(db, 'timetableCounters', key), { last: version, ...stamp(uid) });
    else b.set(ref(db, 'timetableCounters', key), { schoolId: A, branchId: NORTH, last: version, ...stamp(uid) });
  }
  b.set(ref(db, 'timetables', tt), timetableDoc({ section, version, uid, overrides }));
  if (!skip.includes('history')) b.set(ref(db, 'timetableHistory', `${tt}__1`), historyDoc({ tt, rev: 1, toStatus: 'DRAFT', event: 'CREATED', uid, version }));
  for (const e of entries) b.set(ref(db, 'timetableEntries', entryId(tt, e.weekday, e.slot)), entryDoc({ tt, section, ...e }));
  return b;
}

/** Publish: lock bump + timetable + history + entries live. */
function publishBatch(db, uid, {
  tt, section = 'sa', rev = 2, entries = ['MONDAY__p1'], lockSeq = 1, lockExists = false, skip = [], version = 1,
  supersede = [], truncate = [], extra = {},
} = {}) {
  const b = writeBatch(db);
  if (!skip.includes('lock')) {
    if (lockExists) b.update(ref(db, 'timetableLocks', 'branch'), { publishSeq: lockSeq, ...stamp(uid) });
    else b.set(ref(db, 'timetableLocks', 'branch'), { schoolId: A, branchId: NORTH, publishSeq: lockSeq, ...stamp(uid) });
  }
  b.update(ref(db, 'timetables', tt), {
    status: 'PUBLISHED', revision: rev, lastEvent: 'PUBLISHED', publishedBy: uid, publishedAt: serverTimestamp(), lockSeq, ...stamp(uid), ...extra,
  });
  if (!skip.includes('history')) b.set(ref(db, 'timetableHistory', `${tt}__${rev}`), historyDoc({ tt, rev, toStatus: 'PUBLISHED', event: 'PUBLISHED', uid, version }));
  for (const key of entries) {
    const [weekday, slot] = key.split('__');
    b.update(ref(db, 'timetableEntries', entryId(tt, weekday, slot)), { live: true });
  }
  for (const s of supersede) {
    b.update(ref(db, 'timetables', s.id), { status: 'ARCHIVED', revision: s.rev, lastEvent: 'SUPERSEDED', supersededBy: tt, lockSeq, ...stamp(uid) });
    b.set(ref(db, 'timetableHistory', `${s.id}__${s.rev}`), historyDoc({ tt: s.id, rev: s.rev, toStatus: 'ARCHIVED', event: 'SUPERSEDED', uid, version: s.version ?? 1 }));
    for (const key of s.entries ?? []) {
      const [weekday, slot] = key.split('__');
      b.update(ref(db, 'timetableEntries', entryId(s.id, weekday, slot)), { live: false });
    }
  }
  for (const s of truncate) {
    b.update(ref(db, 'timetables', s.id), { effectiveToKey: s.end, revision: s.rev, lastEvent: 'TRUNCATED', supersededBy: tt, lockSeq, ...stamp(uid) });
    b.set(ref(db, 'timetableHistory', `${s.id}__${s.rev}`), historyDoc({ tt: s.id, rev: s.rev, toStatus: 'PUBLISHED', event: 'TRUNCATED', uid, version: s.version ?? 1 }));
  }
  return b;
}

const subId = (date, tt, slot = 'p1') => `${date}__${tt}__${slot}`;
const subIdAlias = subId;

function substitutionDoc({ date, tt, section = 'sa', slot = 'p1', weekday = 'MONDAY', original = 'st1', substitute = 'st3', subject = 'math', start = 540, end = 580, uid, overrides = {} }) {
  return {
    schoolId: A, branchId: NORTH, academicYearId: YEAR, dateKey: date, date: new Date(date), timetableId: tt, timetableVersion: 1,
    entryId: entryId(tt, weekday, slot), slotId: slot, weekday, periodNumber: 1, startMin: start, endMin: end, classId: 'c5', sectionId: section,
    classLabel: 'Class 5 SA', subjectId: subject, subjectName: subject, originalTeacherId: original, originalTeacherName: original,
    substituteTeacherId: substitute, substituteTeacherName: substitute, reasonKind: 'LEAVE', reason: 'Approved leave', leaveApplicationId: null,
    status: 'ACTIVE', revision: 1, lastEvent: 'ASSIGNED', cancelReason: null, ...audit(uid), ...overrides,
  };
}

const subHistory = ({ id, date, rev, event, substitute = 'st3', uid }) => ({
  schoolId: A, branchId: NORTH, substitutionId: id, dateKey: date, revision: rev, event, substituteTeacherId: substitute,
  substituteTeacherName: substitute, actorId: uid, actorName: 'Admin', note: null, at: serverTimestamp(),
});

function assignBatch(db, uid, { date, tt, daySeq = 1, dayExists = false, skip = [], ...o }) {
  const id = subId(date, tt, o.slot);
  const b = writeBatch(db);
  if (!skip.includes('day')) {
    if (dayExists) b.update(ref(db, 'substitutionDays', date), { seq: daySeq, ...stamp(uid) });
    else b.set(ref(db, 'substitutionDays', date), { schoolId: A, branchId: NORTH, dateKey: date, seq: daySeq, ...stamp(uid) });
  }
  b.set(ref(db, 'substitutions', id), substitutionDoc({ date, tt, uid, ...o }));
  if (!skip.includes('history')) b.set(ref(db, 'substitutionHistory', `${id}__1`), subHistory({ id, date, rev: 1, event: 'ASSIGNED', substitute: o.substitute ?? 'st3', uid }));
  return b;
}

async function seedWorld() {
  counter += 1;
  A = `tt-a-${counter}`;
  B = `tt-b-${counter}`;
  await seed(async (db) => {
    for (const s of [A, B]) {
      await setDoc(doc(db, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      for (const b of s === A ? [NORTH, SOUTH] : [NORTH]) await setDoc(doc(db, ...branch(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'tt-admin': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'tt-admin2': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'tt-admin-b': { schoolId: B, branchId: NORTH, role: 'SCHOOL_ADMIN' },
      'tt-br-north': { schoolId: A, branchId: NORTH, role: 'BRANCH_ADMIN' },
      'tt-br-south': { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' },
      'tt-t1': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'tt-t2': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'tt-t3': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'tt-t-south': { schoolId: A, branchId: SOUTH, role: 'TEACHER' },
      'tt-fin': { schoolId: A, branchId: NORTH, role: 'FINANCE' },
      'tt-parent': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'parent-1' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, 'users', uid), { branchId: null, name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    const n = branch(A, NORTH);
    for (const [staffId, uid, isTeacher] of [['st1', 'tt-t1', true], ['st2', 'tt-t2', true], ['st3', 'tt-t3', true], ['st-office', 'tt-fin', false]]) {
      await setDoc(doc(db, ...n, 'staff', staffId), { schoolId: A, branchId: NORTH, userId: uid, status: 'ACTIVE', isTeacher, ...audit('seed') });
    }
    await setDoc(doc(db, ...n, 'staff', 'st-gone'), { schoolId: A, branchId: NORTH, userId: null, status: 'RESIGNED', isTeacher: true, ...audit('seed') });
    for (const sec of ['sa', 'sb']) {
      await setDoc(doc(db, ...n, 'academicYears', YEAR, 'classes', 'c5', 'sections', sec), { schoolId: A, branchId: NORTH, name: sec, status: 'ACTIVE', ...audit('seed') });
    }
    await setDoc(doc(db, ...n, 'academicYears', YEAR, 'classes', 'c5', 'sections', 'sx'), { schoolId: A, branchId: NORTH, name: 'sx', status: 'INACTIVE', ...audit('seed') });
    const slot = (section, subject, teacher) => setDoc(doc(db, ...n, 'assignmentSlots', `${YEAR}__c5__${section}__${subject}`), {
      schoolId: A, branchId: NORTH, assignmentId: `a-${section}-${subject}`, teacherStaffId: teacher, createdBy: 'seed', createdAt: serverTimestamp(),
    });
    await slot('sa', 'math', 'st1');
    await slot('sa', 'eng', 'st2');
    await slot('sb', 'math', 'st1');
    await slot('sb', 'sci', 'st3');
    // Milestone 12A: the parent has a child in section sa (class c5) only.
    await setDoc(doc(db, ...n, 'parentAccess', 'parent-1'), {
      schoolId: A, branchId: NORTH, parentId: 'parent-1', classKeys: ['c5'], sectionKeys: ['c5__sa'],
      updatedAt: serverTimestamp(), updatedBy: 'seed',
    });
  });
}

const FULL = { entries: [{ weekday: 'MONDAY', slot: 'p1' }, { weekday: 'MONDAY', slot: 'p2', period: 2, start: 590, end: 630, subject: 'eng', teacher: 'st2' }] };

/** A published timetable (v1 of section sa) ready for substitution tests. */
async function seedPublished({ section = 'sa', version = 1 } = {}) {
  const admin = asUser('tt-admin');
  await assertSucceeds(createBatch(admin, 'tt-admin', { section, version, ...FULL, counterExists: version > 1, overrides: { entryCount: 2, teacherIds: ['st1', 'st2'] } }).commit());
  await assertSucceeds(publishBatch(admin, 'tt-admin', {
    tt: ttId(section, version), section, version, entries: ['MONDAY__p1', 'MONDAY__p2'], lockSeq: 1,
  }).commit());
  return ttId(section, version);
}

// ===================================================================== TESTS

test('Tenant isolation: School B admin and a South-branch admin cannot read or write North timetables', async () => {
  await seedWorld();
  const tt = await seedPublished();
  for (const uid of ['tt-admin-b', 'tt-br-south']) {
    const db = asUser(uid);
    await assertFails(getDoc(ref(db, 'timetables', tt)));
    await assertFails(getDocs(col(db, 'timetables')));
    await assertFails(getDocs(col(db, 'timetableEntries')));
    await assertFails(createBatch(db, uid, { section: 'sb' }).commit());
    await assertFails(updateDoc(ref(db, 'timetables', tt), { name: 'x', ...stamp(uid) }));
  }
  await assertSucceeds(getDoc(ref(asUser('tt-admin'), 'timetables', tt)));
  await assertSucceeds(getDoc(ref(asUser('tt-br-north'), 'timetables', tt)));
});

test('Only managers create drafts; version comes from the counter and cannot be skipped or reused', async () => {
  await seedWorld();
  for (const uid of ['tt-t1', 'tt-fin', 'tt-parent']) await assertFails(createBatch(asUser(uid), uid).commit());
  const admin = asUser('tt-admin');
  await assertFails(createBatch(admin, 'tt-admin', { skip: ['counter'] }).commit());
  await assertFails(createBatch(admin, 'tt-admin', { skip: ['history'] }).commit());
  await assertFails(createBatch(admin, 'tt-admin', { version: 3 }).commit()); // no v1/v2 yet
  await assertSucceeds(createBatch(admin, 'tt-admin').commit());
  // v1 again (counter would not advance)
  await assertFails(createBatch(admin, 'tt-admin', { counterExists: true }).commit());
  await assertSucceeds(createBatch(admin, 'tt-admin', { version: 2, counterExists: true }).commit());
  // a draft cannot be born published, or for an inactive section
  await assertFails(createBatch(admin, 'tt-admin', { section: 'sb', overrides: { status: 'PUBLISHED' } }).commit());
  await assertFails(createBatch(admin, 'tt-admin', { section: 'sx' }).commit());
});

test('Entries: only an ACTIVE assignment holder may be placed; fields must match the timetable', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  const tt = ttId('sa');
  await assertSucceeds(createBatch(admin, 'tt-admin').commit());
  const put = (e) => setDoc(ref(admin, 'timetableEntries', entryId(tt, e.weekday ?? 'MONDAY', e.slot ?? 'p1')), entryDoc({ tt, ...e }));
  await assertSucceeds(put({}));
  // st2 does not teach maths in sa; st3 not at all
  await assertFails(put({ slot: 'p3', teacher: 'st2' }));
  await assertFails(put({ slot: 'p3', teacher: 'st3' }));
  // a subject nobody is assigned to
  await assertFails(put({ slot: 'p3', subject: 'art', teacher: 'st1' }));
  // bad times / ids / live
  await assertFails(put({ slot: 'p3', start: 600, end: 600 }));
  await assertFails(put({ slot: 'p3', start: 600, end: 1500 }));
  await assertFails(put({ slot: 'p3', overrides: { live: true } }));
  await assertFails(put({ slot: 'p3', overrides: { classId: 'c9' } }));
  await assertFails(put({ weekday: 'FRIDAY', slot: 'p3' })); // FRIDAY not a day of this timetable
  // the id must be timetable + weekday + slot
  await assertFails(setDoc(ref(admin, 'timetableEntries', 'free-text-id'), entryDoc({ tt })));
  // teacher and a parent cannot write entries
  await assertFails(setDoc(ref(asUser('tt-t1'), 'timetableEntries', entryId(tt, 'TUESDAY', 'p1')), entryDoc({ tt, weekday: 'TUESDAY' })));
});

test('A teacher of another section cannot be placed even if they teach the subject elsewhere', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  await assertSucceeds(createBatch(admin, 'tt-admin', { section: 'sb' }).commit());
  const tt = ttId('sb');
  // st3 teaches sci in sb: fine. st1 teaches maths in sa and sb. st2 teaches eng in sa only.
  await assertSucceeds(setDoc(ref(admin, 'timetableEntries', entryId(tt, 'MONDAY', 'p1')), entryDoc({ tt, section: 'sb', subject: 'sci', teacher: 'st3' })));
  await assertFails(setDoc(ref(admin, 'timetableEntries', entryId(tt, 'MONDAY', 'p2')), entryDoc({ tt, section: 'sb', slot: 'p2', subject: 'eng', teacher: 'st2' })));
});

test('Publish needs the lock bump, the history record and a draft with entries', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  const tt = ttId('sa');
  await assertSucceeds(createBatch(admin, 'tt-admin', FULL).commit());
  await assertFails(publishBatch(admin, 'tt-admin', { tt, skip: ['lock'] }).commit());
  await assertFails(publishBatch(admin, 'tt-admin', { tt, skip: ['history'] }).commit());
  await assertFails(publishBatch(admin, 'tt-admin', { tt, lockSeq: 5 }).commit()); // first publish must be seq 1
  await assertFails(publishBatch(asUser('tt-t1'), 'tt-t1', { tt }).commit());
  await assertFails(publishBatch(asUser('tt-parent'), 'tt-parent', { tt }).commit());
  // a draft with no entries cannot be published (entryCount is 0 until saved)
  await assertFails(publishBatch(admin, 'tt-admin', { tt, entries: ['MONDAY__p1', 'MONDAY__p2'] }).commit());
});

test('CONCURRENT PUBLISH: two admins publish different timetables from the same lock sequence — exactly one commits', async () => {
  await seedWorld();
  const a1 = asUser('tt-admin');
  const a2 = asUser('tt-admin2');
  await assertSucceeds(createBatch(a1, 'tt-admin', { section: 'sa', entries: [{ weekday: 'MONDAY', slot: 'p1' }], overrides: { entryCount: 1, teacherIds: ['st1'] } }).commit());
  await assertSucceeds(createBatch(a1, 'tt-admin', { section: 'sb', entries: [{ weekday: 'MONDAY', slot: 'p1', subject: 'sci', teacher: 'st3' }], overrides: { entryCount: 1, teacherIds: ['st3'] } }).commit());
  const x = publishBatch(a1, 'tt-admin', { tt: ttId('sa'), section: 'sa', entries: ['MONDAY__p1'], lockSeq: 1 });
  const y = publishBatch(a2, 'tt-admin2', { tt: ttId('sb'), section: 'sb', entries: ['MONDAY__p1'], lockSeq: 1 });
  const results = await Promise.allSettled([x.commit(), y.commit()]);
  const won = results.filter((r) => r.status === 'fulfilled').length;
  if (won !== 1) throw new Error(`expected exactly one winner, got ${won}`);
});

test('A published version is immutable: no edit, no entry change, no delete, history append-only', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  const tt = await seedPublishedWithCount();
  await assertFails(updateDoc(ref(admin, 'timetables', tt), { name: 'renamed', revision: 3, lastEvent: 'EDITED', ...stamp('tt-admin') }));
  await assertFails(setDoc(ref(admin, 'timetableEntries', entryId(tt, 'MONDAY', 'p3')), entryDoc({ tt, slot: 'p3' })));
  await assertFails(updateDoc(ref(admin, 'timetableEntries', entryId(tt)), { teacherStaffId: 'st2' }));
  await assertFails(deleteDoc(ref(admin, 'timetableEntries', entryId(tt))));
  await assertFails(deleteDoc(ref(admin, 'timetables', tt)));
  await assertFails(updateDoc(ref(admin, 'timetableHistory', `${tt}__2`), { note: 'rewritten' }));
  await assertFails(deleteDoc(ref(admin, 'timetableHistory', `${tt}__2`)));
});

async function seedPublishedWithCount({ section = 'sa', version = 1, from = '2026-06-01', counterExists = false, lockSeq = 1, lockExists = false, supersede = [], truncate = [] } = {}) {
  const admin = asUser('tt-admin');
  const tt = ttId(section, version);
  await assertSucceeds(createBatch(admin, 'tt-admin', {
    section, version, counterExists, entries: [{ weekday: 'MONDAY', slot: 'p1' }],
    overrides: { entryCount: 1, teacherIds: ['st1'], effectiveFromKey: from },
  }).commit());
  await assertSucceeds(publishBatch(admin, 'tt-admin', { tt, section, version, entries: ['MONDAY__p1'], lockSeq, lockExists, supersede, truncate }).commit());
  return tt;
}

test('Editing a draft: metadata plus changed cells; revision and history must advance', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  const tt = ttId('sa');
  await assertSucceeds(createBatch(admin, 'tt-admin').commit());
  const edit = (db, uid, o = {}) => {
    const b = writeBatch(db);
    b.update(ref(db, 'timetables', tt), { name: 'Term 1 (revised)', entryCount: 1, teacherIds: ['st1'], revision: 2, lastEvent: 'EDITED', ...stamp(uid), ...o.patch });
    if (!o.skipHistory) b.set(ref(db, 'timetableHistory', `${tt}__2`), historyDoc({ tt, rev: 2, toStatus: 'DRAFT', event: 'EDITED', uid }));
    b.set(ref(db, 'timetableEntries', entryId(tt, 'MONDAY', 'p1')), entryDoc({ tt }));
    return b;
  };
  await assertFails(edit(asUser('tt-t1'), 'tt-t1').commit());
  await assertFails(edit(admin, 'tt-admin', { skipHistory: true }).commit());
  await assertFails(edit(admin, 'tt-admin', { patch: { revision: 5 } }).commit());
  await assertFails(edit(admin, 'tt-admin', { patch: { status: 'PUBLISHED' } }).commit());
  await assertFails(edit(admin, 'tt-admin', { patch: { classId: 'c9' } }).commit());
  await assertFails(edit(admin, 'tt-admin', { patch: { effectiveToKey: '2026-01-01' } }).commit()); // before from
  await assertSucceeds(edit(admin, 'tt-admin').commit());
});

test('Supersede and truncate: a new version replaces or ends the old one in the same commit; history is kept', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  const v1 = await seedPublishedWithCount({ from: '2026-06-01' });
  // v2 starts later: v1 is truncated to the day before, not archived
  await assertSucceeds(createBatch(admin, 'tt-admin', {
    version: 2, counterExists: true, entries: [{ weekday: 'MONDAY', slot: 'p1' }], overrides: { entryCount: 1, teacherIds: ['st1'], effectiveFromKey: '2026-09-01' },
  }).commit());
  const v2 = ttId('sa', 2);
  // truncating without the new version being published in the same commit is refused
  await assertFails(updateDoc(ref(admin, 'timetables', v1), { effectiveToKey: '2026-08-31', revision: 3, lastEvent: 'TRUNCATED', supersededBy: v2, lockSeq: 2, ...stamp('tt-admin') }));
  // an end date before the old version even started is not a valid range
  await assertFails(publishBatch(admin, 'tt-admin', {
    tt: v2, version: 2, entries: ['MONDAY__p1'], lockSeq: 2, lockExists: true, truncate: [{ id: v1, end: '2026-05-31', rev: 3 }],
  }).commit());
  // no lock bump: refused
  await assertFails(publishBatch(admin, 'tt-admin', {
    tt: v2, version: 2, entries: ['MONDAY__p1'], lockSeq: 2, lockExists: true, skip: ['lock'], truncate: [{ id: v1, end: '2026-08-31', rev: 3 }],
  }).commit());
  await assertSucceeds(publishBatch(admin, 'tt-admin', {
    tt: v2, version: 2, entries: ['MONDAY__p1'], lockSeq: 2, lockExists: true, truncate: [{ id: v1, end: '2026-08-31', rev: 3 }],
  }).commit());
  // v1 keeps its cells and its content; only its end date moved
  const old = (await getDoc(ref(admin, 'timetables', v1))).data();
  if (old.effectiveToKey !== '2026-08-31' || old.status !== 'PUBLISHED' || old.entryCount !== 1) throw new Error('v1 was altered beyond its end date');
  const cell = (await getDoc(ref(admin, 'timetableEntries', entryId(v1)))).data();
  if (cell.live !== true || cell.teacherStaffId !== 'st1') throw new Error('v1 cells were changed');
  // a later version that starts before v1 replaces it outright (archived, cells hidden)
  await assertSucceeds(createBatch(admin, 'tt-admin', {
    version: 3, counterExists: true, entries: [{ weekday: 'MONDAY', slot: 'p1' }], overrides: { entryCount: 1, teacherIds: ['st1'], effectiveFromKey: '2026-05-01' },
  }).commit());
  const v3 = ttId('sa', 3);
  await assertSucceeds(publishBatch(admin, 'tt-admin', {
    tt: v3, version: 3, entries: ['MONDAY__p1'], lockSeq: 3, lockExists: true, supersede: [{ id: v1, rev: 4, entries: ['MONDAY__p1'] }],
  }).commit());
  const replaced = (await getDoc(ref(admin, 'timetables', v1))).data();
  if (replaced.status !== 'ARCHIVED' || replaced.supersededBy !== v3) throw new Error('v1 was not archived by v3');
});

test('Superseding another section\'s timetable is refused', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  const sa1 = await seedPublishedWithCount({ section: 'sa' });
  await assertSucceeds(createBatch(admin, 'tt-admin', {
    section: 'sb', entries: [{ weekday: 'MONDAY', slot: 'p1', subject: 'sci', teacher: 'st3' }], overrides: { entryCount: 1, teacherIds: ['st3'] },
  }).commit());
  const sb1 = ttId('sb');
  await assertFails(publishBatch(admin, 'tt-admin', {
    tt: sb1, section: 'sb', entries: ['MONDAY__p1'], lockSeq: 2, lockExists: true, supersede: [{ id: sa1, rev: 3, entries: ['MONDAY__p1'] }],
  }).commit());
});

test('Withdrawing a published version needs the lock bump and hides its entries', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  const tt = await seedPublishedWithCount();
  const withdraw = (o = {}) => {
    const b = writeBatch(admin);
    if (!o.noLock) b.update(ref(admin, 'timetableLocks', 'branch'), { publishSeq: 2, ...stamp('tt-admin') });
    b.update(ref(admin, 'timetables', tt), { status: 'ARCHIVED', revision: 3, lastEvent: 'ARCHIVED', lockSeq: 2, ...stamp('tt-admin') });
    b.set(ref(admin, 'timetableHistory', `${tt}__3`), historyDoc({ tt, rev: 3, toStatus: 'ARCHIVED', event: 'ARCHIVED', uid: 'tt-admin' }));
    b.update(ref(admin, 'timetableEntries', entryId(tt)), { live: false });
    return b;
  };
  await assertFails(withdraw({ noLock: true }).commit());
  await assertSucceeds(withdraw().commit());
});

test('Visibility: drafts are for managers; published schedules for branch teachers and parents only', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  await assertSucceeds(createBatch(admin, 'tt-admin', { section: 'sb', entries: [{ weekday: 'MONDAY', slot: 'p1', subject: 'sci', teacher: 'st3' }], overrides: { entryCount: 1 } }).commit());
  const draft = ttId('sb');
  const published = await seedPublishedWithCount({ section: 'sa' });

  for (const uid of ['tt-t1', 'tt-parent']) {
    await assertFails(getDoc(ref(asUser(uid), 'timetables', draft)));
    await assertFails(getDoc(ref(asUser(uid), 'timetableEntries', entryId(draft, 'MONDAY', 'p1'))));
    await assertSucceeds(getDoc(ref(asUser(uid), 'timetables', published)));
    await assertSucceeds(getDocs(query(col(asUser(uid), 'timetableEntries'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), where('live', '==', true))));
    await assertSucceeds(getDocs(query(col(asUser(uid), 'timetables'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), where('status', '==', 'PUBLISHED'))));
    // and cannot list drafts or everything
    await assertFails(getDocs(col(asUser(uid), 'timetables')));
    await assertFails(getDocs(query(col(asUser(uid), 'timetables'), where('status', '==', 'DRAFT'))));
  }
  // M12A: a parent is tied to the sections of their own children
  const parent = asUser('tt-parent');
  await assertFails(getDocs(query(col(parent, 'timetables'), where('status', '==', 'PUBLISHED')))); // unpinned
  await assertFails(getDocs(query(col(parent, 'timetables'), where('classId', '==', 'c5'), where('sectionId', '==', 'sb'), where('status', '==', 'PUBLISHED'))));
  await assertFails(getDocs(query(col(parent, 'timetableEntries'), where('classId', '==', 'c5'), where('sectionId', '==', 'sb'), where('live', '==', true))));
  await assertFails(getDocs(query(col(parent, 'timetableEntries'), where('live', '==', true))));
  // a teacher's own timetable by staff id
  await assertSucceeds(getDocs(query(col(asUser('tt-t1'), 'timetableEntries'), where('teacherStaffId', '==', 'st1'), where('live', '==', true))));
  // finance, another branch's teacher, another school: nothing
  for (const uid of ['tt-fin', 'tt-t-south', 'tt-admin-b']) {
    await assertFails(getDoc(ref(asUser(uid), 'timetables', published)));
    await assertFails(getDocs(query(col(asUser(uid), 'timetableEntries'), where('live', '==', true))));
  }
  // nobody below a manager reads history, counters or locks
  for (const uid of ['tt-t1', 'tt-parent']) {
    await assertFails(getDocs(col(asUser(uid), 'timetableHistory')));
    await assertFails(getDocs(col(asUser(uid), 'timetableLocks')));
  }
});

test('Period sets: managers only', async () => {
  await seedWorld();
  const set = (uid) => ({
    schoolId: A, branchId: NORTH, academicYearId: YEAR, name: 'Regular', status: 'ACTIVE', ...audit(uid),
    slots: [{ slotId: 'p1', number: 1, kind: 'TEACHING', label: '', startMin: 540, endMin: 580 }],
  });
  await assertSucceeds(setDoc(ref(asUser('tt-admin'), 'periodSets', 'y1__regular'), set('tt-admin')));
  await assertFails(setDoc(ref(asUser('tt-t1'), 'periodSets', 'y1__x'), set('tt-t1')));
  await assertFails(getDoc(ref(asUser('tt-t1'), 'periodSets', 'y1__regular')));
  await assertFails(deleteDoc(ref(asUser('tt-admin'), 'periodSets', 'y1__regular')));
  await assertFails(setDoc(ref(asUser('tt-admin'), 'periodSets', 'y1__empty'), { ...set('tt-admin'), slots: [] }));
});

// ------------------------------------------------------------ substitutions

test('Substitution create: valid cover; wrong original, same person, non-teacher, draft entry, out-of-range date all refused', async () => {
  await seedWorld();
  const tt = await seedPublishedWithCount({ section: 'sa' });
  const admin = asUser('tt-admin');
  const date = '2026-08-03';
  await assertFails(assignBatch(admin, 'tt-admin', { date, tt, original: 'st2' }).commit());        // st2 does not teach this slot
  await assertFails(assignBatch(admin, 'tt-admin', { date, tt, substitute: 'st1' }).commit());      // covering themself
  await assertFails(assignBatch(admin, 'tt-admin', { date, tt, substitute: 'st-office' }).commit()); // not a teacher
  await assertFails(assignBatch(admin, 'tt-admin', { date, tt, substitute: 'st-gone' }).commit());   // not active
  await assertFails(assignBatch(admin, 'tt-admin', { date: '2026-05-01', tt }).commit());           // before the timetable starts
  await assertFails(assignBatch(admin, 'tt-admin', { date, tt, skip: ['day'] }).commit());
  await assertFails(assignBatch(admin, 'tt-admin', { date, tt, skip: ['history'] }).commit());
  await assertFails(assignBatch(admin, 'tt-admin', { date, tt, subject: 'eng' }).commit());          // subject mismatch
  await assertFails(assignBatch(asUser('tt-t1'), 'tt-t1', { date, tt }).commit());
  await assertFails(assignBatch(asUser('tt-parent'), 'tt-parent', { date, tt }).commit());
  await assertSucceeds(assignBatch(admin, 'tt-admin', { date, tt }).commit());
  // never for a draft's entry
  await assertSucceeds(createBatch(admin, 'tt-admin', { section: 'sb', entries: [{ weekday: 'MONDAY', slot: 'p1' }], overrides: { entryCount: 1 } }).commit());
  await assertFails(assignBatch(admin, 'tt-admin', { date: '2026-08-10', tt: ttId('sb'), section: 'sb' }).commit());
});

test('DUPLICATE: a second cover for the same slot and date is impossible; a retry changes nothing', async () => {
  await seedWorld();
  const tt = await seedPublishedWithCount();
  const admin = asUser('tt-admin');
  const date = '2026-08-03';
  await assertSucceeds(assignBatch(admin, 'tt-admin', { date, tt }).commit());
  await assertFails(assignBatch(asUser('tt-admin2'), 'tt-admin2', { date, tt, substitute: 'st2', daySeq: 2, dayExists: true }).commit());
  await assertFails(assignBatch(admin, 'tt-admin', { date, tt, daySeq: 2, dayExists: true }).commit());
});

test('CONCURRENT covers on one date: two admins from the same day sequence — exactly one commits', async () => {
  await seedWorld();
  const tt = await seedPublishedWithCount();
  // add a second live slot to cover
  const admin = asUser('tt-admin');
  const date = '2026-08-03';
  const x = assignBatch(admin, 'tt-admin', { date, tt, slot: 'p1' });
  const y = assignBatch(asUser('tt-admin2'), 'tt-admin2', {
    date, tt, slot: 'p1', substitute: 'st2',
  });
  const results = await Promise.allSettled([x.commit(), y.commit()]);
  if (results.filter((r) => r.status === 'fulfilled').length !== 1) throw new Error('expected exactly one cover to commit');
});

test('Change, cancel, reinstate — each needs its history record and the day sequence', async () => {
  await seedWorld();
  const tt = await seedPublishedWithCount();
  const admin = asUser('tt-admin');
  const date = '2026-08-03';
  const id = subId(date, tt);
  await assertSucceeds(assignBatch(admin, 'tt-admin', { date, tt }).commit());

  const step = (uid, { rev, event, patch, daySeq, skipDay, skipHistory, substitute = 'st3' }) => {
    const db = asUser(uid);
    const b = writeBatch(db);
    if (!skipDay) b.update(ref(db, 'substitutionDays', date), { seq: daySeq, ...stamp(uid) });
    b.update(ref(db, 'substitutions', id), { revision: rev, lastEvent: event, ...patch, ...stamp(uid) });
    if (!skipHistory) b.set(ref(db, 'substitutionHistory', `${id}__${rev}`), subHistory({ id, date, rev, event, substitute, uid }));
    return b;
  };
  // change to st2 (who is free: not in this slot) — but st1 can't be the substitute of their own period
  await assertFails(step('tt-admin', { rev: 2, event: 'CHANGED', daySeq: 2, patch: { substituteTeacherId: 'st1', substituteTeacherName: 'st1', reason: 'Approved leave' } }).commit());
  await assertFails(step('tt-admin', { rev: 2, event: 'CHANGED', daySeq: 2, skipDay: true, patch: { substituteTeacherId: 'st2', substituteTeacherName: 'st2', reason: 'Approved leave' } }).commit());
  await assertFails(step('tt-t3', { rev: 2, event: 'CHANGED', daySeq: 2, patch: { substituteTeacherId: 'st2', substituteTeacherName: 'st2', reason: 'Approved leave' } }).commit());
  await assertSucceeds(step('tt-admin', { rev: 2, event: 'CHANGED', daySeq: 2, substitute: 'st2', patch: { substituteTeacherId: 'st2', substituteTeacherName: 'st2', reason: 'Approved leave' } }).commit());
  // the original teacher / date / slot cannot be moved
  await assertFails(step('tt-admin', { rev: 3, event: 'CHANGED', daySeq: 3, patch: { originalTeacherId: 'st2', substituteTeacherId: 'st3', substituteTeacherName: 'st3', reason: 'Approved leave' } }).commit());
  // cancel needs a reason
  await assertFails(step('tt-admin', { rev: 3, event: 'CANCELLED', daySeq: 3, patch: { status: 'CANCELLED', cancelReason: '' } }).commit());
  await assertSucceeds(step('tt-admin', { rev: 3, event: 'CANCELLED', daySeq: 3, patch: { status: 'CANCELLED', cancelReason: 'Teacher returned' } }).commit());
  // a cancelled cover cannot be "changed"; it is reinstated
  await assertFails(step('tt-admin', { rev: 4, event: 'CHANGED', daySeq: 4, patch: { substituteTeacherId: 'st3', substituteTeacherName: 'st3', reason: 'Approved leave' } }).commit());
  await assertSucceeds(step('tt-admin', {
    rev: 4, event: 'REINSTATED', daySeq: 4,
    patch: { status: 'ACTIVE', cancelReason: null, substituteTeacherId: 'st3', substituteTeacherName: 'st3', reasonKind: 'LEAVE', reason: 'Approved leave', leaveApplicationId: null },
  }).commit());
});

test('The original timetable is untouched by substitutions; substitution history is append-only', async () => {
  await seedWorld();
  const tt = await seedPublishedWithCount();
  const admin = asUser('tt-admin');
  const date = '2026-08-03';
  await assertSucceeds(assignBatch(admin, 'tt-admin', { date, tt }).commit());
  const entry = (await getDoc(ref(admin, 'timetableEntries', entryId(tt)))).data();
  if (entry.teacherStaffId !== 'st1') throw new Error('entry was rewritten');
  const id = subId(date, tt);
  await assertFails(updateDoc(ref(admin, 'substitutionHistory', `${id}__1`), { note: 'edited' }));
  await assertFails(deleteDoc(ref(admin, 'substitutionHistory', `${id}__1`)));
  await assertFails(deleteDoc(ref(admin, 'substitutions', id)));
});

test('Reading covers: the substitute and the original teacher see theirs; others only active covers via a pinned query', async () => {
  await seedWorld();
  const tt = await seedPublishedWithCount();
  const admin = asUser('tt-admin');
  const date = '2026-08-03';
  await assertSucceeds(assignBatch(admin, 'tt-admin', { date, tt }).commit());
  const id = subId(date, tt);
  await assertSucceeds(getDoc(ref(asUser('tt-t3'), 'substitutions', id)));   // the substitute
  await assertSucceeds(getDoc(ref(asUser('tt-t1'), 'substitutions', id)));   // the original
  await assertSucceeds(getDocs(query(col(asUser('tt-t3'), 'substitutions'), where('substituteTeacherId', '==', 'st3'), where('status', '==', 'ACTIVE'))));
  await assertSucceeds(getDocs(query(col(asUser('tt-parent'), 'substitutions'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), where('status', '==', 'ACTIVE'))));
  await assertFails(getDocs(col(asUser('tt-t2'), 'substitutions')));
  await assertFails(getDocs(query(col(asUser('tt-parent'), 'substitutions'), where('status', '==', 'CANCELLED'))));
  for (const uid of ['tt-fin', 'tt-t-south', 'tt-admin-b']) await assertFails(getDoc(ref(asUser(uid), 'substitutions', id)));
  await assertFails(getDocs(col(asUser('tt-t3'), 'substitutionHistory')));
});

test('Notifications: a manager writes them with the event; nobody else can plant one; types must match', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  const tt = ttId('sa');
  await assertSucceeds(createBatch(admin, 'tt-admin', { entries: [{ weekday: 'MONDAY', slot: 'p1' }], overrides: { entryCount: 1, teacherIds: ['st1'] } }).commit());
  const note = (uid, type, extra = {}) => ({
    schoolId: A, branchId: NORTH, audience: 'USER', recipientUserId: 'tt-t1', type, applicationId: null, timetableId: tt, substitutionId: null,
    revision: 2, title: 't', body: 'b', createdBy: uid, createdAt: serverTimestamp(), readAt: null, ...extra,
  });
  const publishWith = (db, uid, n) => {
    const b = publishBatch(db, uid, { tt, entries: ['MONDAY__p1'] });
    b.set(ref(db, 'notifications', `${tt}__PUBLISHED__2__tt-t1`), n);
    return b;
  };
  await assertFails(publishWith(admin, 'tt-admin', note('tt-admin', 'SUBSTITUTION_ASSIGNED')).commit()); // wrong type for the event
  await assertFails(publishWith(admin, 'tt-admin', note('tt-admin', 'TIMETABLE_PUBLISHED', { revision: 9 })).commit());
  await assertSucceeds(publishWith(admin, 'tt-admin', note('tt-admin', 'TIMETABLE_PUBLISHED')).commit());
  // the recipient reads it and may only mark it read; nobody else reads it
  const nid = `${tt}__PUBLISHED__2__tt-t1`;
  await assertSucceeds(getDoc(ref(asUser('tt-t1'), 'notifications', nid)));
  await assertFails(getDoc(ref(asUser('tt-t2'), 'notifications', nid)));
  await assertSucceeds(updateDoc(ref(asUser('tt-t1'), 'notifications', nid), { readAt: serverTimestamp() }));
  await assertFails(updateDoc(ref(asUser('tt-t1'), 'notifications', nid), { title: 'x' }));
  // a teacher cannot plant a notice
  await assertFails(setDoc(ref(asUser('tt-t2'), 'notifications', 'forged'), note('tt-t2', 'TIMETABLE_PUBLISHED')));
});

test('A draft\'s cells cannot be made visible by an edit, and a new version must advance the counter', async () => {
  await seedWorld();
  const admin = asUser('tt-admin');
  const tt = ttId('sa');
  await assertSucceeds(createBatch(admin, 'tt-admin', { entries: [{ weekday: 'MONDAY', slot: 'p1' }], overrides: { entryCount: 1, teacherIds: ['st1'] } }).commit());
  // an "edit" that also flips a cell to live while the timetable stays a draft
  const sneaky = writeBatch(admin);
  sneaky.update(ref(admin, 'timetables', tt), { name: 'Term 1b', revision: 2, lastEvent: 'EDITED', ...stamp('tt-admin') });
  sneaky.set(ref(admin, 'timetableHistory', `${tt}__2`), historyDoc({ tt, rev: 2, toStatus: 'DRAFT', event: 'EDITED', uid: 'tt-admin' }));
  sneaky.update(ref(admin, 'timetableEntries', entryId(tt)), { live: true });
  await assertFails(sneaky.commit());
  const cell = (await getDoc(ref(admin, 'timetableEntries', entryId(tt)))).data();
  if (cell.live !== false) throw new Error('a draft cell went live');

  // v2 without bumping the section counter is refused
  await assertFails(createBatch(admin, 'tt-admin', { version: 2, counterExists: true, skip: ['counter'] }).commit());
  await assertSucceeds(createBatch(admin, 'tt-admin', { version: 2, counterExists: true }).commit());
});

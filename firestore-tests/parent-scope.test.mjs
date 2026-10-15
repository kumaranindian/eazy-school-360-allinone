// Milestone 12A — F-SEC-3: a family reads class-specific content only for
// classes/sections where it has a (linked, active, portal-enabled) child, as
// recorded in the branch's `parentAccess/{parentId}` index. School-wide
// announcements stay school-wide. A missing index grants nothing.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, collectionGroup, doc, getDoc, getDocs, query, where, serverTimestamp, setDoc, updateDoc, deleteDoc,
} from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await seedAll();
});
after(async () => env.cleanup());

const A = 'ps-a';
const B = 'ps-b';
const N = 'north';
const S = 'south';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const nb = (s = A, b = N) => ['schools', s, 'branches', b];
const db = (uid) => env.authenticatedContext(uid).firestore();
const ref = (d, name, id, b = N, s = A) => doc(d, ...nb(s, b), name, id);
const col = (d, name, b = N, s = A) => collection(d, ...nb(s, b), name);

const ids = { hw: 'b1__sa', hwB: 'b1__sb' };

async function seedAll() {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...base });
    for (const [s, b] of [[A, N], [A, S], [B, N]]) await setDoc(doc(d, ...nb(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...base });
    const users = {
      'ps-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'ps-br-north': { schoolId: A, branchId: N, role: 'BRANCH_ADMIN' },
      'ps-br-south': { schoolId: A, branchId: S, role: 'BRANCH_ADMIN' },
      'ps-teacher': { schoolId: A, branchId: N, role: 'TEACHER' },
      'ps-p-sa': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par-sa' },
      'ps-p-sb': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par-sb' },
      'ps-p-none': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par-none' },
      'ps-p-south': { schoolId: A, branchId: S, role: 'PARENT', linkedParentId: 'par-south' },
      'ps-p-b': { schoolId: B, branchId: N, role: 'PARENT', linkedParentId: 'par-b' },
      // another school's parent whose record id happens to equal a School A parent id
      'ps-p-b-clash': { schoolId: B, branchId: N, role: 'PARENT', linkedParentId: 'par-sa' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    const access = (parentId, classes, sections, b = N) => setDoc(doc(d, ...nb(A, b), 'parentAccess', parentId), {
      schoolId: A, branchId: b, parentId, classKeys: classes, sectionKeys: sections, updatedAt: serverTimestamp(), updatedBy: 'seed',
    });
    await access('par-sa', ['c5'], ['c5__sa']);
    await access('par-sb', ['c5'], ['c5__sb']);
    await access('par-south', ['c9'], ['c9__sx'], S);
    // par-none: deliberately no index document
    const n = nb(A, N);
    const hw = (id, section, status = 'PUBLISHED') => setDoc(doc(d, ...n, 'homework', id), {
      schoolId: A, branchId: N, academicYearId: 'y1', classId: 'c5', sectionId: section, status, teacherStaffId: 'st1', ...base,
    });
    await hw(ids.hw, 'sa');
    await hw(ids.hwB, 'sb');
    await hw('draft__sa', 'sa', 'DRAFT');
    const exam = (id, section) => setDoc(doc(d, ...n, 'examinations', id), {
      schoolId: A, branchId: N, academicYearId: 'y1', classId: 'c5', sectionId: section, status: 'PUBLISHED', name: id, ...base,
    });
    await exam('y1__c5__ALL__final', null);
    await exam('y1__c5__sa__unit', 'sa');
    await exam('y1__c5__sb__unit', 'sb');
    await setDoc(doc(d, ...n, 'timetables', 'tt-sa'), { schoolId: A, branchId: N, academicYearId: 'y1', classId: 'c5', sectionId: 'sa', status: 'PUBLISHED', ...base });
    await setDoc(doc(d, ...n, 'timetables', 'tt-sb'), { schoolId: A, branchId: N, academicYearId: 'y1', classId: 'c5', sectionId: 'sb', status: 'PUBLISHED', ...base });
    await setDoc(doc(d, ...n, 'timetableEntries', 'e-sa'), { schoolId: A, branchId: N, academicYearId: 'y1', classId: 'c5', sectionId: 'sa', live: true, teacherStaffId: 'st1', ...base });
    await setDoc(doc(d, ...n, 'timetableEntries', 'e-sb'), { schoolId: A, branchId: N, academicYearId: 'y1', classId: 'c5', sectionId: 'sb', live: true, teacherStaffId: 'st1', ...base });
    await setDoc(doc(d, ...n, 'substitutions', 'sub-sa'), { schoolId: A, branchId: N, classId: 'c5', sectionId: 'sa', status: 'ACTIVE', dateKey: '2026-08-03', substituteTeacherId: 'st2', originalTeacherId: 'st1', ...base });
    await setDoc(doc(d, ...n, 'substitutions', 'sub-sb'), { schoolId: A, branchId: N, classId: 'c5', sectionId: 'sb', status: 'ACTIVE', dateKey: '2026-08-03', substituteTeacherId: 'st2', originalTeacherId: 'st1', ...base });
    for (const kind of ['ALL', 'BRANCH', 'PARENTS', 'CLASS', 'SECTION']) {
      await setDoc(doc(d, ...n, 'announcements', `an-${kind}`), {
        schoolId: A, branchId: N, status: 'PUBLISHED', audienceKind: kind, classId: 'c5', sectionId: kind === 'SECTION' ? 'sa' : null,
        authorId: 'ps-admin', title: kind, ...base,
      });
      await setDoc(doc(d, ...n, 'broadcastNotices', `bn-${kind}`), {
        schoolId: A, branchId: N, audienceKind: kind, classId: 'c5', sectionId: kind === 'SECTION' ? 'sa' : null, type: 'ANNOUNCEMENT_PUBLISHED', title: kind, ...base,
      });
    }
  });
}

const ok = (p) => assertSucceeds(p);
const no = (p) => assertFails(p);

test('homework: a family reads only the sections of its own children', async () => {
  await ok(getDoc(ref(db('ps-p-sa'), 'homework', ids.hw)));
  await no(getDoc(ref(db('ps-p-sa'), 'homework', ids.hwB)));
  await no(getDoc(ref(db('ps-p-sb'), 'homework', ids.hw)));
  await ok(getDoc(ref(db('ps-p-sb'), 'homework', ids.hwB)));
  await no(getDoc(ref(db('ps-p-sa'), 'homework', 'draft__sa'))); // drafts never
  const pinned = (uid, section) => getDocs(query(col(db(uid), 'homework'), where('academicYearId', '==', 'y1'), where('classId', '==', 'c5'),
    where('sectionId', '==', section), where('status', 'in', ['PUBLISHED', 'CLOSED'])));
  await ok(pinned('ps-p-sa', 'sa'));
  await no(pinned('ps-p-sa', 'sb'));
  await no(getDocs(col(db('ps-p-sa'), 'homework')));
});

test('a family with no index, another branch\'s family and another school\'s family read nothing class-specific', async () => {
  for (const uid of ['ps-p-none', 'ps-p-south', 'ps-p-b']) {
    await no(getDoc(ref(db(uid), 'homework', ids.hw)));
    await no(getDoc(ref(db(uid), 'examinations', 'y1__c5__ALL__final')));
    await no(getDoc(ref(db(uid), 'timetables', 'tt-sa')));
    await no(getDoc(ref(db(uid), 'timetableEntries', 'e-sa')));
    await no(getDoc(ref(db(uid), 'substitutions', 'sub-sa')));
    await no(getDoc(ref(db(uid), 'announcements', 'an-BRANCH')));
    await no(getDoc(ref(db(uid), 'announcements', 'an-SECTION')));
    await no(getDoc(ref(db(uid), 'broadcastNotices', 'bn-PARENTS')));
  }
});

test('a parent record id shared with another school grants nothing across schools', async () => {
  const clash = db('ps-p-b-clash');
  await no(getDoc(ref(clash, 'homework', ids.hw)));
  await no(getDoc(ref(clash, 'parentAccess', 'par-sa')));
  await no(getDoc(ref(clash, 'announcements', 'an-BRANCH')));
  await no(getDoc(ref(clash, 'examinations', 'y1__c5__ALL__final')));
  // and the same id inside its own school (B/north) has no index either
  await no(getDoc(ref(clash, 'homework', 'x', N, B)));
});

test('examinations: class-wide ones need the class; section ones need the section', async () => {
  const p = db('ps-p-sa');
  await ok(getDoc(ref(p, 'examinations', 'y1__c5__ALL__final')));
  await ok(getDoc(ref(p, 'examinations', 'y1__c5__sa__unit')));
  await no(getDoc(ref(p, 'examinations', 'y1__c5__sb__unit')));
  const q = (section) => getDocs(query(col(p, 'examinations'), where('academicYearId', '==', 'y1'), where('classId', '==', 'c5'),
    where('status', '==', 'PUBLISHED'), where('sectionId', '==', section)));
  await ok(q(null));
  await ok(q('sa'));
  await no(q('sb'));
});

test('schedules: timetable, live entries and substitutions are per section', async () => {
  const p = db('ps-p-sa');
  await ok(getDoc(ref(p, 'timetables', 'tt-sa')));
  await no(getDoc(ref(p, 'timetables', 'tt-sb')));
  await ok(getDoc(ref(p, 'timetableEntries', 'e-sa')));
  await no(getDoc(ref(p, 'timetableEntries', 'e-sb')));
  await ok(getDoc(ref(p, 'substitutions', 'sub-sa')));
  await no(getDoc(ref(p, 'substitutions', 'sub-sb')));
  await ok(getDocs(query(col(p, 'substitutions'), where('classId', '==', 'c5'), where('sectionId', '==', 'sa'), where('status', '==', 'ACTIVE'),
    where('dateKey', '>=', '2026-08-01'), where('dateKey', '<=', '2026-08-31'))));
  await no(getDocs(query(col(p, 'substitutions'), where('status', '==', 'ACTIVE'))));
  // teachers of the branch are unaffected
  await ok(getDoc(ref(db('ps-teacher'), 'timetables', 'tt-sb')));
  await ok(getDoc(ref(db('ps-teacher'), 'homework', ids.hwB)));
});

test('announcements: school-wide stays school-wide; branch-targeted ones need a child in the branch', async () => {
  // an ALL announcement is for everyone in the school, whatever their branch
  for (const uid of ['ps-p-sa', 'ps-p-none', 'ps-p-south']) {
    await ok(getDoc(ref(db(uid), 'announcements', 'an-ALL')));
    await ok(getDoc(ref(db(uid), 'broadcastNotices', 'bn-ALL')));
  }
  await no(getDoc(ref(db('ps-p-b'), 'announcements', 'an-ALL'))); // other school
  // BRANCH / PARENTS: the family must have a child in this branch;
  // CLASS: a child in THAT class; SECTION: a child in THAT section.
  for (const kind of ['BRANCH', 'PARENTS', 'CLASS', 'SECTION']) {
    await ok(getDoc(ref(db('ps-p-sa'), 'announcements', `an-${kind}`)));
    await ok(getDoc(ref(db('ps-p-sa'), 'broadcastNotices', `bn-${kind}`)));
    await no(getDoc(ref(db('ps-p-south'), 'announcements', `an-${kind}`)));
    await no(getDoc(ref(db('ps-p-none'), 'announcements', `an-${kind}`)));
  }
  // same class, different section: the class notice yes, the section notice no
  await ok(getDoc(ref(db('ps-p-sb'), 'announcements', 'an-CLASS')));
  await no(getDoc(ref(db('ps-p-sb'), 'announcements', 'an-SECTION')));
  await no(getDoc(ref(db('ps-p-sb'), 'broadcastNotices', 'bn-SECTION')));
  // another class's family: nothing class/section-scoped
  await no(getDoc(ref(db('ps-p-south'), 'announcements', 'an-CLASS')));
  // the lists the app runs: one pinned query per audience scope, provable for a family with the index
  // announcements are listed as PUBLISHED only (the rule needs the status to prove the query)
  const st = (name) => (name === 'announcements' ? [where('status', '==', 'PUBLISHED')] : []);
  const pinned = (uid, name, kind, extra = []) => getDocs(query(col(db(uid), name), ...st(name), where('audienceKind', '==', kind), ...extra));
  const general = (uid, name) => getDocs(query(col(db(uid), name), ...st(name), where('audienceKind', 'in', ['ALL', 'BRANCH', 'PARENTS'])));
  for (const name of ['announcements', 'broadcastNotices']) {
    await ok(general('ps-p-sa', name));
    await ok(pinned('ps-p-sa', name, 'CLASS', [where('classId', '==', 'c5')]));
    await ok(pinned('ps-p-sa', name, 'SECTION', [where('classId', '==', 'c5'), where('sectionId', '==', 'sa')]));
    // not their section / class, or not pinned at all: refused
    await no(pinned('ps-p-sa', name, 'SECTION', [where('classId', '==', 'c5'), where('sectionId', '==', 'sb')]));
    await no(pinned('ps-p-sa', name, 'CLASS', [where('classId', '==', 'c9')]));
    await no(pinned('ps-p-sa', name, 'CLASS'));
    await no(getDocs(query(col(db('ps-p-sa'), name), ...st(name), where('audienceKind', 'in', ['ALL', 'BRANCH', 'PARENTS', 'CLASS', 'SECTION']))));
    await no(general('ps-p-south', name));
  }
});

test('the index: only staff who manage student data write it; families read only their own', async () => {
  const doc1 = (uid, parentId, o = {}) => ({
    schoolId: A, branchId: N, parentId, classKeys: ['c5'], sectionKeys: ['c5__sa'], updatedAt: serverTimestamp(), updatedBy: uid, ...o,
  });
  // a family cannot grant itself access (nor anyone else)
  await no(setDoc(ref(db('ps-p-none'), 'parentAccess', 'par-none'), doc1('ps-p-none', 'par-none')));
  await no(updateDoc(ref(db('ps-p-sb'), 'parentAccess', 'par-sb'), { sectionKeys: ['c5__sa', 'c5__sb'], updatedAt: serverTimestamp(), updatedBy: 'ps-p-sb' }));
  // teachers do not write it either
  await no(setDoc(ref(db('ps-teacher'), 'parentAccess', 'par-none'), doc1('ps-teacher', 'par-none')));
  // admins of another branch/school cannot write into this branch
  await no(setDoc(ref(db('ps-br-south'), 'parentAccess', 'par-none'), doc1('ps-br-south', 'par-none')));
  // validation
  const admin = db('ps-br-north');
  await no(setDoc(ref(admin, 'parentAccess', 'par-none'), doc1('ps-br-north', 'par-none', { branchId: S })));
  await no(setDoc(ref(admin, 'parentAccess', 'par-none'), doc1('ps-br-north', 'par-none', { parentId: 'someone-else' })));
  await no(setDoc(ref(admin, 'parentAccess', 'par-none'), doc1('ps-br-north', 'par-none', { updatedBy: 'ps-admin' })));
  await no(setDoc(ref(admin, 'parentAccess', 'par-none'), doc1('ps-br-north', 'par-none', { sectionKeys: 'c5__sa' })));
  await no(setDoc(ref(admin, 'parentAccess', 'par-none'), doc1('ps-br-north', 'par-none', { sectionKeys: Array.from({ length: 201 }, (_, i) => `c5__s${i}`) })));
  await no(setDoc(ref(admin, 'parentAccess', 'par-none'), doc1('ps-br-north', 'par-none', { classKeys: Array.from({ length: 101 }, (_, i) => `c${i}`) })));
  await ok(setDoc(ref(admin, 'parentAccess', 'par-none'), doc1('ps-br-north', 'par-none')));
  await no(deleteDoc(ref(admin, 'parentAccess', 'par-none')));
  // the family then sees exactly that
  await ok(getDoc(ref(db('ps-p-none'), 'homework', ids.hw)));
  await no(getDoc(ref(db('ps-p-none'), 'homework', ids.hwB)));
  // reading: own document only
  await ok(getDoc(ref(db('ps-p-sa'), 'parentAccess', 'par-sa')));
  await no(getDoc(ref(db('ps-p-sa'), 'parentAccess', 'par-sb')));
  await no(getDocs(col(db('ps-p-sa'), 'parentAccess')));
  await ok(getDoc(ref(db('ps-br-north'), 'parentAccess', 'par-sa')));
  await no(getDoc(ref(db('ps-br-south'), 'parentAccess', 'par-sa')));
});

test('removing a section from the index ends access at once (a transfer or ended link)', async () => {
  await no(getDoc(ref(db('ps-p-sb'), 'homework', ids.hw)));
  await env.withSecurityRulesDisabled(async (c) => {
    await updateDoc(doc(c.firestore(), ...nb(A, N), 'parentAccess', 'par-sb'), { sectionKeys: ['c5__sa'] });
  });
  await ok(getDoc(ref(db('ps-p-sb'), 'homework', ids.hw)));
  await no(getDoc(ref(db('ps-p-sb'), 'homework', ids.hwB)));
  await env.withSecurityRulesDisabled(async (c) => {
    await updateDoc(doc(c.firestore(), ...nb(A, N), 'parentAccess', 'par-sb'), { sectionKeys: [], classKeys: [] });
  });
  await no(getDoc(ref(db('ps-p-sb'), 'homework', ids.hw)));
  await no(getDoc(ref(db('ps-p-sb'), 'examinations', 'y1__c5__ALL__final')));
});

test('the branch lookup of a family\'s links is for staff of that branch only', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), ...nb(A, N), 'students', 's1', 'parentLinks', 'par-sa'), {
      schoolId: A, branchId: N, studentId: 's1', parentId: 'par-sa', canAccessPortal: true, status: 'ACTIVE', ...base,
    });
  });
  const q = (uid, branch) => getDocs(query(collectionGroup(db(uid), 'parentLinks'),
    where('schoolId', '==', A), where('branchId', '==', branch), where('parentId', '==', 'par-sa')));
  await ok(q('ps-br-north', N));
  await ok(q('ps-admin', N));
  await no(q('ps-br-south', N));
  await no(q('ps-p-b', N));
  // the family's own lookup keeps working
  await ok(getDocs(query(collectionGroup(db('ps-p-sa'), 'parentLinks'), where('schoolId', '==', A), where('parentId', '==', 'par-sa'))));
  await no(getDocs(query(collectionGroup(db('ps-p-sb'), 'parentLinks'), where('schoolId', '==', A), where('parentId', '==', 'par-sa'))));
});

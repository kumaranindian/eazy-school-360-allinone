// A parent's two portal flows, exactly as the app reads them:
//   * Apply for leave for a child — the form loads the child's academic-year
//     document, the leave types, the branch working days and the year's
//     holidays (to count the leave days), and the child's existing leave.
//   * My results — the published examinations of the child's class/section,
//     then the child's finalised result for each.
// Own school ids (`plr-`) so it can share the emulator with the other files.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, collectionGroup, doc, getDoc, getDocs, orderBy, query, serverTimestamp, setDoc, updateDoc, where, deleteDoc,
} from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
  await seedAll();
});
after(async () => env.cleanup());

const A = 'plr-a';
const B = 'plr-b';
const N = 'north';
const S = 'south';
const YEAR = 'y1';
const EXAM = 'y1__c5__sa__final';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const nb = (s = A, b = N) => ['schools', s, 'branches', b];
const db = (uid) => env.authenticatedContext(uid).firestore();
const ref = (d, name, id, b = N, s = A) => doc(d, ...nb(s, b), name, id);
const col = (d, name, b = N, s = A) => collection(d, ...nb(s, b), name);
const resultId = (exam, student, v = 1) => `${exam}__${student}__v${v}`;

async function seedAll() {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...base });
    for (const [s, b] of [[A, N], [A, S], [B, N]]) await setDoc(doc(d, ...nb(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...base });
    const users = {
      'plr-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'plr-br-north': { schoolId: A, branchId: N, role: 'BRANCH_ADMIN' },
      'plr-teacher': { schoolId: A, branchId: N, role: 'TEACHER' },
      'plr-p1': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par1' },
      'plr-p2': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par2' },
      'plr-p-noindex': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par-none' },
      'plr-p-south': { schoolId: A, branchId: S, role: 'PARENT', linkedParentId: 'par-south' },
      'plr-p-b': { schoolId: B, branchId: N, role: 'PARENT', linkedParentId: 'par1' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    const n = nb(A, N);
    // children: stu1 (par1) in c5/sa, stu2 (par2) in c5/sa, stu3 (par1) in c6/sb
    const student = (id, cls, sec) => setDoc(doc(d, ...n, 'students', id), {
      schoolId: A, branchId: N, status: 'ACTIVE', currentAcademicYearId: YEAR, currentClassId: cls, currentSectionId: sec, ...base,
    });
    await student('stu1', 'c5', 'sa');
    await student('stu2', 'c5', 'sa');
    await student('stu3', 'c6', 'sb');
    const link = (stu, parent) => setDoc(doc(d, ...n, 'students', stu, 'parentLinks', parent), {
      schoolId: A, branchId: N, studentId: stu, parentId: parent, status: 'ACTIVE', canAccessPortal: true, ...base,
    });
    await link('stu1', 'par1');
    await link('stu3', 'par1');
    await link('stu2', 'par2');
    const access = (parentId, classes, sections, b = N) => setDoc(doc(d, ...nb(A, b), 'parentAccess', parentId), {
      schoolId: A, branchId: b, parentId, classKeys: classes, sectionKeys: sections, updatedAt: serverTimestamp(), updatedBy: 'seed',
    });
    await access('par1', ['c5', 'c6'], ['c5__sa', 'c6__sb']);
    await access('par2', ['c5'], ['c5__sa']);
    await access('par-south', ['c9'], ['c9__sx'], S);
    await setDoc(doc(d, ...n, 'academicYears', YEAR), { schoolId: A, branchId: N, name: '2026-27', status: 'ACTIVE', ...base });
    await setDoc(doc(d, ...n, 'settings', 'workingDays'), { schoolId: A, branchId: N, days: ['MON', 'TUE'], ...base });
    await setDoc(doc(d, ...n, 'settings', 'academic'), { schoolId: A, branchId: N, dateFormat: 'dd/MM/yyyy', ...base });
    await setDoc(doc(d, ...n, 'academicYears', YEAR, 'holidays', 'h1'), {
      schoolId: A, branchId: N, academicYearId: YEAR, date: '2026-08-15', name: 'Independence Day', ...base,
    });
    await setDoc(doc(d, ...n, 'leaveTypes', 'STUDENT__sick'), {
      schoolId: A, branchId: N, kind: 'STUDENT', code: 'sick', name: 'Sick', payType: 'NA', status: 'ACTIVE', ...base,
    });
    const exam = (id, over = {}) => {
      const e = {
        schoolId: A, branchId: N, academicYearId: YEAR, classId: 'c5', sectionId: 'sa', status: 'PUBLISHED', name: id,
        resultVersion: 1, ...over, ...base,
      };
      return setDoc(doc(d, ...n, 'examinations', id), { ...e, sectionScope: e.sectionId ?? 'ALL' });
    };
    await exam(EXAM);
    await exam('y1__c5__ALL__annual', { sectionId: null });
    await exam('y1__c5__sa__draft', { status: 'COMPLETED' });
    await exam('y1__c6__sb__unit', { classId: 'c6', sectionId: 'sb' });
    const result = (exam, stu) => setDoc(doc(d, ...n, 'resultSummaries', resultId(exam, stu)), {
      schoolId: A, branchId: N, examId: exam, studentId: stu, version: 1, ...base,
    });
    await result(EXAM, 'stu1');
    await result(EXAM, 'stu2');
    await result('y1__c6__sb__unit', 'stu3');
    await result('y1__c5__sa__draft', 'stu1');
  });
}

// ------------------------------------------------------------ apply leave

test('apply leave: the parent can load everything the form needs for a linked child', async () => {
  const p = db('plr-p1');
  await assertSucceeds(getDocs(query(collectionGroup(p, 'parentLinks'), where('schoolId', '==', A), where('parentId', '==', 'par1'))));
  await assertSucceeds(getDoc(ref(p, 'students', 'stu1')));
  await assertSucceeds(getDoc(ref(p, 'academicYears', YEAR)));
  await assertSucceeds(getDocs(query(col(p, 'leaveTypes'), where('kind', '==', 'STUDENT'))));
  await assertSucceeds(getDocs(query(col(p, 'leaveApplications'), where('subjectKind', '==', 'STUDENT'), where('subjectId', '==', 'stu1'))));
});

test('apply leave: the parent can read the branch working days and the year holidays', async () => {
  const p = db('plr-p1');
  await assertSucceeds(getDoc(ref(p, 'settings', 'workingDays')));
  await assertSucceeds(getDocs(query(collection(p, ...nb(A, N), 'academicYears', YEAR, 'holidays'), orderBy('date'))));
});

test('apply leave: a branch with no working days configured is a normal miss, not a denial', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    await setDoc(doc(d, ...nb(A, S), 'parentAccess', 'par-south'), {
      schoolId: A, branchId: S, parentId: 'par-south', classKeys: ['c9'], sectionKeys: ['c9__sx'], updatedAt: serverTimestamp(), updatedBy: 'seed',
    });
  });
  const snap = await assertSucceeds(getDoc(ref(db('plr-p-south'), 'settings', 'workingDays', S)));
  void snap;
});

test('apply leave: only the working-days setting is opened, nothing else under settings', async () => {
  const p = db('plr-p1');
  await assertFails(getDoc(ref(p, 'settings', 'academic')));
  await assertFails(getDocs(col(p, 'settings')));
});

test('apply leave: a parent cannot write the calendar settings or holidays', async () => {
  const p = db('plr-p1');
  await assertFails(updateDoc(ref(p, 'settings', 'workingDays'), { days: ['SUN'] }));
  await assertFails(setDoc(ref(p, 'settings', 'workingDays'), { schoolId: A, branchId: N, days: [] }));
  await assertFails(setDoc(doc(p, ...nb(A, N), 'academicYears', YEAR, 'holidays', 'h2'), { schoolId: A, branchId: N, academicYearId: YEAR }));
  await assertFails(deleteDoc(doc(p, ...nb(A, N), 'academicYears', YEAR, 'holidays', 'h1')));
});

test('apply leave: calendar access needs a family with a child in that branch', async () => {
  // no parentAccess document in this branch
  await assertFails(getDoc(ref(db('plr-p-noindex'), 'settings', 'workingDays')));
  await assertFails(getDocs(query(collection(db('plr-p-noindex'), ...nb(A, N), 'academicYears', YEAR, 'holidays'), orderBy('date'))));
  // a family of another branch
  await assertFails(getDoc(ref(db('plr-p-south'), 'settings', 'workingDays', N)));
  // another school's parent whose record id equals par1
  await assertFails(getDoc(ref(db('plr-p-b'), 'settings', 'workingDays')));
});

test('apply leave: staff keep their access to the calendar', async () => {
  for (const uid of ['plr-admin', 'plr-br-north', 'plr-teacher']) {
    await assertSucceeds(getDoc(ref(db(uid), 'settings', 'workingDays')));
    await assertSucceeds(getDocs(query(collection(db(uid), ...nb(A, N), 'academicYears', YEAR, 'holidays'), orderBy('date'))));
  }
});

// ------------------------------------------------------------- my results

test('my results: the parent lists published exams of the child and reads the results', async () => {
  const p = db('plr-p1');
  const q = (section) => getDocs(query(col(p, 'examinations'),
    where('academicYearId', '==', YEAR), where('classId', '==', 'c5'),
    where('status', '==', 'PUBLISHED'), where('sectionScope', '==', section ?? 'ALL')));
  const classWide = await assertSucceeds(q(null));
  const section = await assertSucceeds(q('sa'));
  const ids = [...classWide.docs, ...section.docs].map((x) => x.id).sort();
  if (ids.join() !== ['y1__c5__ALL__annual', EXAM].sort().join()) throw new Error(`unexpected exams ${ids}`);
  await assertSucceeds(getDoc(ref(p, 'examinations', EXAM)));
  await assertSucceeds(getDoc(ref(p, 'resultSummaries', resultId(EXAM, 'stu1'))));
});

test('my results: a parent with two children reads each child\'s own results', async () => {
  const p = db('plr-p1');
  await assertSucceeds(getDoc(ref(p, 'resultSummaries', resultId('y1__c6__sb__unit', 'stu3'))));
  await assertSucceeds(getDocs(query(col(p, 'examinations'),
    where('academicYearId', '==', YEAR), where('classId', '==', 'c6'),
    where('status', '==', 'PUBLISHED'), where('sectionScope', '==', 'sb'))));
});

test('my results: a missing result document is a normal miss for the linked parent', async () => {
  const snap = await assertSucceeds(getDoc(ref(db('plr-p1'), 'resultSummaries', resultId('y1__c5__ALL__annual', 'stu1'))));
  if (snap.exists()) throw new Error('should not exist');
});

test('my results: unpublished results and other children\'s results stay hidden', async () => {
  const p = db('plr-p1');
  await assertFails(getDoc(ref(p, 'resultSummaries', resultId('y1__c5__sa__draft', 'stu1')))); // exam not published
  await assertFails(getDoc(ref(p, 'resultSummaries', resultId(EXAM, 'stu2')))); // another family's child
  await assertFails(getDoc(ref(db('plr-p2'), 'resultSummaries', resultId('y1__c6__sb__unit', 'stu3')))); // class the family has no child in
  await assertFails(getDoc(ref(db('plr-p-noindex'), 'resultSummaries', resultId(EXAM, 'stu1'))));
  await assertFails(getDoc(ref(db('plr-p-b'), 'resultSummaries', resultId(EXAM, 'stu1'))));
  await assertFails(getDocs(query(col(p, 'resultSummaries'), where('examId', '==', EXAM))));
});

test('my results: a parent can never write marks, grades or publication', async () => {
  const p = db('plr-p1');
  await assertFails(setDoc(ref(p, 'resultSummaries', resultId(EXAM, 'stu1', 2)), { schoolId: A, branchId: N, examId: EXAM, studentId: 'stu1', version: 2 }));
  await assertFails(updateDoc(ref(p, 'resultSummaries', resultId(EXAM, 'stu1')), { overallGrade: 'A+' }));
  await assertFails(updateDoc(ref(p, 'examinations', EXAM), { status: 'WITHDRAWN' }));
  await assertFails(deleteDoc(ref(p, 'resultSummaries', resultId(EXAM, 'stu1'))));
});

test('my results: staff keep their access', async () => {
  for (const uid of ['plr-admin', 'plr-br-north', 'plr-teacher']) {
    await assertSucceeds(getDoc(ref(db(uid), 'resultSummaries', resultId(EXAM, 'stu1'))));
  }
});

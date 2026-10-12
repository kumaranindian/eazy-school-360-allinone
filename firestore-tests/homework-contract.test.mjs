// Contract test: the documents the Dart homework / submission / announcement
// code actually writes (fixtures/homework-write-plans.json, exported by
// test/homework/homework_write_contract_test.dart) must be accepted by the
// real firestore.rules, step by step through each workflow.
//
// Regenerate with:  flutter test test/homework/homework_write_contract_test.dart
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp, Timestamp, writeBatch } from 'firebase/firestore';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

const SCHOOL = 'hwc-a';
const BRANCH = 'north';
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const branchPath = ['schools', SCHOOL, 'branches', BRANCH];

function decode(value) {
  if (Array.isArray(value)) return value.map(decode);
  if (value && typeof value === 'object') {
    if (value.$serverTimestamp) return serverTimestamp();
    if (value.$time) return Timestamp.fromDate(new Date(value.$time));
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, decode(v)]));
  }
  return value;
}

async function seedWorld() {
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'schools', SCHOOL), { name: 'S', status: 'ACTIVE', ...audit('seed') });
    await setDoc(doc(db, ...branchPath), { schoolId: SCHOOL, name: BRANCH, status: 'ACTIVE', ...audit('seed') });
    const users = {
      'hc-admin': { schoolId: SCHOOL, role: 'SCHOOL_ADMIN' },
      'hc-t1': { schoolId: SCHOOL, branchId: BRANCH, role: 'TEACHER' },
      'hc-t2': { schoolId: SCHOOL, branchId: BRANCH, role: 'TEACHER' },
      'hc-p1': { schoolId: SCHOOL, branchId: BRANCH, role: 'PARENT', linkedParentId: 'hc-par1' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, 'users', uid), { branchId: null, name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    for (const [staffId, uid] of [['st1', 'hc-t1'], ['st2', 'hc-t2']]) {
      await setDoc(doc(db, ...branchPath, 'staff', staffId), { schoolId: SCHOOL, branchId: BRANCH, userId: uid, status: 'ACTIVE', isTeacher: true, ...audit('seed') });
    }
    await setDoc(doc(db, ...branchPath, 'academicYears', 'y1', 'classes', 'c5', 'sections', 'sa'), { schoolId: SCHOOL, branchId: BRANCH, name: 'A', status: 'ACTIVE', ...audit('seed') });
    const slot = (key, teacher) => setDoc(doc(db, ...branchPath, 'assignmentSlots', key), {
      schoolId: SCHOOL, branchId: BRANCH, assignmentId: `a-${key}`, teacherStaffId: teacher, createdBy: 'seed', createdAt: serverTimestamp(),
    });
    await slot('y1__c5__sa__math', 'st1');
    await slot('y1__c5__sa__CLASS_TEACHER', 'st2');
    await setDoc(doc(db, ...branchPath, 'students', 'hc-stu1'), {
      schoolId: SCHOOL, branchId: BRANCH, status: 'ACTIVE', currentAcademicYearId: 'y1', currentClassId: 'c5', currentSectionId: 'sa', ...audit('seed'),
    });
    await setDoc(doc(db, ...branchPath, 'students', 'hc-stu1', 'parentLinks', 'hc-par1'), {
      schoolId: SCHOOL, branchId: BRANCH, studentId: 'hc-stu1', parentId: 'hc-par1', canAccessPortal: true, status: 'ACTIVE', ...audit('seed'),
    });
  });
}

const plans = JSON.parse(readFileSync('fixtures/homework-write-plans.json', 'utf8').replaceAll('__SCHOOL__', SCHOOL));

test('Dart-written homework, submission and announcement documents are accepted by the rules, workflow by workflow', async () => {
  await seedWorld();
  for (const scenario of plans.scenarios) {
    for (const [index, batchPlan] of scenario.batches.entries()) {
      const db = testEnv.authenticatedContext(batchPlan.as).firestore();
      const batch = writeBatch(db);
      for (const op of batchPlan.ops) {
        const ref = doc(db, ...branchPath, ...op.path.split('/'));
        if (op.op === 'set') batch.set(ref, decode(op.data));
        else if (op.op === 'update') batch.update(ref, decode(op.data));
        else batch.delete(ref);
      }
      try {
        await assertSucceeds(batch.commit());
      } catch (e) {
        throw new Error(`"${scenario.name}" step ${index + 1} (${batchPlan.label}, as ${batchPlan.as}) was refused: ${e.message}`);
      }
    }
  }
});

// Contract test: the documents the Dart communication code writes
// (fixtures/communication-write-plans.json, exported by
// test/communication/communication_write_contract_test.dart) are accepted by
// the real rules, step by step.
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

const SCHOOL = 'ccc-a';
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
      'cc-p1': { schoolId: SCHOOL, branchId: BRANCH, role: 'PARENT', linkedParentId: 'cc-par1' },
      'cc-t1': { schoolId: SCHOOL, branchId: BRANCH, role: 'TEACHER' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, 'users', uid), { branchId: null, name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    await setDoc(doc(db, ...branchPath, 'staff', 'st1'), { schoolId: SCHOOL, branchId: BRANCH, userId: 'cc-t1', status: 'ACTIVE', isTeacher: true, ...audit('seed') });
    await setDoc(doc(db, ...branchPath, 'assignmentSlots', 'y1__c5__sa__math'), {
      schoolId: SCHOOL, branchId: BRANCH, assignmentId: 'a1', teacherStaffId: 'st1', createdBy: 'seed', createdAt: serverTimestamp(),
    });
    await setDoc(doc(db, ...branchPath, 'students', 'cc-s1'), {
      schoolId: SCHOOL, branchId: BRANCH, status: 'ACTIVE', currentAcademicYearId: 'y1', currentClassId: 'c5', currentSectionId: 'sa', ...audit('seed'),
    });
    await setDoc(doc(db, ...branchPath, 'students', 'cc-s1', 'parentLinks', 'cc-par1'), {
      schoolId: SCHOOL, branchId: BRANCH, studentId: 'cc-s1', parentId: 'cc-par1', canAccessPortal: true, status: 'ACTIVE', ...audit('seed'),
    });
  });
}

const plans = JSON.parse(readFileSync('fixtures/communication-write-plans.json', 'utf8').replaceAll('__SCHOOL__', SCHOOL));

test('Dart-written conversation documents are accepted by the rules, step by step', async () => {
  await seedWorld();
  for (const scenario of plans.scenarios) {
    for (const [index, plan] of scenario.batches.entries()) {
      const db = testEnv.authenticatedContext(plan.as).firestore();
      const batch = writeBatch(db);
      for (const op of plan.ops) {
        const ref = doc(db, ...branchPath, ...op.path.split('/'));
        if (op.op === 'set') batch.set(ref, decode(op.data));
        else batch.update(ref, decode(op.data));
      }
      try {
        await assertSucceeds(batch.commit());
      } catch (e) {
        throw new Error(`"${scenario.name}" step ${index + 1} (${plan.label}, as ${plan.as}) was refused: ${e.message}`);
      }
    }
  }
});

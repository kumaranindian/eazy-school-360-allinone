// Contract test: the documents the Dart leave code actually writes
// (fixtures/leave-write-plans.json, exported by
// test/leave/leave_write_contract_test.dart) must be accepted by the real
// firestore.rules, step by step through each workflow. A renamed field or a
// changed value in Dart that the rules refuse fails here.
//
// Regenerate the fixture with:  flutter test test/leave/leave_write_contract_test.dart
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

const SCHOOL = 'lvc-a';
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
      'lv-admin': { schoolId: SCHOOL, role: 'SCHOOL_ADMIN' },
      'lv-admin2': { schoolId: SCHOOL, role: 'SCHOOL_ADMIN' },
      'lv-parent': { schoolId: SCHOOL, branchId: BRANCH, role: 'PARENT', linkedParentId: 'parent-1' },
      'lv-teacher': { schoolId: SCHOOL, branchId: BRANCH, role: 'TEACHER' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, 'users', uid), {
        branchId: null, name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed'),
      });
    }
    await setDoc(doc(db, ...branchPath, 'students', 'stu-1'), { schoolId: SCHOOL, branchId: BRANCH, status: 'ACTIVE', ...audit('seed') });
    await setDoc(doc(db, ...branchPath, 'students', 'stu-1', 'parentLinks', 'parent-1'), {
      schoolId: SCHOOL, branchId: BRANCH, studentId: 'stu-1', parentId: 'parent-1', canAccessPortal: true, status: 'ACTIVE', ...audit('seed'),
    });
    await setDoc(doc(db, ...branchPath, 'staff', 'staff-t'), { schoolId: SCHOOL, branchId: BRANCH, userId: 'lv-teacher', status: 'ACTIVE', ...audit('seed') });
    const type = (kind, code, name, payType, entitlement) => ({
      schoolId: SCHOOL, branchId: BRANCH, kind, code, name, payType, requiresDocument: false, requiresReason: true, allowHalfDay: true,
      countNonWorkingDays: false, maxDaysPerRequest: null, applicableRoles: [], applicableEmploymentTypes: [],
      annualEntitlementUnits: entitlement, accrual: 'UPFRONT', carryForwardMaxUnits: 0, exceedPolicy: 'BLOCK', status: 'ACTIVE', ...audit('seed'),
    });
    await setDoc(doc(db, ...branchPath, 'leaveTypes', 'STUDENT__sick'), type('STUDENT', 'SICK', 'Sick leave', 'NA', null));
    await setDoc(doc(db, ...branchPath, 'leaveTypes', 'STAFF__cl'), type('STAFF', 'CL', 'Casual leave', 'PAID', 24));
  });
}

const plans = JSON.parse(readFileSync('fixtures/leave-write-plans.json', 'utf8').replaceAll('__SCHOOL__', SCHOOL));

test('Dart-written documents are accepted by the rules, workflow by workflow', async () => {
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

// Pay data has NO client rules: every read and write goes through a callable (functions/payroll*.js), where the
// role, branch scope, module switch and school state are checked. This proves the default deny: not a school admin,
// not finance, not the staff member whose pay it is, not a parent, not another school's admin, not a signed-out
// client can read or write ANY payroll document, nor query one through a collection group. If a rule for one of
// these collections is ever added, this file fails. Own ids (pr-) so it runs beside the other files.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';

let testEnv;
const A = 'pr-a';
const B = 'pr-b';
const NORTH = 'north';
const base = ['schools', A, 'branches', NORTH];

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const user = (uid, schoolId, role, branchId = null) => setDoc(doc(db, 'users', uid), { schoolId, branchId, name: uid, email: `${uid}@example.com`, role, status: 'ACTIVE' });
    await user('pr-owner', A, 'SCHOOL_ADMIN');
    await user('pr-finance', A, 'FINANCE', NORTH);
    await user('pr-branchadmin', A, 'BRANCH_ADMIN', NORTH);
    await user('pr-teacher', A, 'TEACHER', NORTH);
    await user('pr-parent', A, 'PARENT');
    await user('pr-other-owner', B, 'SCHOOL_ADMIN');
    await setDoc(doc(db, 'schools', A), { schoolId: A, name: 'A', status: 'ACTIVE' });
    await setDoc(doc(db, 'schools', B), { schoolId: B, name: 'B', status: 'ACTIVE' });
    await setDoc(doc(db, ...base, 'staff', 'st1'), { schoolId: A, branchId: NORTH, firstName: 'Priya', userId: 'pr-teacher', status: 'ACTIVE' });
    await setDoc(doc(db, 'schools', A, 'payComponents', 'pc_basic'), { schoolId: A, name: 'Basic salary', kind: 'EARNING', calc: 'FIXED' });
    await setDoc(doc(db, 'schools', A, 'payrollSettings', 'config'), { schoolId: A, unmarkedDays: 'PAID' });
    await setDoc(doc(db, ...base, 'salaryStructures', 'st1_00001'), { schoolId: A, staffId: 'st1', grossMinor: 5000000, netMinor: 5000000 });
    await setDoc(doc(db, ...base, 'payrollRuns', '2026-11'), { schoolId: A, period: '2026-11', status: 'PAID', netMinor: 5000000 });
    await setDoc(doc(db, ...base, 'payrollRuns', '2026-11', 'payslips', 'st1'), { schoolId: A, staffId: 'st1', netMinor: 5000000 });
    await setDoc(doc(db, ...base, 'payrollRuns', '2026-11', 'history', '00001'), { seq: 1, action: 'pay', actorId: 'pr-finance' });
    await setDoc(doc(db, ...base, 'expenses', 'payroll_2026-11'), { schoolId: A, amountMinor: 5000000, source: 'PAYROLL', status: 'PAID' });
    await setDoc(doc(db, ...base, 'expenseSequences', 'EXP-2026'), { schoolId: A, next: 1 });
  });
});

after(async () => {
  await testEnv.cleanup();
});

const actors = {
  'a school admin': (e) => e.authenticatedContext('pr-owner').firestore(),
  'finance': (e) => e.authenticatedContext('pr-finance').firestore(),
  'a branch admin': (e) => e.authenticatedContext('pr-branchadmin').firestore(),
  'the staff member whose pay it is': (e) => e.authenticatedContext('pr-teacher').firestore(),
  'a parent': (e) => e.authenticatedContext('pr-parent').firestore(),
  "another school's admin": (e) => e.authenticatedContext('pr-other-owner').firestore(),
  'a signed-out client': (e) => e.unauthenticatedContext().firestore(),
};

const docs = {
  'pay component': ['schools', A, 'payComponents', 'pc_basic'],
  'payroll settings': ['schools', A, 'payrollSettings', 'config'],
  'salary structure': [...base, 'salaryStructures', 'st1_00001'],
  'payroll run': [...base, 'payrollRuns', '2026-11'],
  'payslip': [...base, 'payrollRuns', '2026-11', 'payslips', 'st1'],
  'run history entry': [...base, 'payrollRuns', '2026-11', 'history', '00001'],
  'payroll expense': [...base, 'expenses', 'payroll_2026-11'],
  'expense sequence': [...base, 'expenseSequences', 'EXP-2026'],
};

for (const [who, dbFor] of Object.entries(actors)) {
  for (const [what, path] of Object.entries(docs)) {
    test(`${who} cannot read, write, change or delete a ${what}`, async () => {
      const db = dbFor(testEnv);
      await assertFails(getDoc(doc(db, ...path)));
      await assertFails(getDocs(collection(db, ...path.slice(0, -1))));
      await assertFails(setDoc(doc(db, ...path), { schoolId: A, netMinor: 1 }));
      await assertFails(updateDoc(doc(db, ...path), { netMinor: 1 }));
      await assertFails(deleteDoc(doc(db, ...path)));
      await assertFails(setDoc(doc(db, ...path.slice(0, -1), 'new-doc'), { schoolId: A, netMinor: 1 }));
    });
  }
  test(`${who} cannot find pay data with a collection-group query`, async () => {
    const db = dbFor(testEnv);
    for (const group of ['payslips', 'salaryStructures', 'payrollRuns', 'payComponents']) {
      await assertFails(getDocs(collectionGroup(db, group)));
      await assertFails(getDocs(query(collectionGroup(db, group), where('schoolId', '==', A))));
    }
  });
}

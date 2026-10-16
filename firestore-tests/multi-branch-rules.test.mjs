// Multi-branch staff: a profile has a home branch (+role) and optionally
// `branchRoles: { <branchId>: <role> }` (server-written). Prefix: mb-.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, limit, query, serverTimestamp, setDoc, updateDoc,
} from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await seed();
});
after(async () => env.cleanup());

const A = 'mb-a';
const Z = 'mb-z';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const nb = (s, b) => ['schools', s, 'branches', b];
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const BR = ['north', 'south', 'east'];

async function seed() {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, Z]) {
      await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...base });
      for (const b of BR) {
        await setDoc(doc(d, ...nb(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...base });
        await setDoc(doc(d, ...nb(s, b), 'academicYears', 'y1'), { schoolId: s, branchId: b, name: 'Y1', status: 'ACTIVE', ...base });
      }
    }
    const users = {
      // home north TEACHER, also BRANCH_ADMIN in south
      'mb-multi': { schoolId: A, branchId: 'north', role: 'TEACHER', branchRoles: { south: 'BRANCH_ADMIN' } },
      // home north FINANCE, also TEACHER in south
      'mb-fin': { schoolId: A, branchId: 'north', role: 'FINANCE', branchRoles: { south: 'TEACHER' } },
      'mb-single': { schoolId: A, branchId: 'north', role: 'TEACHER' },
      'mb-off': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN', status: 'DISABLED', branchRoles: { south: 'BRANCH_ADMIN' } },
      // corrupt data must not escalate
      'mb-bad': { schoolId: A, branchId: 'north', role: 'TEACHER', branchRoles: { south: 'SCHOOL_ADMIN', east: 'PLATFORM_ADMIN' } },
      // a mapping for a branch name that exists in ANOTHER school only
      'mb-other': { schoolId: Z, branchId: 'north', role: 'TEACHER', branchRoles: { south: 'TEACHER' } },
      'mb-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
  });
}

const yearDoc = (b, s = A) => ['schools', s, 'branches', b, 'academicYears', 'y1'];
const newClass = (b) => ['schools', A, 'branches', b, 'academicYears', 'y1', 'classes', `c-${b}-${Math.random().toString(36).slice(2, 7)}`];
const classBody = (b) => ({
  schoolId: A, branchId: b, academicYearId: 'y1', name: 'C', code: 'c', displayOrder: 1, status: 'ACTIVE',
  createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'x', updatedBy: 'x',
});

test('a multi-branch user holds a different role in each assigned branch', async () => {
  const d = as('mb-multi');
  // home branch: teacher → may read academic setup, may not write
  await assertSucceeds(getDoc(doc(d, ...yearDoc('north'))));
  const homeClass = newClass('north');
  await assertFails(setDoc(doc(d, ...homeClass), { ...classBody('north'), createdBy: 'mb-multi', updatedBy: 'mb-multi' }));
  // second branch: branch admin → may write
  await assertSucceeds(getDoc(doc(d, ...yearDoc('south'))));
  await assertSucceeds(setDoc(doc(d, ...newClass('south')), { ...classBody('south'), createdBy: 'mb-multi', updatedBy: 'mb-multi' }));
  // a branch they are not assigned to
  await assertFails(getDoc(doc(d, ...yearDoc('east'))));
  await assertFails(setDoc(doc(d, ...newClass('east')), { ...classBody('east'), createdBy: 'mb-multi', updatedBy: 'mb-multi' }));
});

test('roles do not leak between branches (finance home, teacher elsewhere)', async () => {
  const d = as('mb-fin');
  await assertSucceeds(getDoc(doc(d, ...yearDoc('north'))));
  await assertSucceeds(getDoc(doc(d, ...yearDoc('south'))));
  await assertFails(setDoc(doc(d, ...newClass('south')), { ...classBody('south'), createdBy: 'mb-fin', updatedBy: 'mb-fin' }));
  await assertFails(getDoc(doc(d, ...yearDoc('east'))));
});

test('a user without branchRoles is limited to the home branch (unchanged)', async () => {
  const d = as('mb-single');
  await assertSucceeds(getDoc(doc(d, ...yearDoc('north'))));
  await assertFails(getDoc(doc(d, ...yearDoc('south'))));
});

test('a disabled account loses every branch', async () => {
  const d = as('mb-off');
  await assertFails(getDoc(doc(d, ...yearDoc('north'))));
  await assertFails(getDoc(doc(d, ...yearDoc('south'))));
});

test('corrupt branchRoles values never escalate beyond branch roles', async () => {
  const d = as('mb-bad');
  await assertFails(getDoc(doc(d, ...yearDoc('south'))));
  await assertFails(getDoc(doc(d, ...yearDoc('east'))));
  await assertFails(updateDoc(doc(d, 'schools', A), { name: 'hijack', updatedAt: serverTimestamp(), updatedBy: 'mb-bad' }));
  await assertFails(setDoc(doc(d, ...newClass('south')), { ...classBody('south'), createdBy: 'mb-bad', updatedBy: 'mb-bad' }));
});

test('branchRoles never reaches another school, even with a matching branch id', async () => {
  const d = as('mb-other');
  await assertFails(getDoc(doc(d, ...yearDoc('south', A))));
  await assertFails(getDoc(doc(d, ...yearDoc('north', A))));
  await assertSucceeds(getDoc(doc(d, ...yearDoc('south', Z))));
});

test('clients cannot grant branch roles — self, school admin or at creation', async () => {
  // self
  await assertFails(updateDoc(doc(as('mb-single'), 'users', 'mb-single'), {
    branchRoles: { south: 'BRANCH_ADMIN' }, updatedAt: serverTimestamp(), updatedBy: 'mb-single',
  }));
  // branch admin of the home branch
  await assertFails(updateDoc(doc(as('mb-off'), 'users', 'mb-single'), {
    branchRoles: { south: 'BRANCH_ADMIN' }, updatedAt: serverTimestamp(), updatedBy: 'mb-off',
  }));
  // school admin (the Cloud Function is the only writer)
  await assertFails(updateDoc(doc(as('mb-admin'), 'users', 'mb-single'), {
    branchRoles: { south: 'BRANCH_ADMIN' }, updatedAt: serverTimestamp(), updatedBy: 'mb-admin',
  }));
  // creation with the field
  await assertFails(setDoc(doc(as('mb-admin'), 'users', 'mb-new'), {
    schoolId: A, branchId: 'north', role: 'TEACHER', status: 'INVITED', name: 'N', email: 'n@example.com',
    linkedParentId: null, branchRoles: { south: 'BRANCH_ADMIN' }, ...{ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'mb-admin', updatedBy: 'mb-admin' },
  }));
  // …and the same without the field is allowed (control)
  await assertSucceeds(setDoc(doc(as('mb-admin'), 'users', 'mb-new2'), {
    schoolId: A, branchId: 'north', role: 'TEACHER', status: 'INVITED', name: 'N', email: 'n2@example.com',
    linkedParentId: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'mb-admin', updatedBy: 'mb-admin',
  }));
});

test('own-profile reads still work and list queries stay branch-pinned', async () => {
  const d = as('mb-multi');
  await assertSucceeds(getDoc(doc(d, 'users', 'mb-multi')));
  await assertSucceeds(getDocs(query(collection(d, ...nb(A, 'south'), 'academicYears'), limit(5))));
  await assertFails(getDocs(query(collection(d, ...nb(A, 'east'), 'academicYears'), limit(5))));
});

test('a teacher in a second branch reads exactly that branch\'s assigned sections (teacherAccess)', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    const sb = nb(A, 'south');
    await setDoc(doc(d, ...sb, 'teacherAccess', 'mb-fin'), { schoolId: A, branchId: 'south', staffId: 's1', userId: 'mb-fin', sectionKeys: ['c5__sa'], scopes: [], updatedAt: serverTimestamp() });
    await setDoc(doc(d, ...sb, 'students', 'stu-a'), { schoolId: A, branchId: 'south', status: 'ACTIVE', currentClassId: 'c5', currentSectionId: 'sa', ...base });
    await setDoc(doc(d, ...sb, 'students', 'stu-b'), { schoolId: A, branchId: 'south', status: 'ACTIVE', currentClassId: 'c5', currentSectionId: 'sb', ...base });
    await setDoc(doc(d, ...nb(A, 'north'), 'students', 'stu-n'), { schoolId: A, branchId: 'north', status: 'ACTIVE', currentClassId: 'c5', currentSectionId: 'sa', ...base });
  });
  const d = as('mb-fin');
  await assertSucceeds(getDoc(doc(d, ...nb(A, 'south'), 'students', 'stu-a')));
  await assertFails(getDoc(doc(d, ...nb(A, 'south'), 'students', 'stu-b')));
  // the home FINANCE role reads the home branch's students; a teacherAccess doc is not needed there
  await assertSucceeds(getDoc(doc(d, ...nb(A, 'north'), 'students', 'stu-n')));
  // the audit trail is for school admins
  await assertFails(getDocs(collection(d, 'schools', A, 'branchAccessAudit')));
  await assertSucceeds(getDocs(collection(as('mb-admin'), 'schools', A, 'branchAccessAudit')));
});

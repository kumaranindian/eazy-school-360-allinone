// A signed-in Firebase user with NO /users/{uid} profile must be denied
// everything tenant-scoped (the helpers call get() on the caller's profile
// directly, so a missing profile is an evaluation error = deny), exactly like
// a user whose profile exists but who has no role. Prefix: np-.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
    await setDoc(doc(d, 'schools', S), { name: S, status: 'ACTIVE', ...base });
    await setDoc(doc(d, ...B), { schoolId: S, name: 'n', status: 'ACTIVE', ...base });
    await setDoc(doc(d, ...B, 'staff', 'st1'), { schoolId: S, branchId: 'n', ...base });
    await setDoc(doc(d, ...B, 'students', 'su1'), { schoolId: S, branchId: 'n', ...base });
    await setDoc(doc(d, 'users', 'np-admin'), {
      schoolId: S, branchId: 'n', role: 'SCHOOL_ADMIN', status: 'ACTIVE',
    });
  });
});
after(async () => env.cleanup());

const S = 'np-school';
const B = ['schools', S, 'branches', 'n'];
const noProfile = () => env.authenticatedContext('np-ghost', { firebase: { sign_in_provider: 'password' } }).firestore();
const admin = () => env.authenticatedContext('np-admin', { firebase: { sign_in_provider: 'password' } }).firestore();
const anon = () => env.unauthenticatedContext().firestore();

test('control: an active school admin of the school can read and write the branch', async () => {
  await assertSucceeds(getDoc(doc(admin(), ...B, 'staff', 'st1')));
  await assertSucceeds(getDoc(doc(admin(), ...B, 'students', 'su1')));
});

test('a signed-in user without a profile cannot read tenant data', async () => {
  const d = noProfile();
  await assertFails(getDoc(doc(d, 'schools', S)));
  await assertFails(getDoc(doc(d, ...B)));
  await assertFails(getDoc(doc(d, ...B, 'staff', 'st1')));
  await assertFails(getDoc(doc(d, ...B, 'students', 'su1')));
  await assertFails(getDocs(collection(d, ...B, 'staff')));
  await assertFails(getDocs(collection(d, ...B, 'students')));
});

test('a signed-in user without a profile cannot write tenant data', async () => {
  const d = noProfile();
  const base = { schoolId: S, branchId: 'n', createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'np-ghost', updatedBy: 'np-ghost' };
  await assertFails(setDoc(doc(d, ...B, 'staff', 'st-new'), base));
  await assertFails(setDoc(doc(d, ...B, 'students', 'su-new'), base));
  await assertFails(updateDoc(doc(d, ...B, 'staff', 'st1'), { updatedBy: 'np-ghost', updatedAt: serverTimestamp() }));
  await assertFails(deleteDoc(doc(d, ...B, 'students', 'su1')));
  await assertFails(setDoc(doc(d, ...B, 'academicYears', 'y1'), base));
  await assertFails(setDoc(doc(d, ...B, 'feeStructures', 'f1'), base));
});

test('a user without a profile cannot create a profile for another uid or an admin profile in an existing school', async () => {
  const d = noProfile();
  await assertFails(setDoc(doc(d, 'users', 'np-other'), { schoolId: S, role: 'SCHOOL_ADMIN', status: 'ACTIVE' }));
  await assertFails(setDoc(doc(d, 'users', 'np-ghost'), { schoolId: S, branchId: 'n', role: 'SCHOOL_ADMIN', status: 'ACTIVE' }));
});

test('unauthenticated callers stay denied', async () => {
  const d = anon();
  await assertFails(getDoc(doc(d, 'schools', S)));
  await assertFails(getDoc(doc(d, ...B, 'staff', 'st1')));
  await assertFails(setDoc(doc(d, ...B, 'staff', 'st-anon'), { schoolId: S }));
});

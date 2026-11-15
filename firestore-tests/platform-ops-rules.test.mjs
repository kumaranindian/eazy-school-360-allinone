// Platform Phase 3-4: a suspended school is paused for all its users (Firestore
// and Storage), dashboard stats, notices, app settings; billing/offboarding have
// no client access; nobody writes any of it from a client. Prefix: pfo-.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp, collection, query, where } from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
    storage: { rules: readFileSync(process.env.STORAGE_RULES_FILE || '../storage.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const A = 'pfo-a';
const B = 'pfo-b';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const PW = { firebase: { sign_in_provider: 'password' } };
const as = (uid, token = PW) => env.authenticatedContext(uid, token).firestore();
const mfa = (uid) => as(uid, MFA);
const student = (d, sch = A) => doc(d, 'schools', sch, 'branches', 'north', 'students', 's1');
const future = () => Timestamp.fromMillis(Date.now() + 3600e3);

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) {
      await setDoc(doc(d, 'schools', s), { name: s, email: `${s}@e.com`, status: 'ACTIVE', ...base });
      await setDoc(student(d, s), { schoolId: s, branchId: 'north', firstName: 'Kid', lastName: s, status: 'ACTIVE', ...base });
    }
    const login = { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'] };
    const users = {
      'pfo-admin': { role: 'SCHOOL_ADMIN', schoolId: A, branchId: null },
      'pfo-branch': { role: 'BRANCH_ADMIN', schoolId: A, branchId: 'north' },
      'pfo-teacher': { role: 'TEACHER', schoolId: A, branchId: 'north' },
      'pfo-admin-b': { role: 'SCHOOL_ADMIN', schoolId: B, branchId: null },
      'pfo-paused-admin': { role: 'SCHOOL_ADMIN', schoolId: A, branchId: null, schoolAccess: 'SUSPENDED' },
      'pfo-paused-branch': { role: 'BRANCH_ADMIN', schoolId: A, branchId: 'north', schoolAccess: 'SUSPENDED' },
      'pfo-paused-teacher': { role: 'TEACHER', schoolId: A, branchId: 'north', schoolAccess: 'SUSPENDED' },
      'pfo-owner': { role: 'PLATFORM_ADMIN', platformRole: 'OWNER', schoolId: null, branchId: null, login },
      'pfo-viewer': { role: 'PLATFORM_ADMIN', platformRole: 'VIEWER', schoolId: null, branchId: null, login },
    };
    for (const [uid, u] of Object.entries(users)) await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@e.com`, status: 'ACTIVE', ...u, ...base });
    await setDoc(doc(d, 'platformStats', 'current'), { schools: { total: 2 }, computedAtMs: 1 });
    await setDoc(doc(d, 'schoolUsage', A), { schoolId: A, students: 1 });
    await setDoc(doc(d, 'platformSettings', 'app'), { minBuild: { android: 13, ios: 0 }, maintenance: { enabled: false } });
    await setDoc(doc(d, 'platformSettings', 'secret'), { x: 1 });
    await setDoc(doc(d, 'platformNotices', 'all'), { title: 'All', audienceAll: true, schoolIds: [], status: 'ACTIVE', endsAt: future() });
    await setDoc(doc(d, 'platformNotices', 'a-only'), { title: 'A', audienceAll: false, schoolIds: [A], status: 'ACTIVE', endsAt: future() });
    await setDoc(doc(d, 'platformNotices', 'b-only'), { title: 'B', audienceAll: false, schoolIds: [B], status: 'ACTIVE', endsAt: future() });
    await setDoc(doc(d, 'platformBilling', 'b1'), { schoolId: A, amountMinor: 1 });
    await setDoc(doc(d, 'platformOffboarding', A), { schoolId: A, state: 'REQUESTED' });
  });
});

// ---- suspension ---------------------------------------------------------------------

test('a suspended school is paused: its users read none of its data, but can still read their own profile', async () => {
  for (const uid of ['pfo-paused-admin', 'pfo-paused-branch', 'pfo-paused-teacher']) {
    const d = as(uid);
    await assertSucceeds(getDoc(doc(d, 'users', uid)));
    await assertFails(getDoc(student(d, A)), `${uid} student`);
    await assertFails(getDoc(doc(d, 'schools', A)), `${uid} school`);
    await assertFails(getDoc(doc(d, 'schools', A, 'branches', 'north')), `${uid} branch`);
  }
});

test('the same roles of a school that is NOT suspended work as before', async () => {
  const d = as('pfo-admin');
  await assertSucceeds(getDoc(doc(d, 'schools', A)));
  await assertSucceeds(getDoc(student(d, A)));
  await assertSucceeds(getDoc(student(as('pfo-branch'), A)));
  await assertSucceeds(getDoc(doc(as('pfo-teacher'), 'schools', A)));
});

test('a suspended user cannot write either', async () => {
  const d = as('pfo-paused-admin');
  await assertFails(updateDoc(doc(d, 'schools', A), { name: 'Renamed', updatedAt: serverTimestamp(), updatedBy: 'pfo-paused-admin' }));
  await assertFails(updateDoc(student(d, A), { firstName: 'X', updatedAt: serverTimestamp(), updatedBy: 'pfo-paused-admin' }));
  await assertFails(setDoc(doc(d, 'users', 'pfo-new'), { name: 'N', email: 'n@e.com', role: 'TEACHER', schoolId: A, branchId: 'north', status: 'ACTIVE', ...base }));
});

test('a suspended user cannot lift it from the client, nor can anyone else', async () => {
  for (const [uid, d] of [['pfo-paused-admin', as('pfo-paused-admin')], ['pfo-owner', mfa('pfo-owner')], ['pfo-admin', as('pfo-admin')]]) {
    await assertFails(updateDoc(doc(d, 'users', 'pfo-paused-teacher'), { schoolAccess: 'ACTIVE', updatedAt: serverTimestamp(), updatedBy: uid }));
    await assertFails(updateDoc(doc(d, 'users', 'pfo-paused-admin'), { schoolAccess: 'ACTIVE', updatedAt: serverTimestamp(), updatedBy: uid }));
  }
});

test('nobody pauses or un-pauses a school from a client: status, reason and features are server-only', async () => {
  for (const [uid, d] of [['pfo-admin', as('pfo-admin')], ['pfo-owner', mfa('pfo-owner')]]) {
    for (const change of [{ status: 'SUSPENDED' }, { statusReason: 'x' }, { features: { admission: false } }]) {
      await assertFails(updateDoc(doc(d, 'schools', A), { ...change, updatedAt: serverTimestamp(), updatedBy: uid }));
    }
  }
});

test('a platform admin is never paused: the directory and a support session still work for a suspended school', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await updateDoc(doc(c.firestore(), 'schools', A), { status: 'SUSPENDED' });
    await setDoc(doc(c.firestore(), 'supportGrants', `pfo-owner__${A}`), {
      adminUid: 'pfo-owner', schoolId: A, scope: 'READ', reason: 'checking a suspended school', expiresAt: future(), revokedAt: null,
    });
  });
  const d = mfa('pfo-owner');
  await assertSucceeds(getDoc(doc(d, 'schools', A)));
  await assertSucceeds(getDoc(student(d, A)));
  await assertFails(updateDoc(student(d, A), { firstName: 'X', updatedAt: serverTimestamp(), updatedBy: 'pfo-owner' }));
});

test('Storage: a suspended school\'s users lose file access too', async () => {
  const path = `schools/${A}/logo.png`;
  const png = new Uint8Array([137, 80, 78, 71]);
  await env.withSecurityRulesDisabled(async (c) => uploadBytes(ref(c.storage(), path), png, { contentType: 'image/png' }));
  await assertSucceeds(getBytes(ref(env.authenticatedContext('pfo-admin', PW).storage(), path)));
  await assertSucceeds(getBytes(ref(env.authenticatedContext('pfo-teacher', PW).storage(), path)));
  for (const uid of ['pfo-paused-admin', 'pfo-paused-teacher']) {
    await assertFails(getBytes(ref(env.authenticatedContext(uid, PW).storage(), path)));
  }
  await assertFails(uploadBytes(ref(env.authenticatedContext('pfo-paused-admin', PW).storage(), path), png, { contentType: 'image/png' }));
});

// ---- dashboard numbers ---------------------------------------------------------------

test('stats, usage and notices have no client access at all (they are read through callables)', async () => {
  const everyone = [['owner', mfa('pfo-owner')], ['viewer', mfa('pfo-viewer')], ['admin', as('pfo-admin')], ['branch', as('pfo-branch')], ['teacher', as('pfo-teacher')], ['anon', env.unauthenticatedContext().firestore()]];
  for (const [who, d] of everyone) {
    await assertFails(getDoc(doc(d, 'platformStats', 'current')), `${who} stats`);
    await assertFails(getDoc(doc(d, 'schoolUsage', A)), `${who} usage`);
    await assertFails(getDoc(doc(d, 'platformNotices', 'all')), `${who} notice`);
    await assertFails(getDocs(query(collection(d, 'platformNotices'), where('audienceAll', '==', true))), `${who} notice list`);
    await assertFails(getDocs(query(collection(d, 'platformNotices'), where('schoolIds', 'array-contains', A))), `${who} notice list for the school`);
  }
});

test('nobody writes stats, usage or notices from a client', async () => {
  for (const d of [mfa('pfo-owner'), as('pfo-admin')]) {
    await assertFails(setDoc(doc(d, 'platformStats', 'current'), { forged: 1 }));
    await assertFails(updateDoc(doc(d, 'platformStats', 'current'), { students: 9 }));
    await assertFails(setDoc(doc(d, 'schoolUsage', A), { students: 9 }));
    await assertFails(setDoc(doc(d, 'platformNotices', 'forged'), { title: 'x', audienceAll: true, schoolIds: [], status: 'ACTIVE' }));
    await assertFails(updateDoc(doc(d, 'platformNotices', 'all'), { title: 'edited' }));
    await assertFails(deleteDoc(doc(d, 'platformNotices', 'all')));
  }
});

// ---- notices ---------------------------------------------------------------------------




// ---- app settings, billing, offboarding ----------------------------------------------

test('app settings: the "app" document is public (a signed-out app must see maintenance mode); nothing else is', async () => {
  await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), 'platformSettings', 'app')));
  await assertSucceeds(getDoc(doc(as('pfo-teacher'), 'platformSettings', 'app')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'platformSettings', 'secret')));
  await assertFails(getDoc(doc(mfa('pfo-owner'), 'platformSettings', 'secret')));
});

test('app settings are never written from a client, not even by an owner', async () => {
  for (const d of [mfa('pfo-owner'), as('pfo-admin'), env.unauthenticatedContext().firestore()]) {
    await assertFails(setDoc(doc(d, 'platformSettings', 'app'), { maintenance: { enabled: true }, minBuild: { android: 99, ios: 99 } }));
    await assertFails(updateDoc(doc(d, 'platformSettings', 'app'), { maintenance: { enabled: true } }));
    await assertFails(deleteDoc(doc(d, 'platformSettings', 'app')));
  }
});

test('billing records and offboarding have no client access at all: not even an owner', async () => {
  for (const d of [mfa('pfo-owner'), as('pfo-admin'), as('pfo-teacher')]) {
    await assertFails(getDoc(doc(d, 'platformBilling', 'b1')));
    await assertFails(getDocs(collection(d, 'platformBilling')));
    await assertFails(setDoc(doc(d, 'platformBilling', 'x'), { schoolId: A, amountMinor: 1 }));
    await assertFails(getDoc(doc(d, 'platformOffboarding', A)));
    await assertFails(setDoc(doc(d, 'platformOffboarding', A), { state: 'APPROVED' }));
  }
});

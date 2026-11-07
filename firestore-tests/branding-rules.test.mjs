// Tenant branding: schools/{s}/branding/config is read by EVERY member of the
// school (all roles, all branches) and by platform admins, never by another
// school; nobody writes it from a client (updateSchoolBranding does).
// platformBranding/default: any signed-in user reads, nobody writes from a
// client. Prefix: brd-.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const A = 'brd-a';
const B = 'brd-b';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const cfg = (d, s = A) => doc(d, 'schools', s, 'branding', 'config');
const plat = (d) => doc(d, 'platformBranding', 'default');
const theme = { version: 1, preset: 'indigo', appearance: 'system' };
const MEMBERS = ['brd-admin', 'brd-ba', 'brd-teacher', 'brd-finance', 'brd-parent'];

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) await setDoc(doc(d, 'schools', s), { name: s, email: `${s}@example.com`, status: 'ACTIVE', ...base });
    const users = {
      'brd-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'brd-admin-b': { schoolId: B, branchId: null, role: 'SCHOOL_ADMIN' },
      'brd-ba': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN' },
      'brd-teacher': { schoolId: A, branchId: 'north', role: 'TEACHER' },
      'brd-finance': { schoolId: A, branchId: 'north', role: 'FINANCE' },
      'brd-parent': { schoolId: A, branchId: 'north', role: 'PARENT', linkedParentId: 'p1' },
      'brd-parent-b': { schoolId: B, branchId: 'north', role: 'PARENT', linkedParentId: 'p2' },
      'brd-platform': { schoolId: null, branchId: null, role: 'PLATFORM_ADMIN' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    await setDoc(cfg(d), theme);
    await setDoc(cfg(d, B), { ...theme, preset: 'crimson' });
    await setDoc(plat(d), { version: 1, defaultPreset: 'emerald', presets: {} });
  });
});

test('every role of the school reads the school theme', async () => {
  for (const uid of MEMBERS) await assertSucceeds(getDoc(cfg(as(uid))));
});

test('a platform admin reads any school theme', async () => {
  await assertSucceeds(getDoc(cfg(as('brd-platform'))));
  await assertSucceeds(getDoc(cfg(as('brd-platform'), B)));
});

test('another school and signed-out users cannot read it', async () => {
  await assertFails(getDoc(cfg(as('brd-admin-b'))));
  await assertFails(getDoc(cfg(as('brd-parent-b'))));
  await assertFails(getDoc(cfg(env.unauthenticatedContext().firestore())));
  await assertFails(getDoc(cfg(as('brd-admin'), B)));
});

test('nobody writes the school theme from a client, not even the school admin', async () => {
  for (const uid of [...MEMBERS, 'brd-admin-b', 'brd-platform']) {
    await assertFails(setDoc(cfg(as(uid)), { ...theme, preset: 'plum' }));
    await assertFails(updateDoc(cfg(as(uid)), { preset: 'plum' }));
    await assertFails(deleteDoc(cfg(as(uid))));
  }
  await assertFails(setDoc(doc(as('brd-admin'), 'schools', A, 'branding', 'other'), theme));
});

test('the school document cannot carry theme fields of its own', async () => {
  await assertFails(updateDoc(doc(as('brd-admin'), 'schools', A), { theme: { preset: 'plum' }, updatedAt: serverTimestamp(), updatedBy: 'brd-admin' }));
});

test('any signed-in user reads the platform default; signed-out users cannot', async () => {
  for (const uid of [...MEMBERS, 'brd-admin-b', 'brd-platform']) await assertSucceeds(getDoc(plat(as(uid))));
  await assertFails(getDoc(plat(env.unauthenticatedContext().firestore())));
});

test('nobody writes the platform default from a client, not even a platform admin', async () => {
  for (const uid of [...MEMBERS, 'brd-platform']) {
    await assertFails(setDoc(plat(as(uid)), { version: 2, defaultPreset: 'indigo' }));
    await assertFails(updateDoc(plat(as(uid)), { defaultPreset: 'indigo' }));
    await assertFails(deleteDoc(plat(as(uid))));
  }
});

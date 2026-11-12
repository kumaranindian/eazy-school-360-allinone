// Admission enquiries: schools/{s}/branches/{b}/admissionEnquiries and
// admissionStatusHistory are READ by the school admin, a platform admin and the
// branch admin of THAT branch; nobody else (teacher, finance, parent, another
// school, another branch's admin, signed-out). Nobody WRITES them from a client
// (the admission callables do). admissionSequences has no rule (server-only).
// schools/{s}/admissionSettings/config: read by administrators of the school,
// never written from a client. Prefix: adm-.
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

const A = 'adm-a';
const B = 'adm-b';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const enq = (d, s = A, b = 'north', id = 'e1') => doc(d, 'schools', s, 'branches', b, 'admissionEnquiries', id);
const hist = (d, s = A, b = 'north', id = 'e1__1') => doc(d, 'schools', s, 'branches', b, 'admissionStatusHistory', id);
const seq = (d) => doc(d, 'schools', A, 'branches', 'north', 'admissionSequences', 'ENQ-2026');
const settings = (d, s = A) => doc(d, 'schools', s, 'admissionSettings', 'config');
const enquiry = (s, b) => ({ schoolId: s, branchId: b, enquiryNumber: 'ENQ-2026-00001', status: 'NEW', studentName: 'Asha Nair', revision: 1, ...base });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) {
      await setDoc(doc(d, 'schools', s), { name: s, email: `${s}@example.com`, status: 'ACTIVE', ...base });
      for (const b of ['north', 'south']) {
        await setDoc(doc(d, 'schools', s, 'branches', b), { schoolId: s, branchId: b, name: b, status: 'ACTIVE', ...base });
        await setDoc(enq(d, s, b), enquiry(s, b));
        await setDoc(hist(d, s, b), { schoolId: s, branchId: b, enquiryId: 'e1', revision: 1, from: null, to: 'NEW' });
      }
      await setDoc(settings(d, s), { schoolId: s, enabled: true, version: 1 });
    }
    await setDoc(seq(d), { next: 1 });
    const users = {
      'adm-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'adm-admin-b': { schoolId: B, branchId: null, role: 'SCHOOL_ADMIN' },
      'adm-north': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN' },
      'adm-south': { schoolId: A, branchId: 'south', role: 'BRANCH_ADMIN' },
      'adm-teacher': { schoolId: A, branchId: 'north', role: 'TEACHER' },
      'adm-finance': { schoolId: A, branchId: 'north', role: 'FINANCE' },
      'adm-parent': { schoolId: A, branchId: 'north', role: 'PARENT', linkedParentId: 'p1' },
      'adm-platform': { schoolId: null, branchId: null, role: 'PLATFORM_ADMIN' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
  });
});

test('the school admin, a platform admin and the branch admin of that branch read enquiries and history', async () => {
  for (const uid of ['adm-admin', 'adm-platform', 'adm-north']) {
    await assertSucceeds(getDoc(enq(as(uid))));
    await assertSucceeds(getDoc(hist(as(uid))));
  }
});

test('a branch admin cannot read another branch', async () => {
  await assertFails(getDoc(enq(as('adm-south'))));
  await assertFails(getDoc(hist(as('adm-south'))));
  await assertSucceeds(getDoc(enq(as('adm-south'), A, 'south')));
});

test('teacher, finance, parent, another school and signed-out users read nothing', async () => {
  for (const uid of ['adm-teacher', 'adm-finance', 'adm-parent', 'adm-admin-b']) {
    await assertFails(getDoc(enq(as(uid))));
    await assertFails(getDoc(hist(as(uid))));
  }
  await assertFails(getDoc(enq(env.unauthenticatedContext().firestore())));
  await assertFails(getDoc(enq(as('adm-admin'), B, 'north')));
});

test('nobody writes enquiries, history or settings from a client, not even a school admin', async () => {
  for (const uid of ['adm-admin', 'adm-north', 'adm-platform', 'adm-teacher']) {
    const d = as(uid);
    await assertFails(setDoc(enq(d, A, 'north', 'new'), enquiry(A, 'north')));
    await assertFails(updateDoc(enq(d), { status: 'APPROVED' }));
    await assertFails(deleteDoc(enq(d)));
    await assertFails(setDoc(hist(d, A, 'north', 'x__2'), { schoolId: A, branchId: 'north' }));
    await assertFails(updateDoc(hist(d), { to: 'APPROVED' }));
    await assertFails(setDoc(settings(d), { schoolId: A, enabled: true, version: 9 }));
  }
});

test('the sequence collection is server-only', async () => {
  for (const uid of ['adm-admin', 'adm-north', 'adm-platform']) {
    await assertFails(getDoc(seq(as(uid))));
    await assertFails(setDoc(seq(as(uid)), { next: 99 }));
  }
});

test('admission settings are read by the school admin, platform admin and branch admins of the school only', async () => {
  for (const uid of ['adm-admin', 'adm-platform', 'adm-north']) await assertSucceeds(getDoc(settings(as(uid))));
  for (const uid of ['adm-teacher', 'adm-finance', 'adm-parent', 'adm-admin-b']) await assertFails(getDoc(settings(as(uid))));
  await assertFails(getDoc(settings(as('adm-admin'), B)));
});

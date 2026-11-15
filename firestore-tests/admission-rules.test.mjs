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
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp } from 'firebase/firestore';

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
// Platform admins always sign in with a second factor (rules require it).
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password', ...(uid.includes('platform') ? { sign_in_second_factor: 'totp' } : {}) } }).firestore();
const enq = (d, s = A, b = 'north', id = 'e1') => doc(d, 'schools', s, 'branches', b, 'admissionEnquiries', id);
const hist = (d, s = A, b = 'north', id = 'e1__1') => doc(d, 'schools', s, 'branches', b, 'admissionStatusHistory', id);
const act = (d, s = A, b = 'north', id = 'a1') => doc(d, 'schools', s, 'branches', b, 'admissionActivities', id);
const ahist = (d, s = A, b = 'north', id = 'a1__1') => doc(d, 'schools', s, 'branches', b, 'admissionActivityHistory', id);
const app = (d, s = A, b = 'north', id = 'e1') => doc(d, 'schools', s, 'branches', b, 'admissionApplications', id);
const apphist = (d, s = A, b = 'north', id = 'e1__1') => doc(d, 'schools', s, 'branches', b, 'admissionApplicationHistory', id);
const adoc = (d, s = A, b = 'north', id = 'd1') => doc(d, 'schools', s, 'branches', b, 'admissionDocuments', id);
const fee = (d, s = A, b = 'north', id = 'e1__APPLICATION') => doc(d, 'schools', s, 'branches', b, 'admissionFees', id);
const feepay = (d, s = A, b = 'north', id = 'e1__req00001') => doc(d, 'schools', s, 'branches', b, 'admissionFeePayments', id);
const conv = (d, s = A, b = 'north', id = 'e1') => doc(d, 'schools', s, 'branches', b, 'admissionConversions', id);
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
        await setDoc(act(d, s, b), { schoolId: s, branchId: b, enquiryId: 'e1', status: 'SCHEDULED', scheduledDate: '2026-11-10' });
        await setDoc(app(d, s, b), { schoolId: s, branchId: b, enquiryId: 'e1', status: 'DRAFT' });
        await setDoc(apphist(d, s, b), { schoolId: s, branchId: b, enquiryId: 'e1', revision: 1, event: 'CREATED' });
        await setDoc(adoc(d, s, b), { schoolId: s, branchId: b, enquiryId: 'e1', type: 'BIRTH_CERTIFICATE', status: 'UPLOADED' });
        await setDoc(fee(d, s, b), { schoolId: s, branchId: b, enquiryId: 'e1', category: 'APPLICATION', amountMinor: 1000, status: 'DUE' });
        await setDoc(feepay(d, s, b), { schoolId: s, branchId: b, enquiryId: 'e1', kind: 'PAYMENT', amountMinor: 1000 });
        await setDoc(conv(d, s, b), { schoolId: s, branchId: b, enquiryId: 'e1', studentId: 's_e1', status: 'COMPLETED' });
        await setDoc(ahist(d, s, b), { schoolId: s, branchId: b, activityId: 'a1', enquiryId: 'e1', revision: 1, event: 'CREATED' });
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
    // The platform admin reads this school only through an ACTIVE support grant
    // (read-only; without one every platform-admin read below is refused: see
    // platform-admin-rules.test.mjs).
    await setDoc(doc(d, 'supportGrants', `adm-platform__${A}`), {
      adminUid: 'adm-platform', schoolId: A, scope: 'READ', reason: 'test grant for admission rules',
      expiresAt: Timestamp.fromMillis(Date.now() + 3600e3), revokedAt: null, grantedAt: serverTimestamp(),
    });
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

test('follow-up activities and their history follow the same read scope as enquiries', async () => {
  for (const uid of ['adm-admin', 'adm-platform', 'adm-north']) {
    await assertSucceeds(getDoc(act(as(uid))));
    await assertSucceeds(getDoc(ahist(as(uid))));
  }
  for (const uid of ['adm-south', 'adm-teacher', 'adm-finance', 'adm-parent', 'adm-admin-b']) {
    await assertFails(getDoc(act(as(uid))));
    await assertFails(getDoc(ahist(as(uid))));
  }
  await assertFails(getDoc(act(env.unauthenticatedContext().firestore())));
  await assertFails(getDoc(act(as('adm-admin'), B, 'north')));
});

test('nobody writes activities or their history from a client', async () => {
  for (const uid of ['adm-admin', 'adm-north', 'adm-platform', 'adm-teacher']) {
    const d = as(uid);
    await assertFails(setDoc(act(d, A, 'north', 'new'), { schoolId: A, branchId: 'north', status: 'SCHEDULED' }));
    await assertFails(updateDoc(act(d), { status: 'COMPLETED' }));
    await assertFails(deleteDoc(act(d)));
    await assertFails(setDoc(ahist(d, A, 'north', 'a1__2'), { schoolId: A }));
    await assertFails(updateDoc(ahist(d), { event: 'EDITED' }));
    await assertFails(deleteDoc(ahist(d)));
  }
});

test('applications, their history and document records follow the same read scope', async () => {
  for (const read of [app, apphist, adoc]) {
    for (const uid of ['adm-admin', 'adm-platform', 'adm-north']) await assertSucceeds(getDoc(read(as(uid))));
    for (const uid of ['adm-south', 'adm-teacher', 'adm-finance', 'adm-parent', 'adm-admin-b']) await assertFails(getDoc(read(as(uid))));
    await assertFails(getDoc(read(env.unauthenticatedContext().firestore())));
    await assertFails(getDoc(read(as('adm-admin'), B, 'north')));
  }
});

test('nobody writes applications, history or document records from a client', async () => {
  for (const uid of ['adm-admin', 'adm-north', 'adm-platform', 'adm-teacher']) {
    const d = as(uid);
    await assertFails(setDoc(app(d, A, 'north', 'new'), { schoolId: A, branchId: 'north', status: 'APPROVED' }));
    await assertFails(updateDoc(app(d), { status: 'APPROVED' }));
    await assertFails(deleteDoc(app(d)));
    await assertFails(setDoc(apphist(d, A, 'north', 'e1__2'), { schoolId: A }));
    await assertFails(updateDoc(apphist(d), { event: 'EDITED' }));
    await assertFails(setDoc(adoc(d, A, 'north', 'new'), { schoolId: A, status: 'VERIFIED' }));
    await assertFails(updateDoc(adoc(d), { status: 'VERIFIED' }));
    await assertFails(deleteDoc(adoc(d)));
  }
});

test('admission fees and fee payments: administrators and the branch\'s Finance read; nobody else; nobody writes from a client', async () => {
  for (const read of [fee, feepay]) {
    for (const uid of ['adm-admin', 'adm-platform', 'adm-north', 'adm-finance']) await assertSucceeds(getDoc(read(as(uid))));
    for (const uid of ['adm-south', 'adm-teacher', 'adm-parent', 'adm-admin-b']) await assertFails(getDoc(read(as(uid))));
    await assertFails(getDoc(read(env.unauthenticatedContext().firestore())));
    await assertFails(getDoc(read(as('adm-finance'), A, 'south')));
  }
  for (const uid of ['adm-admin', 'adm-north', 'adm-platform', 'adm-finance']) {
    const d = as(uid);
    await assertFails(setDoc(fee(d, A, 'north', 'e1__ADMISSION'), { schoolId: A, branchId: 'north', status: 'PAID' }));
    await assertFails(updateDoc(fee(d), { status: 'PAID', paidMinor: 1000 }));
    await assertFails(deleteDoc(fee(d)));
    await assertFails(setDoc(feepay(d, A, 'north', 'e1__new'), { schoolId: A, kind: 'PAYMENT' }));
    await assertFails(updateDoc(feepay(d), { amountMinor: 1 }));
    await assertFails(deleteDoc(feepay(d)));
  }
});

test('Finance still cannot read enquiries, applications, documents, activities, settings or conversions', async () => {
  const d = as('adm-finance');
  for (const ref of [enq(d), hist(d), act(d), ahist(d), app(d), apphist(d), adoc(d), conv(d), settings(d)]) await assertFails(getDoc(ref));
});

test('conversion records follow the same read scope and are never written from a client', async () => {
  for (const uid of ['adm-admin', 'adm-platform', 'adm-north']) await assertSucceeds(getDoc(conv(as(uid))));
  for (const uid of ['adm-south', 'adm-teacher', 'adm-finance', 'adm-parent', 'adm-admin-b']) await assertFails(getDoc(conv(as(uid))));
  for (const uid of ['adm-admin', 'adm-north', 'adm-platform']) {
    await assertFails(setDoc(conv(as(uid), A, 'north', 'x'), { schoolId: A, status: 'COMPLETED' }));
    await assertFails(updateDoc(conv(as(uid)), { studentId: 'other' }));
    await assertFails(deleteDoc(conv(as(uid))));
  }
});

test('the public page bookkeeping (portal addresses, rate-limit counters) is server-only', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'admissionPortalSlugs', 'adm-slug'), { schoolId: A, branchId: 'north', enabled: true });
    await setDoc(doc(c.firestore(), 'schools', A, 'publicLimits', 'ip_x'), { count: 1 });
  });
  const unauth = env.unauthenticatedContext().firestore();
  for (const d of [unauth, as('adm-admin'), as('adm-platform'), as('adm-north')]) {
    await assertFails(getDoc(doc(d, 'admissionPortalSlugs', 'adm-slug')));
    await assertFails(setDoc(doc(d, 'admissionPortalSlugs', 'mine'), { schoolId: A, branchId: 'north', enabled: true }));
    await assertFails(getDoc(doc(d, 'schools', A, 'publicLimits', 'ip_x')));
    await assertFails(setDoc(doc(d, 'schools', A, 'publicLimits', 'ip_y'), { count: 0 }));
  }
});

test('a signed-out visitor cannot read or write any enquiry (the public form goes through the server only)', async () => {
  const unauth = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(enq(unauth)));
  await assertFails(setDoc(enq(unauth, A, 'north', 'pub_x'), enquiry(A, 'north')));
});

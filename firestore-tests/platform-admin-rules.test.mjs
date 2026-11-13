// Platform administrators (Avail404): the second factor is required by every
// rule, nobody can create or promote a platform admin from a client, and the
// audit log is readable by owners/compliance only and never writable.
// Prefix: pfa-.
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

const A = 'pfa-a';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const NO_MFA = { firebase: { sign_in_provider: 'password' } };
const as = (uid, token = NO_MFA) => env.authenticatedContext(uid, token).firestore();
const mfa = (uid) => as(uid, MFA);
const PLATFORM = ['pfa-owner', 'pfa-support', 'pfa-compliance', 'pfa-viewer', 'pfa-legacy'];

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    await setDoc(doc(d, 'schools', A), { name: A, email: 'a@example.com', status: 'ACTIVE', ...base });
    const login = { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'] };
    const users = {
      'pfa-owner': { role: 'PLATFORM_ADMIN', platformRole: 'OWNER', schoolId: null, branchId: null, login },
      'pfa-support': { role: 'PLATFORM_ADMIN', platformRole: 'SUPPORT', schoolId: null, branchId: null, login },
      'pfa-compliance': { role: 'PLATFORM_ADMIN', platformRole: 'COMPLIANCE', schoolId: null, branchId: null, login },
      'pfa-viewer': { role: 'PLATFORM_ADMIN', platformRole: 'VIEWER', schoolId: null, branchId: null, login },
      'pfa-legacy': { role: 'PLATFORM_ADMIN', schoolId: null, branchId: null, login },
      'pfa-admin': { role: 'SCHOOL_ADMIN', schoolId: A, branchId: null },
      'pfa-teacher': { role: 'TEACHER', schoolId: A, branchId: 'north' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', ...u, ...base });
    }
    await setDoc(doc(d, 'platformAuditLog', 'e1'), { action: 'PLATFORM_ADMIN_CREATED', actorUid: 'pfa-owner', createdAt: serverTimestamp() });
  });
});

test('without a second factor a platform admin can read only their own profile', async () => {
  for (const uid of PLATFORM) {
    const d = as(uid);
    await assertSucceeds(getDoc(doc(d, 'users', uid)));
    await assertFails(getDoc(doc(d, 'users', 'pfa-teacher')));
    await assertFails(getDoc(doc(d, 'schools', A)));
    await assertFails(getDoc(doc(d, 'platformAuditLog', 'e1')));
  }
});

test('with a second factor a platform admin reads users and schools', async () => {
  for (const uid of PLATFORM) {
    const d = mfa(uid);
    await assertSucceeds(getDoc(doc(d, 'users', 'pfa-teacher')));
    await assertSucceeds(getDoc(doc(d, 'schools', A)));
  }
});

test('the audit log is read by owners and compliance (and legacy owners) with a second factor only', async () => {
  for (const uid of ['pfa-owner', 'pfa-compliance', 'pfa-legacy']) {
    await assertSucceeds(getDoc(doc(mfa(uid), 'platformAuditLog', 'e1')));
    await assertFails(getDoc(doc(as(uid), 'platformAuditLog', 'e1')));
  }
  for (const uid of ['pfa-support', 'pfa-viewer', 'pfa-admin', 'pfa-teacher']) {
    await assertFails(getDoc(doc(mfa(uid), 'platformAuditLog', 'e1')));
  }
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'platformAuditLog', 'e1')));
});

test('nobody writes the audit log from a client, not even an owner with a second factor', async () => {
  for (const uid of [...PLATFORM, 'pfa-admin', 'pfa-teacher']) {
    const d = mfa(uid);
    await assertFails(setDoc(doc(d, 'platformAuditLog', 'x'), { action: 'FORGED', createdAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(d, 'platformAuditLog', 'e1'), { action: 'EDITED' }));
    await assertFails(deleteDoc(doc(d, 'platformAuditLog', 'e1')));
  }
});

test('no client can create a platform admin profile', async () => {
  const profile = (over) => ({ name: 'P', email: 'p@x.com', status: 'ACTIVE', role: 'PLATFORM_ADMIN', schoolId: null, branchId: null, ...base, ...over });
  // Self-signup as a platform admin, with or without a school.
  await assertFails(setDoc(doc(env.authenticatedContext('pfa-new', NO_MFA).firestore(), 'users', 'pfa-new'), profile()));
  await assertFails(setDoc(doc(env.authenticatedContext('pfa-new', NO_MFA).firestore(), 'users', 'pfa-new'), profile({ schoolId: A })));
  // A school admin provisioning one.
  await assertFails(setDoc(doc(as('pfa-admin'), 'users', 'pfa-x'), profile({ schoolId: A })));
  // A platform admin with a second factor, including an owner.
  for (const uid of PLATFORM) {
    await assertFails(setDoc(doc(mfa(uid), 'users', 'pfa-y'), profile()));
    await assertFails(setDoc(doc(mfa(uid), 'users', 'pfa-y'), profile({ schoolId: A })));
    await assertFails(setDoc(doc(mfa(uid), 'users', 'pfa-y'), profile({ platformRole: 'OWNER' })));
  }
});

test('no client can promote anyone to platform admin or change a platformRole', async () => {
  // Everyone, including every platform admin with a second factor and an owner.
  for (const uid of [...PLATFORM, 'pfa-admin', 'pfa-teacher']) {
    const d = mfa(uid);
    for (const target of ['pfa-teacher', 'pfa-admin', 'pfa-support', 'pfa-viewer', uid]) {
      const meta = { updatedAt: serverTimestamp(), updatedBy: uid };
      // (Setting a value someone already has is a no-op, not a change.)
      const isSelfAdmin = target === uid && PLATFORM.includes(uid);
      if (!isSelfAdmin) await assertFails(updateDoc(doc(d, 'users', target), { role: 'PLATFORM_ADMIN', ...meta }));
      await assertFails(updateDoc(doc(d, 'users', target), { platformRole: target === uid ? 'ROOT' : 'OWNER', ...meta }));
      await assertFails(updateDoc(doc(d, 'users', target), { login: { enabled: true, methods: ['PASSWORD', 'GOOGLE'], effective: ['PASSWORD', 'GOOGLE'] }, ...meta }));
    }
  }
});

test('a platform admin cannot disable or demote another platform admin from a client', async () => {
  for (const uid of PLATFORM) {
    await assertFails(updateDoc(doc(mfa(uid), 'users', 'pfa-owner'), { status: 'DISABLED', updatedAt: serverTimestamp(), updatedBy: uid }));
  }
});

test('self edits stay profile-only for a platform admin too', async () => {
  const d = mfa('pfa-support');
  await assertSucceeds(updateDoc(doc(d, 'users', 'pfa-support'), { name: 'New Name', updatedAt: serverTimestamp(), updatedBy: 'pfa-support' }));
  await assertFails(updateDoc(doc(d, 'users', 'pfa-support'), { platformRole: 'OWNER', updatedAt: serverTimestamp(), updatedBy: 'pfa-support' }));
  await assertFails(updateDoc(doc(d, 'users', 'pfa-support'), { status: 'ACTIVE', role: 'SCHOOL_ADMIN', updatedAt: serverTimestamp(), updatedBy: 'pfa-support' }));
});

test('ordinary roles are unaffected by the second-factor rule', async () => {
  const admin = as('pfa-admin');
  const teacher = as('pfa-teacher');
  await assertSucceeds(getDoc(doc(admin, 'schools', A)));
  await assertSucceeds(getDoc(doc(teacher, 'users', 'pfa-teacher')));
});

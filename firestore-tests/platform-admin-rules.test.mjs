// Platform administrators (Avail404): the second factor is required by every
// rule, nobody can create or promote a platform admin from a client, and the
// audit log is readable by owners/compliance only and never writable.
// Prefix: pfa-.
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

const A = 'pfa-a';
const B = 'pfa-b';
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
    for (const sch of [A, B]) {
      await setDoc(doc(d, 'schools', sch), { name: sch, email: `${sch}@example.com`, status: 'ACTIVE', ...base });
      await setDoc(doc(d, 'schools', sch, 'branches', 'north', 'students', 's1'), { schoolId: sch, branchId: 'north', firstName: 'Kid', lastName: sch, status: 'ACTIVE', ...base });
    }
    const login = { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'] };
    const users = {
      'pfa-owner': { role: 'PLATFORM_ADMIN', platformRole: 'OWNER', schoolId: null, branchId: null, login },
      'pfa-support': { role: 'PLATFORM_ADMIN', platformRole: 'SUPPORT', schoolId: null, branchId: null, login },
      'pfa-compliance': { role: 'PLATFORM_ADMIN', platformRole: 'COMPLIANCE', schoolId: null, branchId: null, login },
      'pfa-viewer': { role: 'PLATFORM_ADMIN', platformRole: 'VIEWER', schoolId: null, branchId: null, login },
      'pfa-legacy': { role: 'PLATFORM_ADMIN', schoolId: null, branchId: null, login },
      'pfa-admin': { role: 'SCHOOL_ADMIN', schoolId: A, branchId: null },
      'pfa-teacher': { role: 'TEACHER', schoolId: A, branchId: 'north' },
      'pfa-admin-b': { role: 'SCHOOL_ADMIN', schoolId: B, branchId: null },
      'pfa-school-owner': { role: 'PLATFORM_ADMIN', platformRole: 'OWNER', schoolId: A, branchId: null, login },
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

test('with a second factor a platform admin reads their own profile and school metadata, not school users', async () => {
  for (const uid of PLATFORM) {
    const d = mfa(uid);
    await assertSucceeds(getDoc(doc(d, 'users', uid)));
    await assertSucceeds(getDoc(doc(d, 'schools', A)));
    await assertFails(getDoc(doc(d, 'users', 'pfa-teacher')), 'school users need a support grant');
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

// ---- support grants (audit finding H1) ----------------------------------------

const student = (d, sch = A) => doc(d, 'schools', sch, 'branches', 'north', 'students', 's1');
const grant = (uid, sch, over = {}) =>
  env.withSecurityRulesDisabled(async (c) =>
    setDoc(doc(c.firestore(), 'supportGrants', `${uid}__${sch}`), {
      adminUid: uid, adminName: uid, adminEmail: `${uid}@avail404.com`, schoolId: sch, scope: 'READ',
      reason: 'investigating a fee question for this school', ticket: null,
      grantedAt: serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 3600e3), revokedAt: null, revokedBy: null,
      ...over,
    }),
  );

test('without a grant a platform admin reads no school data and no school user profiles', async () => {
  for (const uid of PLATFORM) {
    const d = mfa(uid);
    await assertFails(getDoc(student(d)));
    await assertFails(getDoc(doc(d, 'users', 'pfa-teacher')));
    await assertFails(getDoc(doc(d, 'users', 'pfa-admin')));
  }
});

test('school metadata (name, status) stays readable without a grant: it is the directory', async () => {
  await assertSucceeds(getDoc(doc(mfa('pfa-support'), 'schools', A)));
  await assertSucceeds(getDoc(doc(mfa('pfa-support'), 'schools', B)));
});

test('an active grant opens exactly one school, read-only', async () => {
  await grant('pfa-support', A);
  const d = mfa('pfa-support');
  await assertSucceeds(getDoc(student(d, A)));
  await assertSucceeds(getDoc(doc(d, 'users', 'pfa-teacher')));
  await assertSucceeds(getDocs(query(collection(d, 'users'), where('schoolId', '==', A))));
  await assertFails(getDoc(student(d, B)), 'another school stays closed');
  await assertFails(getDoc(doc(d, 'users', 'pfa-admin-b')));
});

test('school security records (auth settings, audit trail) need a grant too, and are read-only', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'schools', A, 'authSettings', 'methods'), { schoolId: A, methods: ['PASSWORD'] });
    await setDoc(doc(c.firestore(), 'schools', A, 'authAudit', 'e1'), { schoolId: A, event: 'LOGIN_ENABLED' });
  });
  const d = mfa('pfa-support');
  await assertFails(getDoc(doc(d, 'schools', A, 'authSettings', 'methods')));
  await assertFails(getDoc(doc(d, 'schools', A, 'authAudit', 'e1')));
  await grant('pfa-support', A);
  await assertSucceeds(getDoc(doc(d, 'schools', A, 'authSettings', 'methods')));
  await assertSucceeds(getDoc(doc(d, 'schools', A, 'authAudit', 'e1')));
  await assertFails(setDoc(doc(d, 'schools', A, 'authAudit', 'forged'), { schoolId: A, event: 'FORGED' }));
});

test('a grant never allows a write, whatever the school data', async () => {
  await grant('pfa-support', A);
  await grant('pfa-owner', A);
  for (const uid of ['pfa-support', 'pfa-owner']) {
    const d = mfa(uid);
    await assertFails(updateDoc(student(d, A), { firstName: 'Changed', updatedAt: serverTimestamp(), updatedBy: uid }));
    await assertFails(setDoc(doc(d, 'schools', A, 'branches', 'north', 'students', 's9'), { schoolId: A, branchId: 'north', firstName: 'New', ...base }));
    await assertFails(deleteDoc(student(d, A)));
    await assertFails(updateDoc(doc(d, 'users', 'pfa-teacher'), { name: 'X', updatedAt: serverTimestamp(), updatedBy: uid }));
    await assertFails(updateDoc(doc(d, 'schools', A), { status: 'SUSPENDED', updatedAt: serverTimestamp(), updatedBy: uid }));
  }
});

test('an expired, revoked or someone else\'s grant opens nothing', async () => {
  await grant('pfa-support', A, { expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  await assertFails(getDoc(student(mfa('pfa-support'), A)));
  await grant('pfa-support', A, { revokedAt: Timestamp.now(), revokedBy: 'pfa-admin' });
  await assertFails(getDoc(student(mfa('pfa-support'), A)));
  await grant('pfa-owner', A);
  await assertFails(getDoc(student(mfa('pfa-support'), A)), 'a colleague\'s grant is not yours');
  await assertSucceeds(getDoc(student(mfa('pfa-owner'), A)));
});

test('a grant without a second factor opens nothing', async () => {
  await grant('pfa-support', A);
  await assertFails(getDoc(student(as('pfa-support'), A)));
});

test('a disabled platform admin with a grant opens nothing', async () => {
  await grant('pfa-support', A);
  await env.withSecurityRulesDisabled(async (c) => updateDoc(doc(c.firestore(), 'users', 'pfa-support'), { status: 'DISABLED' }));
  await assertFails(getDoc(student(mfa('pfa-support'), A)));
});

test('grants are readable by their holder and by the school admin of that school only', async () => {
  await grant('pfa-support', A);
  await assertSucceeds(getDoc(doc(mfa('pfa-support'), 'supportGrants', `pfa-support__${A}`)));
  await assertSucceeds(getDocs(query(collection(mfa('pfa-support'), 'supportGrants'), where('adminUid', '==', 'pfa-support'))));
  await assertSucceeds(getDoc(doc(as('pfa-admin'), 'supportGrants', `pfa-support__${A}`)));
  await assertSucceeds(getDocs(query(collection(as('pfa-admin'), 'supportGrants'), where('schoolId', '==', A))));
  for (const [who, d] of [['another platform admin', mfa('pfa-owner')], ['another school admin', as('pfa-admin-b')], ['a teacher', as('pfa-teacher')]]) {
    await assertFails(getDoc(doc(d, 'supportGrants', `pfa-support__${A}`)), who);
  }
  await assertFails(getDoc(doc(as('pfa-support'), 'supportGrants', `pfa-support__${A}`)), 'holder without a second factor');
});

test('nobody writes a grant or the school-visible log from a client, not even the holder or an owner', async () => {
  await grant('pfa-support', A);
  for (const [uid, d] of [['pfa-support', mfa('pfa-support')], ['pfa-owner', mfa('pfa-owner')], ['pfa-admin', as('pfa-admin')]]) {
    await assertFails(setDoc(doc(d, 'supportGrants', `${uid}__${A}`), { adminUid: uid, schoolId: A, expiresAt: Timestamp.fromMillis(Date.now() + 1e9), revokedAt: null }));
    await assertFails(updateDoc(doc(d, 'supportGrants', `pfa-support__${A}`), { expiresAt: Timestamp.fromMillis(Date.now() + 1e9) }));
    await assertFails(updateDoc(doc(d, 'supportGrants', `pfa-support__${A}`), { revokedAt: Timestamp.now() }));
    await assertFails(deleteDoc(doc(d, 'supportGrants', `pfa-support__${A}`)));
    await assertFails(setDoc(doc(d, 'schools', A, 'supportAccessLog', 'x'), { event: 'GRANTED', createdAt: serverTimestamp() }));
  }
});

test('the support access log is read by the school admin of that school only', async () => {
  await env.withSecurityRulesDisabled(async (c) => setDoc(doc(c.firestore(), 'schools', A, 'supportAccessLog', 'e1'), { event: 'GRANTED', schoolId: A, createdAt: serverTimestamp() }));
  await assertSucceeds(getDoc(doc(as('pfa-admin'), 'schools', A, 'supportAccessLog', 'e1')));
  await assertFails(getDoc(doc(as('pfa-admin-b'), 'schools', A, 'supportAccessLog', 'e1')));
  await assertFails(getDoc(doc(as('pfa-teacher'), 'schools', A, 'supportAccessLog', 'e1')));
  await grant('pfa-support', A);
  await assertFails(getDoc(doc(mfa('pfa-support'), 'schools', A, 'supportAccessLog', 'e1')), 'a platform admin reads it through the callable/audit log, not here');
});

test('a platform admin with a school on their profile still needs the second factor in Storage, and never writes there', async () => {
  const path = `schools/${A}/logo.png`;
  const png = new Uint8Array([137, 80, 78, 71]);
  await env.withSecurityRulesDisabled(async (c) => uploadBytes(ref(c.storage(), path), png, { contentType: 'image/png' }));
  await assertSucceeds(getBytes(ref(env.authenticatedContext('pfa-school-owner', MFA).storage(), path)));
  await assertFails(getBytes(ref(env.authenticatedContext('pfa-school-owner', NO_MFA).storage(), path)));
  await assertFails(uploadBytes(ref(env.authenticatedContext('pfa-school-owner', MFA).storage(), path), png, { contentType: 'image/png' }));
});

// Phase 12: the governance collections have NO client rules (default deny) for every kind of caller, and the
// server-owned fields on a school document cannot be written by a school admin. Prefix: gv-.
import { readFileSync } from 'node:fs';
import assert from 'node:assert';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, serverTimestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const S = 'gv-s1';
const OTHER = 'gv-s2';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: uid });
const password = { firebase: { sign_in_provider: 'password' } };
const mfa = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const as = (uid, token = password) => env.authenticatedContext(uid, token).firestore();

const USERS = {
  'gv-admin': { schoolId: S, branchId: null, role: 'SCHOOL_ADMIN' },
  'gv-ba': { schoolId: S, branchId: 'b1', role: 'BRANCH_ADMIN' },
  'gv-teacher': { schoolId: S, branchId: 'b1', role: 'TEACHER' },
  'gv-finance': { schoolId: S, branchId: 'b1', role: 'FINANCE' },
  'gv-parent': { schoolId: S, branchId: null, role: 'PARENT' },
  'gv-other-admin': { schoolId: OTHER, branchId: null, role: 'SCHOOL_ADMIN' },
  'gv-owner': { schoolId: null, branchId: null, role: 'PLATFORM_ADMIN', platformRole: 'OWNER' },
  'gv-compliance': { schoolId: null, branchId: null, role: 'PLATFORM_ADMIN', platformRole: 'COMPLIANCE' },
  'gv-nopro': null,
};
const CALLERS = [
  ...Object.keys(USERS).filter((u) => u !== 'gv-nopro').map((u) => [u, USERS[u].role === 'PLATFORM_ADMIN' ? mfa : password]),
  ['gv-owner-nomfa', password],
  ['gv-unknown-uid', password],
];

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    await setDoc(doc(d, 'schools', S), { name: 'S1', email: 's@example.com', status: 'ACTIVE', ...base });
    await setDoc(doc(d, 'schools', OTHER), { name: 'S2', email: 'o@example.com', status: 'ACTIVE', ...base });
    for (const [uid, u] of Object.entries(USERS)) {
      if (u) await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    await setDoc(doc(d, 'users', 'gv-owner-nomfa'), { name: 'T', email: 'n@example.com', status: 'ACTIVE', linkedParentId: null, schoolId: null, branchId: null, role: 'PLATFORM_ADMIN', platformRole: 'OWNER', ...base });
    // one document in every governance collection, so a read cannot "fail" merely because nothing exists
    const seeded = [
      ['platformNotifications', 'n1'], ['schoolSubscriptions', S], ['schoolSubscriptionHistory', 'h1'], ['platformPlans', 'p1'],
      ['platformFeatureDefaults', 'default'], ['schoolFeatureHistory', 'f1'], ['schoolLifecycleHistory', 'l1'], ['schoolRecovery', S],
      ['auditArchives', '202606'], ['auditClientRate', 'gv-teacher'], ['platformAuditLog', 'a1'],
    ];
    for (const [c1, id] of seeded) await setDoc(doc(d, c1, id), { recipientUserId: 'gv-admin', schoolId: S, note: 'seed' });
    await setDoc(doc(d, 'auditEvents', '202606', 'events', 'e1'), { schoolId: S, actorUserId: 'gv-admin', category: 'STUDENT', timestampMs: 1 });
  });
});

const PATHS = [
  ['platformNotifications', 'n1'], ['schoolSubscriptions', S], ['schoolSubscriptionHistory', 'h1'], ['platformPlans', 'p1'],
  ['platformFeatureDefaults', 'default'], ['schoolFeatureHistory', 'f1'], ['schoolLifecycleHistory', 'l1'], ['schoolRecovery', S],
  ['auditEvents', '202606', 'events', 'e1'], ['auditArchives', '202606'], ['auditClientRate', 'gv-teacher'], ['platformAuditLog', 'a1'],
];
const ref = (db, p) => doc(db, ...p);
const listOf = (db, p) => collection(db, ...p.slice(0, -1));

test('every governance collection denies reads, lists and writes to EVERY caller, platform owner and compliance included', async () => {
  for (const [uid, token] of CALLERS) {
    const db = as(uid, token);
    for (const p of PATHS) {
      const label = `${uid} ${p.join('/')}`;
      await assertFails(getDoc(ref(db, p)), `get ${label}`);
      await assertFails(getDocs(listOf(db, p)), `list ${label}`);
      await assertFails(setDoc(ref(db, p), { schoolId: S, note: 'x', ...stamp(uid) }), `set ${label}`);
      await assertFails(updateDoc(ref(db, p), { note: 'y' }), `update ${label}`);
      await assertFails(deleteDoc(ref(db, p)), `delete ${label}`);
    }
  }
});

test('signed-out callers cannot read or write them either', async () => {
  const db = env.unauthenticatedContext().firestore();
  for (const p of PATHS) {
    await assertFails(getDoc(ref(db, p)), p.join('/'));
    await assertFails(setDoc(ref(db, p), { note: 'x' }), p.join('/'));
  }
});

test('a client cannot create new documents in a governance collection either (no creating your own notification, plan or audit event)', async () => {
  const db = as('gv-admin');
  for (const p of [['platformNotifications', 'mine'], ['platformPlans', 'mine'], ['auditEvents', '202606', 'events', 'mine'], ['schoolSubscriptions', 'gv-new'], ['platformFeatureDefaults', 'other']]) {
    await assertFails(setDoc(ref(db, p), { schoolId: S, recipientUserId: 'gv-admin', ...base }), p.join('/'));
  }
});

// ---- server-owned fields on the school document ---------------------------------------------------------------

const school = (db, id = S) => doc(db, 'schools', id);

test('control: a school admin can still edit the school profile', async () => {
  await assertSucceeds(updateDoc(school(as('gv-admin')), { name: 'Renamed', ...stamp('gv-admin') }));
});

test('a school admin cannot write any server-owned field (lifecycle, subscription, features, mirror)', async () => {
  const db = as('gv-admin');
  const forbidden = {
    status: 'CLOSED', statusReason: 'x', lifecycleVersion: 9, activatedAt: serverTimestamp(), activatedBy: 'gv-admin', activationRemarks: 'x',
    suspendedAt: serverTimestamp(), closedAt: serverTimestamp(), features: { fees: true }, featuresVersion: 5,
    subscriptionStatus: 'ACTIVE', subscriptionEndDate: '2099-01-01', accessMirror: 'ACTIVE', currencyLocked: false, schoolAccess: 'x',
  };
  const succeeded = [];
  for (const [k, v] of Object.entries(forbidden)) {
    try {
      await assertFails(updateDoc(school(db), { [k]: v, ...stamp('gv-admin') }));
    } catch {
      succeeded.push(k);
    }
  }
  assert.deepEqual(succeeded, [], `a school admin could write: ${succeeded.join(', ')}`);
});

test('nobody but the school\'s own admin can edit its profile: branch admin, teacher, finance, parent, other school, platform admin', async () => {
  for (const [uid, token] of CALLERS) {
    if (uid === 'gv-admin') continue;
    await assertFails(updateDoc(school(as(uid, token)), { name: 'Hijack', ...stamp(uid) }), uid);
  }
});

test('self-registration: only an INACTIVE school can be created, and a client can never claim ACTIVE, SUSPENDED, EXPIRED or CLOSED', async () => {
  const { writeBatch } = await import('firebase/firestore');
  const regional = { countryCode: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', dateFormat: 'dd/MM/yyyy' };
  const attempt = async (uid, status, extra = {}) => {
    const db = as(uid);
    const id = `${uid}-school`;
    const b = writeBatch(db);
    b.set(doc(db, 'schools', id), { name: 'N', email: 'n@example.com', status, ...regional, ...extra, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
    b.set(doc(db, 'users', uid), { name: 'N', email: 'n@example.com', schoolId: id, branchId: null, role: 'SCHOOL_ADMIN', status: 'ACTIVE', linkedParentId: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
    return b.commit();
  };
  for (const [i, status] of ['ACTIVE', 'SUSPENDED', 'EXPIRED', 'CLOSED', 'active', '', null].entries()) {
    await assertFails(attempt(`gv-reg${i}`, status), String(status));
  }
  await assertSucceeds(attempt('gv-reg-ok', 'INACTIVE'));
});

// ---- the mirror that pauses a school ---------------------------------------------------------------------------

test('every mirrored state pauses the user: reads of their own school data are refused, not just some states', async () => {
  for (const state of ['INACTIVE', 'SUSPENDED', 'EXPIRED', 'CLOSED', 'SUBSCRIPTION_NOT_STARTED']) {
    await env.withSecurityRulesDisabled(async (c) => updateDoc(doc(c.firestore(), 'users', 'gv-admin'), { schoolAccess: state }));
    const db = as('gv-admin');
    await assertFails(getDoc(school(db)), `school read while ${state}`);
    await assertFails(updateDoc(school(db), { name: 'x', ...stamp('gv-admin') }), `school write while ${state}`);
    await env.withSecurityRulesDisabled(async (c) => updateDoc(doc(c.firestore(), 'users', 'gv-admin'), { schoolAccess: null }));
  }
});

test('a user cannot lift their own pause by editing their profile (and the one thing a paused user may still edit)', async () => {
  await env.withSecurityRulesDisabled(async (c) => updateDoc(doc(c.firestore(), 'users', 'gv-teacher'), { schoolAccess: 'SUSPENDED' }));
  const db = as('gv-teacher');
  await assertFails(updateDoc(doc(db, 'users', 'gv-teacher'), { schoolAccess: null, ...stamp('gv-teacher') }));
  // KNOWN LIMITATION (documented in SECURITY_TEST_REPORT.md): the self-edit rule does not look at the pause, so a
  // paused user may still change their OWN name/phone/photo. It touches no school data and cannot lift the pause.
  await assertSucceeds(updateDoc(doc(db, 'users', 'gv-teacher'), { name: 'Still editable', ...stamp('gv-teacher') }));
  await assertFails(updateDoc(doc(db, 'users', 'gv-teacher'), { schoolAccess: null, role: 'SCHOOL_ADMIN', ...stamp('gv-teacher') }));
});

test('a user cannot pause or un-pause anyone else, nor write the mirror on their own profile when active', async () => {
  const db = as('gv-admin');
  await assertFails(updateDoc(doc(db, 'users', 'gv-teacher'), { schoolAccess: 'SUSPENDED', ...stamp('gv-admin') }));
  await assertFails(updateDoc(doc(db, 'users', 'gv-admin'), { schoolAccess: 'SUSPENDED', ...stamp('gv-admin') }));
});

test('a user profile cannot be promoted to a platform role by a client', async () => {
  const db = as('gv-admin');
  await assertFails(updateDoc(doc(db, 'users', 'gv-admin'), { platformRole: 'OWNER', ...stamp('gv-admin') }));
  await assertFails(updateDoc(doc(db, 'users', 'gv-teacher'), { platformRole: 'OWNER', role: 'PLATFORM_ADMIN', ...stamp('gv-admin') }));
  const reg = as('gv-newbie');
  await assertFails(setDoc(doc(reg, 'users', 'gv-newbie'), { name: 'N', email: 'n@x.com', schoolId: null, branchId: null, role: 'PLATFORM_ADMIN', status: 'ACTIVE', linkedParentId: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'gv-newbie', updatedBy: 'gv-newbie' }));
});

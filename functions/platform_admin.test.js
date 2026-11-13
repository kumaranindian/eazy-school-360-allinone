'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb, fakeAuth } = require('./test_support');
const pa = require('./platform_admin');
const access = require('./access');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const NO_MFA = { firebase: { sign_in_provider: 'password' } };
const NOW = 'now';

const admin = (over = {}) => ({
  role: 'PLATFORM_ADMIN',
  status: 'ACTIVE',
  name: 'Owner',
  email: 'owner@avail404.com',
  schoolId: null,
  branchId: null,
  login: { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'] },
  ...over,
});

function world(seed = {}, authUsers = {}) {
  const db = fakeDb({
    'users/owner': admin({ platformRole: 'OWNER' }),
    'users/support': admin({ platformRole: 'SUPPORT', email: 'support@avail404.com', name: 'Support' }),
    'users/legacy': admin({ email: 'legacy@avail404.com', name: 'Legacy' }),
    'users/teacher': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1', branchId: 'b1', email: 't@school.test', name: 'T' },
    ...seed,
  });
  const auth = fakeAuth(authUsers);
  return { db, auth, ctx: { db, auth, now: NOW } };
}
const audits = (db) => [...db.store.entries()].filter(([k]) => k.startsWith('platformAuditLog/')).map(([, v]) => v);

test('platformRoleOf: a missing role is the legacy OWNER, an unknown role grants nothing', () => {
  assert.equal(pa.platformRoleOf({ role: 'PLATFORM_ADMIN' }), 'OWNER');
  assert.equal(pa.platformRoleOf({ role: 'PLATFORM_ADMIN', platformRole: 'SUPPORT' }), 'SUPPORT');
  assert.equal(pa.platformRoleOf({ role: 'PLATFORM_ADMIN', platformRole: 'GOD' }), null);
  assert.equal(pa.platformRoleOf({ role: 'SCHOOL_ADMIN', platformRole: 'OWNER' }), null);
  assert.equal(pa.platformRoleOf(undefined), null);
});

test('access.loginAllowed demands a second factor for platform admins only', () => {
  const p = admin();
  assert.equal(access.loginAllowed(p, NO_MFA), false);
  assert.equal(access.loginAllowed(p, MFA), true);
  assert.equal(access.methodAllowed(p, NO_MFA), true);
  const teacher = { role: 'TEACHER', status: 'ACTIVE' };
  assert.equal(access.loginAllowed(teacher, NO_MFA), true);
});

test('create: only an owner with a second factor; support and signed-in-without-MFA are refused', async () => {
  const w = world();
  const data = { name: 'New Person', email: 'New.Person@Avail404.com', platformRole: 'SUPPORT' };
  assert.equal((await pa.createPlatformAdmin(w.ctx, 'owner', NO_MFA, data)).error, 'MFA_REQUIRED');
  assert.equal((await pa.createPlatformAdmin(w.ctx, 'support', MFA, data)).error, 'PERMISSION_DENIED');
  assert.equal((await pa.createPlatformAdmin(w.ctx, 'teacher', MFA, data)).error, 'PERMISSION_DENIED');
  assert.equal((await pa.createPlatformAdmin(w.ctx, 'nobody', MFA, data)).error, 'PERMISSION_DENIED');
  assert.equal(Object.keys(w.auth.users).length, 0, 'nothing created by refused calls');
  assert.equal(audits(w.db).length, 0);

  const out = await pa.createPlatformAdmin(w.ctx, 'owner', MFA, data);
  assert.equal(out.error, undefined);
  assert.equal(out.email, 'new.person@avail404.com');
  const u = w.db.store.get(`users/${out.uid}`);
  assert.equal(u.role, 'PLATFORM_ADMIN');
  assert.equal(u.platformRole, 'SUPPORT');
  assert.equal(u.schoolId, null);
  assert.deepEqual(u.login.effective, ['PASSWORD']);
  assert.equal(w.auth.users[out.uid].emailVerified, true, 'verified so a second factor can be enrolled');
  assert.ok(w.auth.users[out.uid].password.length >= 32, 'unknown random password');
  assert.equal(JSON.stringify(out).includes(w.auth.users[out.uid].password), false, 'password never returned');
  const a = audits(w.db);
  assert.equal(a.length, 1);
  assert.equal(a[0].action, 'PLATFORM_ADMIN_CREATED');
  assert.equal(a[0].actorUid, 'owner');
  assert.equal(JSON.stringify(a[0]).includes(w.auth.users[out.uid].password), false);
});

test('create: validation (name, email, domain, role) and reuse of an existing email', async () => {
  const w = world({}, { 'taken@avail404.com': 'existing-uid' });
  const ok = { name: 'New Person', email: 'new@avail404.com', platformRole: 'VIEWER' };
  for (const bad of [
    { ...ok, name: 'x' },
    { ...ok, email: 'not-an-email' },
    { ...ok, platformRole: 'GOD' },
    { ...ok, platformRole: undefined },
    { ...ok, email: 'someone@gmail.com' },
  ]) {
    assert.equal((await pa.createPlatformAdmin(w.ctx, 'owner', MFA, bad)).error, 'INVALID_ARGUMENT');
  }
  assert.equal((await pa.createPlatformAdmin(w.ctx, 'owner', MFA, { ...ok, email: 'taken@avail404.com' })).error, 'EMAIL_IN_USE');
  // Another domain is possible only when configured.
  const gm = { ...ok, email: 'x@partner.test' };
  assert.equal((await pa.createPlatformAdmin(w.ctx, 'owner', MFA, gm)).error, 'INVALID_ARGUMENT');
  const out = await pa.createPlatformAdmin(w.ctx, 'owner', MFA, gm, { PLATFORM_ADMIN_EMAIL_DOMAINS: 'avail404.com, partner.test' });
  assert.equal(out.error, undefined);
});

test('bootstrap (script path): creates the account, returns a reset link, audits as SCRIPT, refuses duplicates', async () => {
  const w = world();
  const out = await pa.bootstrapPlatformAdmin(w.ctx, { name: 'Admin', email: 'admin@avail404.com', platformRole: 'OWNER' }, {}, 'ops@laptop');
  assert.equal(out.error, undefined);
  assert.equal(out.resetLink, 'https://reset.example/admin@avail404.com');
  const a = audits(w.db).find((x) => x.action === 'PLATFORM_ADMIN_CREATED');
  assert.equal(a.source, 'SCRIPT');
  assert.equal(a.actorEmail, 'ops@laptop');
  const again = await pa.bootstrapPlatformAdmin(w.ctx, { name: 'Admin', email: 'admin@avail404.com', platformRole: 'OWNER' }, {}, 'ops');
  assert.equal(again.error, 'EMAIL_IN_USE');
});

test('list: owner only; shows role, MFA state and marks the caller', async () => {
  const w = world({}, {});
  w.auth.users.owner = { uid: 'owner', multiFactor: { enrolledFactors: [{ uid: 'f1' }] }, metadata: { lastSignInTime: 'yesterday' } };
  assert.equal((await pa.listPlatformAdmins(w.ctx, 'support', MFA)).error, 'PERMISSION_DENIED');
  assert.equal((await pa.listPlatformAdmins(w.ctx, 'owner', NO_MFA)).error, 'MFA_REQUIRED');
  const out = await pa.listPlatformAdmins(w.ctx, 'owner', MFA);
  assert.deepEqual(out.admins.map((a) => a.email), ['legacy@avail404.com', 'owner@avail404.com', 'support@avail404.com']);
  const owner = out.admins.find((a) => a.uid === 'owner');
  assert.equal(owner.mfaEnrolled, true);
  assert.equal(owner.isSelf, true);
  assert.equal(owner.lastSignIn, 'yesterday');
  const legacy = out.admins.find((a) => a.uid === 'legacy');
  assert.equal(legacy.platformRole, 'OWNER');
  assert.equal(legacy.roleAssigned, false);
  assert.equal(legacy.mfaEnrolled, false);
  assert.equal(out.admins.some((a) => a.uid === 'teacher'), false, 'only platform admins');
});

test('setPlatformRole: owner only, never yourself, target must be a platform admin, audited', async () => {
  const w = world();
  assert.equal((await pa.setPlatformRole(w.ctx, 'support', MFA, { uid: 'legacy', platformRole: 'VIEWER' })).error, 'PERMISSION_DENIED');
  assert.equal((await pa.setPlatformRole(w.ctx, 'owner', NO_MFA, { uid: 'legacy', platformRole: 'VIEWER' })).error, 'MFA_REQUIRED');
  assert.equal((await pa.setPlatformRole(w.ctx, 'owner', MFA, { uid: 'owner', platformRole: 'VIEWER' })).error, 'FAILED_PRECONDITION');
  assert.equal((await pa.setPlatformRole(w.ctx, 'owner', MFA, { uid: 'teacher', platformRole: 'VIEWER' })).error, 'NOT_FOUND');
  assert.equal((await pa.setPlatformRole(w.ctx, 'owner', MFA, { uid: 'legacy', platformRole: 'GOD' })).error, 'INVALID_ARGUMENT');
  assert.equal(audits(w.db).length, 0);
  const out = await pa.setPlatformRole(w.ctx, 'owner', MFA, { uid: 'legacy', platformRole: 'COMPLIANCE' });
  assert.equal(out.ok, true);
  assert.equal(w.db.store.get('users/legacy').platformRole, 'COMPLIANCE');
  const a = audits(w.db);
  assert.equal(a.length, 1);
  assert.deepEqual(a[0].meta, { from: 'OWNER', to: 'COMPLIANCE' });
});

test('setPlatformAdminStatus: disables the Auth user, revokes sessions, never yourself, re-enable works', async () => {
  const w = world({}, {});
  w.auth.users.support = { uid: 'support' };
  assert.equal((await pa.setPlatformAdminStatus(w.ctx, 'support', MFA, { uid: 'legacy', status: 'DISABLED' })).error, 'PERMISSION_DENIED');
  assert.equal((await pa.setPlatformAdminStatus(w.ctx, 'owner', MFA, { uid: 'owner', status: 'DISABLED' })).error, 'FAILED_PRECONDITION');
  assert.equal((await pa.setPlatformAdminStatus(w.ctx, 'owner', MFA, { uid: 'support', status: 'GONE' })).error, 'INVALID_ARGUMENT');
  const off = await pa.setPlatformAdminStatus(w.ctx, 'owner', MFA, { uid: 'support', status: 'DISABLED' });
  assert.equal(off.ok, true);
  assert.equal(w.db.store.get('users/support').status, 'DISABLED');
  assert.equal(w.auth.users.support.disabled, true);
  assert.deepEqual(w.auth.revoked, ['support']);
  // A disabled platform admin can no longer act.
  assert.equal((await pa.listPlatformAdmins(w.ctx, 'support', MFA)).error, 'PERMISSION_DENIED');
  const on = await pa.setPlatformAdminStatus(w.ctx, 'owner', MFA, { uid: 'support', status: 'ACTIVE' });
  assert.equal(on.ok, true);
  assert.equal(w.auth.users.support.disabled, false);
  assert.deepEqual(audits(w.db).map((a) => a.action), ['PLATFORM_ADMIN_DISABLED', 'PLATFORM_ADMIN_ENABLED']);
});

test('a legacy platform admin (no platformRole) can still act as owner but only with a second factor', async () => {
  const w = world();
  assert.equal((await pa.listPlatformAdmins(w.ctx, 'legacy', NO_MFA)).error, 'MFA_REQUIRED');
  assert.equal((await pa.listPlatformAdmins(w.ctx, 'legacy', MFA)).error, undefined);
});

test('a platform admin whose login policy excludes PASSWORD is refused', async () => {
  const w = world({ 'users/owner': admin({ platformRole: 'OWNER', login: { enabled: true, methods: ['GOOGLE'], effective: ['GOOGLE'] } }) });
  assert.equal((await pa.listPlatformAdmins(w.ctx, 'owner', MFA)).error, 'PERMISSION_DENIED');
});

'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb, fakeAuth } = require('./test_support');
const a = require('./access');
const { ensureAuthUser } = require('./provision');

const B = 'schools/s1/branches/b1';
const TOKEN = { firebase: { sign_in_provider: 'password' } };
const seed = (extra = {}) => ({
  'users/admin': { schoolId: 's1', branchId: 'b1', role: 'SCHOOL_ADMIN', status: 'ACTIVE', login: { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD', 'GOOGLE'].slice(0, 1) } },
  'users/tuid': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE', email: 't@x.com' },
  'users/puid': { schoolId: 's1', branchId: 'b1', role: 'PARENT', status: 'ACTIVE', email: 'p@x.com' },
  'users/other': { schoolId: 's2', branchId: 'b9', role: 'TEACHER', status: 'ACTIVE' },
  [`${B}/staff/t1`]: { firstName: 'Asha', lastName: 'K', email: 'T@x.com', phone: '98765 43210', status: 'ACTIVE', isTeacher: true, userId: 'tuid' },
  [`${B}/staff/t2`]: { firstName: 'New', lastName: 'Hire', email: 'new@x.com', phone: '9000000001', status: 'ACTIVE', isTeacher: true },
  [`${B}/parents/p1`]: { firstName: 'Pia', lastName: 'R', email: 'p@x.com', phone: '9000000002', status: 'ACTIVE', linkedUserId: 'puid' },
  [`${B}/parents/p2`]: { firstName: 'NoMail', lastName: 'R', phone: '9000000003', status: 'ACTIVE' },
  ...extra,
});
const mk = (extra, school) => {
  const db = fakeDb(seed({ ...(school ? { 'schools/s1/authSettings/methods': { methods: school } } : {}), ...extra }));
  const auth = fakeAuth();
  return { db, auth, ctx: { db, auth, now: 'NOW', ensureAuthUser, configured: { phoneOtp: true } } };
};
const set = (ctx, d, uid = 'admin') =>
  a.setLoginAccess(ctx, uid, TOKEN, { schoolId: 's1', branchId: 'b1', kind: 'STAFF', id: 't1', enabled: true, methods: ['PASSWORD'], ...d });

test('normalizes phones and emails', () => {
  assert.strictEqual(a.normalizePhone('98765 43210'), '+919876543210');
  assert.strictEqual(a.normalizePhone('09876543210'), '+919876543210');
  assert.strictEqual(a.normalizePhone('+1 (415) 555-0100'), '+14155550100');
  assert.strictEqual(a.normalizePhone('12345'), null);
  assert.strictEqual(a.normalizePhone('abc'), null);
  assert.strictEqual(a.normalizeEmail(' A@B.Com '), 'a@b.com');
  assert.strictEqual(a.normalizeEmail('nope'), null);
});

test('loginAllowed mirrors the rules', () => {
  const t = (p, via) => ({ firebase: { sign_in_provider: p }, via });
  assert.ok(a.loginAllowed({ status: 'ACTIVE' }, t('password')), 'legacy account is allowed');
  assert.ok(!a.loginAllowed({ status: 'DISABLED' }, t('password')));
  const u = { status: 'ACTIVE', login: { enabled: true, effective: ['PASSWORD', 'PHONE_OTP'] } };
  assert.ok(a.loginAllowed(u, t('password')));
  assert.ok(!a.loginAllowed(u, t('google.com')), 'method not permitted');
  assert.ok(a.loginAllowed(u, t('custom', 'PHONE_OTP')));
  assert.ok(!a.loginAllowed(u, t('custom')), 'a custom token without the OTP claim is not phone login');
  assert.ok(!a.loginAllowed({ ...u, login: { ...u.login, enabled: false } }, t('password')));
});

test('admin can grant methods; effective is limited to the school', async () => {
  const { db, ctx } = mk({}, ['PASSWORD', 'GOOGLE']);
  const r = await set(ctx, { methods: ['PASSWORD', 'GOOGLE'] });
  assert.deepStrictEqual(r.result.effective, ['PASSWORD', 'GOOGLE']);
  assert.deepStrictEqual(db.store.get('users/tuid').login.methods, ['PASSWORD', 'GOOGLE']);
  assert.ok([...db.store.keys()].some((k) => k.startsWith('schools/s1/authAudit/')), 'audit written');
});

test('a method the school disabled is refused; phone needs a number and is unique', async () => {
  const { ctx } = mk({}, ['PASSWORD']);
  assert.strictEqual((await set(ctx, { methods: ['GOOGLE'] })).error, 'METHOD_NOT_ENABLED');
  const m = mk({}, ['PASSWORD', 'PHONE_OTP']);
  assert.strictEqual((await set(m.ctx, { kind: 'PARENT', id: 'p2', methods: ['PASSWORD'] })).error, 'EMAIL_REQUIRED');
  assert.strictEqual((await set(m.ctx, { methods: ['PHONE_OTP'], phone: '123' })).error, 'INVALID_PHONE');
  assert.ok((await set(m.ctx, { methods: ['PHONE_OTP'] })).result);
  assert.strictEqual(m.db.store.get('users/tuid').login.phone, '+919876543210');
  // the same number cannot be bound to a second user
  const dup = await set(m.ctx, { kind: 'PARENT', id: 'p1', methods: ['PHONE_OTP'], phone: '9876543210' });
  assert.strictEqual(dup.error, 'PHONE_IN_USE');
});

test('disabling keeps the account and records, empties effective, revokes sessions', async () => {
  const { db, auth, ctx } = mk();
  await set(ctx, {});
  const r = await set(ctx, { enabled: false, methods: [] });
  assert.strictEqual(r.result.revoked, true);
  assert.ok(auth.revoked.includes('tuid'));
  const u = db.store.get('users/tuid');
  assert.strictEqual(u.status, 'ACTIVE');
  assert.strictEqual(u.login.enabled, false);
  assert.deepStrictEqual(u.login.effective, []);
  assert.ok(db.store.has(`${B}/staff/t1`), 'staff record untouched');
  assert.ok(!a.loginAllowed(u, TOKEN));
});

test('only school admins/branch admins of the right scope may change access', async () => {
  const { ctx } = mk({ 'users/teacher2': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE' }, 'users/otherAdmin': { schoolId: 's2', role: 'SCHOOL_ADMIN', status: 'ACTIVE' }, 'users/ba2': { schoolId: 's1', branchId: 'zz', role: 'BRANCH_ADMIN', status: 'ACTIVE' } });
  assert.strictEqual((await set(ctx, {}, 'teacher2')).error, 'PERMISSION_DENIED');
  assert.strictEqual((await set(ctx, {}, 'otherAdmin')).error, 'PERMISSION_DENIED');
  assert.strictEqual((await set(ctx, {}, 'ba2')).error, 'PERMISSION_DENIED');
  assert.strictEqual((await set(ctx, {}, 'nobody')).error, 'PERMISSION_DENIED');
});

test('a disabled admin (login revoked) cannot administer even with a valid token', async () => {
  const { db, ctx } = mk();
  await db.collection('users').doc('admin').update({ 'login.enabled': false });
  assert.strictEqual((await set(ctx, {})).error, 'PERMISSION_DENIED');
});

test('cannot manage yourself, school admins or other schools', async () => {
  const { ctx } = mk({ 'users/admin2': { schoolId: 's1', branchId: 'b1', role: 'SCHOOL_ADMIN', status: 'ACTIVE' }, [`${B}/staff/adm`]: { firstName: 'A', email: 'a@x.com', status: 'ACTIVE', userId: 'admin2' } });
  assert.strictEqual((await set(ctx, { id: 'adm' })).error, 'PERMISSION_DENIED');
  assert.strictEqual((await set(ctx, { schoolId: 's2' })).error, 'PERMISSION_DENIED');
});

test('a record without an account gets one; phone-only needs no email', async () => {
  const m = mk({ [`${B}/staff/t3`]: { firstName: 'Ph', lastName: 'One', phone: '9000000009', status: 'ACTIVE', isTeacher: true } }, ['PASSWORD', 'PHONE_OTP']);
  const r = await set(m.ctx, { id: 't3', methods: ['PHONE_OTP'] });
  assert.ok(r.result.created);
  const uid = r.result.uid;
  assert.strictEqual(m.db.store.get(`${B}/staff/t3`).userId, uid);
  assert.strictEqual(m.db.store.get(`users/${uid}`).role, 'TEACHER');
  assert.deepStrictEqual(m.db.store.get(`users/${uid}`).login.effective, ['PHONE_OTP']);
  // creating the account is never done for a disable request
  assert.strictEqual((await set(m.ctx, { id: 't2', enabled: false, methods: [] })).error, 'NO_ACCOUNT');
});

test('getLoginAccess reports status without secrets', async () => {
  const { auth, ctx } = mk();
  await auth.createUser({ email: 't@x.com' });
  const r = await a.getLoginAccess(ctx, 'admin', TOKEN, { schoolId: 's1', branchId: 'b1', kind: 'STAFF', id: 't2' });
  assert.strictEqual(r.result.activation, 'NO_ACCOUNT');
  assert.strictEqual(r.result.registeredEmail, 'new@x.com');
  const g = await a.getLoginAccess(ctx, 'admin', TOKEN, { schoolId: 's1', branchId: 'b1', kind: 'PARENT', id: 'p1' });
  assert.strictEqual(g.result.legacy, true);
  assert.strictEqual(g.result.userType, 'PARENT');
});

test('school settings: validated, audited, fan out, no lockout, other schools untouched', async () => {
  const { db, auth, ctx } = mk({
    'users/s2admin': { schoolId: 's2', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
    'users/tuid': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE', login: { enabled: true, methods: ['PASSWORD', 'GOOGLE'], effective: ['PASSWORD', 'GOOGLE'] } },
  });
  const upd = (d, uid = 'admin') => a.updateSchoolAuthSettings(ctx, uid, TOKEN, { schoolId: 's1', emailPassword: true, google: true, phoneOtp: false, ...d });
  assert.strictEqual((await upd({ emailPassword: false, google: false })).error, 'NO_METHOD');
  assert.strictEqual((await upd({}, 'tuid')).error, 'PERMISSION_DENIED');
  assert.strictEqual((await upd({ emailPassword: 'yes' })).error, 'INVALID_ARGUMENT');
  // the admin only holds PASSWORD, so turning it off would lock everyone out
  assert.strictEqual((await upd({ emailPassword: false })).error, 'CALLER_LOCKOUT');
  assert.strictEqual((await upd({ phoneOtp: true })).result.methods.includes('PHONE_OTP'), true);

  await db.collection('users').doc('admin').update({ 'login.methods': ['PASSWORD', 'GOOGLE'] });
  const r = await upd({ google: false });
  assert.deepStrictEqual(r.result.methods, ['PASSWORD']);
  assert.deepStrictEqual(db.store.get('users/tuid').login.effective, ['PASSWORD']);
  assert.ok(auth.revoked.includes('tuid'), 'users who lost a method are signed out');
  // legacy parent was materialised and restricted; other school untouched
  assert.deepStrictEqual(db.store.get('users/puid').login.effective, ['PASSWORD']);
  assert.strictEqual(db.store.get('users/s2admin').login, undefined);
  assert.strictEqual(db.store.get('users/other').login, undefined);
});

test('PHONE_OTP cannot be enabled before Meta is configured', async () => {
  const { ctx } = mk();
  const r = await a.updateSchoolAuthSettings({ ...ctx, configured: { phoneOtp: false } }, 'admin', TOKEN, { schoolId: 's1', emailPassword: true, google: true, phoneOtp: true });
  assert.strictEqual(r.error, 'PHONE_OTP_NOT_CONFIGURED');
});

test('default settings leave legacy users untouched (no surprise lockout)', async () => {
  const { db, ctx } = mk();
  const r = await a.updateSchoolAuthSettings(ctx, 'admin', TOKEN, { schoolId: 's1', emailPassword: true, google: true, phoneOtp: false });
  assert.strictEqual(r.result.usersUpdated, 0);
  assert.strictEqual(db.store.get('users/puid').login, undefined);
});

test('ensureAuthUser replaces the password of an unclaimed pre-registered account', async () => {
  const db = fakeDb({});
  const auth = fakeAuth({ 'x@y.com': 'pre' });
  const r = await ensureAuthUser(auth, db, { email: 'x@y.com', name: 'X' });
  assert.deepStrictEqual(r, { uid: 'pre', created: false });
  assert.ok(auth.users.pre.passwordReset);
  assert.deepStrictEqual(auth.revoked, ['pre']);
  const phoneOnly = await ensureAuthUser(auth, db, { email: null, name: 'P' });
  assert.ok(phoneOnly.created);
});

test('a new parent login enables portal access to their children', async () => {
  const { db, ctx } = mk(
    {
      [`${B}/students/st1`]: { status: 'ACTIVE', currentClassId: 'c1', currentSectionId: 'sa' },
      [`${B}/students/st1/parentLinks/l1`]: { schoolId: 's1', branchId: 'b1', parentId: 'p2', studentId: 'st1', status: 'ACTIVE', canAccessPortal: false },
    },
    ['PASSWORD', 'PHONE_OTP'],
  );
  const r = await a.setLoginAccess(
    { ...ctx, enablePortalLinks: require('./provision').enablePortalLinks },
    'admin',
    TOKEN,
    { schoolId: 's1', branchId: 'b1', kind: 'PARENT', id: 'p2', enabled: true, methods: ['PHONE_OTP'] },
  );
  assert.ok(r.result.created, JSON.stringify(r));
  assert.strictEqual(db.store.get(`${B}/students/st1/parentLinks/l1`).canAccessPortal, true);
  assert.deepStrictEqual(db.store.get(`${B}/parentAccess/p2`).classKeys, ['c1']);
  assert.strictEqual(db.store.get(`users/${r.result.uid}`).role, 'PARENT');
  assert.strictEqual(db.store.get(`users/${r.result.uid}`).linkedParentId, 'p2');
});

test('re-enabling an account never creates a second one', async () => {
  const { auth, ctx } = mk({}, ['PASSWORD']);
  const before = Object.keys(auth.users).length;
  await set(ctx, {});
  await set(ctx, { enabled: false, methods: [] });
  await set(ctx, {});
  assert.strictEqual(Object.keys(auth.users).length, before);
});

test('a branch admin through a per-branch role may administer that branch, but not accounts homed elsewhere', async () => {
  const { assertAdmin } = require('./access');
  const db = fakeDb({
    'users/multi': { schoolId: 's1', status: 'ACTIVE', role: 'TEACHER', branchId: 'b1', branchRoles: { b2: 'BRANCH_ADMIN' } },
    'users/plain': { schoolId: 's1', status: 'ACTIVE', role: 'TEACHER', branchId: 'b1', branchRoles: { b2: 'TEACHER' } },
  });
  const ok = await assertAdmin(db, 'multi', 's1', 'b2', {});
  assert.equal(ok.role, 'BRANCH_ADMIN');
  assert.equal(await assertAdmin(db, 'multi', 's1', 'b1', {}), null); // home role is teacher
  assert.equal(await assertAdmin(db, 'multi', 's1', 'b3', {}), null);
  assert.equal(await assertAdmin(db, 'plain', 's1', 'b2', {}), null);
});

test('NOTIF-1: signing a user out everywhere also removes their push devices', async () => {
  const { db, auth, ctx } = mk();
  await set(ctx, {});
  db.store.set('users/tuid/devices/d1', { token: 'tok-aaaaaaaaaaaaaaaaaaaaaaaa' });
  db.store.set('users/other/devices/d2', { token: 'tok-bbbbbbbbbbbbbbbbbbbbbbbb' });
  const r = await set(ctx, { revokeSessions: true });
  assert.strictEqual(r.result.revoked, true);
  assert.ok(auth.revoked.includes('tuid'));
  assert.strictEqual(db.store.has('users/tuid/devices/d1'), false);
  assert.strictEqual(db.store.has('users/other/devices/d2'), true, 'other accounts are untouched');
});

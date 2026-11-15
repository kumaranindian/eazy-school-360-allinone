'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb, fakeAuth, DELETE_FIELD } = require('./test_support');
const sl = require('./school_lifecycle');
const access = require('./access');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const NO_MFA = { firebase: { sign_in_provider: 'password' } };
const T0 = new Date('2026-11-13T10:00:00Z');
const admin = (role, email) => ({
  role: 'PLATFORM_ADMIN', platformRole: role, status: 'ACTIVE', name: role, email, schoolId: null,
  login: { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'] },
});
const school = (over = {}) => ({ name: 'Rosewood', status: 'ACTIVE', ...over });

function world(extra = {}, authUsers = {}) {
  const db = fakeDb({
    'users/owner': admin('OWNER', 'owner@avail404.com'),
    'users/owner2': admin('OWNER', 'owner2@avail404.com'),
    'users/support': admin('SUPPORT', 'support@avail404.com'),
    'users/viewer': admin('VIEWER', 'v@avail404.com'),
    'users/sa1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1', branchId: 'main', name: 'Head', email: 'head@rw.test' },
    'users/t1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1', branchId: 'main', name: 'T', email: 't@rw.test' },
    'users/p1': { role: 'PARENT', status: 'ACTIVE', schoolId: 's1', branchId: 'main', name: 'P', email: 'p@x.test' },
    'users/other': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's2', branchId: 'main', name: 'O', email: 'o@x.test' },
    'schools/s1': school(),
    'schools/s2': school({ name: 'Elm' }),
    ...extra,
  });
  const auth = fakeAuth(authUsers);
  return { db, auth, ctx: { db, auth, now: 'TS', nowDate: () => T0, deleteField: DELETE_FIELD } };
}
const audits = (db) => [...db.store.entries()].filter(([k]) => k.startsWith('platformAuditLog/')).map(([, v]) => v);
const input = { schoolName: 'New School', adminName: 'Head Teacher', adminEmail: 'Head@NewSchool.test', regional: { countryCode: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', dateFormat: 'dd/MM/yyyy' } };

test('suspension is mirrored onto every profile of THAT school and enforced by access checks', async () => {
  const { db, ctx } = world();
  const out = await sl.setSchoolStatus(ctx, 'owner', MFA, { schoolId: 's1', status: 'SUSPENDED', reason: 'Unpaid for three months' });
  assert.equal(out.ok, true);
  assert.equal(out.usersUpdated, 3);
  const s = db.store.get('schools/s1');
  assert.equal(s.status, 'SUSPENDED');
  assert.equal(s.statusReason, 'Unpaid for three months');
  for (const uid of ['sa1', 't1', 'p1']) assert.equal(db.store.get(`users/${uid}`).schoolAccess, 'SUSPENDED', uid);
  assert.equal(db.store.get('users/other').schoolAccess, undefined, 'another school untouched');
  assert.equal(db.store.get('users/owner').schoolAccess, undefined, 'platform admins are never paused');
  assert.equal(db.store.get('schools/s2').status, 'ACTIVE');
  // The same check the callables use.
  assert.equal(access.loginAllowed(db.store.get('users/t1'), MFA), false);
  assert.equal(access.methodAllowed(db.store.get('users/t1'), MFA), false);
  assert.equal(access.loginAllowed(db.store.get('users/other'), MFA), true);
  const a = audits(db);
  assert.equal(a.length, 1);
  assert.equal(a[0].action, 'SCHOOL_SUSPENDED');
  assert.equal(a[0].reason, 'Unpaid for three months');
});

test('reactivation lifts it again; an unchanged status is a no-op', async () => {
  const { db, ctx } = world();
  await sl.setSchoolStatus(ctx, 'owner', MFA, { schoolId: 's1', status: 'SUSPENDED', reason: 'Unpaid for three months' });
  const again = await sl.setSchoolStatus(ctx, 'owner', MFA, { schoolId: 's1', status: 'SUSPENDED', reason: 'Unpaid for three months' });
  assert.equal(again.unchanged, true);
  const n = audits(db).length;
  const back = await sl.setSchoolStatus(ctx, 'owner', MFA, { schoolId: 's1', status: 'ACTIVE' });
  assert.equal(back.ok, true);
  assert.equal(back.usersUpdated, 3);
  for (const uid of ['sa1', 't1', 'p1']) assert.equal('schoolAccess' in db.store.get(`users/${uid}`), false, uid);
  assert.equal(db.store.get('schools/s1').statusReason, null);
  assert.equal(access.loginAllowed(db.store.get('users/t1'), MFA), true);
  assert.equal(audits(db).length, n + 1);
});

test('only an owner with a second factor; a suspension needs a real reason; unknown values are refused', async () => {
  const { db, ctx } = world();
  const body = { schoolId: 's1', status: 'SUSPENDED', reason: 'Unpaid for three months' };
  assert.equal((await sl.setSchoolStatus(ctx, 'owner', NO_MFA, body)).error, 'MFA_REQUIRED');
  for (const uid of ['support', 'viewer', 'sa1', 'nobody']) assert.equal((await sl.setSchoolStatus(ctx, uid, MFA, body)).error, 'PERMISSION_DENIED', uid);
  assert.equal((await sl.setSchoolStatus(ctx, 'owner', MFA, { ...body, reason: 'short' })).error, 'INVALID_ARGUMENT');
  assert.equal((await sl.setSchoolStatus(ctx, 'owner', MFA, { ...body, status: 'DELETED' })).error, 'INVALID_ARGUMENT');
  assert.equal((await sl.setSchoolStatus(ctx, 'owner', MFA, { ...body, schoolId: 'ghost' })).error, 'NOT_FOUND');
  assert.equal(db.store.get('schools/s1').status, 'ACTIVE');
  assert.equal(audits(db).length, 0);
});

test('refreshSchoolAccess repairs a profile that drifted (a user added while suspended)', async () => {
  const { db, ctx } = world({ 'schools/s1': school({ status: 'SUSPENDED' }) });
  const out = await sl.refreshSchoolAccess(ctx, 'support', MFA, { schoolId: 's1' });
  assert.equal(out.usersUpdated, 3);
  assert.equal(db.store.get('users/p1').schoolAccess, 'SUSPENDED');
  assert.equal((await sl.refreshSchoolAccess(ctx, 'viewer', MFA, { schoolId: 's1' })).error, 'PERMISSION_DENIED');
  assert.equal((await sl.refreshSchoolAccess(ctx, 'owner', MFA, { schoolId: 'ghost' })).error, 'NOT_FOUND');
  assert.equal((await sl.refreshSchoolAccess(ctx, 'owner', MFA, { schoolId: 's1' })).usersUpdated, 0, 'idempotent');
});

test('applySchoolAccess pages through large schools', async () => {
  const seed = {};
  for (let i = 0; i < 950; i++) seed[`users/u${String(i).padStart(4, '0')}`] = { role: 'PARENT', status: 'ACTIVE', schoolId: 'big' };
  const { ctx } = world({ ...seed, 'schools/big': school({ status: 'SUSPENDED' }) });
  const out = await sl.applySchoolAccess(ctx, 'big', 'SUSPENDED');
  assert.deepEqual([out.updated, out.scanned, out.done], [950, 950, true]);
});

test('create school: school, Main Branch and first admin in one go; the password is unknown to everyone', async () => {
  const { db, auth, ctx } = world();
  const out = await sl.createSchoolWithAdmin(ctx, 'owner', MFA, input);
  assert.equal(out.ok, true);
  assert.equal(out.adminEmail, 'head@newschool.test');
  const s = db.store.get(`schools/${out.schoolId}`);
  assert.equal(s.name, 'New School');
  assert.equal(s.status, 'INACTIVE', 'every new school starts INACTIVE');
  assert.equal(s.lifecycleVersion, 1);
  assert.equal(s.currency, 'INR');
  assert.equal(s.countryCode, 'IN');
  assert.equal(s.timezone, 'Asia/Kolkata');
  const b = db.store.get(`schools/${out.schoolId}/branches/main`);
  assert.equal(b.schoolId, out.schoolId);
  assert.equal(b.status, 'ACTIVE');
  const u = db.store.get(`users/${out.adminUid}`);
  assert.equal(u.role, 'SCHOOL_ADMIN');
  assert.equal(u.schoolId, out.schoolId);
  assert.equal(u.branchId, 'main');
  assert.equal(u.schoolAccess, 'INACTIVE', 'the first admin is paused until the school is activated');
  assert.deepEqual(u.login.effective, ['PASSWORD', 'GOOGLE']);
  const created = [...db.store.entries()].filter(([k]) => k.startsWith('schoolLifecycleHistory/')).map(([, v]) => v);
  assert.deepEqual(created.map((h) => [h.event, h.from, h.to, h.schoolId]), [['SCHOOL_CREATED', null, 'INACTIVE', out.schoolId]]);
  assert.ok(auth.users[out.adminUid].password.length >= 32);
  assert.equal(JSON.stringify(out).includes(auth.users[out.adminUid].password), false);
  const a = audits(db);
  assert.equal(a.length, 1);
  assert.equal(a[0].action, 'SCHOOL_CREATED');
  assert.equal(a[0].schoolId, out.schoolId);
});

test('create school: owner only, validated, and an existing email is never reused', async () => {
  const { db, ctx } = world({}, { 'taken@x.test': 'existing' });
  assert.equal((await sl.createSchoolWithAdmin(ctx, 'owner', NO_MFA, input)).error, 'MFA_REQUIRED');
  for (const uid of ['support', 'viewer', 'sa1']) assert.equal((await sl.createSchoolWithAdmin(ctx, uid, MFA, input)).error, 'PERMISSION_DENIED', uid);
  for (const bad of [
    { ...input, schoolName: 'x' }, { ...input, adminName: '' }, { ...input, adminEmail: 'nope' },
    { ...input, regional: { ...input.regional, currency: 'rupees' } }, { ...input, regional: { ...input.regional, countryCode: 'India' } },
    { ...input, regional: { ...input.regional, timezone: '' } }, { ...input, regional: undefined },
  ]) assert.equal((await sl.createSchoolWithAdmin(ctx, 'owner', MFA, bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad).slice(0, 60));
  assert.equal((await sl.createSchoolWithAdmin(ctx, 'owner', MFA, { ...input, adminEmail: 'taken@x.test' })).error, 'EMAIL_IN_USE');
  assert.equal([...db.store.keys()].filter((k) => k.startsWith('schools/') && k.split('/').length === 2).length, 2, 'no school created by refused calls');
});

test('add school admin: owner only; admins of a suspended school start paused', async () => {
  const { db, ctx } = world({ 'schools/s1': school({ status: 'SUSPENDED' }) });
  assert.equal((await sl.addSchoolAdmin(ctx, 'support', MFA, { schoolId: 's1', name: 'New Head', email: 'n@rw.test' })).error, 'PERMISSION_DENIED');
  assert.equal((await sl.addSchoolAdmin(ctx, 'owner', MFA, { schoolId: 'ghost', name: 'New Head', email: 'n@rw.test' })).error, 'NOT_FOUND');
  const out = await sl.addSchoolAdmin(ctx, 'owner', MFA, { schoolId: 's1', name: 'New Head', email: 'N@rw.test' });
  assert.equal(out.ok, true);
  const u = db.store.get(`users/${out.adminUid}`);
  assert.equal(u.role, 'SCHOOL_ADMIN');
  assert.equal(u.schoolAccess, 'SUSPENDED');
  assert.equal(audits(db).at(-1).action, 'SCHOOL_ADMIN_ADDED');
});

test('reset school admin access: owner or support; only a SCHOOL admin of that school', async () => {
  const { db, auth, ctx } = world();
  assert.equal((await sl.resetSchoolAdminAccess(ctx, 'viewer', MFA, { schoolId: 's1', uid: 'sa1' })).error, 'PERMISSION_DENIED');
  assert.equal((await sl.resetSchoolAdminAccess(ctx, 'support', MFA, { schoolId: 's1', uid: 't1' })).error, 'NOT_FOUND', 'a teacher is not a school admin');
  assert.equal((await sl.resetSchoolAdminAccess(ctx, 'support', MFA, { schoolId: 's2', uid: 'sa1' })).error, 'NOT_FOUND', 'wrong school');
  const out = await sl.resetSchoolAdminAccess(ctx, 'support', MFA, { schoolId: 's1', uid: 'sa1' });
  assert.equal(out.ok, true);
  assert.equal(out.email, 'head@rw.test');
  assert.deepEqual(auth.revoked, ['sa1']);
  assert.equal(audits(db).at(-1).action, 'SCHOOL_ADMIN_ACCESS_RESET');
});

test('feature switches: owner only, known features, booleans; a missing switch means on', async () => {
  const { db, ctx } = world();
  assert.equal((await sl.setSchoolFeatures(ctx, 'support', MFA, { schoolId: 's1', features: { admission: false } })).error, 'PERMISSION_DENIED');
  for (const bad of [{ admission: 'no' }, { payroll: false }, 'x', null]) {
    assert.equal((await sl.setSchoolFeatures(ctx, 'owner', MFA, { schoolId: 's1', features: bad })).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
  assert.equal(await sl.featureEnabled(db, 's1', 'admission'), true);
  const out = await sl.setSchoolFeatures(ctx, 'owner', MFA, { schoolId: 's1', features: { admission: false }, reason: 'Not part of this plan', confirmDependants: true });
  assert.equal(out.features.admission, false);
  assert.equal(await sl.featureEnabled(db, 's1', 'admission'), false);
  assert.equal(await sl.featureEnabled(db, 's1', 'publicAdmission'), false, 'a dependant goes with it');
  assert.equal(await sl.featureEnabled(db, 's1', 'fees'), true, 'unrelated switches untouched');
  assert.equal(await sl.featureEnabled(db, 'ghost', 'admission'), false, 'no school, no feature');
  await sl.setSchoolFeatures(ctx, 'owner', MFA, { schoolId: 's1', features: { admission: true } });
  assert.equal(await sl.featureEnabled(db, 's1', 'admission'), true);
  assert.equal(audits(db).at(-1).action, 'SCHOOL_FEATURES_CHANGED');
});

test('offboarding: request suspends, a DIFFERENT owner approves, cancelling restores', async () => {
  const { db, ctx } = world();
  const reason = 'Contract ended, school asked to leave';
  assert.equal((await sl.requestSchoolOffboarding(ctx, 'support', MFA, { schoolId: 's1', reason })).error, 'PERMISSION_DENIED');
  assert.equal((await sl.requestSchoolOffboarding(ctx, 'owner', MFA, { schoolId: 's1', reason: 'short' })).error, 'INVALID_ARGUMENT');
  const req = await sl.requestSchoolOffboarding(ctx, 'owner', MFA, { schoolId: 's1', reason });
  assert.equal(req.ok, true);
  assert.equal(req.graceUntilMs, T0.getTime() + 30 * 86400000);
  assert.equal(db.store.get('schools/s1').status, 'SUSPENDED');
  assert.equal(db.store.get('users/t1').schoolAccess, 'SUSPENDED');
  assert.equal(db.store.get('platformOffboarding/s1').state, 'REQUESTED');
  assert.equal((await sl.requestSchoolOffboarding(ctx, 'owner2', MFA, { schoolId: 's1', reason })).error, 'FAILED_PRECONDITION', 'already open');
  // Cannot be reactivated by the normal switch while offboarding.
  assert.equal((await sl.setSchoolStatus(ctx, 'owner', MFA, { schoolId: 's1', status: 'ACTIVE' })).error, 'FAILED_PRECONDITION');
  // Four eyes.
  assert.equal((await sl.approveSchoolOffboarding(ctx, 'owner', MFA, { schoolId: 's1' })).reason, 'SAME_PERSON');
  assert.equal((await sl.approveSchoolOffboarding(ctx, 'support', MFA, { schoolId: 's1' })).error, 'PERMISSION_DENIED');
  assert.equal((await sl.approveSchoolOffboarding(ctx, 'owner2', MFA, { schoolId: 's1' })).ok, true);
  const off = db.store.get('platformOffboarding/s1');
  assert.deepEqual([off.state, off.approvedBy], ['APPROVED', 'owner2']);
  assert.equal((await sl.approveSchoolOffboarding(ctx, 'owner2', MFA, { schoolId: 's1' })).reason, 'NOT_REQUESTED');
  // Nothing was deleted.
  assert.ok(db.store.has('schools/s1') && db.store.has('users/sa1'));
  const cancel = await sl.cancelSchoolOffboarding(ctx, 'owner', MFA, { schoolId: 's1' });
  assert.equal(cancel.ok, true);
  assert.equal(db.store.get('schools/s1').status, 'ACTIVE');
  assert.equal('schoolAccess' in db.store.get('users/t1'), false);
  assert.equal(db.store.get('platformOffboarding/s1').state, 'CANCELLED');
  assert.equal((await sl.cancelSchoolOffboarding(ctx, 'owner', MFA, { schoolId: 's1' })).reason, 'NOT_OPEN');
  assert.deepEqual(audits(db).map((a) => a.action).filter((x) => x.startsWith('SCHOOL_OFFBOARDING')), ['SCHOOL_OFFBOARDING_REQUESTED', 'SCHOOL_OFFBOARDING_APPROVED', 'SCHOOL_OFFBOARDING_CANCELLED']);
});

test('cancelling offboarding of a school that was already suspended leaves it suspended', async () => {
  const { db, ctx } = world({ 'schools/s1': school({ status: 'SUSPENDED' }) });
  await sl.requestSchoolOffboarding(ctx, 'owner', MFA, { schoolId: 's1', reason: 'Contract ended, school asked to leave' });
  await sl.cancelSchoolOffboarding(ctx, 'owner', MFA, { schoolId: 's1' });
  assert.equal(db.store.get('schools/s1').status, 'SUSPENDED');
});

// ---- lifecycle table, history, idempotency, closure and recovery ----------------------------

const hist = (db) => [...db.store.entries()].filter(([k]) => k.startsWith('schoolLifecycleHistory/')).map(([, v]) => v);
const T = (ctx, who, to, extra = {}) => sl.transitionSchool(ctx, who, MFA, { schoolId: 's1', to, ...extra });

test('transition table: only the listed moves exist, and EXPIRED is the system\'s alone', () => {
  const allowed = Object.keys(sl.TRANSITIONS).sort();
  assert.deepEqual(allowed, [
    'ACTIVE>CLOSED', 'ACTIVE>EXPIRED', 'ACTIVE>INACTIVE', 'ACTIVE>SUSPENDED', 'CLOSED>INACTIVE', 'EXPIRED>ACTIVE', 'EXPIRED>CLOSED',
    'EXPIRED>SUSPENDED', 'INACTIVE>ACTIVE', 'INACTIVE>CLOSED', 'SUSPENDED>ACTIVE', 'SUSPENDED>CLOSED', 'SUSPENDED>INACTIVE',
  ]);
  assert.equal(sl.transitionRule('ACTIVE', 'EXPIRED', 'OWNER'), null);
  assert.ok(sl.transitionRule('ACTIVE', 'EXPIRED', 'SYSTEM'));
  assert.equal(sl.transitionRule('CLOSED', 'ACTIVE', 'OWNER'), null, 'CLOSED never goes straight back');
  assert.equal(sl.transitionRule('CLOSED', 'INACTIVE', 'OWNER'), null, 'not even by an owner alone');
  assert.equal(sl.transitionRule('INACTIVE', 'SUSPENDED', 'OWNER'), null);
  for (const to of sl.ALL_STATUSES) assert.equal(sl.transitionRule('CLOSED', to, 'OWNER'), null, to);
  assert.equal(sl.statusOf({}), 'ACTIVE', 'a school from before lifecycle states is ACTIVE');
  assert.equal(sl.statusOf({ status: 'WEIRD' }), 'ACTIVE');
});

test('activation: owner only, records who/when/remarks, writes history + audit, and lifts the pause', async () => {
  const { db, ctx } = world({ 'schools/s1': school({ status: 'INACTIVE' }) });
  await sl.applySchoolAccess(ctx, 's1', 'INACTIVE');
  assert.equal(db.store.get('users/t1').schoolAccess, 'INACTIVE');
  for (const uid of ['support', 'viewer', 'sa1', 'ba', 't1', 'nobody']) assert.equal((await T(ctx, uid, 'ACTIVE')).error, 'PERMISSION_DENIED', uid);
  assert.equal(db.store.get('schools/s1').status, 'INACTIVE');
  const out = await T(ctx, 'owner', 'ACTIVE', { remarks: 'Contract signed 12 Nov', internalNotes: 'Sales ticket 88', message: 'Welcome!' });
  assert.deepEqual([out.ok, out.from, out.to], [true, 'INACTIVE', 'ACTIVE']);
  const s = db.store.get('schools/s1');
  assert.deepEqual([s.status, s.activatedBy, s.activationRemarks, s.lifecycleVersion], ['ACTIVE', 'owner', 'Contract signed 12 Nov', 1]);
  assert.equal(s.statusReason, null);
  assert.equal('schoolAccess' in db.store.get('users/t1'), false);
  const h = hist(db).at(-1);
  assert.deepEqual([h.event, h.from, h.to, h.actorUid, h.remarks, h.internalNotes, h.message], ['SCHOOL_ACTIVATED', 'INACTIVE', 'ACTIVE', 'owner', 'Contract signed 12 Nov', 'Sales ticket 88', 'Welcome!']);
  assert.equal(audits(db).at(-1).action, 'SCHOOL_ACTIVATED');
});

test('every refused transition leaves school, users, history and audit untouched', async () => {
  const { db, ctx } = world();
  const before = JSON.stringify([...db.store.entries()]);
  assert.equal((await T(ctx, 'owner', 'EXPIRED')).error, 'INVALID_TRANSITION', 'EXPIRED is the scheduler\'s');
  assert.equal((await T(ctx, 'owner', 'INACTIVE', { reason: 'short' })).error, 'INVALID_ARGUMENT');
  assert.equal((await T(ctx, 'owner', 'CLOSED', { reason: 'Contract ended for good' })).reason, 'CLOSURE_NOT_APPROVED');
  assert.equal((await T(ctx, 'owner', 'NOPE')).error, 'INVALID_ARGUMENT');
  assert.equal((await T(ctx, 'owner', 'INACTIVE', { schoolId: 'ghost', reason: 'Switching it off now' })).error, 'NOT_FOUND');
  assert.equal(JSON.stringify([...db.store.entries()]), before);
});

test('deactivate and reactivate move through the table with reasons; an unchanged state is a no-op', async () => {
  const { db, ctx } = world();
  assert.equal((await T(ctx, 'owner', 'ACTIVE')).unchanged, true);
  assert.equal((await T(ctx, 'owner', 'INACTIVE', { reason: 'Switching it off pending paperwork' })).ok, true);
  assert.equal(db.store.get('users/p1').schoolAccess, 'INACTIVE');
  assert.equal(db.store.get('schools/s1').statusReason, 'Switching it off pending paperwork');
  assert.equal((await T(ctx, 'owner', 'ACTIVE')).ok, true);
  assert.deepEqual(hist(db).map((h) => h.event), ['SCHOOL_DEACTIVATED', 'SCHOOL_ACTIVATED']);
});

test('the mirror carries the state so the app can say which', async () => {
  const { db, ctx } = world();
  await T(ctx, 'owner', 'SUSPENDED', { reason: 'Unpaid for three months' });
  assert.equal(db.store.get('users/t1').schoolAccess, 'SUSPENDED');
  await sl.applySchoolAccess(ctx, 's1', 'EXPIRED');
  assert.equal(db.store.get('users/t1').schoolAccess, 'EXPIRED');
  assert.equal((await sl.applySchoolAccess(ctx, 's1', 'EXPIRED')).updated, 0, 'idempotent');
  await sl.applySchoolAccess(ctx, 's1', 'ACTIVE');
  assert.equal('schoolAccess' in db.store.get('users/t1'), false);
});

test('an idempotency key makes a retry return the first result and act once', async () => {
  const { db, ctx } = world();
  const a = await T(ctx, 'owner', 'SUSPENDED', { reason: 'Unpaid for three months', idempotencyKey: 'k1' });
  const n = hist(db).length;
  const b = await T(ctx, 'owner', 'SUSPENDED', { reason: 'Unpaid for three months', idempotencyKey: 'k1' });
  assert.equal(a.ok, true);
  assert.equal(b.replayed, true);
  assert.equal(hist(db).length, n);
  assert.equal(audits(db).filter((x) => x.action === 'SCHOOL_SUSPENDED').length, 1);
  // The same key on another school is a different request.
  const other = await sl.transitionSchool(ctx, 'owner', MFA, { schoolId: 's2', to: 'SUSPENDED', reason: 'Unpaid for three months', idempotencyKey: 'k1' });
  assert.equal(other.ok, true);
});

test('closing needs an APPROVED offboarding, then the school is CLOSED and nothing leaves that state normally', async () => {
  const { db, ctx } = world();
  const reason = 'Contract ended, school asked to leave';
  await sl.requestSchoolOffboarding(ctx, 'owner', MFA, { schoolId: 's1', reason });
  assert.equal((await T(ctx, 'owner', 'CLOSED', { reason })).reason, 'CLOSURE_NOT_APPROVED', 'requested but not approved');
  await sl.approveSchoolOffboarding(ctx, 'owner2', MFA, { schoolId: 's1' });
  const out = await T(ctx, 'owner', 'CLOSED', { reason });
  assert.equal(out.ok, true);
  const s = db.store.get('schools/s1');
  assert.deepEqual([s.status, s.closedBy], ['CLOSED', 'owner']);
  assert.equal(db.store.get('platformOffboarding/s1').state, 'COMPLETED');
  assert.equal(db.store.get('users/sa1').schoolAccess, 'CLOSED');
  for (const to of ['ACTIVE', 'INACTIVE', 'SUSPENDED']) assert.equal((await T(ctx, 'owner', to, { reason: 'Trying to reopen it' })).error, 'INVALID_TRANSITION', to);
  assert.equal(hist(db).at(-1).event, 'SCHOOL_CLOSED');
  assert.ok(db.store.has('schools/s1') && db.store.has('users/sa1'), 'nothing is deleted');
});

async function closed(extra = {}) {
  const w = world({ 'schools/s1': school({ status: 'CLOSED', lifecycleVersion: 4 }), ...extra });
  await sl.applySchoolAccess(w.ctx, 's1', 'CLOSED');
  return w;
}

test('recovery of a CLOSED school: a written reason, a DIFFERENT owner approves, the school returns INACTIVE (never straight to ACTIVE)', async () => {
  const { db, ctx } = await closed();
  const reason = 'Closed by mistake, contract was renewed';
  assert.equal((await sl.requestSchoolRecovery(ctx, 'support', MFA, { schoolId: 's1', reason })).error, 'PERMISSION_DENIED');
  assert.equal((await sl.requestSchoolRecovery(ctx, 'owner', MFA, { schoolId: 's1', reason: 'short' })).error, 'INVALID_ARGUMENT');
  assert.equal((await sl.requestSchoolRecovery(ctx, 'owner', MFA, { schoolId: 's2', reason })).reason, 'NOT_CLOSED', 'only a closed school');
  assert.equal((await sl.requestSchoolRecovery(ctx, 'owner', MFA, { schoolId: 's1', reason })).ok, true);
  assert.equal((await sl.requestSchoolRecovery(ctx, 'owner2', MFA, { schoolId: 's1', reason })).reason, 'ALREADY_OPEN');
  assert.equal(db.store.get('schools/s1').status, 'CLOSED', 'a request changes nothing');
  assert.equal((await sl.approveSchoolRecovery(ctx, 'owner', MFA, { schoolId: 's1' })).reason, 'SAME_PERSON');
  assert.equal((await sl.approveSchoolRecovery(ctx, 'support', MFA, { schoolId: 's1' })).error, 'PERMISSION_DENIED');
  assert.equal((await sl.approveSchoolRecovery(ctx, 'owner', NO_MFA, { schoolId: 's1' })).error, 'MFA_REQUIRED');
  const out = await sl.approveSchoolRecovery(ctx, 'owner2', MFA, { schoolId: 's1' });
  assert.deepEqual([out.ok, out.status], [true, 'INACTIVE']);
  const s = db.store.get('schools/s1');
  assert.deepEqual([s.status, s.lifecycleVersion], ['INACTIVE', 5]);
  assert.equal(db.store.get('users/sa1').schoolAccess, 'INACTIVE', 'still paused until activated');
  assert.equal(db.store.get('schoolRecovery/s1').state, 'APPROVED');
  const h = hist(db).at(-1);
  assert.deepEqual([h.event, h.from, h.to, h.actorUid], ['SCHOOL_RECOVERED', 'CLOSED', 'INACTIVE', 'owner2']);
  assert.deepEqual(audits(db).map((a) => a.action).filter((x) => x.includes('RECOVER')), ['SCHOOL_RECOVERY_REQUESTED', 'SCHOOL_RECOVERED']);
  // Activation is the normal, separate step.
  assert.equal((await T(ctx, 'owner', 'ACTIVE')).ok, true);
  assert.equal((await sl.approveSchoolRecovery(ctx, 'owner2', MFA, { schoolId: 's1' })).reason, 'NOT_REQUESTED');
});

test('a recovery request can be cancelled, and then cannot be approved', async () => {
  const { db, ctx } = await closed();
  const reason = 'Closed by mistake, contract was renewed';
  await sl.requestSchoolRecovery(ctx, 'owner', MFA, { schoolId: 's1', reason });
  assert.equal((await sl.cancelSchoolRecovery(ctx, 'viewer', MFA, { schoolId: 's1' })).error, 'PERMISSION_DENIED');
  assert.equal((await sl.cancelSchoolRecovery(ctx, 'owner2', MFA, { schoolId: 's1' })).ok, true);
  assert.equal(db.store.get('schoolRecovery/s1').state, 'CANCELLED');
  assert.equal((await sl.approveSchoolRecovery(ctx, 'owner2', MFA, { schoolId: 's1' })).reason, 'NOT_REQUESTED');
  assert.equal(db.store.get('schools/s1').status, 'CLOSED');
  assert.equal((await sl.cancelSchoolRecovery(ctx, 'owner', MFA, { schoolId: 's1' })).reason, 'NOT_REQUESTED');
  assert.equal((await sl.requestSchoolRecovery(ctx, 'owner2', MFA, { schoolId: 's1', reason })).ok, true, 'a new request is allowed after cancelling');
});

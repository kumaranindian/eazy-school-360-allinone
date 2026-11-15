'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const E = require('./access_engine');

const { CODES } = E;
const PW = { firebase: { sign_in_provider: 'password' } };
const user = (over = {}) => ({ role: 'TEACHER', status: 'ACTIVE', schoolId: 's1', branchId: 'b1', ...over });
const sch = (over = {}) => ({ status: 'ACTIVE', ...over });
const d = (over = {}) => E.decide({ school: sch(), user: user(), token: PW, schoolId: 's1', ...over });

test('every school role is allowed in an ACTIVE school with no subscription (legacy schools keep working)', () => {
  for (const role of ['SCHOOL_ADMIN', 'BRANCH_ADMIN', 'TEACHER', 'FINANCE', 'PARENT']) {
    assert.deepEqual(d({ user: user({ role }) }), { allowed: true, code: CODES.ACCESS_GRANTED }, role);
  }
  assert.equal(d({ school: { name: 'old school with no status' } }).allowed, true, 'missing status = ACTIVE');
  assert.equal(d({ school: { status: 'WEIRD' } }).allowed, true, 'an unknown value is treated as a pre-lifecycle school');
});

test('lifecycle: each non-active state blocks EVERY role with its own code', () => {
  const expected = { INACTIVE: CODES.SCHOOL_INACTIVE, SUSPENDED: CODES.SCHOOL_SUSPENDED, EXPIRED: CODES.SCHOOL_EXPIRED, CLOSED: CODES.SCHOOL_CLOSED };
  for (const [status, code] of Object.entries(expected)) {
    for (const role of ['SCHOOL_ADMIN', 'BRANCH_ADMIN', 'TEACHER', 'FINANCE', 'PARENT']) {
      assert.deepEqual(d({ school: sch({ status }), user: user({ role }) }), { allowed: false, code }, `${status}/${role}`);
    }
  }
});

test('subscription: not started and expired/cancelled block; trial, active and grace allow; absent allows', () => {
  const sub = (status) => d({ subscription: { status } });
  assert.equal(sub('NOT_STARTED').code, CODES.SUBSCRIPTION_NOT_STARTED);
  assert.equal(sub('EXPIRED').code, CODES.SUBSCRIPTION_EXPIRED);
  assert.equal(sub('CANCELLED').code, CODES.SUBSCRIPTION_EXPIRED);
  for (const s of ['TRIAL', 'ACTIVE', 'GRACE_PERIOD']) assert.equal(sub(s).allowed, true, s);
  assert.equal(d({ subscription: null }).allowed, true);
  assert.equal(d({ subscription: {} }).allowed, true);
});

test('the access matrix: lifecycle wins over subscription, subscription wins over feature, feature over user/role', () => {
  const all = { school: sch({ status: 'SUSPENDED', features: { attendance: false } }), subscription: { status: 'EXPIRED' }, user: user({ status: 'DISABLED' }), feature: 'attendance' };
  assert.equal(d(all).code, CODES.SCHOOL_SUSPENDED);
  assert.equal(d({ ...all, school: sch({ features: { attendance: false } }) }).code, CODES.SUBSCRIPTION_EXPIRED);
  assert.equal(d({ ...all, school: sch({ features: { attendance: false } }), subscription: { status: 'ACTIVE' } }).code, CODES.FEATURE_DISABLED);
  assert.equal(d({ ...all, school: sch(), subscription: { status: 'ACTIVE' } }).code, CODES.USER_DISABLED);
});

test('features: only an explicit false disables; other schools and other features are untouched', () => {
  assert.equal(d({ feature: 'admission', school: sch({ features: { admission: false } }) }).code, CODES.FEATURE_DISABLED);
  assert.equal(d({ feature: 'admission', school: sch({ features: { admission: true } }) }).allowed, true);
  assert.equal(d({ feature: 'admission', school: sch({ features: { publicAdmission: false } }) }).allowed, true);
  assert.equal(d({ feature: 'admission', school: sch() }).allowed, true);
  assert.equal(d({ school: sch({ features: { admission: false } }) }).allowed, true, 'no feature asked = no feature check');
});

test('user account: disabled, invited, login switched off, or a method the policy forbids', () => {
  assert.equal(d({ user: user({ status: 'DISABLED' }) }).code, CODES.USER_DISABLED);
  assert.equal(d({ user: user({ status: 'INVITED' }) }).code, CODES.USER_DISABLED);
  assert.equal(d({ user: user({ login: { enabled: false, effective: ['PASSWORD'] } }) }).code, CODES.USER_DISABLED);
  assert.equal(d({ user: user({ login: { enabled: true, effective: ['GOOGLE'] } }) }).code, CODES.USER_DISABLED);
  assert.equal(d({ user: user({ login: { enabled: true, effective: ['PASSWORD'] } }) }).allowed, true);
  assert.equal(d({ user: user({ schoolAccess: 'SUSPENDED' }) }).code, CODES.USER_DISABLED, 'a profile already paused by the mirror');
});

test('tenant isolation: a user of another school is refused without learning that school\'s state', () => {
  for (const status of ['ACTIVE', 'SUSPENDED', 'CLOSED']) {
    assert.deepEqual(d({ school: sch({ status }), user: user({ schoolId: 'other' }) }), { allowed: false, code: CODES.INSUFFICIENT_PERMISSION }, status);
  }
  assert.equal(d({ user: null }).code, CODES.INSUFFICIENT_PERMISSION);
  assert.equal(d({ school: null }).code, CODES.INSUFFICIENT_PERMISSION);
  assert.equal(d({ user: user({ role: 'PLATFORM_ADMIN', schoolId: null }) }).code, CODES.INSUFFICIENT_PERMISSION, 'platform admins act through platform callables');
});

test('roles and branches', () => {
  assert.equal(d({ roles: ['SCHOOL_ADMIN'], user: user({ role: 'SCHOOL_ADMIN' }) }).allowed, true);
  assert.equal(d({ roles: ['SCHOOL_ADMIN'], user: user({ role: 'TEACHER' }) }).code, CODES.INSUFFICIENT_PERMISSION);
  assert.equal(d({ roles: ['SCHOOL_ADMIN', 'BRANCH_ADMIN'], branchId: 'b1', user: user({ role: 'BRANCH_ADMIN' }) }).allowed, true);
  assert.equal(d({ roles: ['BRANCH_ADMIN'], branchId: 'b2', user: user({ role: 'BRANCH_ADMIN' }) }).code, CODES.BRANCH_ACCESS_DENIED, 'admin of another branch');
  assert.equal(d({ roles: ['BRANCH_ADMIN'], branchId: 'b2', user: user({ role: 'BRANCH_ADMIN', branchRoles: { b2: 'BRANCH_ADMIN' } }) }).allowed, true, 'a per-branch role');
  assert.equal(d({ roles: ['BRANCH_ADMIN'], branchId: 'b2', user: user({ role: 'SCHOOL_ADMIN' }) }).allowed, true, 'a school admin acts in every branch');
  assert.equal(d({ branchId: 'b2', user: user({ role: 'TEACHER' }) }).code, CODES.BRANCH_ACCESS_DENIED, 'no role in that branch');
  assert.equal(d({ branchId: 'b1' }).allowed, true);
  assert.equal(d({ roles: ['FINANCE'], branchId: 'b1', user: user({ role: 'FINANCE' }) }).allowed, true);
  assert.equal(d({ roles: ['FINANCE'], branchId: 'b1', user: user({ role: 'TEACHER' }) }).code, CODES.INSUFFICIENT_PERMISSION);
});

function db(extra = {}) {
  return fakeDb({
    'schools/s1': sch(), 'schools/s2': sch({ status: 'SUSPENDED' }),
    'users/t1': user(), 'users/t2': user({ schoolId: 's2' }), 'users/dis': user({ status: 'DISABLED' }),
    ...extra,
  });
}

test('evaluateSchoolAccess reads the CURRENT state each time (no caching)', async () => {
  const store = db();
  const ask = () => E.evaluateSchoolAccess(store, { uid: 't1', token: PW, schoolId: 's1', feature: 'attendance' });
  assert.equal((await ask()).code, CODES.ACCESS_GRANTED);
  await store.collection('schools').doc('s1').update({ status: 'SUSPENDED' });
  assert.equal((await ask()).code, CODES.SCHOOL_SUSPENDED, 'a change applies on the very next call');
  await store.collection('schools').doc('s1').update({ status: 'ACTIVE', features: { attendance: false } });
  assert.equal((await ask()).code, CODES.FEATURE_DISABLED);
  await store.collection('schools').doc('s1').update({ features: { attendance: true } });
  assert.equal((await ask()).code, CODES.ACCESS_GRANTED);
});

test('evaluateSchoolAccess: bad input, outsiders, disabled users', async () => {
  const store = db();
  assert.equal((await E.evaluateSchoolAccess(store, { uid: '', token: PW, schoolId: 's1' })).code, CODES.INSUFFICIENT_PERMISSION);
  assert.equal((await E.evaluateSchoolAccess(store, { uid: 't1', token: PW, schoolId: '' })).code, CODES.INSUFFICIENT_PERMISSION);
  assert.equal((await E.evaluateSchoolAccess(store, { uid: 't1', token: PW, schoolId: 'ghost' })).code, CODES.INSUFFICIENT_PERMISSION);
  assert.equal((await E.evaluateSchoolAccess(store, { uid: 't2', token: PW, schoolId: 's1' })).code, CODES.INSUFFICIENT_PERMISSION, 'cross-tenant');
  assert.equal((await E.evaluateSchoolAccess(store, { uid: 'dis', token: PW, schoolId: 's1' })).code, CODES.USER_DISABLED);
});

test('subscription is evaluated LIVE from its dates, and only when enforcement is on', async () => {
  const sub = { startDate: '2026-01-01', endDate: '2026-06-30', classification: 'PAID', gracePeriodDays: 0, status: 'ACTIVE' }; // stored status is stale
  const store = db({ 'schoolSubscriptions/s1': sub });
  const q = { uid: 't1', token: PW, schoolId: 's1' };
  const during = new Date('2026-06-30T12:00:00Z');
  const after = new Date('2026-07-01T12:00:00Z');
  assert.equal((await E.evaluateSchoolAccess(store, q, { enforceSubscription: false, now: after })).code, CODES.ACCESS_GRANTED, 'off');
  assert.equal((await E.evaluateSchoolAccess(store, q, { enforceSubscription: true, now: during })).code, CODES.ACCESS_GRANTED);
  assert.equal((await E.evaluateSchoolAccess(store, q, { enforceSubscription: true, now: after })).code, CODES.SUBSCRIPTION_EXPIRED, 'stale stored status is ignored');
  assert.equal((await E.evaluateSchoolAccess(store, q, { enforceSubscription: true, now: new Date('2025-12-31T12:00:00Z') })).code, CODES.SUBSCRIPTION_NOT_STARTED);
  assert.equal(E.subscriptionsEnforced({}), true, 'on by default');
  assert.equal(E.subscriptionsEnforced({ GOV_SUBSCRIPTION_ENFORCEMENT: 'false' }), false, 'kill switch');
  assert.equal((await E.schoolUsable(store, 's2', undefined, { enforceSubscription: true, now: after })).code, CODES.SCHOOL_SUSPENDED);
});

test('a school with no subscription document is legacy and stays allowed with enforcement on', async () => {
  const store = db();
  assert.equal((await E.evaluateSchoolAccess(store, { uid: 't1', token: PW, schoolId: 's1' }, { enforceSubscription: true })).code, CODES.ACCESS_GRANTED);
});

test('schoolUsable: the school-level half for gateways that authenticate the caller themselves', async () => {
  const store = db();
  assert.equal((await E.schoolUsable(store, 's1')).allowed, true);
  assert.equal((await E.schoolUsable(store, 's2')).code, CODES.SCHOOL_SUSPENDED);
  assert.equal((await E.schoolUsable(store, 'ghost')).code, CODES.INSUFFICIENT_PERMISSION);
  assert.equal((await E.schoolUsable(store, '')).code, CODES.INSUFFICIENT_PERMISSION);
  await store.collection('schools').doc('s1').update({ features: { admission: false } });
  assert.equal((await E.schoolUsable(store, 's1', 'admission')).code, CODES.FEATURE_DISABLED);
  assert.equal((await E.schoolUsable(store, 's1', 'fees')).allowed, true);
});

test('scheduled jobs skip schools that are not usable (fee and admission reminders)', async () => {
  const notify = require('./notify_events');
  const act = require('./admission_activities');
  for (const status of ['INACTIVE', 'SUSPENDED', 'EXPIRED', 'CLOSED']) {
    const store = fakeDb({ 'schools/s1': { name: 'S', status, timezone: 'UTC' } });
    const r1 = await notify.runFeeDueReminders({ db: store, now: 'N' }, { today: new Date('2026-01-01T09:00:00Z') });
    const r2 = await act.runFollowUpReminders({ db: store, now: 'N' }, { today: new Date('2026-01-01T09:00:00Z') });
    assert.equal((r1.created || 0) + (r1.sent || 0) + (r2.created || 0) + (r2.scanned || 0), 0, status);
  }
  assert.equal(E.featureOff({ features: { fees: false } }, 'fees'), true);
  assert.equal(E.featureOff({}, 'fees'), false);
});

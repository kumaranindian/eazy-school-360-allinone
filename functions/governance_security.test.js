'use strict';
// Phase 12: security and regression for everything the governance programme added.
// (1) cross-role matrix: every callable against every kind of caller, (2) denied calls change NOTHING,
// (3) hostile payloads never crash a callable or corrupt the store, (4) tenant isolation.
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const L = require('./school_lifecycle');
const S = require('./subscriptions');
const F = require('./features');
const N = require('./school_notifications');
const A = require('./audit');
const SA = require('./support_access');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const PW = { firebase: { sign_in_provider: 'password' } };
const NOW = new Date('2026-06-15T10:00:00Z');
const ctxOf = (db) => ({ db, now: 'NOW', nowDate: () => NOW, deleteField: db.deleteField, auth: { getUserByEmail: async () => { const e = new Error('nf'); e.code = 'auth/user-not-found'; throw e; }, createUser: async () => ({ uid: 'new' }), updateUser: async () => {}, revokeRefreshTokens: async () => {}, generatePasswordResetLink: async () => 'x' } });

const WHO = {
  owner: { token: MFA }, support: { token: MFA }, compliance: { token: MFA }, viewer: { token: MFA },
  ownerNoMfa: { token: PW },
  disabledOwner: { token: MFA },
  a1: { token: PW }, b1: { token: PW }, t1: { token: PW }, f1: { token: PW }, p1: { token: PW },
  x1: { token: PW }, // school admin of ANOTHER school
  fakeOwner: { token: MFA }, // a school admin profile carrying a platformRole field
  ghost: { token: PW },
};
const uidOf = { ownerNoMfa: 'owner', disabledOwner: 'dead' };

function world() {
  return fakeDb({
    'schools/s1': { name: 'S1', status: 'ACTIVE', timezone: 'UTC', features: {} },
    'schools/s2': { name: 'S2', status: 'ACTIVE', timezone: 'UTC' },
    'users/owner': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'OWNER', email: 'o@avail404.com' },
    'users/owner2': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'OWNER', email: 'o2@avail404.com' },
    'users/dead': { role: 'PLATFORM_ADMIN', status: 'DISABLED', platformRole: 'OWNER', email: 'd@avail404.com' },
    'users/support': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'SUPPORT', email: 's@avail404.com' },
    'users/compliance': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'COMPLIANCE', email: 'c@avail404.com' },
    'users/viewer': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'VIEWER', email: 'v@avail404.com' },
    'users/a1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1', email: 'a1@s1.test' },
    'users/b1': { role: 'BRANCH_ADMIN', status: 'ACTIVE', schoolId: 's1', branchId: 'b1' },
    'users/t1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1', branchId: 'b1' },
    'users/f1': { role: 'FINANCE', status: 'ACTIVE', schoolId: 's1', branchId: 'b1' },
    'users/p1': { role: 'PARENT', status: 'ACTIVE', schoolId: 's1' },
    'users/x1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's2' },
    'users/fakeOwner': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1', platformRole: 'OWNER' },
    'platformPlans/annual': { name: 'Annual', periodType: 'ANNUAL', active: true },
    'platformNotifications/n-a1': { recipientUserId: 'a1', schoolId: 's1', type: 'T', title: 't', body: 'b', requiresAck: true, state: 'DELIVERED' },
    'schoolSubscriptions/s1': { planId: 'annual', classification: 'PAID', startDate: '2026-01-01', endDate: '2026-12-31', gracePeriodDays: 0, status: 'ACTIVE', version: 1 },
    'schools/s1/branches/b1': { name: 'B' },
  });
}

// name -> { call(ctx, uid, token), allowed: roles that must get past the permission check }
const OWNER_ONLY = ['owner'];
const PLATFORM_READ = ['owner', 'support', 'compliance', 'viewer'];
const AUDIT_READ = ['owner', 'compliance'];
const SCHOOL_USERS = ['a1', 'b1', 't1', 'f1', 'p1', 'x1', 'fakeOwner'];
const base = { schoolId: 's1' };
const CALLABLES = {
  transitionSchool: { f: (c, u, t) => L.transitionSchool(c, u, t, { ...base, to: 'SUSPENDED', reason: 'A proper reason here' }), allowed: OWNER_ONLY },
  requestSchoolRecovery: { f: (c, u, t) => L.requestSchoolRecovery(c, u, t, { ...base, reason: 'A proper reason here ok' }), allowed: OWNER_ONLY },
  approveSchoolRecovery: { f: (c, u, t) => L.approveSchoolRecovery(c, u, t, base), allowed: OWNER_ONLY },
  cancelSchoolRecovery: { f: (c, u, t) => L.cancelSchoolRecovery(c, u, t, base), allowed: OWNER_ONLY },
  setSchoolFeatures: { f: (c, u, t) => F.setSchoolFeatures(c, u, t, { ...base, features: { homework: false }, reason: 'A proper reason here' }), allowed: OWNER_ONLY },
  setFeatureDefaults: { f: (c, u, t) => F.setFeatureDefaults(c, u, t, { features: { homework: false } }), allowed: OWNER_ONLY },
  savePlan: { f: (c, u, t) => S.savePlan(c, u, t, { name: 'Gold', periodType: 'ANNUAL' }), allowed: OWNER_ONLY },
  setSubscription: { f: (c, u, t) => S.setSubscription(c, u, t, { ...base, planId: 'annual', classification: 'PAID', startDate: '2026-01-01', endDate: '2027-01-01', reason: 'A proper reason here' }), allowed: OWNER_ONLY },
  extendSubscription: { f: (c, u, t) => S.extendSubscription(c, u, t, { ...base, endDate: '2027-06-30', reason: 'A proper reason here' }), allowed: OWNER_ONLY },
  renewSubscription: { f: (c, u, t) => S.renewSubscription(c, u, t, { ...base, endDate: '2028-01-01' }), allowed: OWNER_ONLY },
  cancelSubscription: { f: (c, u, t) => S.cancelSubscription(c, u, t, { ...base, reason: 'A proper reason here' }), allowed: OWNER_ONLY },
  grantTrial: { f: (c, u, t) => S.grantTrial(c, u, t, { schoolId: 's2', days: 7 }), allowed: OWNER_ONLY },
  listPlans: { f: (c, u, t) => S.listPlans(c, u, t), allowed: PLATFORM_READ },
  getSubscriptionHistory: { f: (c, u, t) => S.getSubscriptionHistory(c, u, t, base), allowed: PLATFORM_READ },
  getFeatureConfig: { f: (c, u, t) => F.getFeatureConfig(c, u, t), allowed: PLATFORM_READ },
  getFeatureHistory: { f: (c, u, t) => F.getFeatureHistory(c, u, t, base), allowed: PLATFORM_READ },
  getSchoolOverview: { f: (c, u, t) => SA.getSchoolOverview(c, u, t, base), allowed: PLATFORM_READ },
  queryAuditEvents: { f: (c, u, t) => A.queryAuditEvents(c, u, t, {}), allowed: AUDIT_READ },
  exportAuditEvents: { f: (c, u, t) => A.exportAuditEvents(c, u, t, {}), allowed: AUDIT_READ },
  getAuditSummary: { f: (c, u, t) => A.getAuditSummary(c, u, t, {}), allowed: AUDIT_READ },
  listMyPlatformNotifications: { f: (c, u, t) => N.listMyPlatformNotifications(c, u, t), allowed: SCHOOL_USERS },
  acknowledgeNotification: { f: (c, u, t) => N.acknowledgeNotification(c, u, t, { id: 'n-a1' }), allowed: ['a1'] },
  dismissNotification: { f: (c, u, t) => N.dismissNotification(c, u, t, { id: 'n-a1' }), allowed: ['a1'] },
};
const everyone = Object.keys(WHO);
const snapshot = (db) => JSON.stringify([...db.store.entries()].sort(([x], [y]) => (x < y ? -1 : 1)));
const isDenial = (r) => r && ['PERMISSION_DENIED', 'MFA_REQUIRED', 'NOT_FOUND'].includes(r.error);

test('cross-role matrix: only the intended roles pass the permission check, everyone else is refused and NOTHING is written', async () => {
  for (const [name, spec] of Object.entries(CALLABLES)) {
    for (const who of everyone) {
      if (spec.allowed.includes(who)) continue;
      const db = world();
      const before = snapshot(db);
      const out = await spec.f(ctxOf(db), uidOf[who] || who, WHO[who].token);
      assert.ok(isDenial(out), `${name} as ${who} should be refused, got ${JSON.stringify(out).slice(0, 120)}`);
      assert.equal(snapshot(db), before, `${name} as ${who} wrote something while being refused`);
    }
  }
});

test('cross-role matrix: the intended roles are not blocked by the permission check', async () => {
  for (const [name, spec] of Object.entries(CALLABLES)) {
    for (const who of spec.allowed) {
      const db = world();
      const out = await spec.f(ctxOf(db), uidOf[who] || who, WHO[who].token);
      assert.notEqual(out && out.error, 'PERMISSION_DENIED', `${name} as ${who}`);
      assert.notEqual(out && out.error, 'MFA_REQUIRED', `${name} as ${who}`);
    }
  }
});

test('a school admin profile that merely CONTAINS a platformRole field is not a platform admin', async () => {
  const db = world();
  const before = snapshot(db);
  for (const [name, spec] of Object.entries(CALLABLES)) {
    if (SCHOOL_USERS.length && spec.allowed.includes('a1')) continue;
    const out = await spec.f(ctxOf(db), 'fakeOwner', MFA);
    assert.ok(isDenial(out), `${name}: ${JSON.stringify(out).slice(0, 100)}`);
  }
  assert.equal(snapshot(db), before);
});

test('platform callables need a second factor even for an owner', async () => {
  for (const [name, spec] of Object.entries(CALLABLES)) {
    if (!spec.allowed.includes('owner') || SCHOOL_USERS.includes('owner')) continue;
    if (['listMyPlatformNotifications', 'acknowledgeNotification', 'dismissNotification'].includes(name)) continue;
    const out = await spec.f(ctxOf(world()), 'owner', PW);
    assert.equal(out.error, 'MFA_REQUIRED', name);
  }
});

test('a disabled platform admin and an unknown user can do nothing', async () => {
  for (const [name, spec] of Object.entries(CALLABLES)) {
    for (const uid of ['dead', 'ghost']) {
      const db = world();
      const before = snapshot(db);
      const out = await spec.f(ctxOf(db), uid, MFA);
      assert.ok(isDenial(out), `${name} as ${uid}`);
      assert.equal(snapshot(db), before, `${name} as ${uid}`);
    }
  }
});

// ---- hostile payloads --------------------------------------------------------------------------------

const HOSTILE_VALUES = [
  undefined, null, '', 'x', 0, -1, 1e308, NaN, true, [], [1, 2, 3], {}, { $ne: 1 }, { $gt: '' }, 'a/b', '../x', '..', '.', '__proto__', 'constructor', 'toString', '__name__',
  'x'.repeat(100000), '<script>alert(1)</script>', "'; DROP TABLE--", '\u0000', '\n\r', 'schools/s2', JSON.parse('{"__proto__":{"polluted":true}}'), { constructor: { prototype: { polluted: true } } },
];
const FIELDS = ['schoolId', 'planId', 'id', 'type', 'to', 'status', 'reason', 'remarks', 'message', 'features', 'endDate', 'startDate', 'classification', 'days', 'gracePeriodDays', 'name', 'periodType', 'cursor', 'limit', 'hours', 'fromMs', 'toMs', 'category', 'result', 'source', 'eventType', 'actorUserId', 'confirmDependants', 'idempotencyKey', 'defaultFeatures'];

const CALL_WITH = {
  transitionSchool: (c, u, t, d) => L.transitionSchool(c, u, t, d),
  requestSchoolRecovery: (c, u, t, d) => L.requestSchoolRecovery(c, u, t, d),
  approveSchoolRecovery: (c, u, t, d) => L.approveSchoolRecovery(c, u, t, d),
  cancelSchoolRecovery: (c, u, t, d) => L.cancelSchoolRecovery(c, u, t, d),
  setSchoolFeatures: (c, u, t, d) => F.setSchoolFeatures(c, u, t, d),
  setFeatureDefaults: (c, u, t, d) => F.setFeatureDefaults(c, u, t, d),
  savePlan: (c, u, t, d) => S.savePlan(c, u, t, d),
  setSubscription: (c, u, t, d) => S.setSubscription(c, u, t, d),
  extendSubscription: (c, u, t, d) => S.extendSubscription(c, u, t, d),
  renewSubscription: (c, u, t, d) => S.renewSubscription(c, u, t, d),
  cancelSubscription: (c, u, t, d) => S.cancelSubscription(c, u, t, d),
  grantTrial: (c, u, t, d) => S.grantTrial(c, u, t, d),
  getSubscriptionHistory: (c, u, t, d) => S.getSubscriptionHistory(c, u, t, d),
  getFeatureHistory: (c, u, t, d) => F.getFeatureHistory(c, u, t, d),
  getSchoolOverview: (c, u, t, d) => SA.getSchoolOverview(c, u, t, d),
  queryAuditEvents: (c, u, t, d) => A.queryAuditEvents(c, u, t, d),
  exportAuditEvents: (c, u, t, d) => A.exportAuditEvents(c, u, t, d),
  getAuditSummary: (c, u, t, d) => A.getAuditSummary(c, u, t, d),
  reportClientEvent: (c, u, t, d) => A.reportClientEvent(c, u, t, d),
  acknowledgeNotification: (c, u, t, d) => N.acknowledgeNotification(c, u, t, d),
  dismissNotification: (c, u, t, d) => N.dismissNotification(c, u, t, d),
};
const ACTOR = { transitionSchool: 'owner', requestSchoolRecovery: 'owner', approveSchoolRecovery: 'owner', cancelSchoolRecovery: 'owner', setSchoolFeatures: 'owner', setFeatureDefaults: 'owner', savePlan: 'owner', setSubscription: 'owner', extendSubscription: 'owner', renewSubscription: 'owner', cancelSubscription: 'owner', grantTrial: 'owner', getSubscriptionHistory: 'viewer', getFeatureHistory: 'viewer', getSchoolOverview: 'viewer', queryAuditEvents: 'owner', exportAuditEvents: 'owner', getAuditSummary: 'owner', reportClientEvent: 't1', acknowledgeNotification: 'a1', dismissNotification: 'a1' };

test('hostile whole payloads (wrong types, huge, nested, prototype keys) never crash a callable', async () => {
  for (const [name, fn] of Object.entries(CALL_WITH)) {
    for (const payload of HOSTILE_VALUES) {
      const db = world();
      let out;
      try {
        out = await fn(ctxOf(db), ACTOR[name], MFA, payload);
      } catch (e) {
        assert.fail(`${name} threw on payload ${JSON.stringify(payload)?.slice(0, 60)}: ${e.message}`);
      }
      assert.ok(out && typeof out === 'object', `${name} returned ${typeof out}`);
    }
  }
});

test('hostile single fields inside an otherwise valid request never crash a callable or leave odd documents', async () => {
  for (const [name, fn] of Object.entries(CALL_WITH)) {
    for (const field of FIELDS) {
      for (const v of HOSTILE_VALUES) {
        const db = world();
        const valid = { schoolId: 's1', planId: 'annual', classification: 'PAID', startDate: '2026-04-01', endDate: '2027-03-31', reason: 'A proper reason here', features: { homework: false }, to: 'SUSPENDED', id: 'n-a1', type: 'LOGOUT', days: 7, periodType: 'ANNUAL', name: 'Gold', endDate2: 'x' };
        let out;
        try {
          out = await fn(ctxOf(db), ACTOR[name], MFA, { ...valid, [field]: v });
        } catch (e) {
          assert.fail(`${name}.${field}=${JSON.stringify(v)?.slice(0, 40)} threw: ${e.message}`);
        }
        assert.ok(out && typeof out === 'object', `${name}.${field}`);
        for (const key of db.store.keys()) {
          assert.ok(!/\/(__proto__|constructor|toString|\.\.|\.)(\/|$)/.test(key), `${name}.${field} created a document at ${key}`);
        }
        assert.equal({}.polluted, undefined, 'the global object was polluted');
      }
    }
  }
});

test('hostile feature maps: prototype keys are refused, never treated as catalogue modules', async () => {
  for (const key of ['__proto__', 'constructor', 'toString', 'hasOwnProperty', 'valueOf']) {
    const features = JSON.parse(`{"${key}": false}`);
    for (const fn of [(db) => F.setSchoolFeatures(ctxOf(db), 'owner', MFA, { schoolId: 's1', features, reason: 'A proper reason here' }), (db) => F.setFeatureDefaults(ctxOf(db), 'owner', MFA, { features })]) {
      const db = world();
      const before = snapshot(db);
      const out = await fn(db);
      assert.equal(out.error, 'INVALID_ARGUMENT', key);
      assert.equal(snapshot(db), before, key);
    }
  }
  assert.equal(F.planChange(F.effective({}), JSON.parse('{"constructor": true}'), true).error, 'INVALID_ARGUMENT');
  assert.equal(F.usable({}, 'constructor'), true, 'an unknown key is never blocked and never throws');
});

test('hostile client event types: only the three allowlisted names are accepted', async () => {
  for (const type of ['constructor', '__proto__', 'toString', 'hasOwnProperty', 'LOGIN_FAILED', 'LOGOUT ', 'logout', { toString: () => 'LOGOUT' }, ['LOGOUT']]) {
    const db = world();
    const out = await A.reportClientEvent(ctxOf(db), 't1', PW, { type });
    assert.equal(out.error, 'INVALID_ARGUMENT', String(type));
    assert.equal((await db.collection('auditClientRate').get()).docs.length, 0, 'a refused type does not even touch the rate limiter');
  }
});

test('audit cursor and filters: bad shapes are refused, not turned into paths', async () => {
  for (const cursor of [{ m: '../x', id: 'a/b' }, { m: 5, id: {} }, { m: '202606', id: '__proto__' }, { m: '202606', id: 'x'.repeat(500) }, 'str', [], { id: ['a'] }]) {
    const db = world();
    const out = await A.queryAuditEvents(ctxOf(db), 'owner', MFA, { cursor });
    assert.ok(out.events || out.error, JSON.stringify(cursor));
  }
});

// ---- tenant isolation -------------------------------------------------------------------------------------

test('notifications: nobody can read, acknowledge or dismiss another person\'s, in the same school or another', async () => {
  const db = world();
  await db.collection('platformNotifications').doc('n-x1').set({ recipientUserId: 'x1', schoolId: 's2', type: 'T', title: 't', body: 'b', requiresAck: false, state: 'DELIVERED' });
  for (const who of ['b1', 't1', 'p1', 'x1']) {
    assert.deepEqual(await N.acknowledgeNotification(ctxOf(db), who, PW, { id: 'n-a1' }), { error: 'NOT_FOUND' }, who);
    assert.deepEqual(await N.dismissNotification(ctxOf(db), who, PW, { id: 'n-a1' }), { error: 'NOT_FOUND' }, who);
    const mine = await N.listMyPlatformNotifications(ctxOf(db), who, PW);
    assert.ok(!mine.notifications.some((n) => n.id === 'n-a1'), who);
  }
  assert.deepEqual(await N.dismissNotification(ctxOf(db), 'a1', PW, { id: 'n-x1' }), { error: 'NOT_FOUND' });
  assert.equal((await db.collection('platformNotifications').doc('n-a1').get()).data().state, 'DELIVERED', 'untouched');
});

test('school users reach no platform data through the school-side callables', async () => {
  const db = world();
  const r = await N.listMyPlatformNotifications(ctxOf(db), 'a1', PW);
  const text = JSON.stringify(r);
  for (const leak of ['internalNotes', 'recipientUserId', 'sourceEventId', 'platformRole', 'auditEvents']) assert.ok(!text.includes(leak), leak);
});

test('audit events never contain secrets even when a caller tries to smuggle them in', async () => {
  const db = world();
  await A.reportClientEvent(ctxOf(db), 't1', PW, { type: 'PERMISSION_DENIED_UI', route: '/x?token=ABC&password=hunter2', appVersion: 'Bearer eyJhbGciOi', correlationId: 'c1', password: 'hunter2', idToken: 'eyJ' });
  const rows = (await db.collection('auditEvents').doc('202606').collection('events').get()).docs.map((d) => JSON.stringify(d.data())).join('\n');
  for (const secret of ['hunter2', 'ABC', 'eyJ']) assert.ok(!rows.includes(secret), secret);
});

test('a client report cannot name a different actor, school or trust level', async () => {
  const db = world();
  await A.reportClientEvent(ctxOf(db), 't1', PW, { type: 'LOGOUT', actorUserId: 'a1', schoolId: 's2', trust: 'T1', source: 'CALLABLE', result: 'DENIED', category: 'PLATFORM', action: 'DELETE' });
  const e = (await db.collection('auditEvents').doc('202606').collection('events').get()).docs[0].data();
  assert.deepEqual([e.actorUserId, e.schoolId, e.trust, e.source, e.result, e.category, e.action], ['t1', 's1', 'T4', 'CLIENT_REPORTED', 'SUCCESS', 'AUTHENTICATION', 'LOGOUT']);
});

test('subscription and feature changes on one school never touch another', async () => {
  const db = world();
  const before = JSON.parse(JSON.stringify([...db.store.entries()].filter(([k]) => k.includes('s2'))));
  await S.setSubscription(ctxOf(db), 'owner', MFA, { schoolId: 's1', planId: 'annual', classification: 'PAID', startDate: '2026-01-01', endDate: '2027-01-01', reason: 'A proper reason here' });
  await F.setSchoolFeatures(ctxOf(db), 'owner', MFA, { schoolId: 's1', features: { homework: false }, reason: 'A proper reason here' });
  await L.transitionSchool(ctxOf(db), 'owner', MFA, { schoolId: 's1', to: 'SUSPENDED', reason: 'A proper reason here' });
  const after = JSON.parse(JSON.stringify([...db.store.entries()].filter(([k]) => k.includes('s2'))));
  assert.deepEqual(after, before);
  assert.equal((await db.collection('users').doc('x1').get()).data().schoolAccess, undefined, 'the other school\'s users are not paused');
});

test('the access engine never lets a user of one school act in another, whatever their role', async () => {
  const E = require('./access_engine');
  const db = world();
  for (const uid of ['a1', 'b1', 't1', 'f1', 'p1', 'x1']) {
    const other = uid === 'x1' ? 's1' : 's2';
    const r = await E.evaluateSchoolAccess(db, { uid, token: PW, schoolId: other }, { enforceSubscription: true });
    assert.deepEqual(r, { allowed: false, code: E.CODES.INSUFFICIENT_PERMISSION }, uid);
  }
});

// ---- self-registration: a client-created school document ---------------------------------------------------

test('a self-registered school cannot pre-set its own modules, lifecycle bookkeeping or subscription state', () => {
  const defaults = F.effective({ homework: false });
  const planted = {
    name: 'Evil School', status: 'INACTIVE', features: F.effective({}), featuresVersion: 99, lifecycleVersion: 50,
    subscriptionStatus: 'ACTIVE', subscriptionEndDate: '2099-12-31', accessMirror: 'ACTIVE', statusReason: 'Approved by the platform',
    activatedAt: 'x', activatedBy: 'owner', activationRemarks: 'Verified', suspendedBy: 'x', closedAt: 'x',
  };
  const fixes = L.newSchoolFixes(planted, defaults);
  assert.deepEqual(fixes.set.features, defaults, 'the platform default (homework off) wins over the client\'s all-on');
  assert.equal(fixes.set.featuresVersion, 1);
  assert.equal(fixes.set.lifecycleVersion, 1);
  for (const k of ['subscriptionStatus', 'subscriptionEndDate', 'accessMirror', 'statusReason', 'activatedAt', 'activatedBy', 'activationRemarks', 'suspendedBy', 'closedAt']) {
    assert.ok(fixes.remove.includes(k), k);
  }
});

test('a school created by the platform needs no correction', () => {
  const defaults = F.effective({});
  const fromPlatform = { name: 'Good', status: 'INACTIVE', features: defaults, featuresVersion: 1, lifecycleVersion: 1 };
  assert.deepEqual(L.newSchoolFixes(fromPlatform, defaults), { set: {}, remove: [] });
});

test('server-owned fields the trigger resets are exactly the ones the callables write', () => {
  const written = ['subscriptionStatus', 'subscriptionEndDate', 'accessMirror', 'statusReason', 'activatedAt', 'suspendedAt', 'closedAt'];
  for (const k of written) assert.ok(L.SERVER_OWNED_ON_CREATE.includes(k), k);
});

test('an optional plan id that is present but invalid is refused, never silently dropped', async () => {
  for (const planId of ['a b', 'x/y', '__proto__', 5, {}, 'x'.repeat(100)]) {
    const db = world();
    const before = snapshot(db);
    for (const out of [
      await S.grantTrial(ctxOf(db), 'owner', MFA, { schoolId: 's2', days: 7, planId }),
      await S.renewSubscription(ctxOf(db), 'owner', MFA, { schoolId: 's1', endDate: '2028-01-01', planId }),
      await S.savePlan(ctxOf(db), 'owner', MFA, { name: 'Gold', periodType: 'ANNUAL', planId }),
    ]) {
      assert.deepEqual([out.error, out.reason], ['INVALID_ARGUMENT', 'planId'], String(planId));
    }
    assert.equal(snapshot(db), before, String(planId));
  }
});

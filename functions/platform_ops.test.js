'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb, fakeAuth } = require('./test_support');
const po = require('./platform_ops');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const NO_MFA = { firebase: { sign_in_provider: 'password' } };
let nowMs = new Date('2026-11-13T10:00:00Z').getTime();
const DAY = 86400000;
const admin = (role) => ({ role: 'PLATFORM_ADMIN', platformRole: role, status: 'ACTIVE', email: `${role}@avail404.com`, schoolId: null, login: { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'] } });

function world(extra = {}) {
  const db = fakeDb({
    'users/owner': admin('OWNER'), 'users/support': admin('SUPPORT'), 'users/compliance': admin('COMPLIANCE'), 'users/viewer': admin('VIEWER'),
    'users/sa1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1' },
    'users/t1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1' },
    'users/t2': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's2' },
    'schools/s1': { name: 'Rosewood', status: 'ACTIVE', createdAt: new Date(nowMs - 5 * DAY) },
    'schools/s2': { name: 'Elm', status: 'SUSPENDED', createdAt: new Date(nowMs - 200 * DAY) },
    'schools/s3': { name: 'Oak', status: 'INACTIVE', createdAt: new Date(nowMs - 100 * DAY) },
    'schools/s1/branches/main': { name: 'Main' },
    'schools/s1/branches/north': { name: 'North' },
    'schools/s1/branches/main/students/a': {}, 'schools/s1/branches/main/students/b': {}, 'schools/s1/branches/north/students/c': {},
    'schools/s1/branches/main/staff/x': {},
    'schools/s1/branches/main/parents/p1': {}, 'schools/s1/branches/main/parents/p2': {},
    'schools/s2/branches/main': { name: 'Main' },
    'schools/s2/branches/main/students/d': {},
    'accountDeletionRequests/DEL-A': { status: 'UNDER_REVIEW' },
    'accountDeletionRequests/DEL-B': { status: 'COMPLETED' },
    'supportGrants/g1': { revokedAt: null, expiresAt: new Date(nowMs + 3600e3) },
    'supportGrants/g2': { revokedAt: null, expiresAt: new Date(nowMs - 3600e3) },
    'platformOffboarding/s2': { state: 'REQUESTED' },
    'platformBilling/b1': { status: 'DUE', dueDate: '2026-11-01' },
    'platformBilling/b2': { status: 'DUE', dueDate: '2026-12-01' },
    'platformBilling/b3': { status: 'PAID', dueDate: '2026-10-01' },
    ...extra,
  });
  const auth = fakeAuth();
  auth.users.u1 = { uid: 'u1', metadata: { lastSignInTime: new Date(nowMs - 3600e3).toUTCString() } };
  auth.users.u2 = { uid: 'u2', metadata: { lastSignInTime: new Date(nowMs - 3 * DAY).toUTCString() } };
  auth.users.u3 = { uid: 'u3', metadata: { lastSignInTime: new Date(nowMs - 20 * DAY).toUTCString() } };
  auth.users.u4 = { uid: 'u4', metadata: {} };
  return { db, auth, ctx: { db, auth, now: 'TS', nowDate: () => new Date(nowMs) } };
}
const audits = (db) => [...db.store.entries()].filter(([k]) => k.startsWith('platformAuditLog/')).map(([, v]) => v);

test('stats: school status, head counts, activity and backlog; per-school usage', async () => {
  const { db, ctx } = world();
  await po.computeStats(ctx);
  const s = db.store.get('platformStats/current');
  assert.deepEqual(s.schools, { total: 3, active: 1, suspended: 1, inactive: 1 });
  assert.equal(s.newSchools30d, 1);
  assert.deepEqual([s.students, s.staff, s.parents, s.branches], [4, 1, 2, 3]);
  assert.deepEqual(s.users, { total: 4, active1d: 1, active7d: 2, active30d: 3, partial: false });
  assert.deepEqual(s.backlog, { openDeletionRequests: 1, activeSupportGrants: 1, offboardingOpen: 1, billingOverdue: 1 });
  const u = db.store.get('schoolUsage/s1');
  assert.deepEqual([u.students, u.staff, u.parents, u.branches, u.users], [3, 1, 2, 2, 2]);
  assert.equal(db.store.get('schoolUsage/s2').students, 1);
  assert.equal(s.computedAtMs, nowMs);
});

test('refresh: owner, support and compliance may; viewers and school roles may not; throttled to once per 5 minutes', async () => {
  const { db, ctx } = world();
  assert.equal((await po.refreshPlatformStats(ctx, 'owner', NO_MFA)).error, 'MFA_REQUIRED');
  for (const uid of ['viewer', 'sa1', 'nobody']) assert.equal((await po.refreshPlatformStats(ctx, uid, MFA)).error, 'PERMISSION_DENIED', uid);
  assert.equal((await po.refreshPlatformStats(ctx, 'support', MFA)).throttled, false);
  assert.equal((await po.refreshPlatformStats(ctx, 'compliance', MFA)).throttled, true);
  nowMs += po.REFRESH_MIN_GAP_MS + 1000;
  assert.equal((await po.refreshPlatformStats(ctx, 'owner', MFA)).throttled, false);
  assert.ok(db.store.has('platformStats/current'));
});

const notice = (over = {}) => ({ title: 'Planned maintenance', body: 'The system is read-only on Sunday 2-4am.', severity: 'WARNING', audienceAll: true, endsAtMs: nowMs + 3 * DAY, ...over });

test('notices: owner/support publish; validated; audience all or named existing schools', async () => {
  const { db, ctx } = world();
  assert.equal((await po.publishPlatformNotice(ctx, 'owner', NO_MFA, notice())).error, 'MFA_REQUIRED');
  for (const uid of ['viewer', 'compliance', 'sa1']) assert.equal((await po.publishPlatformNotice(ctx, uid, MFA, notice())).error, 'PERMISSION_DENIED', uid);
  for (const bad of [
    notice({ title: 'x' }), notice({ body: '' }), notice({ severity: 'LOUD' }), notice({ endsAtMs: nowMs - 1 }), notice({ endsAtMs: nowMs + 200 * DAY }),
    notice({ endsAtMs: undefined }), notice({ audienceAll: false, schoolIds: [] }), notice({ audienceAll: false, schoolIds: Array.from({ length: 51 }, (_, i) => `s${i}`) }),
  ]) assert.equal((await po.publishPlatformNotice(ctx, 'support', MFA, bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad).slice(0, 80));
  assert.equal((await po.publishPlatformNotice(ctx, 'support', MFA, notice({ audienceAll: false, schoolIds: ['ghost'] }))).error, 'NOT_FOUND');
  const all = await po.publishPlatformNotice(ctx, 'support', MFA, notice());
  const some = await po.publishPlatformNotice(ctx, 'owner', MFA, notice({ audienceAll: false, schoolIds: ['s1', 's1', 's2'] }));
  assert.equal(db.store.get(`platformNotices/${all.id}`).audienceAll, true);
  assert.deepEqual(db.store.get(`platformNotices/${some.id}`).schoolIds, ['s1', 's2']);
  assert.equal(db.store.get(`platformNotices/${some.id}`).status, 'ACTIVE');
  assert.equal(audits(db).filter((a) => a.action === 'PLATFORM_NOTICE_PUBLISHED').length, 2);
});

test('notices: withdraw ends it now; listing says which are live; any platform role may list', async () => {
  const { db, ctx } = world();
  const a = await po.publishPlatformNotice(ctx, 'support', MFA, notice());
  const b = await po.publishPlatformNotice(ctx, 'support', MFA, notice({ title: 'Scheduled one', startsAtMs: nowMs + DAY, endsAtMs: nowMs + 2 * DAY }));
  let list = (await po.listPlatformNotices(ctx, 'viewer', MFA)).notices;
  assert.equal(list.find((n) => n.id === a.id).live, true);
  assert.equal(list.find((n) => n.id === b.id).live, false, 'not started yet');
  assert.equal((await po.withdrawPlatformNotice(ctx, 'viewer', MFA, { id: a.id })).error, 'PERMISSION_DENIED');
  assert.equal((await po.withdrawPlatformNotice(ctx, 'support', MFA, { id: 'ghost' })).error, 'NOT_FOUND');
  assert.equal((await po.withdrawPlatformNotice(ctx, 'support', MFA, { id: a.id })).ok, true);
  assert.equal((await po.withdrawPlatformNotice(ctx, 'support', MFA, { id: a.id })).unchanged, true);
  assert.equal(db.store.get(`platformNotices/${a.id}`).status, 'WITHDRAWN');
  list = (await po.listPlatformNotices(ctx, 'viewer', MFA)).notices;
  assert.equal(list.find((n) => n.id === a.id).live, false);
  assert.equal((await po.listPlatformNotices(ctx, 'sa1', MFA)).error, 'PERMISSION_DENIED');
});

test('app requirements: owner only; builds are whole numbers; maintenance needs a message and a future end', async () => {
  const { db, ctx } = world();
  const ok = { minBuild: { android: 13, ios: 0 }, maintenance: { enabled: false } };
  assert.equal((await po.setAppRequirements(ctx, 'owner', NO_MFA, ok)).error, 'MFA_REQUIRED');
  for (const uid of ['support', 'viewer', 'sa1']) assert.equal((await po.setAppRequirements(ctx, uid, MFA, ok)).error, 'PERMISSION_DENIED', uid);
  for (const bad of [
    { ...ok, minBuild: { android: -1, ios: 0 } }, { ...ok, minBuild: { android: 1.5, ios: 0 } }, { ...ok, minBuild: { android: '13', ios: 0 } }, { ...ok, minBuild: {} },
    { ...ok, maintenance: { enabled: true, message: '' } }, { ...ok, maintenance: { enabled: true, message: 'Back soon', untilMs: nowMs - 1000 } },
  ]) assert.equal((await po.setAppRequirements(ctx, 'owner', MFA, bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  assert.equal(db.store.has('platformSettings/app'), false);
  assert.equal((await po.setAppRequirements(ctx, 'owner', MFA, ok)).version, 1);
  const on = await po.setAppRequirements(ctx, 'owner', MFA, { minBuild: { android: 14, ios: 3 }, maintenance: { enabled: true, message: 'Back at 6am', untilMs: nowMs + 3600e3 } });
  assert.equal(on.version, 2);
  const s = db.store.get('platformSettings/app');
  assert.deepEqual(s.minBuild, { android: 14, ios: 3 });
  assert.equal(s.maintenance.enabled, true);
  assert.equal(s.maintenance.message, 'Back at 6am');
  await po.setAppRequirements(ctx, 'owner', MFA, ok);
  assert.equal(db.store.get('platformSettings/app').maintenance.message, '', 'switching it off clears the message');
  assert.equal(audits(db).filter((a) => a.action === 'APP_REQUIREMENTS_CHANGED').length, 3);
});

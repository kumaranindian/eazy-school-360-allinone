'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const pr = require('./platform_reads');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const NO_MFA = { firebase: { sign_in_provider: 'password' } };
const T = new Date('2026-11-13T10:00:00Z');
const admin = (role) => ({ role: 'PLATFORM_ADMIN', platformRole: role, status: 'ACTIVE', email: `${role}@avail404.com`, schoolId: null, login: { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'] } });
const grant = (over = {}) => ({ schoolId: 's1', adminUid: 'support', adminName: 'Asha', adminEmail: 'a@avail404.com', reason: 'r', ticket: null, expiresAt: new Date(T.getTime() + 3600e3), revokedAt: null, ...over });

function world() {
  const db = fakeDb({
    'users/owner': admin('OWNER'), 'users/support': admin('SUPPORT'), 'users/compliance': admin('COMPLIANCE'), 'users/viewer': admin('VIEWER'),
    'users/sa1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1' },
    'users/sa2': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's2' },
    'users/ba1': { role: 'BRANCH_ADMIN', status: 'ACTIVE', schoolId: 's1', branchId: 'b' },
    'users/t1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1' },
    'users/paused': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1', schoolAccess: 'SUSPENDED' },
    'supportGrants/support__s1': grant(),
    'supportGrants/support__s2': grant({ schoolId: 's2' }),
    'supportGrants/owner__s1': grant({ adminUid: 'owner' }),
    'schools/s1/supportAccessLog/e1': { event: 'GRANTED', adminName: 'Asha', adminEmail: 'a@avail404.com', reason: 'r', createdAt: new Date(T.getTime() - 5000) },
    'schools/s1/supportAccessLog/e2': { event: 'REVOKED', adminName: 'Asha', adminEmail: 'a@avail404.com', createdAt: new Date(T.getTime()) },
    'schools/s2/supportAccessLog/e3': { event: 'GRANTED', createdAt: T },
    'platformStats/current': { schools: { total: 3 }, computedAt: T, computedAtMs: T.getTime() },
    'platformAuditLog/a1': { action: 'X', actorEmail: 'o@a.com', createdAt: new Date(T.getTime() - 1000) },
    'platformAuditLog/a2': { action: 'Y', actorEmail: 'o@a.com', createdAt: T },
    'platformNotices/all': { title: 'All', body: 'b', severity: 'WARNING', audienceAll: true, schoolIds: [], status: 'ACTIVE', startsAt: T, endsAt: T },
    'platformNotices/s1only': { title: 'S1', body: 'b', audienceAll: false, schoolIds: ['s1'], status: 'ACTIVE', startsAt: T, endsAt: T },
    'platformNotices/s2only': { title: 'S2', body: 'b', audienceAll: false, schoolIds: ['s2'], status: 'WITHDRAWN', startsAt: T, endsAt: T },
  });
  return { db, ctx: { db } };
}

test('my support grants: owner/support with a second factor, only their own', async () => {
  const { ctx } = world();
  assert.equal((await pr.listMySupportGrants(ctx, 'support', NO_MFA)).error, 'MFA_REQUIRED');
  for (const uid of ['viewer', 'compliance', 'sa1', 'nobody']) assert.equal((await pr.listMySupportGrants(ctx, uid, MFA)).error, 'PERMISSION_DENIED', uid);
  const out = await pr.listMySupportGrants(ctx, 'support', MFA);
  assert.deepEqual(out.grants.map((g) => g.schoolId).sort(), ['s1', 's2']);
  assert.equal(out.grants[0].adminUid, 'support');
  assert.equal(out.grants[0].revoked, false);
  assert.equal(typeof out.grants[0].expiresAtMs, 'number');
});

test('school support access: only the SCHOOL admin of that school, never another school\'s data', async () => {
  const { ctx } = world();
  for (const uid of ['ba1', 't1', 'owner', 'nobody']) assert.equal((await pr.listSchoolSupportAccess(ctx, uid, MFA)).error, 'PERMISSION_DENIED', uid);
  assert.equal((await pr.listSchoolSupportAccess(ctx, 'paused', MFA)).error, 'PERMISSION_DENIED', 'a paused school is paused');
  const out = await pr.listSchoolSupportAccess(ctx, 'sa1', NO_MFA);
  assert.equal(out.schoolId, 's1');
  assert.deepEqual(out.grants.map((g) => `${g.adminUid}`).sort(), ['owner', 'support']);
  assert.ok(out.grants.every((g) => g.schoolId === 's1'));
  assert.deepEqual(out.log.map((e) => e.event), ['REVOKED', 'GRANTED'], 'newest first, own school only');
  const other = await pr.listSchoolSupportAccess(ctx, 'sa2', NO_MFA);
  assert.deepEqual(other.log.map((e) => e.event), ['GRANTED']);
});

test('stats: any platform role with a second factor; nobody else', async () => {
  const { ctx } = world();
  assert.equal((await pr.getPlatformStats(ctx, 'viewer', NO_MFA)).error, 'MFA_REQUIRED');
  for (const uid of ['sa1', 't1', 'nobody']) assert.equal((await pr.getPlatformStats(ctx, uid, MFA)).error, 'PERMISSION_DENIED', uid);
  for (const uid of ['owner', 'support', 'compliance', 'viewer']) {
    const out = await pr.getPlatformStats(ctx, uid, MFA);
    assert.equal(out.stats.schools.total, 3);
    assert.equal(out.stats.computedAtMs, T.getTime());
    assert.equal('computedAt' in out.stats, false, 'no raw timestamp in the response');
  }
  const empty = fakeDb({ 'users/owner': admin('OWNER') });
  assert.equal((await pr.getPlatformStats({ db: empty }, 'owner', MFA)).stats, null);
});

test('audit log: owner and compliance only, newest first', async () => {
  const { ctx } = world();
  assert.equal((await pr.listAuditLog(ctx, 'owner', NO_MFA)).error, 'MFA_REQUIRED');
  for (const uid of ['support', 'viewer', 'sa1']) assert.equal((await pr.listAuditLog(ctx, uid, MFA)).error, 'PERMISSION_DENIED', uid);
  for (const uid of ['owner', 'compliance']) {
    const out = await pr.listAuditLog(ctx, uid, MFA);
    assert.deepEqual(out.entries.map((e) => e.action), ['Y', 'X']);
  }
});

test('notices: school and branch admins get everyone\'s and their own school\'s; nobody else', async () => {
  const { ctx } = world();
  for (const uid of ['t1', 'owner', 'nobody']) assert.equal((await pr.listMyNotices(ctx, uid, MFA)).error, 'PERMISSION_DENIED', uid);
  assert.equal((await pr.listMyNotices(ctx, 'paused', MFA)).error, 'PERMISSION_DENIED');
  for (const uid of ['sa1', 'ba1']) {
    const out = await pr.listMyNotices(ctx, uid, NO_MFA);
    assert.deepEqual(out.notices.map((n) => n.id).sort(), ['all', 's1only'], uid);
    assert.equal(out.notices.find((n) => n.id === 'all').severity, 'WARNING');
  }
  const s2 = await pr.listMyNotices(ctx, 'sa2', NO_MFA);
  assert.deepEqual(s2.notices.map((n) => n.id).sort(), ['all', 's2only']);
  assert.equal(s2.notices.find((n) => n.id === 's2only').withdrawn, true);
});

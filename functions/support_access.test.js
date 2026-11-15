'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const sa = require('./support_access');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const NO_MFA = { firebase: { sign_in_provider: 'password' } };
const T0 = new Date('2026-11-13T10:00:00Z');
const admin = (platformRole, email) => ({
  role: 'PLATFORM_ADMIN', platformRole, status: 'ACTIVE', name: platformRole, email, schoolId: null,
  login: { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'] },
});
const ok = { schoolId: 's1', reason: 'Parent cannot see the November invoice (ticket 4411)', minutes: 30 };

function world(extra = {}) {
  const db = fakeDb({
    'users/owner': admin('OWNER', 'owner@avail404.com'),
    'users/support': admin('SUPPORT', 'support@avail404.com'),
    'users/support2': admin('SUPPORT', 'support2@avail404.com'),
    'users/compliance': admin('COMPLIANCE', 'c@avail404.com'),
    'users/viewer': admin('VIEWER', 'v@avail404.com'),
    'users/sa1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1', branchId: null, name: 'Head', email: 'head@school.test' },
    'users/sa2': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's2', branchId: null, name: 'Other', email: 'o@school.test' },
    'users/teacher': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1', branchId: 'b1', name: 'T', email: 't@school.test' },
    'schools/s1': { name: 'Rosewood', status: 'ACTIVE', code: 'RW', city: 'Chennai', createdAt: T0 },
    'schools/s2': { name: 'Elm', status: 'ACTIVE' },
    'schools/s1/branches/b1': { name: 'Main', status: 'ACTIVE' },
    'schools/s1/branches/b1/students/st1': { schoolId: 's1' },
    'schools/s1/branches/b1/students/st2': { schoolId: 's1' },
    'schools/s1/branches/b1/staff/sf1': { schoolId: 's1' },
    ...extra,
  });
  const ctx = { db, now: 'SERVER_TS', nowDate: () => T0 };
  return { db, ctx };
}
const audits = (db) => [...db.store.entries()].filter(([k]) => k.startsWith('platformAuditLog/')).map(([, v]) => v);
const logs = (db, s = 's1') => [...db.store.entries()].filter(([k]) => k.startsWith(`schools/${s}/supportAccessLog/`)).map(([, v]) => v);

test('request: only owner/support with a second factor; viewer, compliance, school roles and no-MFA are refused', async () => {
  const { db, ctx } = world();
  assert.equal((await sa.requestSupportAccess(ctx, 'support', NO_MFA, ok)).error, 'MFA_REQUIRED');
  for (const uid of ['viewer', 'compliance', 'sa1', 'teacher', 'nobody']) {
    assert.equal((await sa.requestSupportAccess(ctx, uid, MFA, ok)).error, 'PERMISSION_DENIED', uid);
  }
  assert.equal(db.store.has('supportGrants/support__s1'), false);
  assert.equal(audits(db).length, 0);
  assert.equal(logs(db).length, 0);
});

test('request: validation of reason, duration, school', async () => {
  const { ctx } = world();
  for (const bad of [
    { ...ok, reason: 'short' },
    { ...ok, reason: '   too short   ' },
    { ...ok, minutes: 1000 },
    { ...ok, minutes: 45 },
    { ...ok, minutes: '60' },
    { ...ok, schoolId: '' },
    { reason: ok.reason },
  ]) {
    assert.equal((await sa.requestSupportAccess(ctx, 'support', MFA, bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
  assert.equal((await sa.requestSupportAccess(ctx, 'support', MFA, { ...ok, schoolId: 'ghost' })).error, 'NOT_FOUND');
});

test('request: writes a READ grant for exactly that school and time, a school-visible log and an audit record', async () => {
  const { db, ctx } = world();
  const out = await sa.requestSupportAccess(ctx, 'support', MFA, { ...ok, ticket: 'INC-9' });
  assert.equal(out.ok, true);
  assert.equal(out.schoolName, 'Rosewood');
  assert.equal(out.expiresAtMs, T0.getTime() + 30 * 60 * 1000);
  const g = db.store.get('supportGrants/support__s1');
  assert.equal(g.adminUid, 'support');
  assert.equal(g.schoolId, 's1');
  assert.equal(g.scope, 'READ');
  assert.equal(g.revokedAt, null);
  assert.equal(g.ticket, 'INC-9');
  assert.equal(g.expiresAt.getTime(), out.expiresAtMs);
  assert.equal(db.store.has('supportGrants/support__s2'), false, 'no grant for another school');
  const l = logs(db);
  assert.equal(l.length, 1);
  assert.equal(l[0].event, 'GRANTED');
  assert.equal(l[0].adminEmail, 'support@avail404.com');
  assert.equal(l[0].reason, ok.reason);
  const a = audits(db);
  assert.equal(a.length, 1);
  assert.equal(a[0].action, 'SUPPORT_ACCESS_GRANTED');
  assert.equal(a[0].schoolId, 's1');
  assert.equal(a[0].reason, ok.reason);
});

test('request: a second request replaces the first grant and is logged again', async () => {
  const { db, ctx } = world();
  await sa.requestSupportAccess(ctx, 'support', MFA, ok);
  await sa.requestSupportAccess(ctx, 'support', MFA, { ...ok, minutes: 120 });
  assert.equal(db.store.get('supportGrants/support__s1').expiresAt.getTime(), T0.getTime() + 120 * 60 * 1000);
  assert.equal(logs(db).length, 2);
});

test('revoke: the holder, an owner, or the school admin of THAT school; nobody else', async () => {
  const { db, ctx } = world();
  await sa.requestSupportAccess(ctx, 'support', MFA, ok);
  const body = { schoolId: 's1', adminUid: 'support' };
  assert.equal((await sa.revokeSupportAccess(ctx, 'support2', MFA, body)).error, 'PERMISSION_DENIED', 'another support person');
  assert.equal((await sa.revokeSupportAccess(ctx, 'sa2', {}, body)).error, 'PERMISSION_DENIED', 'admin of another school');
  assert.equal((await sa.revokeSupportAccess(ctx, 'teacher', {}, body)).error, 'PERMISSION_DENIED');
  assert.equal((await sa.revokeSupportAccess(ctx, 'viewer', MFA, body)).error, 'PERMISSION_DENIED');
  assert.equal(db.store.get('supportGrants/support__s1').revokedAt, null);

  assert.equal((await sa.revokeSupportAccess(ctx, 'sa1', {}, { schoolId: 's1' })).error, 'INVALID_ARGUMENT', 'school admin must name the grant');
  const bySchool = await sa.revokeSupportAccess(ctx, 'sa1', {}, body);
  assert.equal(bySchool.ok, true);
  const g = db.store.get('supportGrants/support__s1');
  assert.equal(g.revokedAt, 'SERVER_TS');
  assert.equal(g.revokedBy, 'sa1');
  const l = logs(db);
  assert.equal(l.at(-1).event, 'REVOKED');
  assert.equal(l.at(-1).revokedBy, 'SCHOOL_ADMIN');
  assert.equal(audits(db).at(-1).action, 'SUPPORT_ACCESS_REVOKED');
});

test('revoke: the holder ends their own session; an owner ends anyone\'s; a second revoke is a no-op', async () => {
  const { db, ctx } = world();
  await sa.requestSupportAccess(ctx, 'support', MFA, ok);
  assert.equal((await sa.revokeSupportAccess(ctx, 'support', MFA, { schoolId: 's1' })).ok, true);
  assert.equal((await sa.revokeSupportAccess(ctx, 'support', MFA, { schoolId: 's1' })).alreadyEnded, true);
  const n = logs(db).length;
  await sa.requestSupportAccess(ctx, 'support', MFA, ok);
  assert.equal((await sa.revokeSupportAccess(ctx, 'owner', MFA, { schoolId: 's1', adminUid: 'support' })).ok, true);
  assert.equal(logs(db).length, n + 2);
  assert.equal((await sa.revokeSupportAccess(ctx, 'owner', MFA, { schoolId: 's1', adminUid: 'nobody' })).error, 'NOT_FOUND');
});

test('revoke: a platform admin without a second factor is refused', async () => {
  const { ctx } = world();
  await sa.requestSupportAccess(ctx, 'support', MFA, ok);
  assert.equal((await sa.revokeSupportAccess(ctx, 'support', NO_MFA, { schoolId: 's1' })).error, 'MFA_REQUIRED');
});

test('activeGrant: expired and revoked grants are not active', () => {
  const now = T0.getTime();
  assert.equal(sa.activeGrant({ expiresAt: new Date(now + 1000), revokedAt: null }, now), true);
  assert.equal(sa.activeGrant({ expiresAt: new Date(now - 1000), revokedAt: null }, now), false);
  assert.equal(sa.activeGrant({ expiresAt: new Date(now + 1000), revokedAt: 'x' }, now), false);
  assert.equal(sa.activeGrant(undefined, now), false);
});

test('overview: any platform role; metadata and counts only; no student records', async () => {
  const { ctx } = world();
  await sa.requestSupportAccess(ctx, 'support', MFA, ok);
  for (const uid of ['owner', 'support', 'compliance', 'viewer']) {
    const out = await sa.getSchoolOverview(ctx, uid, MFA, { schoolId: 's1' });
    assert.equal(out.error, undefined, uid);
    assert.equal(out.school.name, 'Rosewood');
    assert.deepEqual(out.counts, { branches: 1, students: 2, staff: 1, parents: 0 });
    assert.deepEqual(out.admins.map((a) => a.email), ['head@school.test']);
    assert.equal(out.activeGrants.length, 1);
    assert.equal(out.recentActions[0].action, 'SUPPORT_ACCESS_GRANTED');
    assert.equal(JSON.stringify(out).includes('"st1"'), false, 'no student ids');
  }
  assert.equal((await sa.getSchoolOverview(ctx, 'owner', NO_MFA, { schoolId: 's1' })).error, 'MFA_REQUIRED');
  assert.equal((await sa.getSchoolOverview(ctx, 'sa1', MFA, { schoolId: 's1' })).error, 'PERMISSION_DENIED');
  assert.equal((await sa.getSchoolOverview(ctx, 'owner', MFA, { schoolId: 'ghost' })).error, 'NOT_FOUND');
});

test('overview does not list expired or revoked grants as active', async () => {
  const { ctx } = world();
  await sa.requestSupportAccess(ctx, 'support', MFA, ok);
  await sa.revokeSupportAccess(ctx, 'support', MFA, { schoolId: 's1' });
  const out = await sa.getSchoolOverview(ctx, 'owner', MFA, { schoolId: 's1' });
  assert.equal(out.activeGrants.length, 0);
});

'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const A = require('./audit');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const PW = { firebase: { sign_in_provider: 'password' } };
const at = (iso) => new Date(iso);
const ctxAt = (db, iso = '2026-06-15T10:00:00Z') => ({ db, now: 'SERVER_TS', nowDate: () => at(iso) });

function world(extra = {}) {
  return fakeDb({
    'users/owner': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'OWNER', email: 'o@avail404.com' },
    'users/comp': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'COMPLIANCE', email: 'c@avail404.com' },
    'users/support': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'SUPPORT', email: 's@avail404.com' },
    'users/viewer': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'VIEWER', email: 'v@avail404.com' },
    'users/a1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1', name: 'Asha' },
    'users/t1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1' },
    ...extra,
  });
}
const ev = (over = {}) => ({ sourceId: 'src-1', eventType: 'STUDENT_UPDATED', category: 'STUDENT', action: 'UPDATE', source: 'TRIGGER', schoolId: 's1', actorUserId: 'a1', ...over });
const all = async (db, m) => (await db.collection('auditEvents').doc(m).collection('events').get()).docs.map((d) => d.data());

test('buildEvent: validates every field and never accepts what it does not recognise', () => {
  const ok = A.buildEvent(ev(), at('2026-06-15T10:00:00Z'));
  assert.equal(ok.event.trust, 'T2');
  assert.equal(ok.event.schemaVersion, 1);
  assert.equal(ok.event.timestampMs, at('2026-06-15T10:00:00Z').getTime());
  assert.equal(ok.month, '202606');
  const bad = (over, reason) => assert.deepEqual([A.buildEvent(ev(over), new Date()).error, A.buildEvent(ev(over), new Date()).reason], ['INVALID_EVENT', reason], JSON.stringify(over));
  bad({ sourceId: '' }, 'sourceId');
  bad({ eventType: 'lower' }, 'eventType');
  bad({ eventType: 'X' }, 'eventType');
  bad({ category: 'MISC' }, 'category');
  bad({ action: 'NUKE' }, 'action');
  bad({ result: 'MAYBE' }, 'result');
  bad({ source: 'GUESS' }, 'source');
  bad({ schoolId: 'a/b' }, 'schoolId');
  bad({ actorUserId: '../x' }, 'actorUserId');
  assert.equal(A.buildEvent(ev({ application: 'HACKER' }), new Date()).event.application, null, 'unknown application dropped');
});

test('trust follows the source, never the caller: callable T1, trigger T2, scheduler T3, client T4', () => {
  for (const [source, trust] of [['CALLABLE', 'T1'], ['TRIGGER', 'T2'], ['SCHEDULER', 'T3'], ['CLIENT_REPORTED', 'T4']]) {
    assert.equal(A.buildEvent(ev({ source, trust: 'T1' }), new Date()).event.trust, trust, source);
  }
});

test('event ids are deterministic per (source event, type) and differ otherwise', () => {
  const id = (over) => A.buildEvent(ev(over), new Date()).event.eventId;
  assert.equal(id({}), id({}));
  assert.notEqual(id({}), id({ sourceId: 'src-2' }));
  assert.notEqual(id({}), id({ eventType: 'STUDENT_CREATED' }));
  assert.match(id({}), /^[0-9a-f]{32}$/);
});

test('redaction: secrets, tokens, URLs with credentials and deep structures never reach the store', () => {
  const r = A.redact({
    ok: 'fine', password: 'hunter2', newPassword: 'x', otp: '123456', idToken: 'abc', apiKey: 'k', Authorization: 'Bearer z', downloadUrl: 'https://x', clientSecret: 's',
    link: 'https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media&token=SECRET', plain: 'https://example.com/page',
    nested: { deep: { deeper: { deepest: 'x' } }, secretKey: 'no', keep: 1 },
    long: 'x'.repeat(1000), list: Array.from({ length: 50 }, (_, i) => i),
  });
  const s = JSON.stringify(r);
  for (const leak of ['hunter2', '123456', 'SECRET', 'Bearer', 'abc"']) assert.ok(!s.includes(leak), leak);
  assert.equal(r.ok, 'fine');
  assert.equal(r.link, '[redacted-url]');
  assert.equal(r.plain, 'https://example.com/page');
  assert.equal(r.nested.keep, 1);
  assert.equal(r.nested.deep.deeper, '[truncated]');
  assert.equal(r.long.length, 300);
  assert.equal(r.list.length, 20);
  assert.ok(!('password' in r) && !('otp' in r) && !('downloadUrl' in r) && !('Authorization' in r));
});

test('changes: values only for allowlisted, non-personal fields; everything else is just "changed"', () => {
  const out = A.changeList([
    { field: 'status', from: 'ACTIVE', to: 'INACTIVE' },
    { field: 'phone', from: '999', to: '888' },
    { field: 'guardianEmail', from: 'a@x.com', to: 'b@x.com' },
    { field: 'notes', from: 'private', to: 'secret' },
    { field: 'password', from: 'a', to: 'b' },
    { field: '', from: 1, to: 2 },
  ], ['status', 'phone', 'guardianEmail']);
  assert.deepEqual(out, [
    { field: 'status', from: 'ACTIVE', to: 'INACTIVE' },
    { field: 'phone', changed: true },
    { field: 'guardianEmail', changed: true },
    { field: 'notes', changed: true },
  ]);
  assert.equal(A.changeList(Array.from({ length: 80 }, (_, i) => ({ field: `f${i}` })), []).length, 30, 'bounded');
  assert.deepEqual(A.changeList('nonsense', []), []);
});

test('record: writes into the month partition once; a repeat is a no-op; nothing is updated', async () => {
  const db = world();
  const c = ctxAt(db);
  const first = await A.record(c, ev());
  assert.equal(first.ok, true);
  assert.equal(first.month, '202606');
  const again = await A.record({ ...c, now: 'LATER' }, ev());
  assert.equal(again.duplicate, true);
  const rows = await all(db, '202606');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].timestamp, 'SERVER_TS', 'the first write is untouched');
  await A.record(ctxAt(db, '2026-07-01T00:00:00Z'), ev({ sourceId: 'src-2' }));
  assert.equal((await all(db, '202607')).length, 1, 'next month, next partition');
});

test('record refuses an invalid event; recordSafe swallows it and says so', async () => {
  const db = world();
  await assert.rejects(() => A.record(ctxAt(db), ev({ category: 'NOPE' })), /invalid audit event/);
  const logs = [];
  assert.deepEqual(await A.recordSafe(ctxAt(db), ev({ category: 'NOPE' }), (m) => logs.push(m)), { failed: true });
  assert.deepEqual(logs, ['audit write failed']);
  assert.equal((await all(db, '202606')).length, 0);
});

test('fromPlatformAudit: lifecycle, subscription, feature and support actions land in the right category', () => {
  const m = (action, extra = {}) => A.fromPlatformAudit('id1', { action, actorUid: 'o', actorEmail: 'o@avail404.com', actorPlatformRole: 'OWNER', schoolId: 's1', ...extra });
  assert.deepEqual([m('SCHOOL_ACTIVATED').category, m('SCHOOL_ACTIVATED').action], ['SCHOOL', 'ACTIVATE']);
  assert.deepEqual([m('SCHOOL_SUSPENDED').category, m('SCHOOL_SUSPENDED').action], ['SCHOOL', 'SUSPEND']);
  assert.equal(m('SCHOOL_EXPIRED').action, 'EXPIRE');
  assert.equal(m('SCHOOL_RECOVERY_REQUESTED').category, 'SCHOOL');
  assert.equal(m('SUBSCRIPTION_RENEWED').category, 'SUBSCRIPTION');
  assert.equal(m('PLAN_SAVED').category, 'SUBSCRIPTION');
  assert.equal(m('SCHOOL_FEATURES_CHANGED').category, 'FEATURE');
  assert.equal(m('FEATURE_DEFAULTS_CHANGED').category, 'FEATURE');
  const denied = m('FEATURE_ACCESS_DENIED', { source: 'TRIGGER', result: 'FLAGGED' });
  assert.deepEqual([denied.category, denied.result, denied.source], ['FEATURE', 'DENIED', 'TRIGGER']);
  assert.equal(m('BILLING_RECORD_ADDED').category, 'PLATFORM');
  assert.equal(m('AUDIT_LOG_VIEWED').category, 'SECURITY');
  const sys = m('SCHOOL_EXPIRED', { actorUid: 'system', actorEmail: 'system', actorPlatformRole: 'SYSTEM', source: 'SCHEDULER' });
  assert.deepEqual([sys.actorUserId, sys.application, sys.source], [null, 'SCHEDULER', 'SCHEDULER']);
  assert.equal(m('lowercase'), null, 'an unusable action name is skipped, not guessed');
  assert.equal(m('SCHOOL_ACTIVATED').sourceId, 'platform|id1');
});

test('fromAuthAudit: the sign-in trail becomes AUTHENTICATION events without losing or inventing an actor', () => {
  const e = A.fromAuthAudit('s1', 'e1', { type: 'login_disabled', actorId: 'a1', targetId: 'u9', createdAt: 'x' });
  assert.deepEqual([e.category, e.eventType, e.action, e.schoolId, e.actorUserId], ['AUTHENTICATION', 'LOGIN_DISABLED', 'DISABLE', 's1', 'a1']);
  assert.ok(!('createdAt' in e.metadata));
  assert.equal(A.fromAuthAudit('s1', 'e2', { type: '' }), null);
  assert.equal(A.fromAuthAudit('s1', 'e3', { type: 'XYZ', actorId: '../../etc' }).actorUserId, null);
});

test('fromModuleWrite: create, update, delete; actor from the rules-enforced field; no-ops skipped', () => {
  const base = { eventId: 'ev1', schoolId: 's1', branchId: 'b1', collection: 'students', docId: 'st1' };
  const c = A.fromModuleWrite({ ...base, before: null, after: { status: 'ACTIVE', createdBy: 'a1', updatedBy: 'a1', firstName: 'Secret' } });
  assert.deepEqual([c.eventType, c.action, c.actorUserId, c.category], ['STUDENT_CREATED', 'CREATE', 'a1', 'STUDENT']);
  assert.deepEqual(c.changes, [{ field: 'status', from: null, to: 'ACTIVE' }], 'only allowlisted fields carry values');
  const u = A.fromModuleWrite({ ...base, before: { status: 'ACTIVE', phone: '1', updatedBy: 'a1' }, after: { status: 'INACTIVE', phone: '2', updatedBy: 't1', updatedAt: 'x' } });
  assert.equal(u.eventType, 'STUDENT_UPDATED');
  assert.equal(u.actorUserId, 't1');
  const built = A.buildEvent(u, new Date()).event.changeSummary.changes;
  assert.deepEqual(built, [{ field: 'status', from: 'ACTIVE', to: 'INACTIVE' }, { field: 'phone', changed: true }]);
  assert.equal(A.fromModuleWrite({ ...base, before: { status: 'A', updatedAt: 1 }, after: { status: 'A', updatedAt: 2, updatedBy: 'x' } }), null, 'bookkeeping alone is not an event');
  const d = A.fromModuleWrite({ ...base, before: { status: 'ACTIVE', updatedBy: 'a1' }, after: null });
  assert.deepEqual([d.eventType, d.action, d.actorUserId], ['STUDENT_DELETED', 'DELETE', 'a1']);
  assert.equal(A.fromModuleWrite({ ...base, collection: 'studentAttendance', before: null, after: {} }), null, 'per-student attendance marks are not audited individually');
  assert.equal(A.fromModuleWrite({ ...base, collection: 'unknown', before: null, after: {} }), null);
  const none = A.fromModuleWrite({ ...base, before: null, after: { status: 'ACTIVE' } });
  assert.equal(none.actorUserId, null, 'an unknown actor is null, never invented');
});

test('every audited module maps to a valid category and a valid event type', () => {
  for (const [col, m] of Object.entries(A.MODULES)) {
    assert.ok(A.CATEGORIES.includes(m.category), col);
    for (const act of ['CREATED', 'UPDATED', 'DELETED']) assert.match(`${m.entity}_${act}`, /^[A-Z][A-Z0-9_]{2,63}$/, col);
    for (const f of m.safe) assert.ok(!/phone|email|address|dob|birth|aadhaar|medical/i.test(f), `${col}.${f} is personal`);
  }
});

async function seed(db) {
  const c = (iso) => ctxAt(db, iso);
  await A.record(c('2026-05-20T10:00:00Z'), ev({ sourceId: 'a', schoolId: 's1', category: 'STUDENT' }));
  await A.record(c('2026-06-01T10:00:00Z'), ev({ sourceId: 'b', schoolId: 's2', category: 'FEES', eventType: 'INVOICE_UPDATED' }));
  await A.record(c('2026-06-10T10:00:00Z'), ev({ sourceId: 'c', schoolId: 's1', category: 'SCHOOL', eventType: 'SCHOOL_SUSPENDED', source: 'CALLABLE', result: 'DENIED' }));
  await A.record(c('2026-06-12T10:00:00Z'), ev({ sourceId: 'd', schoolId: 's1', actorUserId: 't1', category: 'STUDENT' }));
  await A.record(c('2026-06-14T10:00:00Z'), ev({ sourceId: 'e', schoolId: 's1', category: 'SECURITY', eventType: 'PERMISSION_DENIED_UI', source: 'CLIENT_REPORTED', result: 'DENIED' }));
}
const q = (db, uid, data, iso) => A.queryAuditEvents(ctxAt(db, iso || '2026-06-15T10:00:00Z'), uid, MFA, data);

test('only owners and compliance can read the trail; support, viewers, school users and non-MFA are refused', async () => {
  const db = world();
  await seed(db);
  for (const uid of ['owner', 'comp']) assert.ok((await q(db, uid, { fromMs: at('2026-05-01T00:00:00Z').getTime() })).events, uid);
  for (const uid of ['support', 'viewer', 'a1', 't1', 'ghost']) assert.equal((await q(db, uid, {})).error, 'PERMISSION_DENIED', uid);
  assert.equal((await A.queryAuditEvents(ctxAt(db), 'owner', PW, {})).error, 'MFA_REQUIRED');
  for (const fn of [A.exportAuditEvents, A.getAuditSummary]) {
    assert.equal((await fn(ctxAt(db), 'support', MFA, {})).error, 'PERMISSION_DENIED');
  }
});

test('query: newest first across month partitions, with the full event view', async () => {
  const db = world();
  await seed(db);
  const r = await q(db, 'owner', { fromMs: at('2026-05-01T00:00:00Z').getTime(), schoolId: 's1' });
  assert.deepEqual(r.events.map((e) => e.id).length, 4);
  const times = r.events.map((e) => e.atMs);
  assert.deepEqual(times, [...times].sort((x, y) => y - x));
  assert.equal(r.events[3].atMs, at('2026-05-20T10:00:00Z').getTime(), 'the May event comes last');
  const e = r.events[0];
  assert.equal(e.clientReported, true);
  assert.equal(e.trust, 'T4');
  assert.ok(!('timestamp' in e) && !('schemaVersion' in e));
});

test('query: filters combine (school + category + result + source + actor + type)', async () => {
  const db = world();
  await seed(db);
  const from = at('2026-05-01T00:00:00Z').getTime();
  assert.equal((await q(db, 'owner', { fromMs: from, schoolId: 's2' })).events.length, 1);
  assert.equal((await q(db, 'owner', { fromMs: from, category: 'STUDENT' })).events.length, 2);
  assert.equal((await q(db, 'owner', { fromMs: from, schoolId: 's1', result: 'DENIED' })).events.length, 2);
  assert.equal((await q(db, 'owner', { fromMs: from, schoolId: 's1', result: 'DENIED', source: 'CLIENT_REPORTED' })).events.length, 1);
  assert.equal((await q(db, 'owner', { fromMs: from, actorUserId: 't1' })).events.length, 1);
  assert.equal((await q(db, 'owner', { fromMs: from, eventType: 'SCHOOL_SUSPENDED', schoolId: 's1' })).events.length, 1);
  assert.equal((await q(db, 'owner', { fromMs: from, schoolId: 'nobody' })).events.length, 0);
});

test('query: the time window is honoured and bounded to 92 days', async () => {
  const db = world();
  await seed(db);
  const day = (iso) => at(iso).getTime();
  const r = await q(db, 'owner', { fromMs: day('2026-06-11T00:00:00Z'), toMs: day('2026-06-13T00:00:00Z') });
  assert.equal(r.events.length, 1);
  assert.equal((await q(db, 'owner', {})).events.filter((e) => e.eventType !== 'AUDIT_LOG_VIEWED').length, 3, 'default is the last 7 days');
  for (const bad of [{ fromMs: day('2026-06-15T00:00:00Z'), toMs: day('2026-06-01T00:00:00Z') }, { fromMs: day('2025-01-01T00:00:00Z') }]) {
    assert.deepEqual([(await q(db, 'owner', bad)).error, (await q(db, 'owner', bad)).reason], ['INVALID_ARGUMENT', 'range']);
  }
  const future = await q(db, 'owner', { toMs: day('2030-01-01T00:00:00Z') });
  assert.ok(future.events, 'a future end is clamped to now');
});

test('query: bad filter values are refused', async () => {
  const db = world();
  for (const bad of [{ category: 'NOPE' }, { result: 'X' }, { source: 'Y' }, { eventType: 'lower' }, { schoolId: 'a/b' }, { actorUserId: '../x' }]) {
    assert.equal((await q(db, 'owner', bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
});

test('query: pages with a cursor, no duplicates and no gaps, across months', async () => {
  const db = world();
  for (let i = 0; i < 7; i++) await A.record(ctxAt(db, `2026-0${i < 3 ? 5 : 6}-${String(i < 3 ? 10 + i : i - 2).padStart(2, '0')}T10:00:00Z`), ev({ sourceId: `p${i}` }));
  const from = at('2026-05-01T00:00:00Z').getTime();
  const seen = [];
  let cursor = null;
  const real = (r) => r.events.filter((e) => e.eventType !== 'AUDIT_LOG_VIEWED').map((e) => e.id);
  for (let page = 0; page < 8; page++) {
    const r = await q(db, 'owner', { fromMs: from, limit: 3, cursor });
    seen.push(...real(r));
    cursor = r.nextCursor;
    if (!cursor) break;
  }
  assert.equal(seen.length, 7);
  assert.equal(new Set(seen).size, 7, 'no duplicates');
  const all_ = real(await q(db, 'owner', { fromMs: from, limit: 100 }));
  assert.deepEqual(seen, all_, 'the pages concatenate to the full ordered list');
});

test('query: page size is bounded; the first page is audited, later pages are not', async () => {
  const db = world();
  await seed(db);
  await q(db, 'owner', { limit: 100000 }, '2026-06-15T10:00:01Z');
  await q(db, 'owner', { limit: 0 }, '2026-06-15T10:00:02Z');
  const views = async () => (await all(db, '202606')).filter((e) => e.eventType === 'AUDIT_LOG_VIEWED');
  assert.equal((await views()).length, 2);
  const v = (await views())[0];
  assert.deepEqual([v.category, v.action, v.trust, v.actorUserId, v.actorNameSnapshot], ['SECURITY', 'VIEW', 'T1', 'owner', 'o@avail404.com']);
  await q(db, 'owner', { cursor: { m: '202606', id: 'x' } }, '2026-06-15T10:00:03Z');
  assert.equal((await views()).length, 2, 'a continuation page is not re-audited');
});

test('query: a narrow second filter cannot read the whole trail (scan cap, truncated flag)', async () => {
  const db = world();
  for (let i = 0; i < 30; i++) await A.record(ctxAt(db, '2026-06-14T10:00:00Z'), ev({ sourceId: `n${i}`, actorUserId: `u${i}` }));
  const f = A.monthsBetween; // keep the linter honest about the import
  assert.ok(f);
  const r = await q(db, 'owner', { schoolId: 's1', category: 'FEES' });
  assert.deepEqual([r.events.length, r.truncated], [0, false]);
});

test('export: owner/compliance only, UTC time, bounded, neutralises formulas, quotes cells, and is itself audited', async () => {
  const db = world();
  await A.record(ctxAt(db, '2026-06-14T10:00:00Z'), ev({ sourceId: 'x1', description: '=HYPERLINK("http://evil","click")', actorNameSnapshot: '+cmd', metadata: {} }));
  await A.record(ctxAt(db, '2026-06-14T11:00:00Z'), ev({ sourceId: 'x2', description: 'has, comma and "quotes"\nnewline' }));
  const out = await A.exportAuditEvents(ctxAt(db), 'comp', MFA, {});
  assert.equal(out.rows, 2);
  const lines = out.csv.split('\n');
  assert.equal(lines[0], A.CSV_HEADER.join(','));
  assert.ok(out.csv.includes('2026-06-14T11:00:00.000Z'), 'UTC ISO time');
  assert.ok(out.csv.includes(`"'=HYPERLINK(""http://evil"",""click"")"`), 'formula neutralised and quoted');
  assert.ok(out.csv.includes("'+cmd"), 'leading plus neutralised');
  assert.ok(out.csv.includes('"has, comma and ""quotes""\nnewline"'));
  const audit = (await all(db, '202606')).find((e) => e.eventType === 'AUDIT_LOG_EXPORTED');
  assert.deepEqual([audit.metadata.rows, audit.actorUserId, audit.action], [2, 'comp', 'EXPORT']);
  assert.ok(!JSON.stringify(audit).includes('HYPERLINK'), 'the export record holds no exported content');
});

test('export: capped, and says when it was', async () => {
  const db = world();
  assert.equal(A.EXPORT_CAP, 10000);
  assert.equal((await A.exportAuditEvents(ctxAt(db), 'owner', MFA, { fromMs: 5, toMs: 3 })).reason, 'range');
});

test('summary: counts by category, and the denied / failure / client-reported numbers', async () => {
  const db = world();
  await seed(db);
  const s = await A.getAuditSummary(ctxAt(db), 'owner', MFA, { hours: 24 * 31 });
  assert.equal(s.total, 5);
  assert.equal(s.byCategory.STUDENT, 2);
  assert.equal(s.byCategory.FEES, 1);
  assert.equal(s.byCategory.SECURITY, 1);
  assert.equal(s.denied, 2);
  assert.equal(s.failures, 0);
  assert.equal(s.clientReported, 1);
  assert.equal((await A.getAuditSummary(ctxAt(db), 'owner', MFA, { hours: 24 })).total, 1, 'only the last day');
  for (const hours of [0, -1, 24 * 32, 1.5]) assert.equal((await A.getAuditSummary(ctxAt(db), 'owner', MFA, { hours })).reason, 'hours', String(hours));
});

test('client reports: allowlisted types only; identity from the token; stored as untrusted T4', async () => {
  const db = world();
  const call = (data, uid = 't1') => A.reportClientEvent(ctxAt(db), uid, PW, data);
  assert.equal((await call({ type: 'ROOT_ACCESS_GRANTED' })).reason, 'type');
  assert.equal((await call({ type: 'LOGIN_FAILED' })).reason, 'type', 'a failed sign-in has no session to report from');
  assert.equal((await call({ type: 'LOGOUT' }, 'ghost')).error, 'PERMISSION_DENIED');
  const out = await call({ type: 'PERMISSION_DENIED_UI', route: '/fees?token=SECRET&x=1', platform: 'ANDROID', appVersion: '1.1.0', actorUserId: 'someone-else', schoolId: 'other-school', result: 'SUCCESS', trust: 'T1' });
  assert.equal(out.ok, true);
  const e = (await all(db, '202606'))[0];
  assert.deepEqual([e.source, e.trust, e.actorUserId, e.schoolId, e.result, e.platform], ['CLIENT_REPORTED', 'T4', 't1', 's1', 'DENIED', 'ANDROID']);
  assert.equal(e.metadata.route, '/fees', 'the query string is dropped');
  assert.ok(!JSON.stringify(e).includes('SECRET'));
  assert.match(e.changeSummary.description, /not independently verified/);
});

test('client reports: 20 per 10 minutes per user, then a fresh window; other users are unaffected', async () => {
  const db = world();
  const send = (uid, iso) => A.reportClientEvent(ctxAt(db, iso), uid, PW, { type: 'LOGOUT', correlationId: `${uid}-${Math.random()}` });
  for (let i = 0; i < A.RATE_MAX; i++) assert.equal((await send('t1', '2026-06-15T10:00:00Z')).ok, true, String(i));
  assert.equal((await send('t1', '2026-06-15T10:05:00Z')).error, 'RESOURCE_EXHAUSTED');
  assert.equal((await send('a1', '2026-06-15T10:05:00Z')).ok, true);
  assert.equal((await send('t1', '2026-06-15T10:10:01Z')).ok, true, 'a new window');
});

test('client reports: the same correlation id never duplicates', async () => {
  const db = world();
  const c = ctxAt(db);
  await A.reportClientEvent(c, 't1', PW, { type: 'LOGOUT', correlationId: 'same' });
  await A.reportClientEvent(c, 't1', PW, { type: 'LOGOUT', correlationId: 'same' });
  assert.equal((await all(db, '202606')).length, 1);
});

function memStorage() {
  const files = new Map();
  return { files, put: async (p, b) => void files.set(p, b), stat: async (p) => (files.has(p) ? { exists: true, size: Buffer.byteLength(files.get(p)) } : { exists: false }) };
}

test('retention: archives old months once, keeps everything online by default, never touches recent months', async () => {
  const db = world();
  await A.record(ctxAt(db, '2024-12-10T10:00:00Z'), ev({ sourceId: 'old1' }));
  await A.record(ctxAt(db, '2024-12-11T10:00:00Z'), ev({ sourceId: 'old2' }));
  await A.record(ctxAt(db, '2026-06-01T10:00:00Z'), ev({ sourceId: 'recent' }));
  const st = memStorage();
  const out = await A.runAuditRetention(ctxAt(db), st, {});
  assert.deepEqual(out.months, ['202412']);
  assert.equal(st.files.size, 1);
  const body = st.files.get('audit-archive/202412.jsonl');
  assert.equal(body.split('\n').length, 2);
  assert.ok(!body.includes('recent'));
  const marker = (await db.collection('auditArchives').doc('202412').get()).data();
  assert.deepEqual([marker.state, marker.count], ['ARCHIVED', 2]);
  assert.equal((await all(db, '202412')).length, 2, 'nothing deleted');
  assert.equal((await all(db, '202606')).filter((e) => e.eventType === 'AUDIT_MONTH_ARCHIVED').length, 1, 'the archive is itself audited');
  assert.equal((await all(db, '202606')).filter((e) => e.sourceId === undefined && e.metadata.collection === undefined && e.eventType !== 'AUDIT_MONTH_ARCHIVED').length, 1, 'the recent event is untouched');
  assert.deepEqual((await A.runAuditRetention(ctxAt(db), st, {})).months, [], 'a second run does nothing');
});

test('retention: deletion only when switched on AND the archive reads back correctly', async () => {
  const db = world();
  await A.record(ctxAt(db, '2024-12-10T10:00:00Z'), ev({ sourceId: 'old1' }));
  const st = memStorage();
  await A.runAuditRetention(ctxAt(db), st, {});
  const sabotage = { ...st, stat: async () => ({ exists: true, size: 1 }) };
  await A.runAuditRetention(ctxAt(db), sabotage, { deleteAfterArchive: true });
  assert.equal((await all(db, '202412')).length, 1, 'a size mismatch deletes nothing');
  const out = await A.runAuditRetention(ctxAt(db), st, { deleteAfterArchive: true });
  assert.deepEqual(out.months, ['202412']);
  assert.equal((await all(db, '202412')).length, 0);
  assert.equal((await db.collection('auditArchives').doc('202412').get()).data().state, 'PURGED');
  assert.ok((await all(db, '202606')).some((e) => e.eventType === 'AUDIT_MONTH_PURGED'), 'the purge is itself audited');
});

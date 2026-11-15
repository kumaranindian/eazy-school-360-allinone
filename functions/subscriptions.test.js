'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const S = require('./subscriptions');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const NOW = new Date('2026-06-15T10:00:00Z');
const ctxOf = (db, now = NOW) => ({ db, now: 'NOW', nowDate: () => now });

function world(extra = {}) {
  return fakeDb({
    'schools/s1': { name: 'S1', status: 'ACTIVE', timezone: 'Asia/Kolkata' },
    'schools/s2': { name: 'S2', status: 'ACTIVE', timezone: 'Pacific/Auckland' },
    'users/owner': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'OWNER', email: 'o@avail404.com' },
    'users/support': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'SUPPORT', email: 's@avail404.com' },
    'users/viewer': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'VIEWER', email: 'v@avail404.com' },
    'users/teacher': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1' },
    'platformPlans/annual': { name: 'Annual', periodType: 'ANNUAL', active: true },
    'platformPlans/old': { name: 'Old', periodType: 'MONTHLY', active: false },
    ...extra,
  });
}
const sub = (over = {}) => ({ planId: 'annual', classification: 'PAID', startDate: '2026-04-01', endDate: '2027-03-31', gracePeriodDays: 0, ...over });
const base = { schoolId: 's1', planId: 'annual', classification: 'PAID', startDate: '2026-04-01', endDate: '2027-03-31' };
const get = async (db, id = 's1') => (await db.collection('schoolSubscriptions').doc(id).get()).data();
const hist = async (db) => (await db.collection('schoolSubscriptionHistory').get()).docs.map((d) => d.data());

test('statusAt: every status, with inclusive end date and start date', () => {
  const at = (s, iso, zone = 'UTC') => S.statusAt(s, new Date(iso), zone);
  assert.equal(at(sub(), '2026-03-31T12:00:00Z'), 'NOT_STARTED');
  assert.equal(at(sub(), '2026-04-01T00:00:00Z'), 'ACTIVE');
  assert.equal(at(sub({ classification: 'TRIAL' }), '2026-05-01T00:00:00Z'), 'TRIAL');
  assert.equal(at(sub(), '2027-03-31T23:59:59.999Z'), 'ACTIVE', 'valid through the last millisecond of the end date');
  assert.equal(at(sub(), '2027-04-01T00:00:00Z'), 'EXPIRED');
  assert.equal(at(sub({ gracePeriodDays: 3 }), '2027-04-03T23:59:59Z'), 'GRACE_PERIOD');
  assert.equal(at(sub({ gracePeriodDays: 3 }), '2027-04-04T00:00:00Z'), 'EXPIRED');
  assert.equal(at(sub({ cancelled: true }), '2026-06-01T00:00:00Z'), 'CANCELLED');
  assert.equal(S.statusAt(null, NOW, 'UTC'), null, 'no subscription = legacy');
  assert.equal(S.statusAt({ startDate: 'x', endDate: 'y' }, NOW, 'UTC'), null, 'unreadable dates never guess a status');
});

test('statusAt: the boundary is the SCHOOL\'s midnight, not UTC (time zone edges)', () => {
  const s = sub({ startDate: '2026-06-16', endDate: '2026-06-30' });
  // 2026-06-15 19:00Z is 2026-06-16 00:30 in Kolkata (UTC+5:30) but still the 15th in New York.
  const t = new Date('2026-06-15T19:00:00Z');
  assert.equal(S.statusAt(s, t, 'Asia/Kolkata'), 'ACTIVE');
  assert.equal(S.statusAt(s, t, 'America/New_York'), 'NOT_STARTED');
  // End date 30th: Kolkata is already on the 1st at 2026-06-30 18:30Z; Los Angeles is not.
  const e = new Date('2026-06-30T19:00:00Z');
  assert.equal(S.statusAt(s, e, 'Asia/Kolkata'), 'EXPIRED');
  assert.equal(S.statusAt(s, e, 'America/Los_Angeles'), 'ACTIVE');
  assert.equal(S.statusAt(s, e, 'Not/AZone'), 'ACTIVE', 'an invalid zone falls back to UTC');
});

test('statusAt: DST days do not shift calendar arithmetic', () => {
  const s = sub({ startDate: '2026-03-01', endDate: '2026-03-08', gracePeriodDays: 2 });
  assert.equal(S.statusAt(s, new Date('2026-03-10T12:00:00Z'), 'America/New_York'), 'GRACE_PERIOD', 'across the US spring-forward');
  assert.equal(S.statusAt(s, new Date('2026-03-11T12:00:00Z'), 'America/New_York'), 'EXPIRED');
});

test('validDate refuses impossible dates', () => {
  for (const ok of ['2026-02-28', '2028-02-29']) assert.equal(S.validDate(ok), true, ok);
  for (const bad of ['2026-02-30', '2027-02-29', '2026-13-01', '2026-1-1', '', null, 20260101, '2026-04-31']) assert.equal(S.validDate(bad), false, String(bad));
});

test('mirrorFor: lifecycle first, then a not-yet-started subscription', () => {
  assert.equal(S.mirrorFor({ status: 'SUSPENDED', subscriptionStatus: 'ACTIVE' }), 'SUSPENDED');
  assert.equal(S.mirrorFor({ status: 'ACTIVE', subscriptionStatus: 'NOT_STARTED' }), 'SUBSCRIPTION_NOT_STARTED');
  assert.equal(S.mirrorFor({ status: 'ACTIVE', subscriptionStatus: 'ACTIVE' }), 'ACTIVE');
  assert.equal(S.mirrorFor({ status: 'ACTIVE' }), 'ACTIVE');
  assert.equal(S.mirrorFor({}), 'ACTIVE', 'a legacy school');
  assert.equal(S.mirrorFor({ status: 'INACTIVE', subscriptionStatus: 'NOT_STARTED' }), 'INACTIVE');
});

test('setSubscription: validates, writes subscription + history + audit, and sets the school status field', async () => {
  const db = world();
  const out = await S.setSubscription(ctxOf(db), 'owner', MFA, { ...base, gracePeriodDays: 5, remarks: 'r', internalNotes: 'n' });
  assert.equal(out.ok, true);
  assert.equal(out.status, 'ACTIVE');
  const cur = await get(db);
  assert.equal(cur.planName, 'Annual');
  assert.equal(cur.version, 1);
  assert.equal(cur.gracePeriodDays, 5);
  const school = (await db.collection('schools').doc('s1').get()).data();
  assert.equal(school.subscriptionStatus, 'ACTIVE');
  assert.equal(school.subscriptionEndDate, '2027-03-31');
  const h = await hist(db);
  assert.equal(h.length, 1);
  assert.equal(h[0].event, 'SUBSCRIPTION_SET');
  assert.equal(h[0].before, null);
  const audit = (await db.collection('platformAuditLog').get()).docs.map((d) => d.data());
  assert.ok(audit.some((a) => a.action === 'SUBSCRIPTION_SET' && a.schoolId === 's1'));
});

test('setSubscription: refused inputs write nothing', async () => {
  const db = world();
  const c = ctxOf(db);
  const bad = async (over, reason) => {
    const out = await S.setSubscription(c, 'owner', MFA, { ...base, ...over });
    assert.deepEqual([out.error, out.reason], reason, JSON.stringify(over));
  };
  await bad({ classification: 'FREE' }, ['INVALID_ARGUMENT', 'classification']);
  await bad({ startDate: '2026-02-30' }, ['INVALID_ARGUMENT', 'startDate']);
  await bad({ endDate: '2026-4-1' }, ['INVALID_ARGUMENT', 'endDate']);
  await bad({ endDate: '2026-03-31' }, ['INVALID_ARGUMENT', 'endBeforeStart']);
  await bad({ gracePeriodDays: -1 }, ['INVALID_ARGUMENT', 'gracePeriodDays']);
  await bad({ gracePeriodDays: 91 }, ['INVALID_ARGUMENT', 'gracePeriodDays']);
  await bad({ gracePeriodDays: 1.5 }, ['INVALID_ARGUMENT', 'gracePeriodDays']);
  await bad({ planId: '' }, ['INVALID_ARGUMENT', 'planId']);
  await bad({ planId: 'nope' }, ['NOT_FOUND', undefined]);
  await bad({ planId: 'old' }, ['FAILED_PRECONDITION', 'PLAN_INACTIVE']);
  await bad({ schoolId: '' }, ['INVALID_ARGUMENT', 'schoolId']);
  await bad({ schoolId: 'ghost' }, ['NOT_FOUND', undefined]);
  assert.equal(await get(db), undefined);
  assert.equal((await hist(db)).length, 0);
});

test('only owners write; support, viewers, school users and outsiders are refused', async () => {
  const db = world();
  const c = ctxOf(db);
  for (const uid of ['support', 'viewer', 'teacher', 'ghost']) {
    assert.equal((await S.setSubscription(c, uid, MFA, base)).error, 'PERMISSION_DENIED', uid);
    assert.equal((await S.cancelSubscription(c, uid, MFA, { schoolId: 's1', reason: 'long enough reason' })).error, 'PERMISSION_DENIED', uid);
  }
  assert.equal((await S.setSubscription(c, 'owner', { firebase: { sign_in_provider: 'password' } }, base)).error, 'MFA_REQUIRED');
  assert.equal(await get(db), undefined);
});

test('replacing a subscription needs a reason and keeps the old values in history', async () => {
  const db = world();
  const c = ctxOf(db);
  await S.setSubscription(c, 'owner', MFA, base);
  assert.equal((await S.setSubscription(c, 'owner', MFA, { ...base, endDate: '2027-06-30' })).reason, 'reason');
  const out = await S.setSubscription(c, 'owner', MFA, { ...base, endDate: '2027-06-30', reason: 'Plan change agreed on call' });
  assert.equal(out.ok, true);
  assert.equal((await get(db)).version, 2);
  const h = (await hist(db)).find((e) => e.reason === 'Plan change agreed on call');
  assert.equal(h.before.endDate, '2027-03-31');
  assert.equal(h.after.endDate, '2027-06-30');
});

test('extend: forward only, with a reason, and cannot extend a cancelled one', async () => {
  const db = world();
  const c = ctxOf(db);
  assert.equal((await S.extendSubscription(c, 'owner', MFA, { schoolId: 's1', endDate: '2027-06-30', reason: 'goodwill extension' })).reason, 'NO_SUBSCRIPTION');
  await S.setSubscription(c, 'owner', MFA, base);
  assert.equal((await S.extendSubscription(c, 'owner', MFA, { schoolId: 's1', endDate: '2027-03-31', reason: 'goodwill extension' })).reason, 'notForward');
  assert.equal((await S.extendSubscription(c, 'owner', MFA, { schoolId: 's1', endDate: '2027-01-01', reason: 'goodwill extension' })).reason, 'notForward');
  assert.equal((await S.extendSubscription(c, 'owner', MFA, { schoolId: 's1', endDate: '2027-06-30', reason: 'short' })).reason, 'reason');
  assert.equal((await S.extendSubscription(c, 'owner', MFA, { schoolId: 's1', endDate: '2027-06-30', reason: 'goodwill extension' })).ok, true);
  assert.equal((await get(db)).endDate, '2027-06-30');
  await S.cancelSubscription(c, 'owner', MFA, { schoolId: 's1', reason: 'Customer left the platform' });
  assert.equal((await S.extendSubscription(c, 'owner', MFA, { schoolId: 's1', endDate: '2028-01-01', reason: 'goodwill extension' })).reason, 'CANCELLED');
});

test('renew: starts the day after the current end, after expiry too, and revives a cancelled one', async () => {
  const db = world();
  const c = ctxOf(db, new Date('2027-05-01T10:00:00Z'));
  await S.setSubscription(ctxOf(db), 'owner', MFA, base);
  const out = await S.renewSubscription(c, 'owner', MFA, { schoolId: 's1', endDate: '2028-03-31' });
  assert.equal(out.ok, true);
  const cur = await get(db);
  assert.equal(cur.startDate, '2027-04-01');
  assert.equal(cur.status, 'ACTIVE');
  assert.equal(cur.classification, 'PAID');
  await S.cancelSubscription(c, 'owner', MFA, { schoolId: 's1', reason: 'Customer paused for a while' });
  assert.equal((await get(db)).status, 'CANCELLED');
  assert.equal((await S.renewSubscription(c, 'owner', MFA, { schoolId: 's1', endDate: '2029-03-31' })).ok, true);
  assert.equal((await get(db)).cancelled, false);
  assert.equal((await S.renewSubscription(c, 'owner', MFA, { schoolId: 's1', endDate: '2027-01-01' })).reason, 'endBeforeStart');
  assert.equal((await S.renewSubscription(c, 'owner', MFA, { schoolId: 'ghost', endDate: '2030-01-01' })).error, 'NOT_FOUND');
});

test('cancel: reason required, once only, status CANCELLED immediately', async () => {
  const db = world();
  const c = ctxOf(db);
  await S.setSubscription(c, 'owner', MFA, base);
  assert.equal((await S.cancelSubscription(c, 'owner', MFA, { schoolId: 's1', reason: 'short' })).reason, 'reason');
  const out = await S.cancelSubscription(c, 'owner', MFA, { schoolId: 's1', reason: 'Customer left the platform' });
  assert.equal(out.status, 'CANCELLED');
  assert.equal((await db.collection('schools').doc('s1').get()).data().subscriptionStatus, 'CANCELLED');
  assert.equal((await S.cancelSubscription(c, 'owner', MFA, { schoolId: 's1', reason: 'Customer left the platform' })).reason, 'CANCELLED');
});

test('trial: starts today in the school zone for N days; not over a live subscription', async () => {
  const db = world();
  const c = ctxOf(db, new Date('2026-06-15T20:00:00Z')); // already the 16th in Kolkata and Auckland
  const out = await S.grantTrial(c, 'owner', MFA, { schoolId: 's1', days: 14 });
  assert.equal(out.status, 'TRIAL');
  const cur = await get(db);
  assert.equal(cur.startDate, '2026-06-16');
  assert.equal(cur.endDate, '2026-06-29');
  assert.equal(cur.classification, 'TRIAL');
  assert.equal((await S.grantTrial(c, 'owner', MFA, { schoolId: 's1', days: 14 })).reason, 'HAS_SUBSCRIPTION');
  for (const days of [0, 91, 1.5, '7', undefined]) assert.equal((await S.grantTrial(c, 'owner', MFA, { schoolId: 's2', days })).reason, 'days', String(days));
  const s2 = await S.grantTrial(c, 'owner', MFA, { schoolId: 's2', days: 1 });
  assert.equal((await get(db, 's2')).startDate, '2026-06-16', 'Auckland');
  assert.equal(s2.status, 'TRIAL');
});

test('trial over an EXPIRED subscription is allowed', async () => {
  const db = world();
  await S.setSubscription(ctxOf(db), 'owner', MFA, { ...base, startDate: '2025-01-01', endDate: '2025-12-31' });
  assert.equal((await get(db)).status, 'EXPIRED');
  assert.equal((await S.grantTrial(ctxOf(db), 'owner', MFA, { schoolId: 's1', days: 7 })).ok, true);
});

test('idempotency: the same key replays the first result and writes nothing more', async () => {
  const db = world();
  const c = ctxOf(db);
  await S.setSubscription(c, 'owner', MFA, { ...base, idempotencyKey: 'k1' });
  const again = await S.setSubscription(c, 'owner', MFA, { ...base, idempotencyKey: 'k1' });
  assert.equal(again.replayed, true);
  assert.equal((await hist(db)).length, 1);
  assert.equal((await get(db)).version, 1);
});

test('plans: owner saves, everyone on the platform lists, no prices anywhere', async () => {
  const db = world();
  const c = ctxOf(db);
  assert.equal((await S.savePlan(c, 'support', MFA, { name: 'Gold', periodType: 'ANNUAL' })).error, 'PERMISSION_DENIED');
  for (const bad of [{ name: 'G', periodType: 'ANNUAL' }, { name: 'Gold', periodType: 'WEEKLY' }, { name: 'Gold', periodType: 'ANNUAL', defaultFeatures: { fees: 'yes' } }, { name: 'Gold', periodType: 'ANNUAL', defaultFeatures: [] }, { name: 'Gold', periodType: 'ANNUAL', planId: 'a b' }]) {
    assert.equal((await S.savePlan(c, 'owner', MFA, bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
  assert.equal((await S.savePlan(c, 'owner', MFA, { name: 'Gold', periodType: 'ANNUAL', planId: 'ghost' })).error, 'NOT_FOUND');
  const made = await S.savePlan(c, 'owner', MFA, { name: 'Gold', periodType: 'QUARTERLY', defaultFeatures: { fees: true, admission: false }, price: 999 });
  assert.equal(made.ok, true);
  const stored = (await db.collection('platformPlans').doc(made.planId).get()).data();
  assert.ok(!('price' in stored), 'a price is never stored');
  assert.equal((await S.savePlan(c, 'owner', MFA, { planId: made.planId, name: 'Gold', periodType: 'QUARTERLY', active: false })).ok, true);
  const list = await S.listPlans(c, 'viewer', MFA);
  assert.deepEqual(list.plans.map((p) => p.name), ['Annual', 'Gold', 'Old']);
  assert.equal(list.plans.find((p) => p.name === 'Gold').active, false);
  assert.equal((await S.listPlans(c, 'teacher', MFA)).error, 'PERMISSION_DENIED');
});

test('history: platform roles read it, newest first; school users cannot', async () => {
  const db = world();
  const c = ctxOf(db);
  await S.setSubscription(c, 'owner', MFA, base);
  await S.extendSubscription({ ...c, nowDate: () => NOW }, 'owner', MFA, { schoolId: 's1', endDate: '2027-06-30', reason: 'goodwill extension' });
  const r = await S.getSubscriptionHistory(c, 'viewer', MFA, { schoolId: 's1' });
  assert.equal(r.entries.length, 2);
  assert.deepEqual(r.entries.map((e) => e.event).sort(), ['SUBSCRIPTION_EXTENDED', 'SUBSCRIPTION_SET']);
  assert.equal((await S.getSubscriptionHistory(c, 'teacher', MFA, { schoolId: 's1' })).error, 'PERMISSION_DENIED');
  assert.equal((await S.getSubscriptionHistory(c, 'viewer', MFA, {})).reason, 'schoolId');
});

test('subscriptionView reports the LIVE status even if the stored one is stale', () => {
  const stale = { ...sub(), status: 'ACTIVE', version: 3 };
  const v = S.subscriptionView(stale, { timezone: 'UTC' }, new Date('2027-05-01T00:00:00Z'));
  assert.equal(v.status, 'EXPIRED');
  assert.equal(v.storedStatus, 'ACTIVE');
  assert.equal(S.subscriptionView(null, {}, NOW), null);
});

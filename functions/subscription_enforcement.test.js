'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const S = require('./subscriptions');
const X = require('./subscription_enforcement');
const L = require('./school_lifecycle');
const E = require('./access_engine');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const PW = { firebase: { sign_in_provider: 'password' } };
const at = (iso) => new Date(iso);
const ctxAt = (db, iso) => ({ db, now: 'NOW', nowDate: () => at(iso), deleteField: db.deleteField });

function world(extra = {}) {
  return fakeDb({
    'schools/s1': { name: 'S1', status: 'ACTIVE', timezone: 'Asia/Kolkata', lifecycleVersion: 1 },
    'schools/s2': { name: 'S2', status: 'ACTIVE', timezone: 'UTC' },
    'users/owner': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'OWNER', email: 'o@avail404.com' },
    'users/a1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1' },
    'users/t1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1' },
    'users/p1': { role: 'PARENT', status: 'ACTIVE', schoolId: 's1' },
    'users/x1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's2' },
    'platformPlans/annual': { name: 'Annual', periodType: 'ANNUAL', active: true },
    ...extra,
  });
}
const user = async (db, id) => (await db.collection('users').doc(id).get()).data();
const school = async (db, id = 's1') => (await db.collection('schools').doc(id).get()).data();
const notes = async (db) => (await db.collection('platformNotifications').get()).docs.map((d) => d.data());
const hist = async (db) => (await db.collection('schoolLifecycleHistory').get()).docs.map((d) => d.data());
const give = (db, iso, over = {}) =>
  X.withReconcile(S.setSubscription)(ctxAt(db, iso), 'owner', MFA, { schoolId: 's1', planId: 'annual', classification: 'PAID', startDate: '2026-04-01', endDate: '2026-12-31', ...over });

test('a valid subscription changes nothing: no mirror, no lifecycle change', async () => {
  const db = world();
  const out = await give(db, '2026-06-15T10:00:00Z');
  assert.equal(out.status, 'ACTIVE');
  assert.equal((await school(db)).status, 'ACTIVE');
  assert.equal((await user(db, 't1')).schoolAccess, undefined);
});

test('a subscription that has not started pauses everyone with its own message code, and is lifted when it starts', async () => {
  const db = world();
  await give(db, '2026-03-01T10:00:00Z');
  assert.equal((await school(db)).subscriptionStatus, 'NOT_STARTED');
  for (const u of ['a1', 't1', 'p1']) assert.equal((await user(db, u)).schoolAccess, 'SUBSCRIPTION_NOT_STARTED', u);
  assert.equal((await user(db, 'x1')).schoolAccess, undefined, 'another school untouched');
  assert.equal((await school(db)).status, 'ACTIVE', 'the lifecycle is not changed');
  const live = await E.evaluateSchoolAccess(db, { uid: 't1', token: PW, schoolId: 's1' }, { enforceSubscription: true, now: at('2026-03-01T10:00:00Z') });
  assert.equal(live.code, 'SUBSCRIPTION_NOT_STARTED');
  // the scheduler lifts it at the start date in the school's zone (Kolkata midnight = 18:30Z the day before)
  const early = await X.runSubscriptionMonitor(ctxAt(db, '2026-03-31T18:00:00Z'));
  assert.equal(early.changed, 0);
  assert.equal((await user(db, 't1')).schoolAccess, 'SUBSCRIPTION_NOT_STARTED');
  const r = await X.runSubscriptionMonitor(ctxAt(db, '2026-03-31T18:31:00Z'));
  assert.equal(r.changed, 1);
  assert.equal((await user(db, 't1')).schoolAccess, undefined);
  assert.equal((await db.collection('schoolSubscriptions').doc('s1').get()).data().status, 'ACTIVE');
});

test('expiry: the school becomes EXPIRED, everyone is paused, administrators are told once, history says SYSTEM', async () => {
  const db = world();
  await give(db, '2026-06-15T10:00:00Z');
  const r = await X.runSubscriptionMonitor(ctxAt(db, '2026-12-31T18:31:00Z')); // Jan 1 in Kolkata
  assert.deepEqual([r.scanned, r.changed, r.failed], [1, 1, 0]);
  assert.equal((await school(db)).status, 'EXPIRED');
  for (const u of ['a1', 't1', 'p1']) assert.equal((await user(db, u)).schoolAccess, 'EXPIRED', u);
  const n = await notes(db);
  assert.equal(n.length, 1);
  assert.equal(n[0].type, 'SCHOOL_EXPIRED');
  assert.equal(n[0].recipientUserId, 'a1');
  const h = (await hist(db)).find((e) => e.event === 'SCHOOL_EXPIRED');
  assert.equal(h.actorKind, 'SYSTEM');
  assert.equal(h.reason, 'Subscription expired');
  const audit = (await db.collection('platformAuditLog').get()).docs.map((d) => d.data()).find((a) => a.action === 'SCHOOL_EXPIRED');
  assert.equal(audit.source, 'SCHEDULER');
  assert.equal(audit.actorPlatformRole, 'SYSTEM');
});

test('the scheduler is idempotent: running again (or overlapping) changes and notifies nothing more', async () => {
  const db = world();
  await give(db, '2026-06-15T10:00:00Z');
  const when = '2027-01-05T00:00:00Z';
  await X.runSubscriptionMonitor(ctxAt(db, when));
  const again = await X.runSubscriptionMonitor(ctxAt(db, when));
  assert.equal(again.changed, 0);
  await Promise.all([X.reconcileSchool(ctxAt(db, when), 's1'), X.reconcileSchool(ctxAt(db, when), 's1')]);
  assert.equal((await notes(db)).length, 1);
  assert.equal((await hist(db)).filter((e) => e.event === 'SCHOOL_EXPIRED').length, 1);
});

test('grace period: allowed with one warning (dismissible), then expires', async () => {
  const db = world();
  await give(db, '2026-06-15T10:00:00Z', { gracePeriodDays: 3 });
  await X.runSubscriptionMonitor(ctxAt(db, '2027-01-02T12:00:00Z'));
  assert.equal((await school(db)).status, 'ACTIVE');
  assert.equal((await user(db, 't1')).schoolAccess, undefined);
  assert.equal((await school(db)).subscriptionStatus, 'GRACE_PERIOD');
  const n = await notes(db);
  assert.equal(n.length, 1);
  assert.deepEqual([n[0].type, n[0].severity, n[0].requiresAck], ['SUBSCRIPTION_GRACE_PERIOD', 'WARNING', false]);
  await X.runSubscriptionMonitor(ctxAt(db, '2027-01-02T15:00:00Z'));
  assert.equal((await notes(db)).length, 1, 'no second warning');
  await X.runSubscriptionMonitor(ctxAt(db, '2027-01-05T12:00:00Z'));
  assert.equal((await school(db)).status, 'EXPIRED');
});

test('renewal revives an expired school: EXPIRED -> ACTIVE, mirror cleared, users told', async () => {
  const db = world();
  await give(db, '2026-06-15T10:00:00Z');
  await X.runSubscriptionMonitor(ctxAt(db, '2027-01-05T00:00:00Z'));
  assert.equal((await school(db)).status, 'EXPIRED');
  const out = await X.withReconcile(S.renewSubscription)(ctxAt(db, '2027-01-05T00:00:00Z'), 'owner', MFA, { schoolId: 's1', endDate: '2027-12-31' });
  assert.equal(out.enforcement.lifecycle, 'ACTIVE');
  assert.equal((await school(db)).status, 'ACTIVE');
  assert.equal((await user(db, 't1')).schoolAccess, undefined);
  assert.ok((await notes(db)).some((x) => x.type === 'SCHOOL_REACTIVATED'));
});

test('cancel pauses immediately; the owner cannot switch the school back on until it is renewed', async () => {
  const db = world();
  const c = ctxAt(db, '2026-06-15T10:00:00Z');
  await give(db, '2026-06-15T10:00:00Z');
  const out = await X.withReconcile(S.cancelSubscription)(c, 'owner', MFA, { schoolId: 's1', reason: 'Customer left the platform' });
  assert.equal(out.enforcement.lifecycle, 'EXPIRED');
  assert.equal((await user(db, 'p1')).schoolAccess, 'EXPIRED');
  const h = (await hist(db)).find((e) => e.event === 'SCHOOL_EXPIRED');
  assert.equal(h.reason, 'Subscription cancelled');
  const refuse = await L.transitionSchool(c, 'owner', MFA, { schoolId: 's1', to: 'ACTIVE' });
  assert.deepEqual([refuse.error, refuse.reason], ['FAILED_PRECONDITION', 'SUBSCRIPTION_EXPIRED']);
  assert.equal((await school(db)).status, 'EXPIRED');
});

test('activating an INACTIVE school with an ended subscription is refused; with a valid one it works', async () => {
  const db = world({ 'schools/s1': { name: 'S1', status: 'INACTIVE', timezone: 'UTC', lifecycleVersion: 1 } });
  await db.collection('schoolSubscriptions').doc('s1').set({ startDate: '2025-01-01', endDate: '2025-12-31', classification: 'PAID', gracePeriodDays: 0, status: 'EXPIRED', version: 1 });
  const c = ctxAt(db, '2026-06-15T10:00:00Z');
  assert.equal((await L.transitionSchool(c, 'owner', MFA, { schoolId: 's1', to: 'ACTIVE' })).reason, 'SUBSCRIPTION_EXPIRED');
  await db.collection('schoolSubscriptions').doc('s1').set({ startDate: '2026-01-01', endDate: '2026-12-31', classification: 'PAID', gracePeriodDays: 0, status: 'ACTIVE', version: 2 });
  assert.equal((await L.transitionSchool(c, 'owner', MFA, { schoolId: 's1', to: 'ACTIVE' })).ok, true);
});

test('a school with no subscription (legacy) is never touched by the scheduler', async () => {
  const db = world();
  const r = await X.runSubscriptionMonitor(ctxAt(db, '2030-01-01T00:00:00Z'));
  assert.deepEqual([r.scanned, r.changed], [0, 0]);
  assert.equal((await school(db)).status, 'ACTIVE');
});

test('lifecycle wins: a SUSPENDED school is not reactivated by a valid subscription, nor expired by an ended one', async () => {
  const db = world({ 'schools/s1': { name: 'S1', status: 'SUSPENDED', timezone: 'UTC', lifecycleVersion: 1 } });
  await give(db, '2026-06-15T10:00:00Z');
  await X.runSubscriptionMonitor(ctxAt(db, '2027-06-01T00:00:00Z'));
  assert.equal((await school(db)).status, 'SUSPENDED');
  await db.collection('users').doc('t1').update({ schoolAccess: 'SUSPENDED' });
  const r = await X.reconcileSchool(ctxAt(db, '2026-06-15T10:00:00Z'), 's1');
  assert.equal(r.lifecycle, null);
});

test('one school failing never stops the others, and is reported', async () => {
  const db = world();
  await give(db, '2026-06-15T10:00:00Z');
  await X.withReconcile(S.setSubscription)(ctxAt(db, '2026-06-15T10:00:00Z'), 'owner', MFA, { schoolId: 's2', planId: 'annual', classification: 'PAID', startDate: '2026-01-01', endDate: '2026-12-31' });
  const real = db.collection.bind(db);
  db.collection = (p) => {
    const c = real(p);
    if (p !== 'schools') return c;
    const doc = c.doc.bind(c);
    c.doc = (id) => {
      if (id === 's1') throw new Error('boom');
      return doc(id);
    };
    return c;
  };
  const logs = [];
  const r = await X.runSubscriptionMonitor(ctxAt(db, '2027-01-05T00:00:00Z'), { log: (e) => logs.push(e) });
  assert.equal(r.failed, 1);
  assert.equal(r.changed, 1, 's2 was still handled');
  assert.ok(logs.includes('subscription monitor: school failed'));
});

test('a failed reconcile after an owner change is flagged for the scheduler to finish', async () => {
  const db = world();
  const real = db.collection.bind(db);
  let armed = false;
  db.collection = (p) => {
    const c = real(p);
    if (armed && p === 'users') c.where = () => { throw new Error('mirror down'); };
    return c;
  };
  const c = ctxAt(db, '2026-06-15T10:00:00Z');
  await give(db, '2026-06-15T10:00:00Z');
  armed = true;
  const out = await X.withReconcile(S.cancelSubscription)(c, 'owner', MFA, { schoolId: 's1', reason: 'Customer left the platform' });
  assert.equal(out.ok, true, 'the change itself stands');
  armed = false;
  assert.equal((await db.collection('schoolSubscriptions').doc('s1').get()).data().status, 'CANCELLED');
  await X.runSubscriptionMonitor(ctxAt(db, '2026-06-15T10:15:00Z'));
  assert.equal((await user(db, 't1')).schoolAccess, 'EXPIRED', 'finished by the scheduler');
});

test('time-zone edge: the same instant expires a Kolkata school but not a Los Angeles one', async () => {
  const db = world({ 'schools/s2': { name: 'S2', status: 'ACTIVE', timezone: 'America/Los_Angeles' } });
  const ctx = ctxAt(db, '2026-06-15T10:00:00Z');
  for (const id of ['s1', 's2']) await X.withReconcile(S.setSubscription)(ctx, 'owner', MFA, { schoolId: id, planId: 'annual', classification: 'PAID', startDate: '2026-01-01', endDate: '2026-06-30' });
  await X.runSubscriptionMonitor(ctxAt(db, '2026-06-30T19:00:00Z'));
  assert.equal((await school(db, 's1')).status, 'EXPIRED');
  assert.equal((await school(db, 's2')).status, 'ACTIVE');
});

test('replayed owner calls do not reconcile again', async () => {
  const db = world();
  const call = () => X.withReconcile(S.setSubscription)(ctxAt(db, '2026-06-15T10:00:00Z'), 'owner', MFA, { schoolId: 's1', planId: 'annual', classification: 'PAID', startDate: '2026-04-01', endDate: '2026-12-31', idempotencyKey: 'k' });
  await call();
  const again = await call();
  assert.equal(again.replayed, true);
  assert.equal(again.enforcement, undefined);
});

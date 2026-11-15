'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('../functions/test_support');
const { analyse, readOnly, parseArgs } = require('./governance_dry_run');

const NOW = new Date('2026-06-15T10:00:00Z');
const snap = (db) => JSON.stringify([...db.store.entries()].sort());

function legacy() {
  return fakeDb({
    'schools/a': { name: 'A', status: 'ACTIVE', timezone: 'Asia/Kolkata' },
    'schools/b': { name: 'B', timezone: 'Asia/Kolkata' }, // pre-lifecycle: no status
    'schools/c': { name: 'C', status: 'SUSPENDED', timezone: 'UTC' },
    'users/pa': { role: 'PLATFORM_ADMIN', status: 'ACTIVE' },
    'users/a1': { role: 'SCHOOL_ADMIN', schoolId: 'a', status: 'ACTIVE' },
    'users/c1': { role: 'TEACHER', schoolId: 'c', status: 'ACTIVE', schoolAccess: 'SUSPENDED' },
  });
}

test('an untouched legacy project needs no data change and nothing is blocked', async () => {
  const db = legacy();
  const r = await analyse(db, { now: NOW });
  assert.equal(r.schools.total, 3);
  assert.deepEqual(r.schools.noStatus, ['b']);
  assert.equal(r.schools.noFeatures, 3);
  assert.equal(r.subscriptions.total, 0);
  assert.deepEqual(r.subscriptions.willBlockOnDeploy, []);
  assert.equal(r.users.platformAdmins, 1);
  assert.equal(r.users.platformAdminsWithoutRole, 1);
  assert.ok(r.findings.some((f) => f.includes('legacy schools are allowed')));
});

test('it NEVER writes: the store is identical afterwards, and every write method is refused', async () => {
  const db = legacy();
  const before = snap(db);
  await analyse(db, { now: NOW });
  assert.equal(snap(db), before);
  const ro = readOnly(db);
  for (const m of ['batch', 'runTransaction']) assert.throws(() => ro[m](), /never writes/, m);
  const doc = ro.collection('schools').doc('a');
  for (const m of ['set', 'update', 'delete', 'create']) assert.throws(() => doc[m]({}), /never writes/, m);
  assert.throws(() => ro.collection('schools').add({}), /never writes/);
  assert.equal(snap(db), before);
});

test('it warns about schools the deployment would pause: ended subscription on an ACTIVE school, not-yet-started ones', async () => {
  const db = legacy();
  await db.collection('schoolSubscriptions').doc('a').set({ startDate: '2025-01-01', endDate: '2025-12-31', classification: 'PAID', gracePeriodDays: 0 });
  await db.collection('schoolSubscriptions').doc('c').set({ startDate: '2030-01-01', endDate: '2030-12-31', classification: 'PAID' });
  await db.collection('schoolSubscriptions').doc('ghost').set({ startDate: '2026-01-01', endDate: '2026-12-31' });
  const r = await analyse(db, { now: NOW });
  assert.deepEqual(r.subscriptions.willBlockOnDeploy, ['a']);
  assert.deepEqual(r.subscriptions.notStarted, ['c']);
  assert.deepEqual(r.subscriptions.noSchool, ['ghost']);
  assert.equal(r.attention >= 3, true);
  assert.ok(r.findings.at(-1).startsWith('RESULT:') && r.findings.at(-1).includes('need a decision'));
});

test('a subscription that is within grace is not reported as blocking', async () => {
  const db = legacy();
  await db.collection('schoolSubscriptions').doc('a').set({ startDate: '2026-01-01', endDate: '2026-06-14', classification: 'PAID', gracePeriodDays: 5 });
  assert.deepEqual((await analyse(db, { now: NOW })).subscriptions.willBlockOnDeploy, []);
});

test('it finds users whose pause mirror is missing or stale (sampled)', async () => {
  const db = legacy();
  await db.collection('users').doc('c2').set({ role: 'PARENT', schoolId: 'c', status: 'ACTIVE' }); // paused school, user not mirrored
  await db.collection('users').doc('a2').set({ role: 'PARENT', schoolId: 'a', status: 'ACTIVE', schoolAccess: 'SUSPENDED' }); // active school, still paused
  const r = await analyse(db, { now: NOW });
  assert.deepEqual(r.users.mirrorMissing, ['c:c2']);
  assert.deepEqual(r.users.mirrorStale, ['a:a2']);
});

test('the sample bounds how many users per school are examined', async () => {
  const seed = { 'schools/a': { status: 'ACTIVE', timezone: 'UTC' } };
  for (let i = 0; i < 30; i++) seed[`users/u${i}`] = { role: 'PARENT', schoolId: 'a', status: 'ACTIVE' };
  const r = await analyse(fakeDb(seed), { sample: 10, now: NOW });
  assert.equal(r.users.schoolUsersSampled, 10);
});

test('unknown module keys and dependency conflicts are reported', async () => {
  const db = legacy();
  await db.collection('schools').doc('a').update({ features: { admission: false, transport: true } });
  const r = await analyse(db, { now: NOW });
  assert.deepEqual(r.features.unknownKeys, ['a:transport']);
  assert.deepEqual(r.features.inconsistent, ['a:publicAdmission'], 'admission is off but its page was never switched off');
});

test('schools without a time zone are flagged; a clean project says so', async () => {
  const bad = await analyse(fakeDb({ 'schools/z': { status: 'ACTIVE' } }), { now: NOW });
  assert.deepEqual(bad.schools.noTimezone, ['z']);
  const ok = await analyse(fakeDb({ 'schools/z': { status: 'ACTIVE', timezone: 'UTC', features: {}, lifecycleVersion: 1 } }), { now: NOW });
  assert.equal(ok.attention, 0);
  assert.ok(ok.findings.at(-1).startsWith('RESULT: nothing needs fixing first'));
});

test('it reports which new collections already exist (a re-run on a deployed project)', async () => {
  const db = legacy();
  await db.collection('platformPlans').doc('p').set({ name: 'x' });
  const r = await analyse(db, { now: NOW });
  assert.equal(r.collectionsAlreadyPresent.platformPlans, true);
  assert.equal(r.collectionsAlreadyPresent.schoolSubscriptions, undefined);
  assert.equal(r.collectionsAlreadyPresent.auditEvents, false);
});

test('command line: project is required, values are checked, and a production project needs --read-prod', () => {
  assert.match(parseArgs([]).error, /--project/);
  assert.match(parseArgs(['--project']).error, /needs a value/);
  assert.match(parseArgs(['--project', 'x', '--sample', '0']).error, /--sample/);
  assert.match(parseArgs(['--project', 'x', '--sample', 'abc']).error, /--sample/);
  assert.match(parseArgs(['--project', 'x', '--bogus']).error, /unknown option/);
  assert.match(parseArgs(['--project', 'eazy-school-360-prod']).error, /--read-prod/);
  assert.equal(parseArgs(['--project', 'eazy-school-360-prod', '--read-prod']).error, undefined);
  assert.equal(parseArgs(['--project', 'eazy-school-360-dev', '--sample', '5', '--json']).sample, 5);
});

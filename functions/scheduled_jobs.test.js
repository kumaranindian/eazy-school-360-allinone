'use strict';
const test = require('node:test');
const assert = require('node:assert');
const sj = require('./scheduled_jobs');
const { fakeDb } = require('./test_support');

const ALL = [
  'pushRedrive', 'subscriptionMonitor',
  'feeDueReminders', 'admissionFollowUpReminders', 'processDeletionRequests',
  'expireDeletionRequests', 'admissionDocumentCleanup', 'expenseReceiptCleanup', 'platformStatsRollup', 'auditRetention',
];
const TICK = ['pushRedrive', 'subscriptionMonitor'];
const HOURLY = ['admissionFollowUpReminders', 'feeDueReminders', 'processDeletionRequests'];
const DAILY = ['admissionDocumentCleanup', 'auditRetention', 'expenseReceiptCleanup', 'expireDeletionRequests', 'platformStatsRollup'];

// Every job records its calls; [fail] names jobs that throw.
function makeJobs(fail = []) {
  const calls = [];
  const jobs = Object.fromEntries(ALL.map((n) => [n, async (o) => {
    calls.push({ n, deadline: o.deadline });
    if (fail.includes(n)) throw new Error(`${n} broke`);
  }]));
  return { jobs, calls, names: () => calls.map((c) => c.n).sort() };
}
const state = (db, name) => db.store.get(`${sj.STATE_COLLECTION}/${name}`);
const at = (iso) => new Date(iso);
const clock = (iso) => () => Date.parse(iso);

test('the plan holds every former scheduled function exactly once', () => {
  assert.deepEqual([...sj.TASK_NAMES].sort(), [...ALL].sort());
  for (const t of sj.PLAN) assert.ok(['tick', 'hourly', 'daily'].includes(t.cadence), t.name);
});

test('one 15-minute job in Asia/Kolkata', () => {
  assert.equal(sj.SCHEDULE, '*/15 * * * *');
  assert.equal(sj.TIME_ZONE, 'Asia/Kolkata');
  assert.ok(sj.STALE_MS > sj.TICK_TIMEOUT_S * 1000, 'a live claim is never taken over');
});

test('the scheduler is off in dev projects and with SCHEDULED_JOBS=off', () => {
  assert.equal(sj.schedulerEnabled({ GCLOUD_PROJECT: 'eazy-school-360-prod' }), true);
  assert.equal(sj.schedulerEnabled({ GCLOUD_PROJECT: 'eazy-school-360-dev' }), false);
  assert.equal(sj.schedulerEnabled({ FIREBASE_CONFIG: JSON.stringify({ projectId: 'eazy-school-360-dev' }) }), false);
  assert.equal(sj.schedulerEnabled({ GCLOUD_PROJECT: 'eazy-school-360-prod', SCHEDULED_JOBS: 'OFF' }), false);
  assert.equal(sj.schedulerEnabled({ FIREBASE_CONFIG: 'not json' }), true);
  assert.equal(sj.schedulerEnabled({}), true);
});

test('windows: UTC hour for hourly tasks, IST day from 02:00 IST for daily tasks', () => {
  const hourly = { cadence: 'hourly' };
  const daily = { cadence: 'daily' };
  assert.equal(sj.windowFor({ cadence: 'tick' }, at('2026-11-22T10:15:00Z')), 'tick');
  assert.equal(sj.windowFor(hourly, at('2026-11-22T10:00:00Z')), 'H:2026-11-22T10');
  assert.equal(sj.windowFor(hourly, at('2026-11-22T10:45:00Z')), 'H:2026-11-22T10');
  // 02:00 IST = 20:30 UTC of the PREVIOUS UTC day: the IST date is used, not the server's UTC date.
  assert.equal(sj.windowFor(daily, at('2026-11-21T20:15:00Z')), null); // 01:45 IST
  assert.equal(sj.windowFor(daily, at('2026-11-21T20:30:00Z')), 'D:2026-11-22'); // 02:00 IST
  assert.equal(sj.windowFor(daily, at('2026-11-22T18:15:00Z')), 'D:2026-11-22'); // 23:45 IST, catch-up
  assert.equal(sj.windowFor(daily, at('2026-11-22T18:30:00Z')), null); // 00:00 IST next day, before 02:00
});

test('a tick at 02:00 IST runs everything once; the next tick only the every-tick tasks', async () => {
  const db = fakeDb();
  const { jobs, names, calls } = makeJobs();
  const first = await sj.runTick(jobs, { db, at: at('2026-11-21T20:30:00Z'), now: clock('2026-11-21T20:30:01Z') });
  assert.deepEqual(first.ran, [...ALL].sort());
  assert.deepEqual(names(), [...ALL].sort());
  for (const n of [...HOURLY, ...DAILY]) assert.equal(state(db, n).status, 'DONE', n);
  assert.equal(state(db, 'auditRetention').lastDoneWindow, 'D:2026-11-22');
  assert.equal(state(db, 'pushRedrive'), undefined, 'every-tick tasks keep no state');

  calls.length = 0;
  const second = await sj.runTick(jobs, { db, at: at('2026-11-21T20:45:00Z'), now: clock('2026-11-21T20:45:01Z') });
  assert.deepEqual(names(), TICK);
  assert.deepEqual(second.skipped, [...HOURLY, ...DAILY].sort());
});

test('a repeated or overlapping tick never runs a windowed task twice', async () => {
  const db = fakeDb();
  const { jobs, names } = makeJobs();
  const opts = { db, at: at('2026-11-22T10:00:00Z'), now: clock('2026-11-22T10:00:01Z') };
  await Promise.all([sj.runTick(jobs, opts), sj.runTick(jobs, opts)]);
  const counts = {};
  for (const n of names()) counts[n] = (counts[n] || 0) + 1;
  for (const n of [...HOURLY, ...DAILY]) assert.equal(counts[n], 1, n);
  for (const n of TICK) assert.equal(counts[n], 2, n);
});

test('a missed tick is caught up: the hourly tasks run on the next tick of the hour', async () => {
  const db = fakeDb();
  const { jobs, names } = makeJobs();
  // The :00 tick never came; the :15 tick is the first of the hour.
  await sj.runTick(jobs, { db, at: at('2026-11-22T10:15:00Z'), now: clock('2026-11-22T10:15:01Z') });
  for (const n of HOURLY) assert.ok(names().includes(n), n);
  assert.equal(state(db, 'feeDueReminders').window, 'H:2026-11-22T10');
});

test('the daily tasks catch up later the same IST day when 02:00 was missed', async () => {
  const db = fakeDb();
  const { jobs, names } = makeJobs();
  await sj.runTick(jobs, { db, at: at('2026-11-22T06:00:00Z'), now: clock('2026-11-22T06:00:01Z') }); // 11:30 IST
  for (const n of DAILY) assert.ok(names().includes(n), n);
});

test('one failing task does not stop the others, is marked FAILED and is retried on the next tick', async () => {
  const db = fakeDb();
  const bad = makeJobs(['feeDueReminders', 'pushRedrive']);
  const logs = [];
  const r = await sj.runTick(bad.jobs, { db, at: at('2026-11-22T10:00:00Z'), now: clock('2026-11-22T10:00:01Z'), log: (m, f) => logs.push([m, f.task]) });
  assert.deepEqual(r.failed, ['feeDueReminders', 'pushRedrive']);
  assert.ok(r.ran.includes('admissionFollowUpReminders'));
  assert.equal(state(db, 'feeDueReminders').status, 'FAILED');
  assert.match(state(db, 'feeDueReminders').error, /broke/);
  assert.deepEqual(logs.map((l) => l[1]).sort(), ['feeDueReminders', 'pushRedrive']);

  const good = makeJobs();
  await sj.runTick(good.jobs, { db, at: at('2026-11-22T10:15:00Z'), now: clock('2026-11-22T10:15:01Z') });
  assert.ok(good.names().includes('feeDueReminders'), 'retried');
  assert.ok(!good.names().includes('admissionFollowUpReminders'), 'a DONE task is not');
  assert.equal(state(db, 'feeDueReminders').status, 'DONE');
  assert.equal(state(db, 'feeDueReminders').attempts, 2);
});

test('a task that keeps failing is tried at most MAX_ATTEMPTS times per window', async () => {
  const db = fakeDb();
  const { jobs, calls } = makeJobs(['feeDueReminders']);
  for (const m of ['00', '15', '30', '45']) {
    await sj.runTick(jobs, { db, at: at(`2026-11-22T10:${m}:00Z`), now: clock(`2026-11-22T10:${m}:01Z`), only: ['feeDueReminders'] });
  }
  assert.equal(calls.length, sj.MAX_ATTEMPTS);
  // A new window starts afresh.
  await sj.runTick(jobs, { db, at: at('2026-11-22T11:00:00Z'), now: clock('2026-11-22T11:00:01Z'), only: ['feeDueReminders'] });
  assert.equal(calls.length, sj.MAX_ATTEMPTS + 1);
  assert.equal(state(db, 'feeDueReminders').attempts, 1);
});

test('a live RUNNING claim is respected; a stale one (dead tick) is taken over', async () => {
  const db = fakeDb();
  const { jobs, calls } = makeJobs();
  db.store.set(`${sj.STATE_COLLECTION}/feeDueReminders`, { window: 'H:2026-11-22T10', status: 'RUNNING', attempts: 1, startedAtMs: Date.parse('2026-11-22T10:00:01Z') });
  await sj.runTick(jobs, { db, at: at('2026-11-22T10:05:00Z'), now: clock('2026-11-22T10:05:00Z'), only: ['feeDueReminders'] });
  assert.equal(calls.length, 0, 'still running elsewhere');
  await sj.runTick(jobs, { db, at: at('2026-11-22T10:15:00Z'), now: clock('2026-11-22T10:15:00Z'), only: ['feeDueReminders'] });
  assert.equal(calls.length, 1, 'older than STALE_MS: taken over');
});

test('every task gets the tick deadline, inside the function timeout', async () => {
  const db = fakeDb();
  const { jobs, calls } = makeJobs();
  const start = Date.parse('2026-11-21T20:30:01Z');
  await sj.runTick(jobs, { db, at: at('2026-11-21T20:30:00Z'), now: () => start });
  assert.equal(calls.length, ALL.length);
  for (const c of calls) assert.equal(c.deadline, start + sj.TICK_TIMEOUT_S * 1000 - sj.TICK_MARGIN_MS, c.n);
});

test('tasks run together, not one after another', async () => {
  const db = fakeDb();
  let running = 0;
  let peak = 0;
  const jobs = Object.fromEntries(ALL.map((n) => [n, async () => {
    running++;
    peak = Math.max(peak, running);
    await new Promise((r) => setTimeout(r, 5));
    running--;
  }]));
  await sj.runTick(jobs, { db, at: at('2026-11-21T20:30:00Z') });
  assert.equal(peak, ALL.length);
});

test('a manual (forced) run ignores windows and claims, and runs only the named task', async () => {
  const db = fakeDb();
  const { jobs, names } = makeJobs();
  const r = await sj.runTick(jobs, { db, at: at('2026-11-22T00:00:00Z'), only: ['platformStatsRollup'], force: true }); // 05:30 IST
  assert.deepEqual(names(), ['platformStatsRollup']);
  assert.deepEqual(r.ran, ['platformStatsRollup']);
  assert.equal(state(db, 'platformStatsRollup'), undefined, 'a manual run does not use up the day\'s window');
});

test('a missing job body is reported as failed, not thrown', async () => {
  const db = fakeDb();
  const r = await sj.runTick({}, { db, at: at('2026-11-22T10:20:00Z'), only: ['pushRedrive'] });
  assert.deepEqual(r.failed, ['pushRedrive']);
});

test('a claim that cannot be written fails only that task', async () => {
  const db = fakeDb();
  db.runTransaction = async () => { throw new Error('firestore down'); };
  const { jobs, names } = makeJobs();
  const r = await sj.runTick(jobs, { db, at: at('2026-11-22T10:00:00Z') });
  assert.deepEqual(names(), TICK, 'every-tick tasks need no claim');
  assert.deepEqual(r.failed, [...HOURLY, ...DAILY].sort()); // 15:30 IST: the daily tasks are due too
});

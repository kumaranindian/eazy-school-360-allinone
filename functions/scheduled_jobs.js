'use strict';

// ALL scheduled work runs in ONE Cloud Scheduler job (`masterScheduler`, every 15 minutes, prod only).
// Cloud Scheduler bills every job ($0.10/month, paused or not) beyond the first three per BILLING ACCOUNT,
// shared by every project on it, so tasks share one tick instead of having a job each.
//
// A task has a cadence:
//   tick    every tick (pushRedrive, subscriptionMonitor; both safe to repeat)
//   hourly  once per UTC hour: the first tick of the hour, or the next one if that was missed
//   daily   once per Asia/Kolkata day, at the first tick at or after 02:00 IST (catches up later that day)
// Hourly/daily tasks claim their window in `schedulerState/{task}` (server-only, no client rules) inside a
// transaction, so a late, repeated or overlapping tick never runs one twice; a failed run is retried on the
// next tick, at most MAX_ATTEMPTS times per window. Due tasks run together (Promise.allSettled) and share the
// tick's deadline. Each task body stays where it was (index.js + its module); this file only dispatches.
//
// Dev gets no scheduler: it is not exported when the project id ends in `-dev` (the Firebase CLI sets
// GCLOUD_PROJECT while it reads the code at deploy time) or when SCHEDULED_JOBS=off. There, the
// OWNER-only callable `runScheduledTask` runs one task on demand instead.

const STATE_COLLECTION = 'schedulerState';
const SCHEDULE = '*/15 * * * *';
const TIME_ZONE = 'Asia/Kolkata';
const DAILY_AT_MINUTES = 2 * 60; // 02:00 Asia/Kolkata
/** Function timeout of the tick; tasks share it. */
const TICK_TIMEOUT_S = 540;
/** Kept free at the end of a tick so tasks can wind down and the state be written. */
const TICK_MARGIN_MS = 40 * 1000;
/** A RUNNING claim older than this belongs to a tick that died (longer than the function timeout). */
const STALE_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 3;

const PLAN = Object.freeze([
  { name: 'pushRedrive', cadence: 'tick' },
  { name: 'subscriptionMonitor', cadence: 'tick' },
  { name: 'feeDueReminders', cadence: 'hourly' },
  { name: 'admissionFollowUpReminders', cadence: 'hourly' },
  { name: 'processDeletionRequests', cadence: 'hourly' },
  { name: 'expireDeletionRequests', cadence: 'daily' },
  { name: 'admissionDocumentCleanup', cadence: 'daily' },
  { name: 'expenseReceiptCleanup', cadence: 'daily' },
  { name: 'platformStatsRollup', cadence: 'daily' },
  { name: 'auditRetention', cadence: 'daily' },
].map(Object.freeze));

const TASK_NAMES = Object.freeze(PLAN.map((t) => t.name));

function projectIdOf(env = process.env) {
  if (env.GCLOUD_PROJECT) return env.GCLOUD_PROJECT;
  try {
    return JSON.parse(env.FIREBASE_CONFIG || '{}').projectId;
  } catch (_) {
    return undefined;
  }
}

/** Whether this project gets the scheduler (false in dev projects and with SCHEDULED_JOBS=off). */
function schedulerEnabled(env = process.env) {
  if (String(env.SCHEDULED_JOBS || '').trim().toLowerCase() === 'off') return false;
  const project = projectIdOf(env);
  return !(project && /-dev$/.test(project));
}

/** { date: 'YYYY-MM-DD', minutes: minutes after local midnight } of [at] in [timeZone]. */
function zoned(at, timeZone) {
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(at);
  const get = (t) => parts.find((p) => p.type === t).value;
  return { date: `${get('year')}-${get('month')}-${get('day')}`, minutes: Number(get('hour')) * 60 + Number(get('minute')) };
}

/**
 * The window [task] is due in at [at], or null when it is not due yet.
 * `tick` -> 'tick' (no claim); `hourly` -> 'H:2026-11-22T10' (UTC); `daily` -> 'D:2026-11-22' (IST, from 02:00).
 */
function windowFor(task, at) {
  if (task.cadence === 'tick') return 'tick';
  if (task.cadence === 'hourly') return `H:${at.toISOString().slice(0, 13)}`;
  if (task.cadence === 'daily') {
    const z = zoned(at, TIME_ZONE);
    return z.minutes >= DAILY_AT_MINUTES ? `D:${z.date}` : null;
  }
  throw new Error(`unknown cadence ${task.cadence}`);
}

/** Claims [window] for [name]; true when this tick should run it. */
async function claim(db, name, window, nowMs) {
  const ref = db.collection(STATE_COLLECTION).doc(name);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const s = snap.exists ? snap.data() : null;
    const same = !!s && s.window === window;
    if (same && s.status === 'DONE') return false;
    if (same && s.status === 'RUNNING' && nowMs - (s.startedAtMs || 0) < STALE_MS) return false;
    if (same && (s.attempts || 0) >= MAX_ATTEMPTS) return false;
    tx.set(ref, {
      task: name,
      window,
      status: 'RUNNING',
      attempts: same ? (s.attempts || 0) + 1 : 1,
      startedAtMs: nowMs,
      finishedAtMs: null,
      error: null,
      lastDoneWindow: (s && s.lastDoneWindow) || null,
    });
    return true;
  });
}

async function finish(db, name, window, ok, error, nowMs) {
  const patch = { status: ok ? 'DONE' : 'FAILED', finishedAtMs: nowMs, error: ok ? null : String(error).slice(0, 200) };
  if (ok) patch.lastDoneWindow = window;
  await db.collection(STATE_COLLECTION).doc(name).update(patch);
}

const messageOf = (e) => String((e && e.message) || e);

/**
 * Runs one tick. [jobs] maps a task name to `async ({ deadline }) => void` (throwing = failed).
 * at: the tick's scheduled time (windows are computed from it); now(): the clock (deadline, claims).
 * only: limit to these task names; force: run them now without claiming a window (manual runs).
 */
async function runTick(jobs, { db, at, now = () => Date.now(), log = () => {}, only, force = false } = {}) {
  const started = now();
  const when = at instanceof Date && !Number.isNaN(at.getTime()) ? at : new Date(started);
  const deadline = started + TICK_TIMEOUT_S * 1000 - TICK_MARGIN_MS;
  const summary = { ran: [], skipped: [], failed: [] };
  const tasks = PLAN.filter((t) => !only || only.includes(t.name));

  const runs = tasks.map(async (task) => {
    const window = force ? null : windowFor(task, when);
    if (!force && window === null) return summary.skipped.push(task.name);
    const claimed = force || window === 'tick' ? false : true;
    try {
      if (claimed && !(await claim(db, task.name, window, now()))) return summary.skipped.push(task.name);
    } catch (e) {
      summary.failed.push(task.name);
      return log('scheduled task could not be claimed', { task: task.name, window, error: messageOf(e) });
    }
    let ok = true;
    let error = null;
    try {
      const job = jobs[task.name];
      if (typeof job !== 'function') throw new Error('no such job');
      await job({ deadline });
    } catch (e) {
      ok = false;
      error = messageOf(e);
    }
    (ok ? summary.ran : summary.failed).push(task.name);
    if (!ok) log('scheduled task failed', { task: task.name, window, error });
    if (claimed) {
      try {
        await finish(db, task.name, window, ok, error, now());
      } catch (e) {
        log('scheduled task state not written', { task: task.name, window, error: messageOf(e) });
      }
    }
  });
  await Promise.allSettled(runs);
  for (const k of Object.keys(summary)) summary[k].sort();
  return summary;
}

module.exports = {
  STATE_COLLECTION,
  SCHEDULE,
  TIME_ZONE,
  DAILY_AT_MINUTES,
  TICK_TIMEOUT_S,
  TICK_MARGIN_MS,
  STALE_MS,
  MAX_ATTEMPTS,
  PLAN,
  TASK_NAMES,
  projectIdOf,
  schedulerEnabled,
  zoned,
  windowFor,
  claim,
  runTick,
};

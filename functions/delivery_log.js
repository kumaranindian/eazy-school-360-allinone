'use strict';

// Exactly-once-ish push delivery. Cloud Functions events are delivered at
// least once, so the same document-created event can arrive twice (or be
// retried). Each delivery claims `pushDeliveries/{eventId}` with an atomic
// create(); a second arrival of the same event finds it and does nothing.
//
// The record also answers "what happened to this notification?": the status
// says whether FCM ACCEPTED the messages, which is all the server can know —
// it is not proof that a person saw or heard anything.
//
// Documents are server-only (firestore.rules default-deny them) and carry an
// `expireAt` so a Firestore TTL policy on that field can delete them.

const COLLECTION = 'pushDeliveries';
const RETENTION_DAYS = 30;
// A claim still PROCESSING after this long belongs to a crashed or timed-out
// invocation; anything younger is assumed to be running. Must stay above the
// push functions' timeout.
const STALE_CLAIM_MS = 10 * 60 * 1000;
// A delivery is attempted at most this many times in total (first send,
// retries after transient failures, and takeovers after crashes).
const MAX_ATTEMPTS = 5;
// Wait before attempt N+1 after attempt N did not finish the job.
const RETRY_BACKOFF_MS = [1, 2, 5, 10].map((m) => m * 60 * 1000);
const MAX_DONE_DEVICES = 5000;

const isAlreadyExists = (e) => e && (e.code === 6 || e.code === 'already-exists' || /already exists/i.test(String(e.message)));
const toMs = (v) => (v && v.toMillis ? v.toMillis() : v instanceof Date ? v.getTime() : v ? new Date(v).getTime() : 0);

/**
 * Claims one attempt at delivering [eventId]. Resolves to
 * `{ ref, attempt, doneDevices }`, or null when there is nothing to do:
 * already finished, still running, out of attempts, or not yet due.
 *
 * A claim carries `retryable` + `nextAttemptAt` while it is PROCESSING (due
 * after [STALE_CLAIM_MS]) and again when an attempt ends without finishing the
 * job, so a crashed invocation and a failed send are picked up the same way —
 * by the next event delivery or by the redrive sweep ([dueDeliveries]).
 *
 * Taking over an existing claim happens in a transaction on its current state,
 * so two concurrent redeliveries cannot both win it (NOTIF-5).
 */
async function claimDelivery(db, eventId, meta, now = () => new Date()) {
  if (!eventId) return null;
  const ref = db.collection(COLLECTION).doc(String(eventId));
  const at = now();
  try {
    await ref.create({
      ...meta,
      status: 'PROCESSING',
      attempts: 1,
      retryable: true,
      nextAttemptAt: new Date(at.getTime() + STALE_CLAIM_MS),
      startedAt: at,
      createdAt: at,
      expireAt: new Date(at.getTime() + RETENTION_DAYS * 24 * 3600 * 1000),
    });
    return { ref, attempt: 1, doneDevices: new Set() };
  } catch (e) {
    if (!isAlreadyExists(e)) throw e;
  }
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const prior = snap.exists ? snap.data() || {} : {};
    const attempts = prior.attempts || 1;
    const due = prior.retryable === true && toMs(prior.nextAttemptAt) <= at.getTime();
    if (!due || attempts >= MAX_ATTEMPTS) return null;
    tx.update(ref, {
      status: 'PROCESSING',
      attempts: attempts + 1,
      retryable: true,
      nextAttemptAt: new Date(at.getTime() + STALE_CLAIM_MS),
      startedAt: at,
      takeovers: (prior.takeovers || 0) + 1,
    });
    return { ref, attempt: attempts + 1, doneDevices: new Set(prior.doneDevices || []) };
  });
}

/**
 * Records the outcome of an attempt. `SENT` is final. Anything else
 * (`PARTIAL`, `INCOMPLETE`, `FAILED`) is scheduled for another attempt with a
 * back-off until [MAX_ATTEMPTS] is reached, then left final so it is visible
 * rather than retried forever. Stores the opaque ids of devices FCM already
 * accepted so a re-run skips them (no duplicates), never tokens or content.
 */
async function finishDelivery(claim, outcome, now = () => new Date()) {
  if (!claim) return;
  const at = now();
  const { doneDevices, ...counts } = outcome;
  const done = new Set([...(claim.doneDevices || []), ...(doneDevices || [])]);
  const retry = counts.status !== 'SENT' && claim.attempt < MAX_ATTEMPTS;
  await claim.ref.update({
    ...counts,
    finishedAt: at,
    retryable: retry,
    nextAttemptAt: retry ? new Date(at.getTime() + (RETRY_BACKOFF_MS[claim.attempt - 1] || RETRY_BACKOFF_MS.at(-1))) : null,
    ...(done.size ? { doneDevices: [...done].slice(0, MAX_DONE_DEVICES) } : {}),
  });
}

/** Deliveries that are due another attempt (failed, partial, or abandoned mid-run). */
async function dueDeliveries(db, now = () => new Date(), limit = 20) {
  const snap = await db
    .collection(COLLECTION)
    .where('retryable', '==', true)
    .where('nextAttemptAt', '<=', now())
    .limit(limit)
    .get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

/** A short, non-sensitive category for an error, for the delivery record and logs. */
function errorCategory(e) {
  const code = String((e && (e.code || e.errorInfo?.code)) || '');
  if (code.startsWith('messaging/')) return code;
  if (code) return `error/${code}`;
  return 'error/unknown';
}

module.exports = {
  claimDelivery,
  finishDelivery,
  dueDeliveries,
  errorCategory,
  COLLECTION,
  STALE_CLAIM_MS,
  RETENTION_DAYS,
  MAX_ATTEMPTS,
  RETRY_BACKOFF_MS,
};

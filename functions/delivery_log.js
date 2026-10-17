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
// A claim still PROCESSING after this long belongs to a crashed invocation and
// may be taken over; anything younger is assumed to be running.
const STALE_CLAIM_MS = 10 * 60 * 1000;

const isAlreadyExists = (e) => e && (e.code === 6 || e.code === 'already-exists' || /already exists/i.test(String(e.message)));

/**
 * Claims the delivery of [eventId]. Returns the claim's document reference, or
 * null when this event was already handled (or is being handled right now).
 */
async function claimDelivery(db, eventId, meta, now = () => new Date()) {
  if (!eventId) return null;
  const ref = db.collection(COLLECTION).doc(String(eventId));
  const at = now();
  try {
    await ref.create({
      ...meta,
      status: 'PROCESSING',
      startedAt: at,
      createdAt: at,
      expireAt: new Date(at.getTime() + RETENTION_DAYS * 24 * 3600 * 1000),
    });
    return ref;
  } catch (e) {
    if (!isAlreadyExists(e)) throw e;
  }
  // Already claimed. Only a stale PROCESSING claim (a crash) may be re-run.
  const prior = (await ref.get()).data() || {};
  const started = prior.startedAt && prior.startedAt.toDate ? prior.startedAt.toDate() : prior.startedAt;
  if (prior.status === 'PROCESSING' && started && at.getTime() - new Date(started).getTime() > STALE_CLAIM_MS) {
    await ref.update({ startedAt: at, takeovers: (prior.takeovers || 0) + 1 });
    return ref;
  }
  return null;
}

/** Records the outcome on a claim. Counts only; never message content or tokens. */
async function finishDelivery(ref, outcome, now = () => new Date()) {
  if (!ref) return;
  await ref.update({ ...outcome, finishedAt: now() });
}

/** A short, non-sensitive category for an error, for the delivery record and logs. */
function errorCategory(e) {
  const code = String((e && (e.code || e.errorInfo?.code)) || '');
  if (code.startsWith('messaging/')) return code;
  if (code) return `error/${code}`;
  return 'error/unknown';
}

module.exports = { claimDelivery, finishDelivery, errorCategory, COLLECTION, STALE_CLAIM_MS, RETENTION_DAYS };

'use strict';

// Push delivery of one notice document, with retry and redrive (NOTIF-3/4/5).
//
// An attempt is claimed in `pushDeliveries/{eventId}` (delivery_log.js). If it
// does not finish the job — FCM was briefly unavailable, the invocation ran out
// of time, the process crashed — the claim stays retryable and is picked up by
// the next event delivery or, reliably, by `redrive()` which a schedule runs
// every few minutes. A re-run skips devices FCM already accepted, so a retry
// never sends the same notice twice to the same phone.

const { claimDelivery, finishDelivery, dueDeliveries, errorCategory, COLLECTION } = require('./delivery_log');
const { pushToUsers } = require('./push');
const { broadcastRecipients, targetedRecipients } = require('./recipients');

const SOURCE_PATH = /^schools\/([^/]+)\/branches\/([^/]+)\/(broadcastNotices|notifications)\/([^/]+)$/;

function makeDelivery({ db, messaging, logger, budgetMs = 240 * 1000, now = () => new Date(), wait } = {}) {
  const resolvers = {
    broadcastNotices: (doc) => broadcastRecipients(db, doc),
    notifications: (doc) => targetedRecipients(db, doc),
  };

  /** One attempt at delivering [data] (the notice document at [ref]). */
  async function runDelivery({ eventId, schoolId, branchId, ref, id, data, kind }) {
    const doc = { ...data, schoolId, branchId };
    let claim = null;
    try {
      claim = await claimDelivery(db, eventId, { schoolId, branchId, path: ref.path, type: data.type || '' }, now);
      if (!claim) {
        logger.info('push skipped: event already handled or not due', { path: ref.path });
        return null;
      }
      const userIds = await resolvers[kind](doc);
      const sent = await pushToUsers({
        db,
        messaging,
        schoolId,
        userIds,
        exclude: data.createdBy,
        type: data.type,
        title: data.title,
        body: data.body,
        notificationId: id,
        data: { refType: data.refType || '', refId: data.refId || '', branchId, schoolId },
        skipDevices: claim.doneDevices,
        deadlineAt: Date.now() + budgetMs,
        wait,
      });
      const { doneDevices, ...counts } = sent;
      const status = sent.incomplete ? 'INCOMPLETE' : sent.transientFailed > 0 ? 'PARTIAL' : 'SENT';
      await finishDelivery(claim, { status, ...counts, doneDevices }, now);
      logger.info('push delivered', { path: ref.path, type: data.type, status, attempt: claim.attempt, ...counts });
      return status;
    } catch (e) {
      const category = errorCategory(e);
      logger.error('push failed', { path: ref.path, category, attempt: claim && claim.attempt });
      await finishDelivery(claim, { status: 'FAILED', errorCategory: category }, now).catch(() => {});
      return 'FAILED';
    }
  }

  /**
   * Re-runs deliveries that are due another attempt. Safe to run at any
   * frequency and concurrently: the claim decides who proceeds.
   */
  async function redrive({ limit = 20 } = {}) {
    const due = await dueDeliveries(db, now, limit);
    const out = { due: due.length, ran: 0, gone: 0 };
    for (const d of due) {
      const m = SOURCE_PATH.exec(String(d.path || ''));
      if (!m) {
        await db.collection(COLLECTION).doc(d.id).update({ retryable: false, status: 'UNROUTABLE' });
        out.gone++;
        continue;
      }
      const snap = await db.doc(d.path).get();
      if (!snap.exists) {
        await db.collection(COLLECTION).doc(d.id).update({ retryable: false, status: 'SOURCE_DELETED' });
        out.gone++;
        continue;
      }
      await runDelivery({ eventId: d.id, schoolId: m[1], branchId: m[2], ref: snap.ref, id: snap.id, data: snap.data(), kind: m[3] });
      out.ran++;
    }
    return out;
  }

  return { runDelivery, redrive };
}

module.exports = { makeDelivery, SOURCE_PATH };

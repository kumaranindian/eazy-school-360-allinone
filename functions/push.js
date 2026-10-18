'use strict';

const crypto = require('node:crypto');
const { allowsPush, categoryFor } = require('./categories');
const { chunk } = require('./recipients');
const { canReceive, isStaleDevice } = require('./device_cleanup');

const MAX_RECIPIENTS = 2000;
const FCM_BATCH = 500; // sendEachForMulticast limit
const ANDROID_CHANNEL = 'eazyschool_general'; // created by the app (see docs/push-notifications.md)
// Where a tap goes. The payload only ever carries one of these, and the app
// checks it again against its own allowlist before navigating.
const DEFAULT_ROUTE = '/notifications';

// Only errors that mean "this token is dead". `invalid-argument` is NOT here:
// FCM also returns it for a bad payload, which would wipe every device's token.
const STALE = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);
// Errors worth trying again within this invocation: FCM or the network had a
// bad moment. Anything else is permanent for this message.
const TRANSIENT = new Set([
  'messaging/internal-error',
  'messaging/server-unavailable',
  'messaging/unknown-error',
  'messaging/message-rate-exceeded',
  'messaging/device-message-rate-exceeded',
  'messaging/topics-message-rate-exceeded',
]);
const MAX_ATTEMPTS = 3;
const BACKOFF_MS = [250, 1000];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** APNs collapse ids are limited to 64 bytes; hash anything longer. */
function collapseId(notificationId) {
  const id = String(notificationId || '');
  if (!id) return undefined;
  return id.length <= 64 ? id : crypto.createHash('sha1').update(id).digest('hex');
}

/** FCM data values must be short strings. Anything else is dropped. */
function safeData(type, notificationId, data) {
  const out = { type: String(type || ''), route: DEFAULT_ROUTE };
  if (notificationId) out.notificationId = String(notificationId);
  const allowed = ['refType', 'refId', 'branchId', 'source', 'schoolId'];
  for (const k of allowed) {
    const v = data && data[k];
    if (typeof v === 'string' && v.length > 0 && v.length <= 200) out[k] = v;
  }
  return out;
}

/**
 * The FCM message for one notification, for every platform at once.
 * - A `notification` block, so the OS shows it (and plays the channel / default
 *   sound) even when the app is closed.
 * - `data` for the app's own routing: type, a safe route, ids. Never content.
 * - Per-platform sound/priority so Android uses its channel, iOS the default
 *   sound, and browsers a tagged notification that replaces a duplicate.
 */
function buildMessage({ type, title, body, data, notificationId }) {
  const cid = collapseId(notificationId);
  return {
    notification: { title: title || 'EazySchool 360', body: body || '' },
    data: safeData(type, notificationId, data),
    android: {
      priority: 'high',
      ttl: 24 * 60 * 60 * 1000,
      // The same tag replaces an earlier copy instead of stacking a duplicate.
      notification: {
        channelId: ANDROID_CHANNEL,
        visibility: 'public',
        priority: 'high',
        defaultSound: true,
        ...(cid ? { tag: cid } : {}),
      },
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
        ...(cid ? { 'apns-collapse-id': cid } : {}),
      },
      payload: { aps: { sound: 'default', 'interruption-level': 'active', 'thread-id': 'eazyschool' } },
    },
    webpush: {
      headers: { Urgency: 'high', TTL: String(24 * 60 * 60) },
      notification: { icon: '/icons/Icon-192.png', ...(cid ? { tag: cid } : {}) },
    },
  };
}

/**
 * Sends [message] to [targets] ({ token, ref }), retrying only the tokens that
 * failed transiently, a bounded number of times. Dead tokens are collected.
 */
async function sendBatch(messaging, targets, message, wait = sleep) {
  const result = { accepted: 0, stale: [], transient: 0, permanent: 0 };
  let pending = targets;
  for (let attempt = 1; attempt <= MAX_ATTEMPTS && pending.length > 0; attempt++) {
    let res;
    try {
      res = await messaging.sendEachForMulticast({ ...message, tokens: pending.map((t) => t.token) });
    } catch (e) {
      // The whole call failed (network, quota): treat every token as transient.
      if (attempt < MAX_ATTEMPTS) {
        await wait(BACKOFF_MS[attempt - 1] || 1000);
        continue;
      }
      result.transient += pending.length;
      pending = [];
      break;
    }
    const retry = [];
    res.responses.forEach((r, i) => {
      if (r.success) {
        result.accepted++;
        return;
      }
      const code = r.error?.code;
      if (STALE.has(code)) result.stale.push(pending[i]);
      else if (TRANSIENT.has(code)) retry.push(pending[i]);
      else result.permanent++;
    });
    pending = retry;
    if (pending.length > 0 && attempt < MAX_ATTEMPTS) await wait(BACKOFF_MS[attempt - 1] || 1000);
  }
  result.transient += pending.length; // still failing after the last attempt
  return result;
}

/** Users who may receive a school's notification: ACTIVE and of that school. */
async function eligibleUsers(db, schoolId, uids) {
  const eligible = [];
  for (const part of chunk(uids, 300)) {
    const docs = await db.getAll(...part.map((u) => db.collection('users').doc(u)));
    docs.forEach((d, i) => {
      const u = d.exists ? d.data() : null;
      // ACTIVE, of this school, and still allowed to sign in (a disabled login
      // keeps status ACTIVE but must not keep receiving notices).
      if (u && canReceive(u) && u.schoolId === schoolId) eligible.push(part[i]);
    });
  }
  return eligible;
}

/**
 * Sends one notification to the devices of [userIds] who may receive it.
 *
 * Returns a summary of what happened — counts only. `accepted` means FCM took
 * the message; it does not mean a device showed or sounded it.
 *
 * Recipients are checked here, whatever the caller resolved: a user of another
 * school, an inactive account, the sender, and anyone who turned push off or
 * muted the category are skipped. Tokens FCM reports as dead are removed.
 */
async function pushToUsers({
  db,
  messaging,
  schoolId,
  userIds,
  exclude,
  type,
  title,
  body,
  data,
  notificationId,
  wait,
}) {
  const summary = {
    requested: 0,
    ineligible: 0,
    muted: 0,
    devices: 0,
    accepted: 0,
    staleRemoved: 0,
    transientFailed: 0,
    permanentFailed: 0,
  };
  const category = categoryFor(type);
  const candidates = [...userIds].filter((u) => u && u !== exclude).slice(0, MAX_RECIPIENTS);
  summary.requested = candidates.length;
  if (candidates.length === 0) return summary;

  const eligible = schoolId ? await eligibleUsers(db, schoolId, candidates) : [];
  summary.ineligible = candidates.length - eligible.length;
  if (eligible.length === 0) return summary;

  const prefDocs = await db.getAll(
    ...eligible.map((u) => db.collection('users').doc(u).collection('preferences').doc('notifications')),
  );
  const allowed = eligible.filter((_, i) => allowsPush(prefDocs[i].exists ? prefDocs[i].data() : null, category));
  summary.muted = eligible.length - allowed.length;

  const targets = []; // { token, ref }
  const seen = new Set();
  for (const part of chunk(allowed, 25)) {
    const snaps = await Promise.all(part.map((u) => db.collection('users').doc(u).collection('devices').get()));
    for (const s of snaps) {
      for (const d of s.docs) {
        const dev = d.data();
        // A token registered under two accounts is sent once; deactivated
        // registrations are skipped.
        // A registration that stopped checking in is not trusted (NOTIF-1).
        if (!dev.token || dev.status === 'INACTIVE' || seen.has(dev.token) || isStaleDevice(dev)) continue;
        seen.add(dev.token);
        targets.push({ token: dev.token, ref: d.ref });
      }
    }
  }
  summary.devices = targets.length;
  if (targets.length === 0) return summary;

  const message = buildMessage({ type, title, body, data, notificationId });
  for (const part of chunk(targets, FCM_BATCH)) {
    const r = await sendBatch(messaging, part, message, wait);
    summary.accepted += r.accepted;
    summary.transientFailed += r.transient;
    summary.permanentFailed += r.permanent;
    const removed = await Promise.allSettled(r.stale.map((t) => t.ref.delete()));
    summary.staleRemoved += removed.filter((x) => x.status === 'fulfilled').length;
  }
  return summary;
}

module.exports = {
  pushToUsers,
  buildMessage,
  sendBatch,
  eligibleUsers,
  collapseId,
  safeData,
  STALE,
  TRANSIENT,
  ANDROID_CHANNEL,
  DEFAULT_ROUTE,
};

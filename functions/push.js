'use strict';

const { allowsPush, categoryFor } = require('./categories');
const { chunk } = require('./recipients');

const MAX_RECIPIENTS = 2000;
const STALE = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

// Sends one notification to the devices of [userIds] who allow it. Returns
// the number of messages accepted. Tokens FCM reports as dead are removed.
async function pushToUsers({ db, messaging, userIds, exclude, type, title, body, data }) {
  const category = categoryFor(type);
  const uids = [...userIds].filter((u) => u && u !== exclude).slice(0, MAX_RECIPIENTS);
  if (uids.length === 0) return 0;

  const prefDocs = await db.getAll(
    ...uids.map((u) => db.collection('users').doc(u).collection('preferences').doc('notifications')),
  );
  const allowed = uids.filter((_, i) => allowsPush(prefDocs[i].exists ? prefDocs[i].data() : null, category));

  const targets = []; // { token, ref }
  for (const part of chunk(allowed, 25)) {
    const snaps = await Promise.all(part.map((u) => db.collection('users').doc(u).collection('devices').get()));
    for (const s of snaps) {
      for (const d of s.docs) {
        const token = d.data().token;
        if (token) targets.push({ token, ref: d.ref });
      }
    }
  }
  if (targets.length === 0) return 0;

  let sent = 0;
  for (const part of chunk(targets, 500)) {
    const res = await messaging.sendEachForMulticast({
      tokens: part.map((t) => t.token),
      notification: { title: title || 'EazySchool 360', body: body || '' },
      data: { type: String(type || ''), route: '/notifications', ...(data || {}) },
      // Shown on the lock screen with its text, as a heads-up alert.
      android: {
        priority: 'high',
        ttl: 24 * 60 * 60 * 1000,
        notification: {
          channelId: 'eazyschool_default',
          visibility: 'public',
          priority: 'high',
          defaultSound: true,
        },
      },
      apns: {
        headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
        payload: { aps: { sound: 'default', 'interruption-level': 'active' } },
      },
    });
    sent += res.successCount;
    const dead = [];
    res.responses.forEach((r, i) => {
      if (!r.success && STALE.has(r.error?.code)) dead.push(part[i].ref.delete());
    });
    await Promise.allSettled(dead);
  }
  return sent;
}

module.exports = { pushToUsers };

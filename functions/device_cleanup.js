'use strict';

// Push-device hygiene (NOTIF-1 / NOTIF-2).
//
// A registered device means "deliver this account's notices here". It must stop
// receiving them when the account can no longer sign in, when the user signs
// out everywhere, and when the device simply stops checking in (a phone left
// signed in on a shelf, or sign-out cleanup that never ran).

/** Devices that have not checked in for this long are not sent to. */
const STALE_DEVICE_MS = 60 * 24 * 60 * 60 * 1000;

const ms = (v) => (v && v.toMillis ? v.toMillis() : v instanceof Date ? v.getTime() : Number(v) || 0);

/** The account may sign in at all: ACTIVE and (if it has a login grant) enabled. */
function canReceive(user) {
  if (!user || user.status !== 'ACTIVE') return false;
  const l = user.login;
  return l == null || l.enabled === true;
}

/** True when a registration is too old to trust. Unknown age is kept. */
function isStaleDevice(dev, nowMs = Date.now()) {
  const seen = ms(dev.lastSeenAt) || ms(dev.updatedAt) || ms(dev.createdAt);
  return seen > 0 && nowMs - seen > STALE_DEVICE_MS;
}

/** The account just lost the right to receive notices (status or login). */
function lostAccess(before, after) {
  return canReceive(before) && !canReceive(after);
}

/** Deletes every registered device of [uid]. Returns how many. */
async function removeAllDevices(db, uid) {
  const snap = await db.collection('users').doc(uid).collection('devices').get();
  for (const d of snap.docs) await d.ref.delete();
  return snap.docs.length;
}

module.exports = { STALE_DEVICE_MS, canReceive, isStaleDevice, lostAccess, removeAllDevices };

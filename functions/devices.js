'use strict';

// Trusted device registration for push. The client never writes a device
// document itself (firestore.rules forbid it): it asks here, so the server —
// not the client — decides which account and school a token belongs to.
//
//  * The caller must be an ACTIVE signed-in user with a school; the device is
//    recorded under THEIR account and school, never one named in the request.
//  * The document id is a hash of the token: stable (a repeat registration
//    updates the same document) and not the raw token.
//  * A token belongs to one account at a time. Registering it releases it from
//    any other account that held it (a phone handed to someone else whose
//    sign-out cleanup never ran), so the previous user stops receiving theirs.
//  * A user keeps at most MAX_DEVICES; the least recently seen are dropped.
//
// An FCM token is never treated as proof of identity — it only says where to
// deliver, and only for the account it was registered under.

const crypto = require('node:crypto');
const { canReceive } = require('./device_cleanup');

const PLATFORMS = ['android', 'ios', 'web'];
const TOKEN_RE = /^[A-Za-z0-9:_.\-]{20,4096}$/;
const MAX_DEVICES = 10;

const deviceId = (token) => crypto.createHash('sha256').update(token).digest('hex');
const ms = (v) => (v && v.toMillis ? v.toMillis() : v instanceof Date ? v.getTime() : Number(v) || 0);
const ownerOf = (ref) => {
  const p = ref.path.split('/');
  return p[0] === 'users' && p[2] === 'devices' ? p[1] : null;
};

function validToken(data) {
  return data && typeof data.token === 'string' && TOKEN_RE.test(data.token);
}

async function activeSchoolUser(db, uid) {
  const snap = await db.collection('users').doc(uid).get();
  const u = snap.exists ? snap.data() : null;
  if (!canReceive(u) || typeof u.schoolId !== 'string' || !u.schoolId) return null;
  return u;
}

/** Registers (or refreshes) the caller's device. */
async function registerDevice({ db, now }, uid, data) {
  if (!validToken(data) || !PLATFORMS.includes(data.platform)) return { error: 'INVALID_ARGUMENT' };
  const user = await activeSchoolUser(db, uid);
  if (!user) return { error: 'PERMISSION_DENIED' };

  const id = deviceId(data.token);
  const ref = db.collection('users').doc(uid).collection('devices').doc(id);
  const prior = await ref.get();
  const appVersion = typeof data.appVersion === 'string' ? data.appVersion.slice(0, 40) : null;
  await ref.set({
    token: data.token,
    platform: data.platform,
    schoolId: user.schoolId,
    branchId: typeof user.branchId === 'string' ? user.branchId : null,
    status: 'ACTIVE',
    appVersion,
    createdAt: prior.exists && prior.data().createdAt ? prior.data().createdAt : now(),
    updatedAt: now(),
    lastSeenAt: now(),
  });

  // One account per token: release it from every other account (and from this
  // account's legacy documents, which used a different id).
  let released = 0;
  const same = await db.collectionGroup('devices').where('token', '==', data.token).get();
  for (const d of same.docs) {
    if (d.ref.path === ref.path) continue;
    await d.ref.delete();
    if (ownerOf(d.ref) !== uid) released++;
  }

  // Bounded devices per user: keep the most recently seen.
  const mine = (await db.collection('users').doc(uid).collection('devices').get()).docs;
  if (mine.length > MAX_DEVICES) {
    const oldest = [...mine].sort((a, b) => ms(a.data().updatedAt) - ms(b.data().updatedAt));
    for (const d of oldest.slice(0, mine.length - MAX_DEVICES)) {
      if (d.ref.path !== ref.path) await d.ref.delete();
    }
  }
  return { result: { deviceId: id, released } };
}

/** Removes the caller's registration of [token] (sign-out, push turned off). */
async function unregisterDevice({ db }, uid, data) {
  if (!validToken(data)) return { error: 'INVALID_ARGUMENT' };
  const same = await db.collectionGroup('devices').where('token', '==', data.token).get();
  let removed = 0;
  for (const d of same.docs) {
    if (ownerOf(d.ref) !== uid) continue; // never touch another account's registration
    await d.ref.delete();
    removed++;
  }
  return { result: { removed } };
}

module.exports = { registerDevice, unregisterDevice, deviceId, MAX_DEVICES, PLATFORMS };

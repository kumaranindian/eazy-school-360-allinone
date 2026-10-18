'use strict';

// Phone OTP: request + verify. The code is generated here, stored only as an
// HMAC (keyed with a server secret "pepper"), delivered via a pluggable
// sender (WhatsApp, see whatsapp.js) and verified on the server. A Firebase
// session is minted (custom token) only after a correct, unexpired,
// unconsumed code for the phone that belongs to exactly one enabled user.
//
// Collections (no client access in firestore.rules):
//   otpChallenges/{id}  { uid, schoolId, phoneHash, codeHash, attempts, status, expiresAt, createdAt }
//   otpRate/{key}       { windowStart, count, lastSentAt }   key = HMAC of phone or ip

const crypto = require('node:crypto');
const { normalizePhone } = require('./access');

const CODE_LENGTH = 6;
const TTL_MS = 5 * 60 * 1000;
const MAX_ATTEMPTS = 5;
const RESEND_COOLDOWN_MS = 60 * 1000;
const WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_PHONE = 5;
const MAX_PER_IP = 20;
// Documents are removed by a Firestore TTL policy on `expireAt` (SEC-3).
const RETAIN_MS = 24 * 60 * 60 * 1000;

const hmac = (pepper, text) => crypto.createHmac('sha256', pepper).update(text).digest('hex');
const safeEqual = (a, b) => {
  const x = Buffer.from(a, 'hex');
  const y = Buffer.from(b, 'hex');
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};

function generateCode(randomInt = crypto.randomInt) {
  return String(randomInt(0, 10 ** CODE_LENGTH)).padStart(CODE_LENGTH, '0');
}

// Fixed-window counter in a transaction. Returns null when allowed or the
// reason it is refused.
async function hit(db, key, max, nowMs, cooldownMs) {
  const ref = db.collection('otpRate').doc(key);
  return db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data() || { windowStart: nowMs, count: 0, lastSentAt: 0 };
    if (nowMs - d.windowStart >= WINDOW_MS) {
      d.windowStart = nowMs;
      d.count = 0;
    }
    if (cooldownMs && nowMs - d.lastSentAt < cooldownMs) {
      return { error: 'RESEND_COOLDOWN', retryAfterSec: Math.ceil((cooldownMs - (nowMs - d.lastSentAt)) / 1000) };
    }
    if (d.count >= max) return { error: 'RATE_LIMITED', retryAfterSec: Math.ceil((WINDOW_MS - (nowMs - d.windowStart)) / 1000) };
    tx.set(ref, { windowStart: d.windowStart, count: d.count + 1, lastSentAt: nowMs, expireAt: new Date(d.windowStart + WINDOW_MS + RETAIN_MS) });
    return null;
  });
}

async function findUserByPhone(db, e164) {
  const q = await db.collection('users').where('login.phone', '==', e164).limit(3).get();
  if (q.docs.length !== 1) return null; // none, or ambiguous: never guess
  const d = q.docs[0];
  const u = d.data();
  const l = u.login;
  if (u.status !== 'ACTIVE' || !l || l.enabled !== true || !(l.effective || []).includes('PHONE_OTP')) return null;
  return { uid: d.id, user: u };
}

/**
 * ctx: { db, sender, pepper, nowMs(), randomInt?, newId() }
 * Always answers the same shape for unknown / ineligible phones so the
 * endpoint cannot be used to discover which numbers are registered.
 */
async function requestOtp(ctx, { phone, ip }) {
  const { db, sender, pepper } = ctx;
  const e164 = normalizePhone(phone);
  if (!e164) return { error: 'INVALID_PHONE' };
  if (!sender.configured) return { error: 'OTP_UNAVAILABLE' };
  const nowMs = ctx.nowMs();
  const phoneKey = `p_${hmac(pepper, `phone:${e164}`)}`;
  const ipKey = `i_${hmac(pepper, `ip:${ip || 'unknown'}`)}`;
  const ipHit = await hit(db, ipKey, MAX_PER_IP, nowMs, 0);
  if (ipHit) return ipHit;
  const phoneHit = await hit(db, phoneKey, MAX_PER_PHONE, nowMs, RESEND_COOLDOWN_MS);
  if (phoneHit) return phoneHit;

  const challengeId = ctx.newId();
  const target = await findUserByPhone(db, e164);
  const reply = { challengeId, expiresInSec: TTL_MS / 1000, resendAfterSec: RESEND_COOLDOWN_MS / 1000 };
  if (!target) return reply; // decoy: nothing stored, nothing sent

  const code = generateCode(ctx.randomInt);
  const ref = db.collection('otpChallenges').doc(challengeId);
  const prev = db.collection('otpChallenges').where('phoneHash', '==', phoneKey).where('status', '==', 'PENDING');
  const old = await prev.get();
  const batch = db.batch();
  // Replay protection: a new code supersedes every earlier pending one.
  for (const d of old.docs) batch.update(d.ref, { status: 'SUPERSEDED' });
  batch.set(ref, {
    uid: target.uid,
    schoolId: target.user.schoolId,
    phoneHash: phoneKey,
    codeHash: hmac(pepper, `code:${challengeId}:${code}`),
    attempts: 0,
    status: 'PENDING',
    createdAt: nowMs,
    expiresAt: nowMs + TTL_MS,
    expireAt: new Date(nowMs + TTL_MS + RETAIN_MS),
  });
  await batch.commit();
  try {
    await sender.sendOtp({ to: e164, code });
  } catch (e) {
    await ref.update({ status: 'FAILED' });
    return { error: 'DELIVERY_FAILED', reason: e.code || 'PROVIDER_ERROR' };
  }
  return reply;
}

/**
 * Returns { uid } on success (caller mints the token) or { error }.
 * ctx adds { auth-less }: { createAudit?(schoolId, event) } is optional.
 */
async function verifyOtp(ctx, { challengeId, code }) {
  const { db, pepper } = ctx;
  if (typeof challengeId !== 'string' || !/^[0-9a-f]{32}$/.test(challengeId)) return { error: 'OTP_INVALID' };
  if (typeof code !== 'string' || !/^\d{6}$/.test(code)) return { error: 'OTP_INVALID' };
  const nowMs = ctx.nowMs();
  const ref = db.collection('otpChallenges').doc(challengeId);
  const out = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { error: 'OTP_INVALID' };
    const c = snap.data();
    if (c.status !== 'PENDING') return { error: c.status === 'LOCKED' ? 'OTP_LOCKED' : 'OTP_INVALID' };
    if (nowMs > c.expiresAt) {
      tx.update(ref, { status: 'EXPIRED' });
      return { error: 'OTP_EXPIRED' };
    }
    if (c.attempts >= MAX_ATTEMPTS) return { error: 'OTP_LOCKED' };
    if (!safeEqual(c.codeHash, hmac(pepper, `code:${challengeId}:${code}`))) {
      const attempts = c.attempts + 1;
      tx.update(ref, { attempts, ...(attempts >= MAX_ATTEMPTS ? { status: 'LOCKED' } : {}) });
      return { error: attempts >= MAX_ATTEMPTS ? 'OTP_LOCKED' : 'OTP_INVALID', attemptsLeft: Math.max(0, MAX_ATTEMPTS - attempts) };
    }
    tx.update(ref, { status: 'CONSUMED', consumedAt: nowMs }); // single use
    return { uid: c.uid, phoneHash: c.phoneHash, schoolId: c.schoolId };
  });
  if (out.error) return out;

  // Re-check the grant AFTER the code was proven: access may have been
  // revoked, or the phone re-bound, while the challenge was pending.
  const snap = await db.collection('users').doc(out.uid).get();
  const u = snap.data();
  const l = u && u.login;
  const stillOk =
    u && u.status === 'ACTIVE' && l && l.enabled === true && (l.effective || []).includes('PHONE_OTP') &&
    l.phone && `p_${hmac(pepper, `phone:${l.phone}`)}` === out.phoneHash;
  if (!stillOk) return { error: 'ACCESS_DISABLED' };
  return { uid: out.uid, schoolId: u.schoolId, phone: l.phone };
}

module.exports = {
  requestOtp,
  verifyOtp,
  generateCode,
  hmac,
  CODE_LENGTH,
  TTL_MS,
  MAX_ATTEMPTS,
  RESEND_COOLDOWN_MS,
  MAX_PER_PHONE,
  MAX_PER_IP,
};

'use strict';

// Account deletion REQUESTS (Google Play account-deletion policy). This module
// is the request lifecycle only: it records, verifies and reviews requests. It
// deletes nothing. Executing an approved request is a separate, flag-guarded
// step (docs/account-deletion.md) so a request can never destroy data on its own.
//
// Collections (no client access in firestore.rules - the default deny applies):
//   accountDeletionRequests/{reference}  the request; the id IS the reference
//   accountDeletionLocks/{uid}           one open request per account
//   accountDeletionRate/{key}            fixed-window counters (hashed keys)
//
// Lifecycle:
//   PENDING_VERIFICATION  public form submitted, e-mail link not yet used
//   UNDER_REVIEW          identity proven; waiting for Avail404 review
//   ACTION_REQUIRED       cannot proceed yet (e.g. the only school admin)
//   APPROVED              Avail404 approved; queued for processing
//   PROCESSING / FAILED_RETRYABLE / COMPLETED   set by the processor
//   REJECTED / CANCELLED / EXPIRED              terminal, never destructive
//
// Nothing here trusts the client for who, which school or which role: identity
// comes from the verified auth token, everything else from the server's own
// /users/{uid} profile. The reference is an unguessable token, not an account id.

const crypto = require('node:crypto');

const STATUS = {
  PENDING_VERIFICATION: 'PENDING_VERIFICATION',
  UNDER_REVIEW: 'UNDER_REVIEW',
  ACTION_REQUIRED: 'ACTION_REQUIRED',
  APPROVED: 'APPROVED',
  PROCESSING: 'PROCESSING',
  FAILED_RETRYABLE: 'FAILED_RETRYABLE',
  COMPLETED: 'COMPLETED',
  REJECTED: 'REJECTED',
  CANCELLED: 'CANCELLED',
  EXPIRED: 'EXPIRED',
};
const OPEN = [
  STATUS.UNDER_REVIEW,
  STATUS.ACTION_REQUIRED,
  STATUS.APPROVED,
  STATUS.PROCESSING,
  STATUS.FAILED_RETRYABLE,
];
const TERMINAL = [STATUS.COMPLETED, STATUS.REJECTED, STATUS.CANCELLED, STATUS.EXPIRED];

// from -> allowed next states. Anything else is refused.
const TRANSITIONS = {
  PENDING_VERIFICATION: ['UNDER_REVIEW', 'ACTION_REQUIRED', 'REJECTED', 'EXPIRED', 'CANCELLED'],
  UNDER_REVIEW: ['APPROVED', 'ACTION_REQUIRED', 'REJECTED', 'CANCELLED'],
  ACTION_REQUIRED: ['UNDER_REVIEW', 'REJECTED', 'CANCELLED'],
  APPROVED: ['PROCESSING', 'REJECTED', 'ACTION_REQUIRED'],
  PROCESSING: ['COMPLETED', 'FAILED_RETRYABLE', 'ACTION_REQUIRED'],
  FAILED_RETRYABLE: ['PROCESSING', 'ACTION_REQUIRED'],
  COMPLETED: [],
  REJECTED: [],
  CANCELLED: [],
  EXPIRED: [],
};
// The user can withdraw a request until Avail404 has approved it.
const CANCELLABLE = [STATUS.PENDING_VERIFICATION, STATUS.UNDER_REVIEW, STATUS.ACTION_REQUIRED];

const REASON = {
  SOLE_ADMIN: 'SOLE_ADMIN', // the only active school admin: school would be orphaned
  NO_ACCOUNT: 'NO_ACCOUNT',
  PLATFORM_ADMIN: 'PLATFORM_ADMIN',
  DUPLICATE: 'DUPLICATE',
  EMAIL_MISMATCH: 'EMAIL_MISMATCH',
  DECLINED: 'DECLINED',
};

const RECENT_SIGN_IN_MS = 5 * 60 * 1000; // in-app: re-authenticated just now
const LINK_SIGN_IN_MS = 15 * 60 * 1000; // web: e-mail link used just now
const VERIFY_WINDOW_MS = 24 * 60 * 60 * 1000;
const RATE_WINDOW_MS = 60 * 60 * 1000;
const MAX_PER_EMAIL = 3;
const MAX_PER_IP = 10;
// A ceiling against floods, set high so an attacker cannot easily lock real users out.
const MAX_GLOBAL = 2000;
const RETAIN_RATE_MS = 24 * 60 * 60 * 1000;
const MAX_HISTORY = 20;
const ROLES = ['PARENT', 'TEACHER', 'FINANCE', 'BRANCH_ADMIN', 'SCHOOL_ADMIN', 'OTHER'];
const EMAIL = /^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,}$/;
const REFERENCE = /^DEL-[A-Z2-7]{16}$/;

const ms = (v) => (v && v.toMillis ? v.toMillis() : v instanceof Date ? v.getTime() : Number(v) || 0);
const sha = (text) => crypto.createHash('sha256').update(text).digest('hex');
const str = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const normEmail = (v) => str(v, 320).toLowerCase();

// 80 random bits, base32: unguessable, easy to read out over the phone.
function newReference(randomBytes = crypto.randomBytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const bytes = randomBytes(16);
  let out = '';
  for (let i = 0; i < 16; i++) out += alphabet[bytes[i] % 32];
  return `DEL-${out}`;
}

const err = (error, extra = {}) => ({ error, ...extra });

/** What the requester (and the public status page) is told. No internals. */
function view(id, r) {
  return {
    reference: id,
    status: r.status,
    reason: r.reason || null,
    createdAt: ms(r.createdAt) || null,
    updatedAt: ms(r.updatedAt) || null,
  };
}

function withHistory(r, status, at) {
  const history = [...(r.history || []), { status, at }].slice(-MAX_HISTORY);
  return { ...r, status, history, updatedAt: at };
}

/** Moves a request to [next], refusing anything outside the lifecycle. */
function advance(r, next, at, extra = {}) {
  if (!(TRANSITIONS[r.status] || []).includes(next)) return null;
  const out = withHistory({ ...r, ...extra }, next, at);
  if (TERMINAL.includes(next)) out.contactEmail = null;
  return out;
}

// ---- guards ---------------------------------------------------------------

async function profileOf(db, uid) {
  const snap = await db.collection('users').doc(uid).get();
  return snap.exists ? snap.data() : null;
}

/** True when [user] is the only ACTIVE SCHOOL_ADMIN of their school. */
async function isSoleAdmin(db, uid, user) {
  if (!user || user.role !== 'SCHOOL_ADMIN' || !user.schoolId) return false;
  const q = await db
    .collection('users')
    .where('schoolId', '==', user.schoolId)
    .where('role', '==', 'SCHOOL_ADMIN')
    .where('status', '==', 'ACTIVE')
    .limit(3)
    .get();
  return !q.docs.some((d) => d.id !== uid);
}

/** Fixed-window counter in a transaction; null when allowed. */
async function hit(db, key, max, nowMs) {
  const ref = db.collection('accountDeletionRate').doc(key);
  return db.runTransaction(async (tx) => {
    const d = (await tx.get(ref)).data() || { windowStart: nowMs, count: 0 };
    if (nowMs - d.windowStart >= RATE_WINDOW_MS) {
      d.windowStart = nowMs;
      d.count = 0;
    }
    if (d.count >= max) {
      return err('RATE_LIMITED', { retryAfterSec: Math.ceil((RATE_WINDOW_MS - (nowMs - d.windowStart)) / 1000) });
    }
    tx.set(ref, { windowStart: d.windowStart, count: d.count + 1, expireAt: new Date(d.windowStart + RATE_WINDOW_MS + RETAIN_RATE_MS) });
    return null;
  });
}

// ---- opening a request for a verified account ------------------------------

/**
 * Creates (or returns the existing) open request for a verified account. The
 * lock document makes this atomic: two taps, two devices, or the app and the
 * web form racing all end up with the same request.
 */
async function openForAccount({ db, now }, { uid, source, requestId }) {
  const at = now();
  const user = await profileOf(db, uid);
  if (user && user.role === 'PLATFORM_ADMIN') return err('PLATFORM_ADMIN');
  const sole = user ? await isSoleAdmin(db, uid, user) : false;
  const lockRef = db.collection('accountDeletionLocks').doc(uid);
  const reqRef = db.collection('accountDeletionRequests').doc(requestId || newReference());

  return db.runTransaction(async (tx) => {
    const lock = await tx.get(lockRef);
    if (lock.exists) {
      const existing = (await tx.get(db.collection('accountDeletionRequests').doc(lock.data().reference))).data();
      if (existing && OPEN.includes(existing.status)) {
        return { duplicate: true, request: view(lock.data().reference, existing) };
      }
    }
    const status = sole ? STATUS.ACTION_REQUIRED : STATUS.UNDER_REVIEW;
    const doc = withHistory(
      {
        source,
        uid,
        // Snapshot for the reviewer. Ids and a role, never a name or contact.
        schoolId: user ? user.schoolId || null : null,
        role: user ? user.role || null : null,
        reason: sole ? REASON.SOLE_ADMIN : null,
        createdAt: at,
        history: [],
      },
      status,
      at,
    );
    tx.set(reqRef, doc);
    tx.set(lockRef, { reference: reqRef.id, createdAt: at });
    return { duplicate: false, request: view(reqRef.id, doc) };
  });
}

async function releaseLock(db, uid) {
  if (uid) await db.collection('accountDeletionLocks').doc(uid).delete();
}

// ---- signed-in (in-app, or web after sign-in) -------------------------------

/** The account holder asks to delete their own account. */
async function requestOwn(ctx, uid, token, data) {
  if (!data || data.confirm !== true) return err('INVALID_ARGUMENT');
  const authTime = ms(token && token.auth_time) * 1000;
  if (!authTime || ctx.now().getTime() - authTime > RECENT_SIGN_IN_MS) return err('REAUTH_REQUIRED');
  const out = await openForAccount(ctx, { uid, source: 'APP' });
  if (out.error) return out;
  return { result: out.request, duplicate: out.duplicate };
}

/** The signed-in caller's own requests, newest first. Never anyone else's. */
async function listOwn({ db }, uid) {
  const q = await db.collection('accountDeletionRequests').where('uid', '==', uid).limit(10).get();
  return {
    result: q.docs
      .map((d) => view(d.id, d.data()))
      .sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0)),
  };
}

/** The caller withdraws their own request (until it is approved). */
async function cancelOwn({ db, now }, uid, data) {
  const reference = str(data && data.reference, 40);
  if (!REFERENCE.test(reference)) return err('INVALID_ARGUMENT');
  const ref = db.collection('accountDeletionRequests').doc(reference);
  const out = await db.runTransaction(async (tx) => {
    const r = (await tx.get(ref)).data();
    // A request that is not the caller's looks exactly like one that does not exist.
    if (!r || r.uid !== uid) return err('NOT_FOUND');
    if (!CANCELLABLE.includes(r.status)) return err('NOT_CANCELLABLE');
    const next = advance(r, STATUS.CANCELLED, now());
    tx.set(ref, next);
    return { result: view(reference, next) };
  });
  if (!out.error) await releaseLock(db, uid);
  return out;
}

// ---- public web form --------------------------------------------------------

/**
 * Anyone may submit the public form. It never reveals whether the address
 * belongs to an account: every valid submission gets a fresh reference and the
 * same answer. The e-mail link (Firebase Auth) is what proves ownership.
 */
async function requestPublic({ db, now }, data, ip) {
  const email = normEmail(data && data.email);
  if (!EMAIL.test(email) || email.length > 254) return err('INVALID_ARGUMENT');
  // Honeypot: a field no person sees. Pretend success, store nothing.
  if (str(data.website, 100)) return { result: { reference: newReference(), status: STATUS.PENDING_VERIFICATION } };

  const at = now();
  const nowMs = at.getTime();
  for (const [key, max] of [
    [`e_${sha(email)}`, MAX_PER_EMAIL],
    [`i_${sha(`ip:${ip || 'unknown'}`)}`, MAX_PER_IP],
    ['global', MAX_GLOBAL],
  ]) {
    const limited = await hit(db, key, max, nowMs);
    if (limited) return limited;
  }

  const reference = newReference();
  const role = ROLES.includes(data.role) ? data.role : 'OTHER';
  const doc = withHistory(
    {
      source: 'WEB',
      uid: null,
      contactEmail: email,
      // Free text only helps a reviewer; kept short and never trusted.
      claimedRole: role,
      claimedSchool: str(data.schoolName, 100) || null,
      reason: null,
      createdAt: at,
      expireAt: new Date(nowMs + VERIFY_WINDOW_MS),
      history: [],
    },
    STATUS.PENDING_VERIFICATION,
    at,
  );
  await db.collection('accountDeletionRequests').doc(reference).create(doc);
  return { result: { reference, status: STATUS.PENDING_VERIFICATION } };
}

/**
 * The person followed the e-mail link (Firebase Auth e-mail-link sign-in) and
 * calls this signed in. The token must carry the SAME verified address the form
 * was submitted with, from a sign-in that just happened.
 */
async function confirmPublic(ctx, uid, token, data, auth) {
  const { db, now } = ctx;
  const reference = str(data && data.reference, 40);
  if (!REFERENCE.test(reference)) return err('INVALID_ARGUMENT');
  const ref = db.collection('accountDeletionRequests').doc(reference);
  const r = (await ref.get()).data();
  if (!r || r.source !== 'WEB') return err('NOT_FOUND');
  if (r.status !== STATUS.PENDING_VERIFICATION) return { result: view(reference, r) }; // idempotent
  const at = now();
  if (ms(r.expireAt) && at.getTime() > ms(r.expireAt)) return err('EXPIRED');

  const email = normEmail(token && token.email);
  const authTime = ms(token && token.auth_time) * 1000;
  if (!token || token.email_verified !== true || !email || email !== r.contactEmail) return err('VERIFICATION_FAILED');
  if (!authTime || at.getTime() - authTime > LINK_SIGN_IN_MS) return err('REAUTH_REQUIRED');

  const user = await profileOf(db, uid);
  if (!user) {
    // Signing in with the link creates an account if the address had none. That
    // stray login is removed again; only a login made for this request.
    if (auth) {
      const record = await auth.getUser(uid);
      // Admin SDK metadata carries a UTC date string, not a Date.
      const created = Date.parse(record.metadata && record.metadata.creationTime) || 0;
      if (created && created >= ms(r.createdAt) - 1000) await auth.deleteUser(uid);
    }
    const next = advance(r, STATUS.REJECTED, at, { reason: REASON.NO_ACCOUNT });
    await ref.set(next);
    return { result: view(reference, next) };
  }

  const opened = await openForAccount(ctx, { uid, source: 'WEB', requestId: reference });
  if (opened.error === 'PLATFORM_ADMIN') {
    const next = advance(r, STATUS.REJECTED, at, { reason: REASON.PLATFORM_ADMIN });
    await ref.set(next);
    return { result: view(reference, next) };
  }
  if (opened.duplicate) {
    // Already has an open request: this one is redundant. Point at the real one.
    const next = advance(r, STATUS.REJECTED, at, { reason: REASON.DUPLICATE, uid });
    await ref.set(next);
    return { result: opened.request, duplicate: true };
  }
  // openForAccount wrote the request under this id with source WEB; keep the
  // fields the form collected for the reviewer, minus the e-mail address.
  const merged = { ...(await ref.get()).data(), claimedRole: r.claimedRole, claimedSchool: r.claimedSchool, contactEmail: null };
  await ref.set(merged);
  return { result: view(reference, merged) };
}

/** Status by reference (the public page): the category only, nothing else. */
async function statusPublic({ db }, data) {
  const reference = str(data && data.reference, 40);
  if (!REFERENCE.test(reference)) return err('INVALID_ARGUMENT');
  const r = (await db.collection('accountDeletionRequests').doc(reference).get()).data();
  if (!r) return err('NOT_FOUND');
  return { result: { reference, status: r.status, updatedAt: ms(r.updatedAt) || null } };
}

// ---- Avail404 review --------------------------------------------------------

async function platformReviewer({ db }, uid) {
  const u = await profileOf(db, uid);
  return u && u.role === 'PLATFORM_ADMIN' && u.status === 'ACTIVE';
}

const DECISIONS = {
  APPROVE: STATUS.APPROVED,
  REJECT: STATUS.REJECTED,
  REQUEST_ACTION: STATUS.ACTION_REQUIRED,
  REOPEN: STATUS.UNDER_REVIEW,
};

/** Avail404 decides. Only an ACTIVE platform administrator may; never on their own request. */
async function review(ctx, uid, data) {
  const { db, now } = ctx;
  if (!(await platformReviewer(ctx, uid))) return err('PERMISSION_DENIED');
  const reference = str(data && data.reference, 40);
  const decision = data && data.decision;
  if (!REFERENCE.test(reference) || !DECISIONS[decision]) return err('INVALID_ARGUMENT');
  const reasonCode = REASON[data.reasonCode] || null;

  const ref = db.collection('accountDeletionRequests').doc(reference);
  const out = await db.runTransaction(async (tx) => {
    const r = (await tx.get(ref)).data();
    if (!r) return err('NOT_FOUND');
    if (r.uid === uid) return err('PERMISSION_DENIED'); // no self-approval
    let target = DECISIONS[decision];
    let reason = reasonCode;
    if (target === STATUS.APPROVED || target === STATUS.UNDER_REVIEW) {
      // Re-checked now: the school may have changed since the request was made.
      const user = r.uid ? await profileOf(db, r.uid) : null;
      if (!user) return err('NOT_FOUND');
      if (await isSoleAdmin(db, r.uid, user)) {
        target = STATUS.ACTION_REQUIRED;
        reason = REASON.SOLE_ADMIN;
      } else if (target === STATUS.UNDER_REVIEW) {
        reason = null;
      }
    }
    // Still blocked for the same reason: nothing to change.
    if (target === r.status) return { result: view(reference, r) };
    const next = advance(r, target, now(), {
      reason,
      reviewedBy: uid,
      ...(target === STATUS.APPROVED ? { approvedAt: now() } : {}),
    });
    if (!next) return err('INVALID_TRANSITION');
    tx.set(ref, next);
    return { result: view(reference, next), release: TERMINAL.includes(target) ? r.uid : null };
  });
  if (out.release) await releaseLock(db, out.release);
  return out.error ? out : { result: out.result };
}

// ---- housekeeping -----------------------------------------------------------

/** Unverified public requests lapse after 24 hours. Returns how many. */
async function expireUnverified({ db, now }) {
  const at = now();
  const q = await db
    .collection('accountDeletionRequests')
    .where('status', '==', STATUS.PENDING_VERIFICATION)
    .where('expireAt', '<', at)
    .limit(200)
    .get();
  for (const d of q.docs) {
    const next = advance(d.data(), STATUS.EXPIRED, at);
    if (next) await d.ref.set(next);
  }
  return q.docs.length;
}

module.exports = {
  STATUS,
  OPEN,
  TERMINAL,
  TRANSITIONS,
  REASON,
  RECENT_SIGN_IN_MS,
  LINK_SIGN_IN_MS,
  newReference,
  isSoleAdmin,
  releaseLock,
  advance,
  platformReviewer,
  requestOwn,
  listOwn,
  cancelOwn,
  requestPublic,
  confirmPublic,
  statusPublic,
  review,
  expireUnverified,
};

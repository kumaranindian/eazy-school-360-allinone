'use strict';

// Persistent per-recipient notifications from the platform to school administrators
// (docs/platform-governance/, Phase 4). One document per (event, recipient) with a
// deterministic id, so a retried fan-out never duplicates. There are NO client rules for
// this collection (default deny): the app reads and updates it only through the callables
// below, which always scope to the caller's own notifications.
//
// States: CREATED -> DELIVERED (first time the recipient's app lists it) ->
// ACKNOWLEDGED (explicit, by the recipient) or DISMISSED (only when no acknowledgement is
// required). "Read" is never claimed before acknowledgement.

const { idOf, own: ownKey } = require('./ids');
const crypto = require('node:crypto');
const { loginAllowed } = require('./access');

const COL = 'platformNotifications';
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const toMs = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : t instanceof Date ? t.getTime() : null);
const idFor = (sourceEventId, uid) => crypto.createHash('sha256').update(`${sourceEventId}|${uid}`).digest('hex').slice(0, 32);

// What each lifecycle event tells the school. The internal reason is never copied here;
// only the owner's optional message to the administrators is.
const LIFECYCLE_COPY = {
  SCHOOL_ACTIVATED: ['Your school is now active', 'Your school has been activated. Everyone can use the app.', 'INFO'],
  SCHOOL_REACTIVATED: ['School access restored', 'Your school access has been restored. Everyone can use the app again.', 'INFO'],
  SCHOOL_SUSPENDED: ['School suspended', 'Your school has been suspended. Please contact admin@avail404.com.', 'CRITICAL'],
  SCHOOL_DEACTIVATED: ['School deactivated', 'Your school has been deactivated. Please contact admin@avail404.com.', 'CRITICAL'],
  SCHOOL_EXPIRED: ['School subscription expired', 'Your school subscription has expired. Please contact admin@avail404.com.', 'CRITICAL'],
  SCHOOL_CLOSED: ['School closed', 'Your school account has been closed. Please contact admin@avail404.com.', 'CRITICAL'],
  SCHOOL_RECOVERED: ['School recovered', 'Your school has been recovered and is waiting to be activated.', 'WARNING'],
};

/**
 * Creates one notification for every ACTIVE school administrator of [schoolId].
 * Safe to repeat for the same [sourceEventId]. Returns { created, recipients }.
 */
async function notifySchoolAdmins(ctx, { schoolId, sourceEventId, type, title, body, severity = 'INFO', requiresAck = true }) {
  const admins = await ctx.db.collection('users').where('schoolId', '==', schoolId).where('role', '==', 'SCHOOL_ADMIN').get();
  let created = 0;
  let recipients = 0;
  for (const d of admins.docs) {
    const u = d.data();
    if (u.status !== 'ACTIVE') continue;
    recipients++;
    const ref = ctx.db.collection(COL).doc(idFor(sourceEventId, d.id));
    const exists = (await ref.get()).data();
    if (exists) continue;
    await ref.set({
      recipientUserId: d.id,
      schoolId,
      type,
      title: text(title, 100),
      body: text(body, 1000),
      severity,
      requiresAck,
      state: 'CREATED',
      sourceEventId,
      createdAt: ctx.now,
      deliveredAt: null,
      acknowledgedAt: null,
      dismissedAt: null,
    });
    created++;
  }
  return { created, recipients };
}

/** The notification a lifecycle change sends (title/body/severity), or null for none. */
function lifecycleNotification(event, message) {
  const c = ownKey(LIFECYCLE_COPY, event);
  if (!c) return null;
  const extra = text(message, 500);
  return { title: c[0], body: extra ? `${c[1]}\n\n${extra}` : c[1], severity: c[2] };
}

// ---- recipient side ---------------------------------------------------------------

/** The caller's own profile if they may sign in (no school-state check: a paused user can still read why). */
async function recipient(ctx, uid, token) {
  const u = (await ctx.db.collection('users').doc(uid).get()).data();
  if (!u || !u.schoolId || u.status !== 'ACTIVE') return null;
  // A school paused by the platform sets users.schoolAccess; that must not hide the explanation.
  const { schoolAccess, ...rest } = u;
  return loginAllowed(rest, token) ? u : null;
}

const view = (id, n) => ({
  id,
  type: n.type || '',
  title: n.title || '',
  body: n.body || '',
  severity: n.severity || 'INFO',
  requiresAck: n.requiresAck !== false,
  state: n.state || 'CREATED',
  createdAtMs: toMs(n.createdAt),
  acknowledgedAtMs: toMs(n.acknowledgedAt),
});

/** The caller's notifications, newest first. First sight marks them DELIVERED. */
async function listMyPlatformNotifications(ctx, uid, token) {
  if (!(await recipient(ctx, uid, token))) return { error: 'PERMISSION_DENIED' };
  const snap = await ctx.db.collection(COL).where('recipientUserId', '==', uid).limit(200).get();
  const out = [];
  for (const d of snap.docs) {
    const n = d.data();
    if (n.state === 'CREATED') {
      await d.ref.update({ state: 'DELIVERED', deliveredAt: ctx.now });
      n.state = 'DELIVERED';
    }
    if (n.state === 'DISMISSED') continue;
    out.push(view(d.id, n));
  }
  out.sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0));
  const pending = out.filter((n) => n.state !== 'ACKNOWLEDGED').length;
  return { notifications: out.slice(0, 50), pending };
}

async function own(ctx, uid, token, data) {
  if (!(await recipient(ctx, uid, token))) return { error: 'PERMISSION_DENIED' };
  const id = idOf(data && data.id, 64);
  if (!id) return { error: 'INVALID_ARGUMENT', reason: 'id' };
  const ref = ctx.db.collection(COL).doc(id);
  const n = (await ref.get()).data();
  // Someone else's notification looks exactly like a missing one.
  if (!n || n.recipientUserId !== uid) return { error: 'NOT_FOUND' };
  return { ref, n };
}

async function acknowledgeNotification(ctx, uid, token, data) {
  const r = await own(ctx, uid, token, data);
  if (r.error) return r;
  if (r.n.state === 'ACKNOWLEDGED') return { ok: true, unchanged: true };
  await r.ref.update({ state: 'ACKNOWLEDGED', acknowledgedAt: ctx.now, deliveredAt: r.n.deliveredAt || ctx.now });
  return { ok: true };
}

async function dismissNotification(ctx, uid, token, data) {
  const r = await own(ctx, uid, token, data);
  if (r.error) return r;
  if (r.n.requiresAck !== false) return { error: 'FAILED_PRECONDITION', reason: 'ACK_REQUIRED' };
  if (r.n.state === 'DISMISSED' || r.n.state === 'ACKNOWLEDGED') return { ok: true, unchanged: true };
  await r.ref.update({ state: 'DISMISSED', dismissedAt: ctx.now });
  return { ok: true };
}

module.exports = {
  COL,
  LIFECYCLE_COPY,
  idFor,
  notifySchoolAdmins,
  lifecycleNotification,
  listMyPlatformNotifications,
  acknowledgeNotification,
  dismissNotification,
};

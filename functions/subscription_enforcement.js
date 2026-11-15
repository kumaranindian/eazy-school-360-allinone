'use strict';

// Subscription enforcement (Phase 6): reconciles a school's lifecycle, mirror and notices with its
// subscription, immediately after an owner's change and every 15 minutes for time-based changes.
//
//  - subscription ended (EXPIRED/CANCELLED) while the school is ACTIVE -> lifecycle EXPIRED (SYSTEM)
//  - subscription valid again while the school is EXPIRED               -> lifecycle ACTIVE (SYSTEM)
//  - subscription NOT_STARTED while ACTIVE                              -> mirror SUBSCRIPTION_NOT_STARTED
//  - GRACE_PERIOD                                                       -> allowed, administrators are warned
// Idempotent: every step is keyed on the subscription version, so a re-run or an overlapping run
// creates no second history entry, transition or notification. Callables ALSO check live
// (access_engine), so the scheduler is never the only control.

const subscriptions = require('./subscriptions');
const lifecycle = require('./school_lifecycle');
const notifications = require('./school_notifications');

const { statusAt, zoneOf, mirrorFor, isBlocking, subRef } = subscriptions;
const PAGE = 300;
const VALID = ['TRIAL', 'ACTIVE', 'GRACE_PERIOD'];

/** Brings one school in line with its subscription. Returns what it did. */
async function reconcileSchool(ctx, schoolId) {
  const db = ctx.db;
  const schoolRef = db.collection('schools').doc(schoolId);
  let school = (await schoolRef.get()).data();
  const sub = (await subRef(db, schoolId).get()).data();
  if (!school || !sub) return { skipped: 'NO_SUBSCRIPTION' };
  const live = statusAt(sub, ctx.nowDate(), zoneOf(school));
  if (!live) return { skipped: 'UNREADABLE' };
  const did = { status: live, statusChanged: false, lifecycle: null, mirrored: false, notified: 0 };

  if (live !== sub.status || school.subscriptionStatus !== live) {
    const hid = `sys-${schoolId}-${sub.version || 0}-${live}`;
    const histDoc = subscriptions.histRef(db, hid);
    const exists = (await histDoc.get()).data();
    if (!exists && live !== sub.status) {
      await histDoc.set({
        schoolId, event: 'SUBSCRIPTION_STATUS_CHANGED', at: ctx.now, actorUid: null, actorEmail: null, actorKind: 'SYSTEM',
        reason: null, fromStatus: sub.status || null, toStatus: live, before: null, after: null,
      });
    }
    await subRef(db, schoolId).update({ status: live });
    await schoolRef.update({ subscriptionStatus: live });
    school = { ...school, subscriptionStatus: live };
    did.statusChanged = live !== sub.status;
    if (live === 'GRACE_PERIOD' && !exists) {
      const r = await notifications.notifySchoolAdmins(ctx, {
        schoolId, sourceEventId: `subscription:${hid}`, type: 'SUBSCRIPTION_GRACE_PERIOD', severity: 'WARNING', requiresAck: false,
        title: 'Subscription ended: grace period',
        body: 'Your school subscription has ended and is in its grace period. Please contact admin@avail404.com to renew so access is not interrupted.',
      });
      did.notified += r.created;
    }
  }

  const state = lifecycle.statusOf(school);
  const key = `sub-${sub.version || 0}-${live}`;
  if (state === 'ACTIVE' && isBlocking(live)) {
    const r = await lifecycle.systemTransition(ctx, schoolId, 'EXPIRED', { expectedFrom: 'ACTIVE', reason: live === 'CANCELLED' ? 'Subscription cancelled' : 'Subscription expired', key });
    did.lifecycle = r.ok ? 'EXPIRED' : r.skipped;
    if (r.ok) school = { ...school, status: 'EXPIRED' };
  } else if (state === 'EXPIRED' && VALID.includes(live)) {
    const r = await lifecycle.systemTransition(ctx, schoolId, 'ACTIVE', { expectedFrom: 'EXPIRED', reason: 'Subscription renewed', key });
    did.lifecycle = r.ok ? 'ACTIVE' : r.skipped;
    if (r.ok) school = { ...school, status: 'ACTIVE' };
  }

  // A NOT_STARTED subscription (or its end) changes the mirror without any lifecycle change.
  const want = mirrorFor(school);
  const current = (await schoolRef.get()).data();
  if (current && current.accessMirror !== want) {
    const r = await lifecycle.applySchoolAccess(ctx, schoolId, want, ctx.nowDate().getTime() + 30000);
    if (r.done) {
      await schoolRef.update({ accessMirror: want });
      did.mirrored = true;
    } else {
      await subRef(db, schoolId).update({ reconcilePending: true });
      return { ...did, incomplete: true };
    }
  }
  if (sub.reconcilePending) await subRef(db, schoolId).update({ reconcilePending: false });
  return did;
}

/** Runs reconcile after an owner's change; a failure marks the subscription for the scheduler. */
function withReconcile(fn) {
  return async (ctx, uid, token, data, env) => {
    const out = await fn(ctx, uid, token, data, env);
    if (!out || out.error || out.replayed) return out;
    try {
      out.enforcement = await reconcileSchool(ctx, data.schoolId);
    } catch (e) {
      out.enforcement = { failed: true };
      try {
        await subRef(ctx.db, data.schoolId).update({ reconcilePending: true });
      } catch (_) {
        // the next scheduler run still recomputes from the dates
      }
    }
    return out;
  };
}

/** The 15-minute job. One school failing never stops the others. */
async function runSubscriptionMonitor(ctx, { log = () => {} } = {}) {
  let scanned = 0;
  let changed = 0;
  let failed = 0;
  let after = null;
  for (;;) {
    let q = ctx.db.collection('schoolSubscriptions').orderBy('__name__').limit(PAGE);
    if (after) q = q.startAfter(after);
    const snap = await q.get();
    if (!snap.docs.length) break;
    for (const d of snap.docs) {
      scanned++;
      try {
        const school = (await ctx.db.collection('schools').doc(d.id).get()).data();
        if (!school) continue;
        const sub = d.data();
        const live = statusAt(sub, ctx.nowDate(), zoneOf(school));
        const drift = school.accessMirror !== mirrorFor({ ...school, subscriptionStatus: live });
        if (live === sub.status && school.subscriptionStatus === live && !sub.reconcilePending && !drift && !(lifecycle.statusOf(school) === 'ACTIVE' && isBlocking(live)) && !(lifecycle.statusOf(school) === 'EXPIRED' && VALID.includes(live))) continue;
        const r = await reconcileSchool(ctx, d.id);
        if (r.statusChanged || r.lifecycle || r.mirrored) changed++;
        if (r.incomplete) failed++;
      } catch (e) {
        failed++;
        log('subscription monitor: school failed', { school: d.id, error: String(e && e.message).slice(0, 200) });
      }
    }
    after = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < PAGE) break;
  }
  return { scanned, changed, failed };
}

module.exports = { reconcileSchool, withReconcile, runSubscriptionMonitor };

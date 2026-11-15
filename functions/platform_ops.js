'use strict';

// Platform operations (Phase 4): the stats rollup behind the platform dashboard,
// in-app notices from Avail404 to school administrators, and the app
// requirements (maintenance mode, minimum app build).

const { platformCaller, auditRecord } = require('./platform_admin');

const DAY = 86400000;
const SEVERITIES = ['INFO', 'WARNING', 'CRITICAL'];
const MAX_NOTICE_DAYS = 90;
const MAX_SCHOOLS_PER_NOTICE = 50;
const REFRESH_MIN_GAP_MS = 5 * 60 * 1000;
const MAX_AUTH_PAGES = 30;
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const toMs = (t) => (t instanceof Date ? t.getTime() : t && t.toMillis ? t.toMillis() : typeof t === 'number' ? t : null);

async function countOf(query) {
  if (typeof query.count === 'function') return (await query.count().get()).data().count;
  return (await query.get()).docs.length;
}

/**
 * Recomputes the platform dashboard numbers and each school's usage. Counts come
 * from aggregation queries and Auth sign-in times, never by reading records.
 * Writes platformStats/current and schoolUsage/{schoolId}.
 */
async function computeStats(ctx) {
  const { db, auth } = ctx;
  const nowMs = ctx.nowDate().getTime();
  const schools = await db.collection('schools').get();
  const totals = { schools: { total: 0, active: 0, suspended: 0, inactive: 0 }, newSchools30d: 0, students: 0, staff: 0, parents: 0, branches: 0 };
  const usage = [];
  for (const d of schools.docs) {
    const s = d.data();
    totals.schools.total++;
    const st = s.status === 'SUSPENDED' ? 'suspended' : s.status === 'INACTIVE' ? 'inactive' : 'active';
    totals.schools[st]++;
    if ((toMs(s.createdAt) || 0) > nowMs - 30 * DAY) totals.newSchools30d++;
    const branches = await d.ref.collection('branches').get();
    let students = 0;
    let staff = 0;
    let parents = 0;
    for (const b of branches.docs) {
      students += await countOf(b.ref.collection('students'));
      staff += await countOf(b.ref.collection('staff'));
      parents += await countOf(b.ref.collection('parents'));
    }
    const users = await countOf(db.collection('users').where('schoolId', '==', d.id));
    totals.students += students;
    totals.staff += staff;
    totals.parents += parents;
    totals.branches += branches.docs.length;
    usage.push({ schoolId: d.id, name: s.name || '', status: s.status || 'ACTIVE', students, staff, parents, branches: branches.docs.length, users });
  }

  // Sign-in activity from Auth (bounded; the number is marked partial if cut off).
  const act = { total: 0, active1d: 0, active7d: 0, active30d: 0, partial: false };
  if (auth && auth.listUsers) {
    let token;
    for (let page = 0; page < MAX_AUTH_PAGES; page++) {
      const res = await auth.listUsers(1000, token);
      for (const u of res.users) {
        act.total++;
        const t = u.metadata && u.metadata.lastSignInTime ? Date.parse(u.metadata.lastSignInTime) : NaN;
        if (!Number.isNaN(t)) {
          if (t > nowMs - DAY) act.active1d++;
          if (t > nowMs - 7 * DAY) act.active7d++;
          if (t > nowMs - 30 * DAY) act.active30d++;
        }
      }
      token = res.pageToken;
      if (!token) break;
      if (page === MAX_AUTH_PAGES - 1) act.partial = true;
    }
  }

  const today = new Date(nowMs).toISOString().slice(0, 10);
  const backlog = {
    openDeletionRequests: await countOf(db.collection('accountDeletionRequests').where('status', 'in', ['UNDER_REVIEW', 'ACTION_REQUIRED'])),
    activeSupportGrants: (await db.collection('supportGrants').where('revokedAt', '==', null).get()).docs.filter((g) => toMs(g.data().expiresAt) > nowMs).length,
    offboardingOpen: await countOf(db.collection('platformOffboarding').where('state', 'in', ['REQUESTED', 'APPROVED'])),
    billingOverdue: (await db.collection('platformBilling').where('status', '==', 'DUE').get()).docs.filter((r) => r.data().dueDate < today).length,
  };

  const batch = db.batch();
  for (const u of usage) batch.set(db.collection('schoolUsage').doc(u.schoolId), { ...u, computedAt: ctx.now });
  batch.set(db.collection('platformStats').doc('current'), { ...totals, users: act, backlog, computedAt: ctx.now, computedAtMs: nowMs });
  await batch.commit();
  return { schools: totals.schools.total };
}

/** Any platform role except viewer may recompute (at most once every 5 minutes). */
async function refreshPlatformStats(ctx, callerUid, token) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT', 'COMPLIANCE']);
  if (caller.error) return { error: caller.error };
  const cur = (await ctx.db.collection('platformStats').doc('current').get()).data();
  if (cur && cur.computedAtMs && ctx.nowDate().getTime() - cur.computedAtMs < REFRESH_MIN_GAP_MS) return { ok: true, throttled: true };
  const out = await computeStats(ctx);
  return { ok: true, throttled: false, schools: out.schools };
}

// ---- notices to school administrators ---------------------------------------------

/** Owner/support: an in-app notice for every school admin or chosen schools. */
async function publishPlatformNotice(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT']);
  if (caller.error) return { error: caller.error };
  const title = text(data && data.title, 100);
  const body = text(data && data.body, 1000);
  const severity = data && data.severity;
  const nowMs = ctx.nowDate().getTime();
  const startsMs = data && data.startsAtMs !== undefined ? data.startsAtMs : nowMs;
  const endsMs = data && data.endsAtMs;
  if (title.length < 3) return { error: 'INVALID_ARGUMENT', reason: 'title' };
  if (body.length < 3) return { error: 'INVALID_ARGUMENT', reason: 'body' };
  if (!SEVERITIES.includes(severity)) return { error: 'INVALID_ARGUMENT', reason: 'severity' };
  if (!Number.isFinite(startsMs) || !Number.isFinite(endsMs) || endsMs <= Math.max(startsMs, nowMs) || endsMs > nowMs + MAX_NOTICE_DAYS * DAY) {
    return { error: 'INVALID_ARGUMENT', reason: 'dates' };
  }
  const all = !!(data && data.audienceAll === true);
  let schoolIds = [];
  if (!all) {
    schoolIds = [...new Set(Array.isArray(data && data.schoolIds) ? data.schoolIds.filter((s) => typeof s === 'string' && s) : [])];
    if (!schoolIds.length || schoolIds.length > MAX_SCHOOLS_PER_NOTICE) return { error: 'INVALID_ARGUMENT', reason: 'audience' };
    for (const id of schoolIds) if (!(await ctx.db.collection('schools').doc(id).get()).exists) return { error: 'NOT_FOUND' };
  }
  const ref = ctx.db.collection('platformNotices').doc();
  const batch = ctx.db.batch();
  batch.set(ref, {
    title,
    body,
    severity,
    audienceAll: all,
    schoolIds,
    startsAt: new Date(startsMs),
    endsAt: new Date(endsMs),
    status: 'ACTIVE',
    createdBy: callerUid,
    createdByEmail: caller.profile.email,
    createdAt: ctx.now,
  });
  const a = auditRecord(ctx, {
    action: 'PLATFORM_NOTICE_PUBLISHED',
    actorUid: callerUid,
    actorEmail: caller.profile.email,
    actorPlatformRole: caller.platformRole,
    meta: { id: ref.id, severity, audience: all ? 'ALL' : schoolIds.length },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, id: ref.id };
}

/** Owner/support: ends a notice now. */
async function withdrawPlatformNotice(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT']);
  if (caller.error) return { error: caller.error };
  const id = text(data && data.id, 128);
  const ref = ctx.db.collection('platformNotices').doc(id || '-');
  const n = (await ref.get()).data();
  if (!n) return { error: 'NOT_FOUND' };
  if (n.status === 'WITHDRAWN') return { ok: true, unchanged: true };
  const batch = ctx.db.batch();
  batch.update(ref, { status: 'WITHDRAWN', endsAt: ctx.nowDate(), withdrawnBy: callerUid });
  const a = auditRecord(ctx, {
    action: 'PLATFORM_NOTICE_WITHDRAWN',
    actorUid: callerUid,
    actorEmail: caller.profile.email,
    actorPlatformRole: caller.platformRole,
    meta: { id },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true };
}

/** Owner/support: the notices still showing or scheduled, newest first. */
async function listPlatformNotices(ctx, callerUid, token) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT', 'COMPLIANCE', 'VIEWER']);
  if (caller.error) return { error: caller.error };
  const snap = await ctx.db.collection('platformNotices').limit(200).get();
  const nowMs = ctx.nowDate().getTime();
  const notices = snap.docs
    .map((d) => {
      const n = d.data();
      return {
        id: d.id,
        title: n.title,
        body: n.body,
        severity: n.severity,
        audienceAll: n.audienceAll === true,
        schoolIds: n.schoolIds || [],
        startsAtMs: toMs(n.startsAt),
        endsAtMs: toMs(n.endsAt),
        status: n.status,
        live: n.status === 'ACTIVE' && toMs(n.startsAt) <= nowMs && toMs(n.endsAt) > nowMs,
        createdByEmail: n.createdByEmail || '',
        createdAtMs: toMs(n.createdAt),
      };
    })
    .sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0));
  return { notices };
}

// ---- app requirements ------------------------------------------------------------------

/**
 * Owner-only: maintenance mode and the oldest app build still allowed.
 * `platformSettings/app` is public-read so a signed-out app can see it.
 */
async function setAppRequirements(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const mb = (data && data.minBuild) || {};
  const m = (data && data.maintenance) || {};
  const build = (v) => (Number.isInteger(v) && v >= 0 && v <= 1000000 ? v : null);
  const android = build(mb.android);
  const ios = build(mb.ios);
  if (android === null || ios === null) return { error: 'INVALID_ARGUMENT', reason: 'minBuild' };
  const enabled = m.enabled === true;
  const message = text(m.message, 300);
  if (enabled && message.length < 3) return { error: 'INVALID_ARGUMENT', reason: 'message' };
  const untilMs = m.untilMs === undefined || m.untilMs === null ? null : m.untilMs;
  if (untilMs !== null && (!Number.isFinite(untilMs) || untilMs <= ctx.nowDate().getTime())) return { error: 'INVALID_ARGUMENT', reason: 'until' };
  const ref = ctx.db.collection('platformSettings').doc('app');
  const cur = (await ref.get()).data();
  const version = ((cur && cur.version) || 0) + 1;
  const batch = ctx.db.batch();
  batch.set(ref, {
    minBuild: { android, ios },
    maintenance: { enabled, message: enabled ? message : '', until: untilMs === null ? null : new Date(untilMs) },
    version,
    updatedAt: ctx.now,
    updatedBy: callerUid,
  });
  const a = auditRecord(ctx, {
    action: 'APP_REQUIREMENTS_CHANGED',
    actorUid: callerUid,
    actorEmail: caller.profile.email,
    actorPlatformRole: caller.platformRole,
    meta: { minBuild: { android, ios }, maintenance: enabled },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, version };
}

module.exports = {
  SEVERITIES,
  REFRESH_MIN_GAP_MS,
  computeStats,
  refreshPlatformStats,
  publishPlatformNotice,
  withdrawPlatformNotice,
  listPlatformNotices,
  setAppRequirements,
};

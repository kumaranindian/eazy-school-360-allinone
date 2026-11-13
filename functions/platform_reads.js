'use strict';

// Read endpoints for platform data. The Firestore rules give clients NO access
// to supportGrants, supportAccessLog, platformAuditLog, platformStats,
// schoolUsage or platformNotices (default deny; it also keeps the rules small);
// the app reads them here, where the caller's role and second factor are checked.

const { platformCaller } = require('./platform_admin');
const { loginAllowed } = require('./access');

const toMs = (t) => (t instanceof Date ? t.getTime() : t && t.toMillis ? t.toMillis() : typeof t === 'number' ? t : null);
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

function grantView(g) {
  return {
    schoolId: g.schoolId || '',
    adminUid: g.adminUid || '',
    adminName: g.adminName || '',
    adminEmail: g.adminEmail || '',
    reason: g.reason || '',
    ticket: g.ticket || null,
    expiresAtMs: toMs(g.expiresAt),
    revoked: g.revokedAt !== null && g.revokedAt !== undefined,
  };
}

/** A school or branch administrator who may sign in, as their profile, or null. */
async function schoolAdminCaller(db, uid, token, roles) {
  const u = (await db.collection('users').doc(uid).get()).data();
  if (!u || !roles.includes(u.role) || !u.schoolId || !loginAllowed(u, token)) return null;
  return u;
}

/** Owner/support: the caller's own support grants (to resume or end a session). */
async function listMySupportGrants(ctx, callerUid, token) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT']);
  if (caller.error) return { error: caller.error };
  const snap = await ctx.db.collection('supportGrants').where('adminUid', '==', callerUid).limit(100).get();
  return { grants: snap.docs.map((d) => grantView(d.data())) };
}

/** A school administrator: who from Avail404 has/had access to THEIR school. */
async function listSchoolSupportAccess(ctx, callerUid, token) {
  const u = await schoolAdminCaller(ctx.db, callerUid, token, ['SCHOOL_ADMIN']);
  if (!u) return { error: 'PERMISSION_DENIED' };
  const schoolId = u.schoolId;
  const grants = await ctx.db.collection('supportGrants').where('schoolId', '==', schoolId).limit(100).get();
  const log = await ctx.db.collection('schools').doc(schoolId).collection('supportAccessLog').limit(200).get();
  return {
    schoolId,
    grants: grants.docs.map((d) => grantView(d.data())),
    log: log.docs
      .map((d) => {
        const e = d.data();
        return {
          event: e.event || '',
          adminName: e.adminName || '',
          adminEmail: e.adminEmail || '',
          reason: e.reason || null,
          ticket: e.ticket || null,
          expiresAtMs: toMs(e.expiresAt),
          atMs: toMs(e.createdAt),
          revokedBy: e.revokedBy || null,
        };
      })
      .sort((a, b) => (b.atMs || 0) - (a.atMs || 0))
      .slice(0, 100),
  };
}

/** Any platform role: the dashboard numbers. */
async function getPlatformStats(ctx, callerUid, token) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT', 'COMPLIANCE', 'VIEWER']);
  if (caller.error) return { error: caller.error };
  const s = (await ctx.db.collection('platformStats').doc('current').get()).data();
  if (!s) return { stats: null };
  const { computedAt, ...rest } = s; // the server timestamp is not JSON; computedAtMs is
  return { stats: { ...rest, computedAtMs: s.computedAtMs || toMs(computedAt) } };
}

/** Owner/compliance: the newest platform actions. */
async function listAuditLog(ctx, callerUid, token) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'COMPLIANCE']);
  if (caller.error) return { error: caller.error };
  const snap = await ctx.db.collection('platformAuditLog').orderBy('createdAt', 'desc').limit(200).get();
  const entries = snap.docs
    .map((d) => {
      const r = d.data();
      return {
        id: d.id,
        action: r.action || '',
        actorEmail: r.actorEmail || '',
        actorPlatformRole: r.actorPlatformRole || '',
        targetEmail: r.targetEmail || '',
        schoolId: r.schoolId || '',
        reason: r.reason || '',
        result: r.result || '',
        source: r.source || '',
        atMs: toMs(r.createdAt),
      };
    })
    .sort((a, b) => (b.atMs || 0) - (a.atMs || 0));
  return { entries };
}

/** School/branch administrators: notices for everyone or their school (the app filters by time). */
async function listMyNotices(ctx, callerUid, token) {
  const u = await schoolAdminCaller(ctx.db, callerUid, token, ['SCHOOL_ADMIN', 'BRANCH_ADMIN']);
  if (!u) return { error: 'PERMISSION_DENIED' };
  const all = await ctx.db.collection('platformNotices').where('audienceAll', '==', true).limit(100).get();
  const mine = await ctx.db.collection('platformNotices').where('schoolIds', 'array-contains', u.schoolId).limit(100).get();
  const byId = new Map();
  for (const d of [...all.docs, ...mine.docs]) {
    const n = d.data();
    byId.set(d.id, {
      id: d.id,
      title: text(n.title, 100),
      body: text(n.body, 1000),
      severity: n.severity || 'INFO',
      startsAtMs: toMs(n.startsAt),
      endsAtMs: toMs(n.endsAt),
      withdrawn: n.status === 'WITHDRAWN',
    });
  }
  return { notices: [...byId.values()] };
}

module.exports = { listMySupportGrants, listSchoolSupportAccess, getPlatformStats, listAuditLog, listMyNotices, grantView };

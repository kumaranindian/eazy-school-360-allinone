'use strict';

// Support access (audit finding H1): a platform admin reaches a school's data
// only through a time-boxed, reasoned, READ-ONLY grant that the school can see
// and revoke. See docs/platform-admin/PLATFORM_ADMIN_PLAN.md (4.4, 5.1).
//
// supportGrants/{adminUid}__{schoolId}  honoured by firestore.rules (supportRead)
// schools/{schoolId}/supportAccessLog/* what the school's admins see
// platformAuditLog/*                    what Avail404 sees

const { platformCaller, auditRecord } = require('./platform_admin');
const { assertAdmin } = require('./access');

const MINUTES = [15, 30, 60, 120, 240];
const REASON_MIN = 15;
const REASON_MAX = 500;
const TICKET_MAX = 60;

const grantId = (adminUid, schoolId) => `${adminUid}__${schoolId}`;
const toMs = (t) => (t instanceof Date ? t.getTime() : t && t.toMillis ? t.toMillis() : typeof t === 'number' ? t : null);
const activeGrant = (g, nowMs) => !!g && !g.revokedAt && toMs(g.expiresAt) > nowMs;
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

function logEntry(ctx, schoolId, e) {
  const ref = ctx.db.collection('schools').doc(schoolId).collection('supportAccessLog').doc();
  return {
    ref,
    rec: {
      schoolId,
      event: e.event, // GRANTED | REVOKED
      adminUid: e.adminUid,
      adminName: e.adminName || '',
      adminEmail: e.adminEmail || '',
      reason: e.reason || null,
      ticket: e.ticket || null,
      scope: 'READ',
      expiresAt: e.expiresAt || null,
      revokedBy: e.revokedBy || null,
      createdAt: ctx.now,
    },
  };
}

/** SUPPORT or OWNER opens a read-only support session for one school. */
async function requestSupportAccess(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT']);
  if (caller.error) return { error: caller.error };
  const schoolId = text(data && data.schoolId, 128);
  const reason = text(data && data.reason, REASON_MAX);
  const ticket = text(data && data.ticket, TICKET_MAX);
  const minutes = data && data.minutes === undefined ? 60 : data && data.minutes;
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  if (reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: 'reason' };
  if (!MINUTES.includes(minutes)) return { error: 'INVALID_ARGUMENT', reason: 'minutes' };
  const school = (await ctx.db.collection('schools').doc(schoolId).get()).data();
  if (!school) return { error: 'NOT_FOUND' };

  const expiresAt = new Date(ctx.nowDate().getTime() + minutes * 60 * 1000);
  const p = caller.profile;
  const batch = ctx.db.batch();
  batch.set(ctx.db.collection('supportGrants').doc(grantId(callerUid, schoolId)), {
    adminUid: callerUid,
    adminName: p.name || '',
    adminEmail: p.email || '',
    schoolId,
    scope: 'READ',
    reason,
    ticket: ticket || null,
    grantedAt: ctx.now,
    expiresAt,
    revokedAt: null,
    revokedBy: null,
  });
  const l = logEntry(ctx, schoolId, { event: 'GRANTED', adminUid: callerUid, adminName: p.name, adminEmail: p.email, reason, ticket: ticket || null, expiresAt });
  batch.set(l.ref, l.rec);
  const a = auditRecord(ctx, {
    action: 'SUPPORT_ACCESS_GRANTED',
    actorUid: callerUid,
    actorEmail: p.email,
    actorPlatformRole: caller.platformRole,
    schoolId,
    reason,
    meta: { minutes, ticket: ticket || null },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, schoolId, schoolName: school.name || '', expiresAtMs: expiresAt.getTime() };
}

/**
 * Ends a grant early. Allowed to: the platform admin who holds it, a platform
 * OWNER, and the SCHOOL ADMIN of the school (their data, their call).
 */
async function revokeSupportAccess(ctx, callerUid, token, data) {
  const schoolId = text(data && data.schoolId, 128);
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  const wantedAdmin = text(data && data.adminUid, 128);

  let actor = null;
  const platform = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT']);
  if (!platform.error) {
    const target = wantedAdmin || callerUid;
    if (target !== callerUid && platform.platformRole !== 'OWNER') return { error: 'PERMISSION_DENIED' };
    actor = { kind: 'PLATFORM', target, profile: platform.profile, platformRole: platform.platformRole };
  } else if (platform.error === 'MFA_REQUIRED') {
    return { error: 'MFA_REQUIRED' };
  } else {
    const admin = await assertAdmin(ctx.db, callerUid, schoolId, null, token);
    if (!admin || admin.role !== 'SCHOOL_ADMIN') return { error: 'PERMISSION_DENIED' };
    if (!wantedAdmin) return { error: 'INVALID_ARGUMENT', reason: 'adminUid' };
    actor = { kind: 'SCHOOL', target: wantedAdmin, profile: admin };
  }

  const ref = ctx.db.collection('supportGrants').doc(grantId(actor.target, schoolId));
  const g = (await ref.get()).data();
  if (!g) return { error: 'NOT_FOUND' };
  if (!activeGrant(g, ctx.nowDate().getTime())) return { ok: true, alreadyEnded: true };

  const batch = ctx.db.batch();
  batch.update(ref, { revokedAt: ctx.now, revokedBy: callerUid });
  const l = logEntry(ctx, schoolId, {
    event: 'REVOKED',
    adminUid: actor.target,
    adminName: g.adminName,
    adminEmail: g.adminEmail,
    reason: g.reason,
    ticket: g.ticket,
    expiresAt: g.expiresAt,
    revokedBy: actor.kind === 'SCHOOL' ? 'SCHOOL_ADMIN' : 'PLATFORM',
  });
  batch.set(l.ref, l.rec);
  const a = auditRecord(ctx, {
    action: 'SUPPORT_ACCESS_REVOKED',
    actorUid: callerUid,
    actorEmail: actor.profile.email,
    actorPlatformRole: actor.platformRole || null,
    targetUid: actor.target,
    schoolId,
    meta: { by: actor.kind },
  });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true };
}

async function countOf(query) {
  if (typeof query.count === 'function') return (await query.count().get()).data().count;
  return (await query.get()).docs.length;
}

/**
 * Metadata and head counts for one school (never student, staff or finance
 * records), for the platform schools directory. Any platform role.
 */
async function getSchoolOverview(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT', 'COMPLIANCE', 'VIEWER']);
  if (caller.error) return { error: caller.error };
  const schoolId = text(data && data.schoolId, 128);
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  const schoolRef = ctx.db.collection('schools').doc(schoolId);
  const s = (await schoolRef.get()).data();
  if (!s) return { error: 'NOT_FOUND' };

  const branchSnap = await schoolRef.collection('branches').get();
  const branches = branchSnap.docs.map((d) => ({ id: d.id, name: d.data().name || d.id, status: d.data().status || '' }));
  const sum = async (coll) => {
    let n = 0;
    for (const b of branches) n += await countOf(schoolRef.collection('branches').doc(b.id).collection(coll));
    return n;
  };
  const [students, staff, parents] = [await sum('students'), await sum('staff'), await sum('parents')];

  const adminSnap = await ctx.db.collection('users').where('schoolId', '==', schoolId).where('role', '==', 'SCHOOL_ADMIN').limit(20).get();
  const admins = adminSnap.docs.map((d) => ({ uid: d.id, name: d.data().name || '', email: d.data().email || '', status: d.data().status || '' }));

  const nowMs = ctx.nowDate().getTime();
  const grantSnap = await ctx.db.collection('supportGrants').where('schoolId', '==', schoolId).limit(50).get();
  const grants = grantSnap.docs
    .map((d) => d.data())
    .filter((g) => activeGrant(g, nowMs))
    .map((g) => ({ adminUid: g.adminUid, adminName: g.adminName || '', adminEmail: g.adminEmail || '', reason: g.reason, expiresAtMs: toMs(g.expiresAt) }));

  const auditSnap = await ctx.db.collection('platformAuditLog').where('schoolId', '==', schoolId).limit(50).get();
  const recentActions = auditSnap.docs
    .map((d) => d.data())
    .sort((a, b) => (toMs(b.createdAt) || 0) - (toMs(a.createdAt) || 0))
    .slice(0, 10)
    .map((r) => ({ action: r.action, actorEmail: r.actorEmail || '', reason: r.reason || null, atMs: toMs(r.createdAt) }));

  const off = (await ctx.db.collection('platformOffboarding').doc(schoolId).get()).data();
  const offboarding = off
    ? {
        state: off.state,
        reason: off.reason || '',
        requestedBy: off.requestedBy || '',
        requestedByEmail: off.requestedByEmail || '',
        graceUntilMs: toMs(off.graceUntil),
        approvedBy: off.approvedBy || null,
      }
    : null;

  return {
    offboarding,
    school: {
      id: schoolId,
      statusReason: s.statusReason || '',
      features: s.features || {},
      name: s.name || '',
      code: s.code || '',
      status: s.status || '',
      email: s.email || '',
      phone: s.phone || '',
      city: s.city || '',
      state: s.state || '',
      country: s.country || '',
      currency: s.currency || '',
      timezone: s.timezone || '',
      createdAtMs: toMs(s.createdAt),
    },
    branches,
    counts: { branches: branches.length, students, staff, parents },
    admins,
    activeGrants: grants,
    recentActions,
  };
}

module.exports = { MINUTES, REASON_MIN, grantId, activeGrant, requestSupportAccess, revokeSupportAccess, getSchoolOverview };

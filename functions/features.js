'use strict';

// Feature catalogue and per-school switches (docs/platform-governance/FEATURE_CONTROL_DESIGN.md,
// Phases 7-8). The catalogue lists ONLY modules that exist in the repository. A school's effective
// switches live in `schools.features` (the keys `admission` and `publicAdmission` predate this
// and are kept, decision D13); a missing key means ON, so every existing school is unchanged.
// `platformFeatureDefaults/default` is the global default for NEW schools; it is copied into the
// school when it is created, so changing a default never changes an existing school.
// `schoolFeatureHistory` is append-only (one entry per key changed). Nothing here touches data.

const { idOf, own } = require('./ids');
const { platformCaller, auditRecord } = require('./platform_admin');
const notifications = require('./school_notifications');

const CATALOGUE = Object.freeze([
  { key: 'students', label: 'Student management', dependsOn: ['academic'] },
  { key: 'parents', label: 'Parents and family links', dependsOn: ['students'] },
  { key: 'staff', label: 'Staff, teachers and departments', dependsOn: [] },
  { key: 'academic', label: 'Academic setup (years, classes, subjects, calendar)', dependsOn: [] },
  { key: 'attendance', label: 'Student and staff attendance', dependsOn: ['students', 'academic'] },
  { key: 'leave', label: 'Leave management', dependsOn: ['staff'] },
  { key: 'fees', label: 'Fees, invoices and payments', dependsOn: ['students'] },
  { key: 'feeReminders', label: 'Fee reminders', dependsOn: ['fees'] },
  { key: 'admission', label: 'Admission management', dependsOn: ['students'] },
  { key: 'publicAdmission', label: 'Public admission enquiry page', dependsOn: ['admission'] },
  { key: 'exams', label: 'Exams, marks and results', dependsOn: ['students', 'academic'] },
  { key: 'timetable', label: 'Timetable and substitutions', dependsOn: ['academic', 'staff'] },
  { key: 'homework', label: 'Homework and submissions', dependsOn: ['academic'] },
  { key: 'announcements', label: 'Announcements', dependsOn: [] },
  { key: 'messages', label: 'Parent-teacher messaging', dependsOn: ['parents'] },
  { key: 'notifications', label: 'Push and in-app notifications', dependsOn: [] },
]);

const KEYS = CATALOGUE.map((f) => f.key);
const BY_KEY = Object.fromEntries(CATALOGUE.map((f) => [f.key, f]));
const REASON_MIN = 10;
const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const toMs = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : t instanceof Date ? t.getTime() : null);

/** Every feature that depends on [key], directly or through others. */
function dependantsOf(key) {
  const out = new Set();
  const walk = (k) => {
    for (const f of CATALOGUE) {
      if (f.dependsOn.includes(k) && !out.has(f.key)) {
        out.add(f.key);
        walk(f.key);
      }
    }
  };
  walk(key);
  return [...out];
}

/** The effective switches of a school (missing = on), for every catalogue key. */
const effective = (features) => Object.fromEntries(KEYS.map((k) => [k, !(features && features[k] === false)]));

/**
 * Whether [key] is usable for a school with switches [features]: it AND everything it depends on
 * is on. A legacy school that switched `admission` off but never `publicAdmission` therefore
 * has no public page either.
 */
function usable(features, key) {
  const f = own(BY_KEY, key);
  if (!f) return true; // not a catalogue feature: never blocked here
  if (features && features[key] === false) return false;
  return f.dependsOn.every((d) => usable(features, d));
}

/** Whether [features] is internally consistent: every ON feature has all its dependencies ON. */
function consistent(eff) {
  return CATALOGUE.every((f) => !eff[f.key] || f.dependsOn.every((d) => eff[d]));
}

/**
 * Applies [changes] ({key: bool}) to [current] effective switches.
 * Returns { next, changed: [{key, from, to, cascade}] } or { error, reason, keys }.
 * Enabling needs every dependency ON; disabling a feature that others depend on needs
 * `confirm` and then switches those dependants off too (nothing else).
 */
function planChange(current, changes, confirm) {
  const next = { ...current };
  const cascade = new Set();
  for (const [k, v] of Object.entries(changes)) {
    if (!own(BY_KEY, k) || typeof v !== 'boolean') return { error: 'INVALID_ARGUMENT', reason: 'features' };
    next[k] = v;
  }
  for (const [k, v] of Object.entries(changes)) {
    if (v) continue;
    const deps = dependantsOf(k).filter((d) => next[d]);
    if (deps.length && !confirm) return { error: 'FAILED_PRECONDITION', reason: 'DEPENDANTS', keys: deps };
    for (const d of deps) {
      next[d] = false;
      cascade.add(d);
    }
  }
  for (const [k, v] of Object.entries(changes)) {
    if (!v) continue;
    const missing = own(BY_KEY, k).dependsOn.filter((d) => !next[d]);
    if (missing.length) return { error: 'FAILED_PRECONDITION', reason: 'DEPENDENCY', keys: missing };
  }
  const changed = KEYS.filter((k) => next[k] !== current[k]).map((k) => ({ key: k, from: current[k], to: next[k], cascade: cascade.has(k) && !(k in changes) }));
  return { next, changed };
}

// ---- defaults for new schools ----------------------------------------------------------

const defaultsRef = (db) => db.collection('platformFeatureDefaults').doc('default');

/** Full explicit switches to copy into a NEW school. */
async function snapshotDefaults(db) {
  const d = (await defaultsRef(db).get()).data();
  return effective(d && d.features);
}

async function getFeatureConfig(ctx, callerUid, token) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT', 'COMPLIANCE', 'VIEWER']);
  if (caller.error) return { error: caller.error };
  return { catalogue: CATALOGUE.map((f) => ({ ...f })), defaults: await snapshotDefaults(ctx.db) };
}

/** Owner: the defaults copied into schools created from now on. Existing schools are unchanged. */
async function setFeatureDefaults(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const incoming = data && data.features;
  if (!incoming || typeof incoming !== 'object' || Array.isArray(incoming)) return { error: 'INVALID_ARGUMENT', reason: 'features' };
  const before = await snapshotDefaults(ctx.db);
  const next = { ...before };
  for (const [k, v] of Object.entries(incoming)) {
    if (!own(BY_KEY, k) || typeof v !== 'boolean') return { error: 'INVALID_ARGUMENT', reason: 'features' };
    next[k] = v;
  }
  if (!consistent(next)) return { error: 'FAILED_PRECONDITION', reason: 'DEPENDENCY' };
  const cur = (await defaultsRef(ctx.db).get()).data();
  const batch = ctx.db.batch();
  batch.set(defaultsRef(ctx.db), { features: next, version: ((cur && cur.version) || 0) + 1, updatedAt: ctx.now, updatedBy: callerUid });
  const a = auditRecord(ctx, { action: 'FEATURE_DEFAULTS_CHANGED', actorUid: callerUid, actorEmail: caller.profile.email, actorPlatformRole: caller.platformRole, meta: { before, after: next } });
  batch.set(a.ref, a.rec);
  await batch.commit();
  return { ok: true, defaults: next };
}

// ---- per-school switches ------------------------------------------------------------------

/**
 * Owner: turns modules on or off for one school. A reason (10+ characters) is required when
 * anything is switched OFF. Writes the school, one history entry per key changed and the
 * audit record together, then tells the school's administrators.
 */
async function setSchoolFeatures(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  const incoming = data && data.features;
  if (!schoolId || !incoming || typeof incoming !== 'object' || Array.isArray(incoming) || !Object.keys(incoming).length) return { error: 'INVALID_ARGUMENT', reason: 'features' };
  const reason = text(data && data.reason, 500);
  const confirm = data && data.confirmDependants === true;

  const out = await ctx.db.runTransaction(async (tx) => {
    const ref = ctx.db.collection('schools').doc(schoolId);
    const school = (await tx.get(ref)).data();
    if (!school) return { error: 'NOT_FOUND' };
    const current = effective(school.features);
    const plan = planChange(current, incoming, confirm);
    if (plan.error) return plan;
    if (!plan.changed.length) return { ok: true, unchanged: true, features: school.features || {} };
    if (plan.changed.some((c) => !c.to) && reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: 'reason' };
    const version = (school.featuresVersion || 0) + 1;
    const features = { ...(school.features || {}) };
    for (const c of plan.changed) features[c.key] = c.to;
    tx.update(ref, { features, featuresVersion: version, updatedAt: ctx.now, updatedBy: callerUid });
    for (const c of plan.changed) {
      tx.set(ctx.db.collection('schoolFeatureHistory').doc(), {
        schoolId, feature: c.key, from: c.from, to: c.to, cascade: c.cascade, version, reason: reason || null,
        actorUid: callerUid, actorEmail: caller.profile.email, at: ctx.now,
      });
    }
    const a = auditRecord(ctx, { action: 'SCHOOL_FEATURES_CHANGED', actorUid: callerUid, actorEmail: caller.profile.email, actorPlatformRole: caller.platformRole, schoolId, reason: reason || null, meta: { changed: plan.changed.map((c) => `${c.key}:${c.to ? 'on' : 'off'}`) } });
    tx.set(a.ref, a.rec);
    return { ok: true, features, changed: plan.changed, version };
  });
  if (out.error || out.unchanged) return out;

  let notified = null;
  try {
    const word = (c) => `${own(BY_KEY, c.key).label} ${c.to ? 'switched on' : 'switched off'}`;
    notified = await notifications.notifySchoolAdmins(ctx, {
      schoolId, sourceEventId: `features:${schoolId}:${out.version}`, type: 'FEATURE_CHANGED', severity: 'INFO', requiresAck: false,
      title: 'Your school modules changed',
      body: `${out.changed.map(word).join('. ')}.\n\nContact admin@avail404.com if this is unexpected.`,
    });
  } catch (e) {
    notified = { failed: true };
  }
  return { ok: true, features: out.features, changed: out.changed.map((c) => ({ key: c.key, from: c.from, to: c.to, cascade: c.cascade })), notified };
}

async function getFeatureHistory(ctx, callerUid, token, data) {
  const caller = await platformCaller(ctx.db, callerUid, token, ['OWNER', 'SUPPORT', 'COMPLIANCE', 'VIEWER']);
  if (caller.error) return { error: caller.error };
  const schoolId = idOf(data && data.schoolId);
  if (!schoolId) return { error: 'INVALID_ARGUMENT', reason: 'schoolId' };
  const snap = await ctx.db.collection('schoolFeatureHistory').where('schoolId', '==', schoolId).limit(300).get();
  const entries = snap.docs
    .map((d) => {
      const h = d.data();
      return { id: d.id, feature: h.feature, from: h.from, to: h.to, cascade: h.cascade === true, reason: h.reason || null, actorEmail: h.actorEmail || null, atMs: toMs(h.at), version: h.version || 0 };
    })
    .sort((a, b) => (b.atMs || 0) - (a.atMs || 0));
  return { entries };
}

module.exports = {
  CATALOGUE, KEYS, BY_KEY, REASON_MIN,
  dependantsOf, effective, consistent, planChange, usable,
  snapshotDefaults, getFeatureConfig, setFeatureDefaults, setSchoolFeatures, getFeatureHistory,
};

'use strict';

// The central audit trail (docs/platform-governance/AUDIT_ARCHITECTURE.md, Phases 9-11).
//
//  - ONE writer: this module is the only code that writes `auditEvents/{yyyyMM}/events/{eventId}`.
//    It validates the schema, redacts, stamps the server time and derives a deterministic event id
//    (hash of the source event id + type), so a retried trigger or callable never duplicates.
//  - Append-only: nothing here updates or deletes an event. Retention exports a month to Cloud Storage
//    and only deletes when explicitly switched on.
//  - Every event carries a TRUST level: T1 written in the same operation as the change (callable),
//    T2 observed by a Firestore trigger after a client-side write, T3 system (scheduler), T4 reported
//    by the app (NOT proof; shown as client-reported).
//  - Clients have no rules for this collection: it is read only through the callables below.
//  - Never stored: passwords, OTPs, tokens, secrets, download URLs, whole documents. Changes carry
//    values only for an explicit per-entity allowlist and never for personal fields.

const crypto = require('node:crypto');
const { platformCaller } = require('./platform_admin');
const { validId, own } = require('./ids');

const CATEGORIES = Object.freeze([
  'AUTHENTICATION', 'SCHOOL', 'SUBSCRIPTION', 'FEATURE', 'STUDENT', 'PARENT', 'STAFF', 'ATTENDANCE_LEAVE',
  'FEES', 'ACADEMIC', 'ADMISSION', 'COMMUNICATION', 'DATA_CONFIG', 'PLATFORM', 'SECURITY',
]);
const ACTIONS = Object.freeze([
  'CREATE', 'UPDATE', 'DELETE', 'ACTIVATE', 'DEACTIVATE', 'SUSPEND', 'REACTIVATE', 'EXPIRE', 'CLOSE', 'RECOVER',
  'APPROVE', 'REJECT', 'ENABLE', 'DISABLE', 'LOGIN', 'LOGOUT', 'EXPORT', 'VIEW', 'RESET', 'ASSIGN', 'ARCHIVE', 'OTHER',
]);
const RESULTS = Object.freeze(['SUCCESS', 'FAILURE', 'DENIED', 'FLAGGED']);
const SOURCES = Object.freeze(['CALLABLE', 'TRIGGER', 'SCHEDULER', 'CLIENT_REPORTED']);
const TRUST = Object.freeze({ CALLABLE: 'T1', TRIGGER: 'T2', SCHEDULER: 'T3', CLIENT_REPORTED: 'T4' });
const APPLICATIONS = Object.freeze(['PLATFORM_ADMIN', 'SCHOOL_ADMIN', 'BRANCH_ADMIN', 'TEACHER', 'PARENT', 'FINANCE', 'WEB', 'PUBLIC_PORTAL', 'FUNCTION', 'SCHEDULER']);
const PLATFORMS = Object.freeze(['ANDROID', 'IOS', 'WEB', 'SERVER']);
const SCHEMA_VERSION = 1;

const EVENT_TYPE = /^[A-Z][A-Z0-9_]{2,63}$/;
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const FORBIDDEN_KEY = /pass(word)?|otp|token|secret|authorization|api[-_]?key|download[-_]?url|signed[-_]?url|^url$|credential/i;
const SENSITIVE_FIELD = /phone|mobile|e?mail|address|dob|birth|aadhaar|aadhar|ssn|medical|blood|passport|nationality|photo|signature|guardian/i;
const URL_WITH_SECRET = /https?:\/\/\S*([?&](token|alt=media|x-goog-signature|key)=)/i;
// Bearer headers and JWT-shaped strings (three dot-separated base64url parts) are never stored, wherever they appear.
const SECRET_STRING = /(^|\s)bearer\s+\S+|eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}|eyJ[A-Za-z0-9_-]{16,}/i;
const MAX_STRING = 300;
const MAX_CHANGES = 30;
const MAX_META_KEYS = 20;

const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const toMs = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : t instanceof Date ? t.getTime() : typeof t === 'number' ? t : null);
const monthOf = (date) => `${date.getUTCFullYear()}${String(date.getUTCMonth() + 1).padStart(2, '0')}`;
const eventIdFor = (sourceId, eventType) => crypto.createHash('sha256').update(`${sourceId}|${eventType}`).digest('hex').slice(0, 32);

const partition = (db, month) => db.collection('auditEvents').doc(month).collection('events');

/** Removes forbidden keys and secret-bearing URLs, bounds depth and size. Returns a fresh value. */
function redact(value, depth = 0) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') return URL_WITH_SECRET.test(value) ? '[redacted-url]' : SECRET_STRING.test(value) ? '[redacted]' : value.slice(0, MAX_STRING);
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (value instanceof Date) return value.toISOString();
  if (depth >= 3) return '[truncated]';
  if (Array.isArray(value)) return value.slice(0, 20).map((v) => redact(v, depth + 1));
  if (typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value).slice(0, MAX_META_KEYS)) {
      if (FORBIDDEN_KEY.test(k)) continue;
      out[k] = redact(v, depth + 1);
    }
    return out;
  }
  return null;
}

/**
 * The change list for an event. A value is recorded only when [safe] allows the field AND it is not
 * a personal field; everything else is recorded as "changed" without values.
 */
function changeList(changes, safe = []) {
  const out = [];
  for (const c of (Array.isArray(changes) ? changes : []).slice(0, MAX_CHANGES)) {
    const field = text(c && c.field, 80);
    if (!field || FORBIDDEN_KEY.test(field)) continue;
    if (safe.includes(field) && !SENSITIVE_FIELD.test(field)) out.push({ field, from: redact(c.from), to: redact(c.to) });
    else out.push({ field, changed: true });
  }
  return out;
}

/** Validates and normalises an event. Returns { event } or { error, reason }. */
function buildEvent(input, nowDate) {
  const i = input || {};
  const sourceId = text(i.sourceId, 200);
  if (!sourceId) return { error: 'INVALID_EVENT', reason: 'sourceId' };
  if (!EVENT_TYPE.test(i.eventType || '')) return { error: 'INVALID_EVENT', reason: 'eventType' };
  if (!CATEGORIES.includes(i.category)) return { error: 'INVALID_EVENT', reason: 'category' };
  const action = i.action || 'OTHER';
  if (!ACTIONS.includes(action)) return { error: 'INVALID_EVENT', reason: 'action' };
  const result = i.result || 'SUCCESS';
  if (!RESULTS.includes(result)) return { error: 'INVALID_EVENT', reason: 'result' };
  if (!SOURCES.includes(i.source)) return { error: 'INVALID_EVENT', reason: 'source' };
  for (const k of ['schoolId', 'branchId', 'actorUserId', 'targetEntityId']) {
    if (i[k] !== undefined && i[k] !== null && !ID.test(String(i[k]))) return { error: 'INVALID_EVENT', reason: k };
  }
  const application = i.application && APPLICATIONS.includes(i.application) ? i.application : null;
  const platform = i.platform && PLATFORMS.includes(i.platform) ? i.platform : i.source === 'CLIENT_REPORTED' ? null : 'SERVER';
  const eventId = eventIdFor(sourceId, i.eventType);
  const event = {
    eventId,
    eventType: i.eventType,
    category: i.category,
    schoolId: i.schoolId || null,
    branchId: i.branchId || null,
    actorUserId: i.actorUserId || null,
    actorRole: text(i.actorRole, 40) || null,
    actorNameSnapshot: text(i.actorNameSnapshot, 120) || null,
    application,
    platform,
    targetEntity: text(i.targetEntity, 60) || null,
    targetEntityId: i.targetEntityId || null,
    action,
    result,
    timestampMs: nowDate.getTime(),
    correlationId: text(i.correlationId, 64) || null,
    source: i.source,
    trust: TRUST[i.source],
    changeSummary: {
      description: text(i.description, 300) || null,
      changes: changeList(i.changes, i.safeFields || []),
    },
    metadata: redact(i.metadata || {}),
    schemaVersion: SCHEMA_VERSION,
  };
  return { event, month: monthOf(nowDate) };
}

/**
 * Writes one event (the ONLY writer). Idempotent: a repeat of the same source event is a no-op
 * ({ duplicate: true }). A write failure is thrown so a trigger retries and a callable fails.
 */
async function record(ctx, input) {
  const built = buildEvent(input, ctx.nowDate());
  if (built.error) throw Object.assign(new Error(`invalid audit event: ${built.reason}`), { code: 'invalid-audit-event' });
  const ref = partition(ctx.db, built.month).doc(built.event.eventId);
  try {
    await ref.create({ ...built.event, timestamp: ctx.now });
  } catch (e) {
    if (e && (e.code === 6 || e.code === 'already-exists' || /already exists/i.test(String(e.message)))) return { duplicate: true, eventId: built.event.eventId };
    throw e;
  }
  return { ok: true, eventId: built.event.eventId, month: built.month };
}

/** Like [record] but never throws: for observers that must not fail the thing they observe. */
async function recordSafe(ctx, input, log = () => {}) {
  try {
    return await record(ctx, input);
  } catch (e) {
    log('audit write failed', { type: input && input.eventType, error: String(e && e.message).slice(0, 200) });
    return { failed: true };
  }
}

// ---- mapping the existing audit sources onto the central schema ----------------------------------

const PLATFORM_CATEGORY = [
  [/^SCHOOL_FEATURES_CHANGED$|^FEATURE_/, 'FEATURE', 'UPDATE'],
  [/^SUBSCRIPTION_|^PLAN_SAVED$/, 'SUBSCRIPTION', 'UPDATE'],
  [/^SCHOOL_CREATED$/, 'SCHOOL', 'CREATE'],
  [/^SCHOOL_ACTIVATED$/, 'SCHOOL', 'ACTIVATE'],
  [/^SCHOOL_DEACTIVATED$/, 'SCHOOL', 'DEACTIVATE'],
  [/^SCHOOL_SUSPENDED$/, 'SCHOOL', 'SUSPEND'],
  [/^SCHOOL_REACTIVATED$/, 'SCHOOL', 'REACTIVATE'],
  [/^SCHOOL_EXPIRED$/, 'SCHOOL', 'EXPIRE'],
  [/^SCHOOL_CLOSED$/, 'SCHOOL', 'CLOSE'],
  [/^SCHOOL_RECOVER/, 'SCHOOL', 'RECOVER'],
  [/^SCHOOL_|^OFFBOARDING_/, 'SCHOOL', 'UPDATE'],
  [/^AUDIT_/, 'SECURITY', 'OTHER'],
  [/ACCESS|LOGIN|PASSWORD|MFA|SECOND_FACTOR|ADMIN_/, 'SECURITY', 'OTHER'],
];

/** The central event for one `platformAuditLog` document (already trustworthy: written with the change). */
function fromPlatformAudit(id, a) {
  const action = text(a && a.action, 64);
  if (!EVENT_TYPE.test(action)) return null;
  const hit = PLATFORM_CATEGORY.find(([re]) => re.test(action));
  const denied = action === 'FEATURE_ACCESS_DENIED' || (a && a.result === 'DENIED');
  const trigger = a && a.source === 'TRIGGER';
  return {
    sourceId: `platform|${id}`,
    eventType: action,
    category: hit ? hit[1] : 'PLATFORM',
    action: hit ? hit[2] : 'OTHER',
    result: denied ? 'DENIED' : a && a.result === 'FLAGGED' ? 'FLAGGED' : a && a.result && a.result !== 'OK' ? 'FAILURE' : 'SUCCESS',
    source: a && a.source === 'SCHEDULER' ? 'SCHEDULER' : trigger ? 'TRIGGER' : 'CALLABLE',
    schoolId: a && a.schoolId,
    actorUserId: a && a.actorUid && a.actorUid !== 'system' ? a.actorUid : null,
    actorRole: a && a.actorPlatformRole,
    actorNameSnapshot: a && a.actorEmail && a.actorEmail !== 'system' ? a.actorEmail : null,
    application: a && (a.actorPlatformRole === 'SYSTEM' || a.source === 'SCHEDULER') ? 'SCHEDULER' : a && a.actorPlatformRole ? 'PLATFORM_ADMIN' : 'FUNCTION',
    targetEntity: a && a.targetUid ? 'USER' : a && a.schoolId ? 'SCHOOL' : null,
    targetEntityId: a && (a.targetUid || null),
    description: a && a.reason,
    metadata: { ...(a && a.meta ? a.meta : {}), mirroredFrom: 'platformAuditLog' },
  };
}

/** The central event for one `schools/{s}/authAudit` document (sign-in and login administration trail). */
function fromAuthAudit(schoolId, id, a) {
  const type = String((a && (a.type || a.event)) || '').toUpperCase().replace(/[^A-Z0-9_]/g, '_');
  if (!EVENT_TYPE.test(type)) return null;
  const { actorId, type: _t, event: _e, createdAt, ...rest } = a || {};
  return {
    sourceId: `auth|${schoolId}|${id}`,
    eventType: type,
    category: 'AUTHENTICATION',
    action: /DISABLE|REVOK/.test(type) ? 'DISABLE' : /ENABLE|GRANT/.test(type) ? 'ENABLE' : /RESET|PASSWORD/.test(type) ? 'RESET' : /CREATE/.test(type) ? 'CREATE' : 'UPDATE',
    result: 'SUCCESS',
    source: 'CALLABLE',
    schoolId,
    actorUserId: typeof actorId === 'string' && ID.test(actorId) ? actorId : null,
    application: 'FUNCTION',
    metadata: { ...rest, mirroredFrom: 'authAudit' },
  };
}

// ---- client-written modules (T2) -----------------------------------------------------------------

// collection -> { category, entity, safe fields whose values may appear in a change }. Values of any
// other field are never recorded, only that it changed.
const MODULES = Object.freeze({
  students: { category: 'STUDENT', entity: 'STUDENT', safe: ['status', 'currentClassId', 'currentSectionId', 'currentAcademicYearId'] },
  parents: { category: 'PARENT', entity: 'PARENT', safe: ['status'] },
  staff: { category: 'STAFF', entity: 'STAFF', safe: ['status', 'role', 'designationId', 'departmentId'] },
  attendanceSessions: { category: 'ATTENDANCE_LEAVE', entity: 'ATTENDANCE_SESSION', safe: ['status', 'date', 'classId', 'sectionId'] },
  staffAttendanceDays: { category: 'ATTENDANCE_LEAVE', entity: 'STAFF_ATTENDANCE_DAY', safe: ['status', 'date'] },
  leaveApplications: { category: 'ATTENDANCE_LEAVE', entity: 'LEAVE_APPLICATION', safe: ['status', 'leaveTypeId', 'fromDate', 'toDate'] },
  feeStructures: { category: 'FEES', entity: 'FEE_STRUCTURE', safe: ['status', 'name'] },
  invoices: { category: 'FEES', entity: 'INVOICE', safe: ['status', 'invoiceNumber', 'totalMinor', 'balanceMinor', 'currency'] },
  payments: { category: 'FEES', entity: 'PAYMENT', safe: ['status', 'amountMinor', 'currency', 'receiptNumber', 'method'] },
  timetables: { category: 'ACADEMIC', entity: 'TIMETABLE', safe: ['status'] },
  substitutions: { category: 'ACADEMIC', entity: 'SUBSTITUTION', safe: ['status', 'date'] },
  homework: { category: 'ACADEMIC', entity: 'HOMEWORK', safe: ['status', 'dueDate', 'classId', 'sectionId'] },
  homeworkSubmissions: { category: 'ACADEMIC', entity: 'HOMEWORK_SUBMISSION', safe: ['status'] },
  examinations: { category: 'ACADEMIC', entity: 'EXAM', safe: ['status', 'name'] },
  marksSheets: { category: 'ACADEMIC', entity: 'MARKS_SHEET', safe: ['status'] },
  announcements: { category: 'COMMUNICATION', entity: 'ANNOUNCEMENT', safe: ['status', 'title'] },
  conversations: { category: 'COMMUNICATION', entity: 'CONVERSATION', safe: [] },
  admissionEnquiries: { category: 'ADMISSION', entity: 'ADMISSION_ENQUIRY', safe: ['status', 'stage'] },
  admissionApplications: { category: 'ADMISSION', entity: 'ADMISSION_APPLICATION', safe: ['status'] },
});
// Not audited per document, on purpose: studentAttendance (one document per student per day: the
// attendance SESSION is the audited unit, otherwise volume explodes).

const BOOKKEEPING = new Set(['updatedAt', 'updatedBy', 'createdAt', 'createdBy', 'schoolId', 'branchId', 'version', 'searchKeys', 'displayNameLower']);
const same = (a, b) => JSON.stringify(a === undefined ? null : a) === JSON.stringify(b === undefined ? null : b);

/** Fields that differ between two versions of a document (top level, bookkeeping excluded). */
function diffFields(before, after) {
  const keys = new Set([...Object.keys(before || {}), ...Object.keys(after || {})]);
  const out = [];
  for (const k of keys) {
    if (BOOKKEEPING.has(k)) continue;
    const a = before ? before[k] : undefined;
    const b = after ? after[k] : undefined;
    const x = a && typeof a.toMillis === 'function' ? a.toMillis() : a;
    const y = b && typeof b.toMillis === 'function' ? b.toMillis() : b;
    if (!same(x, y)) out.push({ field: k, from: a === undefined ? null : x, to: b === undefined ? null : y });
  }
  return out;
}

/** The central event for one write to a client-written module, or null when nothing observable changed. */
function fromModuleWrite({ eventId, schoolId, branchId, collection, docId, before, after }) {
  const m = own(MODULES, collection);
  if (!m) return null;
  const action = !before && after ? 'CREATE' : before && !after ? 'DELETE' : 'UPDATE';
  const changes = action === 'UPDATE' ? diffFields(before, after) : [];
  if (action === 'UPDATE' && !changes.length) return null;
  const doc = after || before || {};
  const actor = action === 'DELETE' ? (before && before.updatedBy) || null : (after && (after.updatedBy || after.createdBy)) || null;
  return {
    sourceId: `module|${eventId}`,
    eventType: `${m.entity}_${action === 'CREATE' ? 'CREATED' : action === 'DELETE' ? 'DELETED' : 'UPDATED'}`,
    category: m.category,
    action,
    result: 'SUCCESS',
    source: 'TRIGGER',
    schoolId,
    branchId,
    actorUserId: typeof actor === 'string' && ID.test(actor) ? actor : null,
    targetEntity: m.entity,
    targetEntityId: docId,
    safeFields: m.safe,
    changes: action === 'UPDATE' ? changes : action === 'CREATE' ? m.safe.filter((f) => doc[f] !== undefined).map((f) => ({ field: f, from: null, to: doc[f] })) : [],
    description: `${m.entity} ${action.toLowerCase()}d`,
    metadata: { collection },
  };
}

// ---- reading (platform owner and compliance only) -------------------------------------------------

const READERS = ['OWNER', 'COMPLIANCE'];
const MAX_SPAN_DAYS = 92;
const DAY = 86400000;
const PAGE_DEFAULT = 50;
const PAGE_MAX = 100;
const SCAN_CAP = 600;
const EXPORT_CAP = 10000;
const PRIMARY = ['schoolId', 'actorUserId', 'category', 'eventType', 'result', 'source'];

const view = (e) => ({
  id: e.eventId,
  eventType: e.eventType,
  category: e.category,
  schoolId: e.schoolId || null,
  branchId: e.branchId || null,
  actorUserId: e.actorUserId || null,
  actorRole: e.actorRole || null,
  actor: e.actorNameSnapshot || null,
  application: e.application || null,
  platform: e.platform || null,
  targetEntity: e.targetEntity || null,
  targetEntityId: e.targetEntityId || null,
  action: e.action,
  result: e.result,
  atMs: e.timestampMs,
  source: e.source,
  trust: e.trust,
  clientReported: e.source === 'CLIENT_REPORTED',
  description: (e.changeSummary && e.changeSummary.description) || null,
  changes: (e.changeSummary && e.changeSummary.changes) || [],
  metadata: e.metadata || {},
  correlationId: e.correlationId || null,
});

/** Validates the filter shape shared by query, export and summary. */
function parseFilters(data, nowDate) {
  const d = data || {};
  const now = nowDate.getTime();
  const toMs_ = Number.isFinite(d.toMs) ? Math.min(d.toMs, now) : now;
  const fromMs_ = Number.isFinite(d.fromMs) ? d.fromMs : toMs_ - 7 * DAY;
  if (fromMs_ >= toMs_) return { error: 'INVALID_ARGUMENT', reason: 'range' };
  if (toMs_ - fromMs_ > MAX_SPAN_DAYS * DAY) return { error: 'INVALID_ARGUMENT', reason: 'range' };
  const eq = {};
  for (const k of PRIMARY) {
    if (d[k] === undefined || d[k] === null || d[k] === '') continue;
    const v = String(d[k]);
    if (k === 'category' && !CATEGORIES.includes(v)) return { error: 'INVALID_ARGUMENT', reason: k };
    if (k === 'result' && !RESULTS.includes(v)) return { error: 'INVALID_ARGUMENT', reason: k };
    if (k === 'source' && !SOURCES.includes(v)) return { error: 'INVALID_ARGUMENT', reason: k };
    if (k === 'eventType' && !EVENT_TYPE.test(v)) return { error: 'INVALID_ARGUMENT', reason: k };
    if ((k === 'schoolId' || k === 'actorUserId') && !ID.test(v)) return { error: 'INVALID_ARGUMENT', reason: k };
    eq[k] = v;
  }
  return { fromMs: fromMs_, toMs: toMs_, eq };
}

/** Months from [toMs] back to [fromMs], newest first. */
function monthsBetween(fromMs, toMs_) {
  const out = [];
  const d = new Date(toMs_);
  let y = d.getUTCFullYear();
  let m = d.getUTCMonth();
  const last = new Date(fromMs);
  const stop = last.getUTCFullYear() * 12 + last.getUTCMonth();
  while (y * 12 + m >= stop) {
    out.push(`${y}${String(m + 1).padStart(2, '0')}`);
    m -= 1;
    if (m < 0) {
      m = 11;
      y -= 1;
    }
  }
  return out;
}

/**
 * Walks the month partitions newest-first and returns up to [limit] events (plus a cursor when more
 * exist). The first equality filter in PRIMARY order uses an index; the others are applied to the
 * fetched documents, bounded by SCAN_CAP so a narrow filter cannot read the whole trail.
 */
async function scan(ctx, f, limit, cursor, scanCap = SCAN_CAP) {
  const months = monthsBetween(f.fromMs, f.toMs);
  const keys = Object.keys(f.eq);
  const primary = keys[0] || null;
  const residual = keys.slice(1);
  const out = [];
  let scanned = 0;
  let start = 0;
  let after = null;
  if (cursor && typeof cursor.m === 'string' && /^\d{6}$/.test(cursor.m)) {
    start = Math.max(0, months.indexOf(cursor.m));
    after = validId(cursor.id) ? cursor.id : null;
  }
  for (let mi = start; mi < months.length; mi++) {
    const col = partition(ctx.db, months[mi]);
    let last = mi === start && after ? await col.doc(after).get() : null;
    if (last && !last.data()) last = null;
    for (;;) {
      let q = col.where('timestampMs', '>=', f.fromMs).where('timestampMs', '<=', f.toMs);
      if (primary) q = q.where(primary, '==', f.eq[primary]);
      q = q.orderBy('timestampMs', 'desc');
      if (last) q = q.startAfter(last);
      const snap = await q.limit(100).get();
      for (const d of snap.docs) {
        scanned++;
        const e = d.data();
        if (residual.every((k) => e[k] === f.eq[k])) {
          out.push(e);
          if (out.length > limit) return { events: out.slice(0, limit), cursor: { m: months[mi], id: out[limit - 1].eventId }, truncated: false };
        }
        last = d;
        if (scanned >= scanCap) return { events: out.slice(0, limit), cursor: out.length ? { m: months[mi], id: out[Math.min(out.length, limit) - 1].eventId } : { m: months[mi], id: d.id }, truncated: true };
      }
      if (snap.docs.length < 100) break;
    }
  }
  return { events: out.slice(0, limit), cursor: null, truncated: false };
}

async function reader(ctx, uid, token) {
  const caller = await platformCaller(ctx.db, uid, token, READERS);
  return caller;
}

/** Owner/compliance: a page of audit events, newest first. Page one is itself audited. */
async function queryAuditEvents(ctx, uid, token, data) {
  const caller = await reader(ctx, uid, token);
  if (caller.error) return { error: caller.error };
  const f = parseFilters(data, ctx.nowDate());
  if (f.error) return f;
  const limit = Math.min(Math.max(Number.isInteger(data && data.limit) ? data.limit : PAGE_DEFAULT, 1), PAGE_MAX);
  const cursor = data && data.cursor && typeof data.cursor === 'object' ? data.cursor : null;
  const r = await scan(ctx, f, limit, cursor);
  if (!cursor) {
    await recordSafe(ctx, {
      sourceId: `view|${uid}|${ctx.nowDate().getTime()}`, eventType: 'AUDIT_LOG_VIEWED', category: 'SECURITY', action: 'VIEW', source: 'CALLABLE',
      actorUserId: uid, actorRole: caller.platformRole, actorNameSnapshot: caller.profile.email, application: 'PLATFORM_ADMIN',
      metadata: { filters: f.eq, fromMs: f.fromMs, toMs: f.toMs },
    });
  }
  return { events: r.events.map(view), nextCursor: r.cursor, truncated: r.truncated };
}

const csvCell = (v) => {
  let s = v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v);
  // A cell that starts like a formula is neutralised so a spreadsheet never runs it.
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const CSV_HEADER = ['time_utc', 'event_type', 'category', 'result', 'trust', 'source', 'school_id', 'branch_id', 'actor_user_id', 'actor', 'actor_role', 'target_entity', 'target_id', 'action', 'description', 'changes', 'correlation_id'];

/** Owner/compliance: the filtered events as CSV (UTC), capped, and the export is itself audited. */
async function exportAuditEvents(ctx, uid, token, data) {
  const caller = await reader(ctx, uid, token);
  if (caller.error) return { error: caller.error };
  const f = parseFilters(data, ctx.nowDate());
  if (f.error) return f;
  const rows = [];
  let cursor = null;
  let truncated = false;
  while (rows.length < EXPORT_CAP) {
    const r = await scan(ctx, f, Math.min(PAGE_MAX, EXPORT_CAP - rows.length), cursor, 5000);
    rows.push(...r.events);
    if (r.truncated) truncated = true;
    if (!r.cursor) break;
    cursor = r.cursor;
    if (r.truncated) break;
  }
  if (rows.length >= EXPORT_CAP) truncated = true;
  const lines = [CSV_HEADER.join(',')];
  for (const e of rows) {
    const changes = ((e.changeSummary && e.changeSummary.changes) || [])
      .map((c) => (c.changed ? `${c.field}: changed` : `${c.field}: ${JSON.stringify(c.from)} -> ${JSON.stringify(c.to)}`))
      .join('; ');
    lines.push([
      new Date(e.timestampMs).toISOString(), e.eventType, e.category, e.result, e.trust, e.source, e.schoolId, e.branchId, e.actorUserId, e.actorNameSnapshot, e.actorRole,
      e.targetEntity, e.targetEntityId, e.action, e.changeSummary && e.changeSummary.description, changes, e.correlationId,
    ].map(csvCell).join(','));
  }
  await record(ctx, {
    sourceId: `export|${uid}|${ctx.nowDate().getTime()}`, eventType: 'AUDIT_LOG_EXPORTED', category: 'SECURITY', action: 'EXPORT', source: 'CALLABLE',
    actorUserId: uid, actorRole: caller.platformRole, actorNameSnapshot: caller.profile.email, application: 'PLATFORM_ADMIN',
    metadata: { rows: rows.length, truncated, filters: f.eq, fromMs: f.fromMs, toMs: f.toMs },
  });
  return { csv: lines.join('\n'), rows: rows.length, truncated, capped: rows.length >= EXPORT_CAP };
}

/** Owner/compliance: counts for the dashboard over a window of up to 31 days. */
async function getAuditSummary(ctx, uid, token, data) {
  const caller = await reader(ctx, uid, token);
  if (caller.error) return { error: caller.error };
  const hours = data && data.hours !== undefined ? data.hours : 24;
  if (!Number.isInteger(hours) || hours < 1 || hours > 31 * 24) return { error: 'INVALID_ARGUMENT', reason: 'hours' };
  const toMs_ = ctx.nowDate().getTime();
  const fromMs_ = toMs_ - hours * 3600000;
  const months = monthsBetween(fromMs_, toMs_);
  const count = async (extra) => {
    let n = 0;
    for (const m of months) {
      let q = partition(ctx.db, m).where('timestampMs', '>=', fromMs_).where('timestampMs', '<=', toMs_);
      for (const [k, v] of extra) q = q.where(k, '==', v);
      n += (await q.count().get()).data().count;
    }
    return n;
  };
  const byCategory = {};
  for (const c of CATEGORIES) byCategory[c] = await count([['category', c]]);
  const total = Object.values(byCategory).reduce((a, b) => a + b, 0);
  return {
    hours,
    total,
    byCategory,
    denied: await count([['result', 'DENIED']]),
    failures: await count([['result', 'FAILURE']]),
    clientReported: await count([['source', 'CLIENT_REPORTED']]),
  };
}

// ---- client-reported events (T4) -------------------------------------------------------------------

const CLIENT_EVENTS = Object.freeze({
  LOGOUT: { category: 'AUTHENTICATION', action: 'LOGOUT' },
  SESSION_EXPIRED: { category: 'AUTHENTICATION', action: 'LOGOUT' },
  PERMISSION_DENIED_UI: { category: 'SECURITY', action: 'OTHER', result: 'DENIED' },
});
const RATE_WINDOW_MS = 10 * 60 * 1000;
const RATE_MAX = 20;

/**
 * Any signed-in user: the app reports what only it can see (sign-out, an expired session, a screen
 * refused for lack of permission). NOT proof: stored as trust T4 / CLIENT_REPORTED, who it is comes
 * from the token (never from the request), only allowlisted types and fields are kept, and each
 * user is limited to 20 reports per 10 minutes.
 */
async function reportClientEvent(ctx, uid, token, data) {
  const type = data && data.type;
  const spec = own(CLIENT_EVENTS, type);
  if (!spec) return { error: 'INVALID_ARGUMENT', reason: 'type' };
  const profile = (await ctx.db.collection('users').doc(uid).get()).data();
  if (!profile) return { error: 'PERMISSION_DENIED' };
  const nowMs = ctx.nowDate().getTime();
  const rateRef = ctx.db.collection('auditClientRate').doc(uid);
  const allowed = await ctx.db.runTransaction(async (tx) => {
    const cur = (await tx.get(rateRef)).data();
    const fresh = cur && nowMs - cur.windowStartMs < RATE_WINDOW_MS;
    const count = fresh ? cur.count : 0;
    if (count >= RATE_MAX) return false;
    tx.set(rateRef, { windowStartMs: fresh ? cur.windowStartMs : nowMs, count: count + 1 });
    return true;
  });
  if (!allowed) return { error: 'RESOURCE_EXHAUSTED' };
  const routeRaw = text(data.route, 100).split('?')[0];
  const route = /^\/[A-Za-z0-9_\-\/.]*$/.test(routeRaw) ? routeRaw : '';
  const platform = PLATFORMS.includes(data.platform) && data.platform !== 'SERVER' ? data.platform : null;
  const correlationId = /^[A-Za-z0-9_-]{1,64}$/.test(text(data.correlationId, 64)) ? text(data.correlationId, 64) : '';
  const role = profile.role === 'SCHOOL_ADMIN' || profile.role === 'BRANCH_ADMIN' || profile.role === 'TEACHER' || profile.role === 'PARENT' || profile.role === 'FINANCE' ? profile.role : profile.role === 'PLATFORM_ADMIN' ? 'PLATFORM_ADMIN' : null;
  const r = await recordSafe(ctx, {
    sourceId: `client|${uid}|${correlationId || nowMs}`,
    eventType: type,
    category: spec.category,
    action: spec.action,
    result: spec.result || 'SUCCESS',
    source: 'CLIENT_REPORTED',
    schoolId: profile.schoolId || null,
    actorUserId: uid,
    actorRole: profile.role,
    application: role,
    platform,
    correlationId,
    description: 'Reported by the app (not independently verified)',
    metadata: { route: route || null, appVersion: /^[0-9A-Za-z._+-]{1,20}$/.test(text(data.appVersion, 20)) ? text(data.appVersion, 20) : null },
  });
  return r.failed ? { error: 'INTERNAL' } : { ok: true };
}

// ---- retention (archive first; delete only when explicitly switched on) ------------------------------

/**
 * Exports every month older than [retentionDays] to Cloud Storage as JSON lines (once), records a
 * marker with the count and checksum, and audits it. Nothing is deleted unless [deleteAfterArchive]
 * is true AND the archive was verified by reading it back: the default keeps everything online.
 */
async function runAuditRetention(ctx, storage, { retentionDays = 400, deleteAfterArchive = false, maxMonths = 3, log = () => {} } = {}) {
  const cutoff = ctx.nowDate().getTime() - retentionDays * DAY;
  const oldest = monthsBetween(cutoff - 36 * 31 * DAY, cutoff);
  const candidates = oldest.filter((m) => {
    const y = Number(m.slice(0, 4));
    const mo = Number(m.slice(4, 6));
    return Date.UTC(y, mo, 1) <= cutoff; // the whole month is older than the cutoff
  }).reverse();
  const done = [];
  for (const m of candidates) {
    if (done.length >= maxMonths) break;
    const markerRef = ctx.db.collection('auditArchives').doc(m);
    const marker = (await markerRef.get()).data();
    if (marker && (marker.state === 'PURGED' || (marker.state === 'ARCHIVED' && !deleteAfterArchive))) continue;
    const docs = [];
    let last = null;
    for (;;) {
      let q = partition(ctx.db, m).orderBy('timestampMs', 'asc').limit(500);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      docs.push(...snap.docs);
      if (snap.docs.length < 500) break;
      last = snap.docs[snap.docs.length - 1];
    }
    if (!docs.length) continue;
    let archive = marker && marker.state === 'ARCHIVED' ? marker : null;
    if (!archive) {
      const body = docs.map((d) => JSON.stringify(d.data())).join('\n');
      const path = `audit-archive/${m}.jsonl`;
      await storage.put(path, body, 'application/x-ndjson');
      archive = { month: m, state: 'ARCHIVED', count: docs.length, bytes: Buffer.byteLength(body), sha256: crypto.createHash('sha256').update(body).digest('hex'), path, archivedAt: ctx.now };
      await markerRef.set(archive);
      await recordSafe(ctx, { sourceId: `archive|${m}`, eventType: 'AUDIT_MONTH_ARCHIVED', category: 'SECURITY', action: 'ARCHIVE', source: 'SCHEDULER', application: 'SCHEDULER', metadata: { month: m, count: docs.length, path } }, log);
    }
    if (deleteAfterArchive) {
      const stat = await storage.stat(archive.path);
      if (!stat.exists || stat.size !== archive.bytes) {
        log('audit retention: archive could not be verified, nothing deleted', { month: m });
        continue;
      }
      for (let i = 0; i < docs.length; i += 400) {
        const batch = ctx.db.batch();
        for (const d of docs.slice(i, i + 400)) batch.delete(d.ref);
        await batch.commit();
      }
      await markerRef.set({ ...archive, state: 'PURGED', purgedAt: ctx.now });
      await recordSafe(ctx, { sourceId: `purge|${m}`, eventType: 'AUDIT_MONTH_PURGED', category: 'SECURITY', action: 'DELETE', source: 'SCHEDULER', application: 'SCHEDULER', metadata: { month: m, count: docs.length } }, log);
    }
    done.push(m);
  }
  return { months: done };
}

module.exports = {
  CATEGORIES, ACTIONS, RESULTS, SOURCES, TRUST, MODULES, CLIENT_EVENTS, EXPORT_CAP, MAX_SPAN_DAYS, RATE_MAX, CSV_HEADER,
  redact, changeList, buildEvent, eventIdFor, monthOf, monthsBetween, partition, diffFields,
  record, recordSafe, fromPlatformAudit, fromAuthAudit, fromModuleWrite,
  queryAuditEvents, exportAuditEvents, getAuditSummary, reportClientEvent, runAuditRetention,
  csvCell, view,
};

'use strict';

// Audits EVERY callable: the action name, who called, the request, the response (or the error), the
// outcome and how long it took, as one `API` event in the central trail (audit.js). It wraps the handler
// handed to onCall, so a new callable is covered without anyone remembering to add a line.
//
//  - The audit write never changes the call: a failure to write is logged and the caller still gets the
//    handler's own result or error.
//  - Secrets (passwords, OTPs, tokens, keys, reset links) are masked in both directions; personal data is
//    kept (only platform owners/compliance can read the trail). Bodies are capped (audit.payload).
//  - Reading the trail itself is not echoed back into it (responses omitted), and the app's own audit
//    reports are not audited twice.

const crypto = require('node:crypto');
const audit = require('./audit');

const NOT_AUDITED = new Set(['reportClientEvent']);
// Reading the trail is not echoed back into it, and an expense export (payees, details) is not copied into the audit either: the event keeps the request, the row count is in the log.
// Salary data is the most sensitive in the system and the trail is broadly readable by platform owners and compliance, so payroll reads are not copied into it (the event keeps who looked, when, and for whom) and a saved structure's amounts are not recorded (only that it was saved, and how many lines).
const RESPONSE_OMITTED = new Set(['queryAuditEvents', 'exportAuditEvents', 'getAuditSummary', 'getAuditEvent', 'exportExpenses', 'getSalaryStructure', 'listSalaryStructures', 'previewPayroll', 'listPayrollRuns', 'getPayrollRun', 'getPayslip', 'listMyPayslips', 'getMyPayslip']);
const REQUEST_REDACTED = {
  adjustPayslip: (d) => ({ ...d, adjustment: d.adjustment && typeof d.adjustment === 'object' ? { ...d.adjustment, amountMinor: '[amount not recorded]' } : '[not recorded]' }),
  saveSalaryStructure: (d) => ({ ...d, lines: Array.isArray(d.lines) ? `[${d.lines.length} lines; amounts not recorded]` : '[not recorded]' }),
};

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const ROLE_APP = { PLATFORM_ADMIN: 'PLATFORM_ADMIN', SCHOOL_ADMIN: 'SCHOOL_ADMIN', BRANCH_ADMIN: 'BRANCH_ADMIN', TEACHER: 'TEACHER', PARENT: 'PARENT', FINANCE: 'FINANCE' };

const eventTypeOf = (name) => {
  const snake = String(name).replace(/([a-z0-9])([A-Z])/g, '$1_$2').replace(/[^A-Za-z0-9]+/g, '_').toUpperCase();
  return `API_${snake}`.slice(0, 64).replace(/_+$/, '');
};

const CATEGORY_RULES = [
  [/Admission/, 'ADMISSION'],
  [/Fee|Invoice|Payment|Receipt/, 'FEES'],
  [/Otp|Password|Login|Auth|Provision|SchoolAdmin/, 'AUTHENTICATION'],
  [/Subscription|Plan|Trial/, 'SUBSCRIPTION'],
  [/Feature|Module/, 'FEATURE'],
  [/Deletion|Branch(Access)?$|Access|Audit|Recovery|SupportGrant|Support/, 'SECURITY'],
  [/Device|Notif|Notice|Announce/, 'COMMUNICATION'],
  [/Branding|Settings|Regional|Reminder/, 'DATA_CONFIG'],
  [/School|Platform|Billing|Offboard/, 'PLATFORM'],
  [/Teacher|Parent|Student|Staff/, 'STAFF'],
];
const categoryOf = (name) => (CATEGORY_RULES.find(([re]) => re.test(name)) || [null, 'API'])[1];

const ACTION_RULES = [
  [/^(get|list|query|diagnose|view|search|check|find|preview)/, 'VIEW'],
  [/^export/, 'EXPORT'],
  [/^(create|add|register|request|submit|schedule|provision|record|grant|convert)/, 'CREATE'],
  [/^(delete|remove|cancel|unregister|refund|dismiss)/, 'DELETE'],
  [/^(approve|verify|decide|confirm|acknowledge)/, 'APPROVE'],
  [/^reject/, 'REJECT'],
  [/^(reset|refresh)/, 'RESET'],
  [/^(assign|reassign)/, 'ASSIGN'],
  [/^(update|save|set|change|reschedule|complete|waive|renew|extend|review|transition|process|adjust|calculate|pay)/, 'UPDATE'],
];
const actionOf = (name) => (ACTION_RULES.find(([re]) => re.test(name)) || [null, 'OTHER'])[1];

const DENIED_CODES = new Set(['permission-denied', 'unauthenticated']);

/**
 * `wrap(handler)` returns a handler with the same contract. Dependencies are passed in so tests can
 * drive it without Firebase: `ctx()` builds the audit context, `nameOf()` returns the callable's name.
 */
function makeAuditedCall({ ctx, nameOf = () => process.env.FUNCTION_TARGET || 'unknown', log = () => {}, now = () => Date.now() }) {
  async function note(name, request, outcome) {
    const c = ctx();
    const uid = request && request.auth && ID.test(request.auth.uid || '') ? request.auth.uid : null;
    let profile = null;
    if (uid) {
      try {
        profile = (await c.db.collection('users').doc(uid).get()).data() || null;
      } catch (_) {
        profile = null;
      }
    }
    const data = request && request.data && typeof request.data === 'object' ? request.data : {};
    const pick = (v) => (typeof v === 'string' && ID.test(v) ? v : null);
    const raw = (request && request.rawRequest) || {};
    const headers = raw.headers || {};
    const trace = String(headers['x-cloud-trace-context'] || '').split('/')[0];
    const e = outcome.error;
    const denied = e && DENIED_CODES.has(e.code);
    await audit.recordSafe(c, {
      sourceId: `call|${name}|${crypto.randomUUID()}`,
      eventType: eventTypeOf(name),
      category: categoryOf(name),
      action: actionOf(name),
      actionName: name,
      result: !e ? 'SUCCESS' : denied ? 'DENIED' : 'FAILURE',
      source: 'CALLABLE',
      schoolId: pick(profile && profile.schoolId) || pick(data.schoolId),
      branchId: pick(data.branchId) || pick(profile && profile.branchId),
      actorUserId: uid,
      actorRole: profile && profile.role,
      actorNameSnapshot: profile && (profile.email || profile.displayName || profile.name),
      application: uid ? ROLE_APP[profile && profile.role] || 'FUNCTION' : 'PUBLIC_PORTAL',
      targetEntityId: pick(data.studentId) || pick(data.enquiryId) || pick(data.uid) || pick(data.targetUid) || null,
      correlationId: /^[A-Za-z0-9_-]{1,64}$/.test(trace) ? trace : null,
      description: `${name} ${e ? `failed (${e.code || 'error'})` : 'succeeded'}`,
      request: request ? (REQUEST_REDACTED[name] && request.data && typeof request.data === 'object' ? REQUEST_REDACTED[name](request.data) : request.data) : undefined,
      response: !e && !RESPONSE_OMITTED.has(name) ? outcome.result : undefined,
      error: e ? { code: e.code, message: e.message, details: e.details } : undefined,
      durationMs: outcome.ms,
      client: { ip: raw.ip || null, userAgent: headers['user-agent'] || null },
    }, log);
  }

  return (handler) => async (request) => {
    const name = nameOf();
    if (NOT_AUDITED.has(name)) return handler(request);
    const t0 = now();
    let result;
    let error = null;
    try {
      result = await handler(request);
    } catch (e) {
      error = e || new Error('unknown error');
    }
    try {
      await note(name, request, { result, error, ms: now() - t0 });
    } catch (e) {
      log('call audit failed', { name, error: String(e && e.message).slice(0, 200) });
    }
    if (error) throw error;
    return result;
  };
}

module.exports = { makeAuditedCall, eventTypeOf, categoryOf, actionOf, NOT_AUDITED, RESPONSE_OMITTED, REQUEST_REDACTED };

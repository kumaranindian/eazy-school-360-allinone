'use strict';

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { setGlobalOptions } = require('firebase-functions/v2');
const { onDocumentCreated, onDocumentUpdated, onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue } = require('firebase-admin/firestore');
const logger = require('firebase-functions/logger');

const { errorCategory } = require('./delivery_log');
const { makeDelivery } = require('./deliver');
const devices = require('./devices');
const notifyEvents = require('./notify_events');
const feeReminders = require('./fee_reminders');
const branding = require('./branding');
const admission = require('./admission');
const admissionActivities = require('./admission_activities');
const admissionApplications = require('./admission_applications');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret, defineString } = require('firebase-functions/params');
const { createSchoolAdmin, provisionLogins, changeInitialPassword, resetLoginPassword, ensureAuthUser, enablePortalLinks } = require('./provision');
const access = require('./access');
const { diagnoseAccess } = require('./diagnose');
const teacherAccess = require('./teacher_access');
const parentAccess = require('./parent_access');
const examScope = require('./exam_scope');
const branchAccess = require('./branch_access');
const deviceCleanup = require('./device_cleanup');
const currencyLock = require('./currency_lock');
const { requestOtp, verifyOtp } = require('./otp');
const { createWhatsAppSender } = require('./whatsapp');
const { callOptions } = require('./call_options');
const accountDeletion = require('./account_deletion');
const deletionProcessor = require('./deletion_processor');
const { bucketStorage } = require('./storage_adapter');
const { getStorage } = require('firebase-admin/storage');

initializeApp();
// Must match the Firestore database region (Firestore triggers are regional).
setGlobalOptions({ region: process.env.FUNCTIONS_REGION || 'asia-south1', maxInstances: 10 });

const db = getFirestore();
const messaging = getMessaging();

// Pushes one notification document. Idempotent and retryable: see deliver.js
// (claims in `pushDeliveries`, device-level de-duplication on re-runs, and the
// `pushRedrive` sweep below for anything that did not finish).
const delivery = makeDelivery({ db, messaging, logger });
const PUSH_TIMEOUT_S = 300;

const deliverEvent = (kind) => (event) => {
  const snap = event.data;
  if (!snap) return;
  const { schoolId, branchId } = event.params;
  return delivery.runDelivery({
    eventId: event.id,
    schoolId,
    branchId,
    ref: snap.ref,
    id: snap.id,
    data: snap.data(),
    kind,
  });
};

// Announcements, homework, results, holidays: audience-addressed notices.
exports.pushBroadcastNotice = onDocumentCreated(
  { document: 'schools/{schoolId}/branches/{branchId}/broadcastNotices/{noticeId}', timeoutSeconds: PUSH_TIMEOUT_S },
  deliverEvent('broadcastNotices'),
);

// Leave decisions, messages, payments, attendance, fee reminders: per-user.
exports.pushNotification = onDocumentCreated(
  { document: 'schools/{schoolId}/branches/{branchId}/notifications/{notificationId}', timeoutSeconds: PUSH_TIMEOUT_S },
  deliverEvent('notifications'),
);

// Finishes deliveries that failed, were cut short or were abandoned by a
// crashed invocation. Frequent and cheap when there is nothing to do.
exports.pushRedrive = onSchedule(
  { schedule: 'every 5 minutes', timeZone: 'Asia/Kolkata', timeoutSeconds: 540 },
  async () => {
    try {
      const r = await delivery.redrive();
      if (r.due > 0) logger.info('push redrive', r);
    } catch (e) {
      logger.error('push redrive failed', { category: errorCategory(e) });
    }
  },
);

// ---- Device registration (push tokens) -------------------------------------
// Clients cannot write device documents (firestore.rules); they register here
// and the server records the token under the CALLER's account and school.

exports.registerDevice = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await devices.registerDevice({ db, now: () => new Date() }, a.uid, request.data);
  if (out.error) fail(out);
  return out.result;
});

exports.unregisterDevice = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await devices.unregisterDevice({ db }, a.uid, request.data);
  if (out.error) fail(out);
  return out.result;
});

// ---- Business events that notify people -----------------------------------

const events = () => ({ db, now: () => new Date() });
const swallow = (what) => (e) => logger.error(`${what} failed`, { category: errorCategory(e) });

exports.notifyPaymentRecorded = onDocumentCreated(
  'schools/{schoolId}/branches/{branchId}/payments/{paymentId}',
  (event) =>
    notifyEvents
      .onPaymentRecorded(events(), event.params, event.data && event.data.data())
      .catch(swallow('payment notice')),
);

exports.notifyRegisterFinalized = onDocumentWritten(
  'schools/{schoolId}/branches/{branchId}/attendanceSessions/{sessionId}',
  (event) =>
    notifyEvents
      .onRegisterFinalized(
        events(),
        event.params,
        event.data.before.exists ? event.data.before.data() : undefined,
        event.data.after.exists ? event.data.after.data() : undefined,
      )
      .catch(swallow('attendance notice')),
);

exports.notifyHolidayWritten = onDocumentWritten(
  'schools/{schoolId}/branches/{branchId}/holidays/{holidayId}',
  (event) =>
    notifyEvents
      .onHolidayWritten(
        events(),
        event.params,
        event.data.before.exists ? event.data.before.data() : undefined,
        event.data.after.exists ? event.data.after.data() : undefined,
      )
      .catch(swallow('holiday notice')),
);

// Hourly; each school is handled at ITS OWN delivery time in ITS OWN time zone
// (Regional settings), following its Fee reminder settings (days before / on /
// after the due date; defaults 3 and 0 before, 1, 7 and 15 after). Idempotent,
// so a re-run (or the next hour's retry) sends nothing new.
exports.feeDueReminders = onSchedule(
  { schedule: 'every 1 hours', timeZone: 'UTC' },
  async () => {
    try {
      const r = await notifyEvents.runFeeDueReminders({ ...events(), log: (event, f) => logger.info(event, f) });
      if (r.failed || r.truncated) logger.warn('fee due reminders finished with problems', r);
      else logger.info('fee due reminders', r);
    } catch (e) {
      logger.error('fee due reminders failed', { category: errorCategory(e) });
    }
  },
);

// Creates sign-in accounts for existing staff / parent records and links them.
// Callable by school/branch admins only (checked server-side).
exports.provisionLogins = onCall(callOptions(), async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const out = await provisionLogins(
    { db, auth: getAuth(), now: FieldValue.serverTimestamp() },
    request.auth.uid,
    request.data,
    request.auth.token,
  );
  if (out.error === 'PERMISSION_DENIED') throw new HttpsError('permission-denied', 'Not allowed.');
  if (out.error) throw new HttpsError('invalid-argument', 'Invalid request.');
  logger.info('provisionLogins', {
    by: request.auth.uid,
    kind: request.data.kind,
    created: out.results.filter((r) => r.outcome === 'CREATED').length,
    total: out.results.length,
    // Per-record outcomes only (ids and flags, never emails or passwords) so a
    // parent who "has a login but cannot sign in" can be traced.
    outcomes: out.results.map((r) => ({
      id: r.id,
      outcome: r.outcome,
      newAccount: r.newAccount === true,
      mapped: r.mapped === true,
      passwordSet: r.passwordSet === true,
    })),
  });
  return out;
});

// Adds another school admin to the caller's own school. Only an existing
// school admin may call it; the Firestore rules forbid this to clients.
exports.createSchoolAdmin = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await createSchoolAdmin({ db, auth: getAuth(), now: FieldValue.serverTimestamp() }, a.uid, request.data, a.token);
  if (out.error) fail(out);
  // Ids and the chosen option only: never the email, name or password.
  logger.info('createSchoolAdmin', { by: a.uid, target: out.uid, passwordSet: out.passwordSet === true });
  return out;
});

// First sign-in after an admin-set / derived password: the person replaces it.
// Allowed only while their profile is flagged; nothing about the password is logged.
exports.changeInitialPassword = onCall(callOptions(), async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const out = await changeInitialPassword(
    { db, auth: getAuth(), now: FieldValue.serverTimestamp() },
    request.auth.uid,
    request.data,
  );
  if (out.error === 'NOT_REQUIRED') throw new HttpsError('failed-precondition', 'NOT_REQUIRED');
  if (out.error) throw new HttpsError('invalid-argument', 'Invalid request.');
  logger.info('changeInitialPassword', { by: request.auth.uid });
  return { ok: true };
});

// Admin sets a new password for an existing staff / parent login (same
// options as when creating logins). Nothing about the password is logged.
exports.resetLoginPassword = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await resetLoginPassword({ db, auth: getAuth(), now: FieldValue.serverTimestamp() }, a.uid, request.data, a.token);
  if (out.error) fail(out);
  logger.info('resetLoginPassword', {
    by: a.uid,
    kind: request.data.kind,
    count: Array.isArray(request.data.ids) ? request.data.ids.length : 1,
  });
  return out.result;
});

// ---- Authentication & login access management -----------------------------
//
// Meta WhatsApp Cloud API settings. The token and the OTP pepper live in
// Secret Manager (firebase functions:secrets:set); the rest is plain config.
// None of these ever reaches the client. See
// docs/authentication-access-management.md for the manual setup.
const META_WA_ACCESS_TOKEN = defineSecret('META_WA_ACCESS_TOKEN');
const OTP_PEPPER = defineSecret('OTP_PEPPER');
const META_WA_PHONE_NUMBER_ID = defineString('META_WA_PHONE_NUMBER_ID', { default: '' });
const META_WA_TEMPLATE_NAME = defineString('META_WA_TEMPLATE_NAME', { default: '' });
const META_WA_TEMPLATE_LANG = defineString('META_WA_TEMPLATE_LANG', { default: 'en' });
const META_WA_API_VERSION = defineString('META_WA_API_VERSION', { default: 'v21.0' });
const META_WA_TEMPLATE_BUTTON = defineString('META_WA_TEMPLATE_BUTTON', { default: 'true' });

const whatsAppConfig = () => ({
  accessToken: META_WA_ACCESS_TOKEN.value(),
  phoneNumberId: META_WA_PHONE_NUMBER_ID.value(),
  templateName: META_WA_TEMPLATE_NAME.value(),
  languageCode: META_WA_TEMPLATE_LANG.value(),
  apiVersion: META_WA_API_VERSION.value(),
  templateHasButton: META_WA_TEMPLATE_BUTTON.value() !== 'false',
});
const phoneOtpConfigured = () => createWhatsAppSender(whatsAppConfig()).configured && !!OTP_PEPPER.value();

const STATUS = {
  PERMISSION_DENIED: 'permission-denied',
  INVALID_ARGUMENT: 'invalid-argument',
  NOT_FOUND: 'not-found',
  ABORTED: 'aborted',
  EMAIL_IN_USE: 'already-exists',
  UNAUTHENTICATED: 'unauthenticated',
  RATE_LIMITED: 'resource-exhausted',
  RESOURCE_EXHAUSTED: 'resource-exhausted',
  RESEND_COOLDOWN: 'resource-exhausted',
  DELIVERY_FAILED: 'unavailable',
  OTP_UNAVAILABLE: 'failed-precondition',
  VERIFICATION_FAILED: 'permission-denied',
  MFA_REQUIRED: 'permission-denied',
  FAILED_PRECONDITION: 'failed-precondition',
};
// Turns a core { error, ... } into an HttpsError whose details.reason the app
// maps to a message. No identifiers or secrets are included.
function fail(out) {
  throw new HttpsError(STATUS[out.error] || 'failed-precondition', out.error, {
    reason: out.error,
    ...(out.retryAfterSec ? { retryAfterSec: out.retryAfterSec } : {}),
    ...(out.reason ? { cause: out.reason } : {}),
    ...(out.attemptsLeft !== undefined ? { attemptsLeft: out.attemptsLeft } : {}),
  });
}
const signedIn = (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  return request.auth;
};
const adminCtx = () => ({
  db,
  auth: getAuth(),
  now: FieldValue.serverTimestamp(),
  nowDate: () => new Date(),
  deleteField: FieldValue.delete(),
  ensureAuthUser,
  enablePortalLinks,
  configured: { phoneOtp: phoneOtpConfigured() },
});

exports.getLoginAccess = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await access.getLoginAccess(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  return out.result;
});

// Read-only: names the missing prerequisite behind a user's permission-denied.
exports.diagnoseAccess = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await diagnoseAccess({ db }, a.uid, a.token, request.data);
  if (out.error) fail(out);
  return out.result;
});

exports.setLoginAccess = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await access.setLoginAccess(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  logger.info('setLoginAccess', { by: a.uid, kind: request.data.kind, enabled: out.result.enabled });
  return out.result;
});

// Saves a school's fee reminder policy (school admin only; validated here, the
// rules deny client writes to the document).
exports.updateFeeReminderSettings = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await feeReminders.updateFeeReminderSettings(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  logger.info('updateFeeReminderSettings', { by: a.uid });
  return out.result;
});

// Tenant-wide branding. School admins save their own school's theme (platform
// admins any school's); platform admins also manage the default and presets.
// The rules deny client writes to both documents.
exports.updateSchoolBranding = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await branding.updateSchoolBranding(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  logger.info('updateSchoolBranding', { by: a.uid, version: out.result.version });
  return out.result;
});

// Admission enquiries (docs/admission-management/). Every write is a callable:
// the rules give clients read access only, so numbering, duplicate flagging,
// the status state machine and branch scoping cannot be bypassed from a client.
const admissionCall = (name, fn, pick) =>
  onCall(callOptions(), async (request) => {
    const a = signedIn(request);
    // The platform can switch the admission module off for a school.
    const sid = request.data && request.data.schoolId;
    if (typeof sid === 'string' && sid && !(await require('./school_lifecycle').featureEnabled(db, sid, 'admission'))) {
      throw new HttpsError('failed-precondition', 'FEATURE_DISABLED', { reason: 'FEATURE_DISABLED' });
    }
    const out = await fn({ ...adminCtx(), wall: () => new Date(), storage: bucketStorage(getStorage().bucket()) }, a.uid, a.token, request.data);
    if (out.error) fail(out);
    logger.info(name, { by: a.uid, ...(pick ? pick(request.data, out.result) : {}) });
    return out.result;
  });
exports.saveAdmissionSettings = admissionCall('saveAdmissionSettings', admission.saveAdmissionSettings);
exports.createAdmissionEnquiry = admissionCall('createAdmissionEnquiry', admission.createEnquiry, (d, r) => ({ enquiry: r.id }));
exports.updateAdmissionEnquiry = admissionCall('updateAdmissionEnquiry', admission.updateEnquiry, (d) => ({ enquiry: d.enquiryId }));
exports.assignAdmissionEnquiry = admissionCall('assignAdmissionEnquiry', admission.assignEnquiry, (d) => ({ enquiry: d.enquiryId }));
exports.scheduleAdmissionActivity = admissionCall('scheduleAdmissionActivity', admissionActivities.scheduleActivity, (d, r) => ({ enquiry: d.enquiryId, activity: r.id }));
exports.createAdmissionApplication = admissionCall('createAdmissionApplication', admissionApplications.createApplication, (d, r) => ({ enquiry: d.enquiryId }));
exports.updateAdmissionApplication = admissionCall('updateAdmissionApplication', admissionApplications.updateApplication, (d) => ({ enquiry: d.enquiryId }));
exports.submitAdmissionApplication = admissionCall('submitAdmissionApplication', admissionApplications.submitApplication, (d) => ({ enquiry: d.enquiryId }));
exports.reviewAdmissionApplication = admissionCall('reviewAdmissionApplication', admissionApplications.reviewApplication, (d) => ({ enquiry: d.enquiryId, action: d.action }));
exports.decideAdmissionApplication = admissionCall('decideAdmissionApplication', admissionApplications.decideApplication, (d, r) => ({ enquiry: d.enquiryId, status: r.status }));
exports.requestAdmissionDocumentUpload = admissionCall('requestAdmissionDocumentUpload', admissionApplications.requestDocumentUpload, (d, r) => ({ enquiry: d.enquiryId, document: r.id }));
exports.confirmAdmissionDocumentUpload = admissionCall('confirmAdmissionDocumentUpload', admissionApplications.confirmDocumentUpload, (d) => ({ enquiry: d.enquiryId, document: d.documentId }));
exports.verifyAdmissionDocument = admissionCall('verifyAdmissionDocument', admissionApplications.verifyDocument, (d) => ({ enquiry: d.enquiryId, document: d.documentId, decision: d.decision }));
exports.removeAdmissionDocument = admissionCall('removeAdmissionDocument', admissionApplications.removeDocument, (d) => ({ enquiry: d.enquiryId, document: d.documentId }));

// Uploads that were requested but never confirmed are cleaned up daily.
exports.admissionDocumentCleanup = onSchedule(
  { schedule: 'every 24 hours', timeZone: 'UTC' },
  async () => {
    try {
      const r = await admissionApplications.cleanupAbandonedUploads({ db, storage: bucketStorage(getStorage().bucket()), now: () => new Date(), log: (event, f) => logger.info(event, f) });
      logger.info('admission document cleanup', r);
    } catch (e) {
      logger.error('admission document cleanup failed', { category: errorCategory(e) });
    }
  },
);

exports.scheduleAdmissionVisit = admissionCall('scheduleAdmissionVisit', admissionActivities.scheduleVisit, (d, r) => ({ enquiry: d.enquiryId, visit: r.id }));
exports.rescheduleAdmissionActivity = admissionCall('rescheduleAdmissionActivity', admissionActivities.rescheduleActivity, (d) => ({ enquiry: d.enquiryId, activity: d.activityId }));
exports.reassignAdmissionActivity = admissionCall('reassignAdmissionActivity', admissionActivities.reassignActivity, (d) => ({ enquiry: d.enquiryId, activity: d.activityId }));
exports.completeAdmissionActivity = admissionCall('completeAdmissionActivity', admissionActivities.completeActivity, (d) => ({ enquiry: d.enquiryId, activity: d.activityId }));
exports.cancelAdmissionActivity = admissionCall('cancelAdmissionActivity', admissionActivities.cancelActivity, (d) => ({ enquiry: d.enquiryId, activity: d.activityId }));

// Follow-up reminders: hourly, at each school's own local reminder time.
// Idempotent (derived ids + create()), so a retry or re-run sends nothing new.
exports.admissionFollowUpReminders = onSchedule(
  { schedule: 'every 1 hours', timeZone: 'UTC' },
  async () => {
    try {
      const r = await admissionActivities.runFollowUpReminders({ ...events(), log: (event, f) => logger.info(event, f) });
      if (r.failed) logger.warn('admission follow-up reminders finished with problems', r);
      else logger.info('admission follow-up reminders', r);
    } catch (e) {
      logger.error('admission follow-up reminders failed', { category: errorCategory(e) });
    }
  },
);

const admissionFees = require('./admission_fees');
exports.setAdmissionFee = admissionCall('setAdmissionFee', admissionFees.setAdmissionFee, (d) => ({ enquiry: d.enquiryId, category: d.category }));
exports.cancelAdmissionFee = admissionCall('cancelAdmissionFee', admissionFees.cancelAdmissionFee, (d) => ({ enquiry: d.enquiryId, category: d.category }));
exports.waiveAdmissionFee = admissionCall('waiveAdmissionFee', admissionFees.waiveAdmissionFee, (d) => ({ enquiry: d.enquiryId, category: d.category }));
exports.recordAdmissionFeePayment = admissionCall('recordAdmissionFeePayment', admissionFees.recordAdmissionFeePayment, (d, r) => ({ enquiry: d.enquiryId, category: d.category, receipt: r.receiptNumber }));
exports.refundAdmissionFee = admissionCall('refundAdmissionFee', admissionFees.refundAdmissionFee, (d) => ({ enquiry: d.enquiryId, category: d.category }));
const admissionConversion = require('./admission_conversion');
exports.convertAdmissionToStudent = admissionCall('convertAdmissionToStudent', admissionConversion.convertToStudent, (d, r) => ({ enquiry: d.enquiryId, student: r.studentId }));

// The public enquiry page: callable by anyone, so it never reads the caller's
// identity; school and branch come from the registered page address only.
const admissionPublic = require('./admission_public');
const publicCall = (name, fn) =>
  onCall(callOptions(), async (request) => {
    const raw = request.rawRequest || {};
    const out = await fn(
      { ...adminCtx(), wall: () => new Date(), clientIp: raw.ip || null, turnstileSecret: process.env.TURNSTILE_SECRET_KEY || null },
      null,
      null,
      request.data,
    );
    if (out.error) fail(out);
    logger.info(name, { slug: request.data && request.data.slug });
    return out.result;
  });
exports.getAdmissionPortal = publicCall('getAdmissionPortal', admissionPublic.getPublicPortal);
exports.submitPublicAdmissionEnquiry = publicCall('submitPublicAdmissionEnquiry', admissionPublic.submitPublicEnquiry);

// Admission notifications (admission_notify.js). One status-history entry or one assignee
// change makes at most one notice per person; ids are derived and created with create(), so
// `retry: true` is safe: a failed run is repeated and only the missing notices are written.
const admissionNotify = require('./admission_notify');
const notifyCtx = () => ({ db, now: () => new Date() });
exports.notifyAdmissionStatus = onDocumentCreated(
  { document: 'schools/{schoolId}/branches/{branchId}/admissionStatusHistory/{entryId}', retry: true },
  async (event) => {
    try {
      await admissionNotify.onStatusHistory(notifyCtx(), event.params, event.data && event.data.data());
    } catch (e) {
      logger.error('admission status notice failed', { category: errorCategory(e) });
      throw e;
    }
  },
);
exports.notifyAdmissionAssignment = onDocumentUpdated(
  { document: 'schools/{schoolId}/branches/{branchId}/admissionEnquiries/{enquiryId}', retry: true },
  async (event) => {
    try {
      await admissionNotify.onEnquiryUpdated(
        notifyCtx(),
        event.params,
        event.data.before.exists ? event.data.before.data() : undefined,
        event.data.after.exists ? event.data.after.data() : undefined,
      );
    } catch (e) {
      logger.error('admission assignment notice failed', { category: errorCategory(e) });
      throw e;
    }
  },
);
exports.getAdmissionReport = admissionCall('getAdmissionReport', require('./admission_reports').getAdmissionReport, (d) => ({ scope: d.branchId ? 'branch' : 'school' }));
exports.changeAdmissionEnquiryStatus = admissionCall('changeAdmissionEnquiryStatus', admission.changeEnquiryStatus, (d, r) => ({ enquiry: d.enquiryId, status: r.status }));

exports.updatePlatformBranding = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await branding.updatePlatformBranding(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  logger.info('updatePlatformBranding', { by: a.uid, version: out.result.version });
  return out.result;
});

// ---- Platform administrators (Avail404) ------------------------------------
// Owner-only, second factor required, every change audited. The new person's
// password is never known to anyone: the app sends them a reset email.
const platformAdmin = require('./platform_admin');
const supportAccess = require('./support_access');
const platformCall = (name, fn, logOf, options = {}) =>
  onCall(callOptions(options), async (request) => {
    const a = signedIn(request);
    const out = await fn(adminCtx(), a.uid, a.token, request.data, process.env);
    if (out.error) fail(out);
    logger.info(name, { by: a.uid, ...(logOf ? logOf(out) : {}) });
    return out;
  });
exports.createPlatformAdmin = platformCall('createPlatformAdmin', platformAdmin.createPlatformAdmin, (o) => ({ target: o.uid, platformRole: o.platformRole }));
exports.listPlatformAdmins = platformCall('listPlatformAdmins', platformAdmin.listPlatformAdmins);
exports.setPlatformRole = platformCall('setPlatformRole', platformAdmin.setPlatformRole, (o) => ({ platformRole: o.platformRole }));
exports.setPlatformAdminStatus = platformCall('setPlatformAdminStatus', platformAdmin.setPlatformAdminStatus, (o) => ({ status: o.status }));

// ---- Platform lifecycle, billing and operations (Phase 3-4) -----------------------
const schoolLifecycle = require('./school_lifecycle');
const platformBilling = require('./platform_billing');
const platformOps = require('./platform_ops');
const LONG = { timeoutSeconds: 120 };
exports.setSchoolStatus = platformCall('setSchoolStatus', schoolLifecycle.setSchoolStatus, (o) => ({ status: o.status, users: o.usersUpdated }), LONG);
exports.refreshSchoolAccess = platformCall('refreshSchoolAccess', schoolLifecycle.refreshSchoolAccess, (o) => ({ users: o.usersUpdated }), LONG);
exports.createSchoolWithAdmin = platformCall('createSchoolWithAdmin', schoolLifecycle.createSchoolWithAdmin, (o) => ({ school: o.schoolId }));
exports.addSchoolAdmin = platformCall('addSchoolAdmin', schoolLifecycle.addSchoolAdmin);
exports.resetSchoolAdminAccess = platformCall('resetSchoolAdminAccess', schoolLifecycle.resetSchoolAdminAccess);
exports.setSchoolFeatures = platformCall('setSchoolFeatures', schoolLifecycle.setSchoolFeatures);
exports.requestSchoolOffboarding = platformCall('requestSchoolOffboarding', schoolLifecycle.requestSchoolOffboarding, undefined, LONG);
exports.approveSchoolOffboarding = platformCall('approveSchoolOffboarding', schoolLifecycle.approveSchoolOffboarding);
exports.cancelSchoolOffboarding = platformCall('cancelSchoolOffboarding', schoolLifecycle.cancelSchoolOffboarding, undefined, LONG);
exports.saveBillingRecord = platformCall('saveBillingRecord', platformBilling.saveBillingRecord);
exports.setBillingStatus = platformCall('setBillingStatus', platformBilling.setBillingStatus, (o) => ({ status: o.status }));
exports.listBillingRecords = platformCall('listBillingRecords', platformBilling.listBillingRecords);
exports.refreshPlatformStats = platformCall('refreshPlatformStats', platformOps.refreshPlatformStats, undefined, { timeoutSeconds: 300, memory: '512MiB' });
exports.publishPlatformNotice = platformCall('publishPlatformNotice', platformOps.publishPlatformNotice);
exports.withdrawPlatformNotice = platformCall('withdrawPlatformNotice', platformOps.withdrawPlatformNotice);
exports.listPlatformNotices = platformCall('listPlatformNotices', platformOps.listPlatformNotices);
exports.setAppRequirements = platformCall('setAppRequirements', platformOps.setAppRequirements);

// Nightly dashboard numbers and per-school usage (also on demand: refreshPlatformStats).
exports.platformStatsRollup = onSchedule(
  { schedule: 'every day 02:00', timeZone: 'Asia/Kolkata', timeoutSeconds: 540, memory: '512MiB' },
  async () => {
    try {
      const r = await platformOps.computeStats(adminCtx());
      logger.info('platform stats rolled up', r);
    } catch (e) {
      logger.error('platform stats rollup failed', { category: errorCategory(e) });
    }
  },
);

// A school's status changed (by setSchoolStatus, offboarding, or a console edit):
// mirror it onto its users so the rules and callables enforce it. Idempotent.
exports.schoolStatusChanged = onDocumentUpdated({ document: 'schools/{schoolId}', timeoutSeconds: 300, retry: true }, async (event) => {
  const before = event.data && event.data.before.data();
  const after = event.data && event.data.after.data();
  if (!before || !after || before.status === after.status) return;
  const r = await schoolLifecycle.applySchoolAccess(adminCtx(), event.params.schoolId, after.status || 'ACTIVE', Date.now() + 240000);
  logger.info('school access applied', { school: event.params.schoolId, status: after.status, updated: r.updated, done: r.done });
  if (!r.done) throw new Error('not finished; retry');
});

// Platform data is read only through these (the Firestore rules give clients no access).
const platformReads = require('./platform_reads');
const schoolCall = (name, fn) =>
  onCall(callOptions(), async (request) => {
    const a = signedIn(request);
    const out = await fn(adminCtx(), a.uid, a.token, request.data);
    if (out.error) fail(out);
    return out;
  });
exports.listMySupportGrants = platformCall('listMySupportGrants', platformReads.listMySupportGrants);
exports.getPlatformStats = platformCall('getPlatformStats', platformReads.getPlatformStats);
exports.listAuditLog = platformCall('listAuditLog', platformReads.listAuditLog);
exports.listSchoolSupportAccess = schoolCall('listSchoolSupportAccess', platformReads.listSchoolSupportAccess);
exports.listMyNotices = schoolCall('listMyNotices', platformReads.listMyNotices);

exports.requestSupportAccess = platformCall('requestSupportAccess', supportAccess.requestSupportAccess, (o) => ({ school: o.schoolId }));
exports.revokeSupportAccess = platformCall('revokeSupportAccess', supportAccess.revokeSupportAccess);
exports.getSchoolOverview = platformCall('getSchoolOverview', supportAccess.getSchoolOverview);

exports.getSchoolAuthSettings = onCall(callOptions({ secrets: [META_WA_ACCESS_TOKEN, OTP_PEPPER] }), async (request) => {
  const a = signedIn(request);
  const out = await access.getSchoolAuthSettings(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  return out.result;
});

exports.updateSchoolAuthSettings = onCall(callOptions({ secrets: [META_WA_ACCESS_TOKEN, OTP_PEPPER] }), async (request) => {
  const a = signedIn(request);
  const out = await access.updateSchoolAuthSettings(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  logger.info('updateSchoolAuthSettings', { by: a.uid, methods: out.result.methods });
  return out.result;
});

// Unauthenticated by design (the caller is signing in). Abuse is bounded by
// the per-phone / per-IP limits in otp.js.
const otpCtx = () => ({
  db,
  sender: createWhatsAppSender(whatsAppConfig()),
  pepper: OTP_PEPPER.value(),
  nowMs: () => Date.now(),
  newId: access.newId,
});

exports.requestPhoneOtp = onCall(callOptions({ secrets: [META_WA_ACCESS_TOKEN, OTP_PEPPER] }), async (request) => {
  if (!OTP_PEPPER.value()) throw new HttpsError('failed-precondition', 'OTP_UNAVAILABLE', { reason: 'OTP_UNAVAILABLE' });
  const d = request.data || {};
  const out = await requestOtp(otpCtx(), { phone: d.phone, ip: request.rawRequest && request.rawRequest.ip });
  if (out.error) {
    logger.warn('requestPhoneOtp refused', { reason: out.error, cause: out.reason });
    fail(out);
  }
  return out;
});

exports.verifyPhoneOtp = onCall(callOptions({ secrets: [OTP_PEPPER] }), async (request) => {
  const d = request.data || {};
  const out = await verifyOtp(otpCtx(), { challengeId: d.challengeId, code: d.code });
  if (out.error) {
    // Locked-out challenges are worth an audit record; routine typos are not.
    if (out.error === 'OTP_LOCKED') logger.warn('otp challenge locked');
    fail(out);
  }
  const auth = getAuth();
  const token = await auth.createCustomToken(out.uid, { via: 'PHONE_OTP' });
  await db.collection('users').doc(out.uid).update({
    'login.phoneVerifiedAt': FieldValue.serverTimestamp(),
    'login.lastOtpLoginAt': FieldValue.serverTimestamp(),
  });
  return { token };
});

// ---- teacherAccess index (see teacher_access.js) ---------------------------
// Rebuilt whenever an assignment changes or a staff record's login link /
// status changes, so the rules' view of "which sections is this teacher
// assigned to" follows the data without any client having to maintain it.
const accessCtx = () => ({ db, now: FieldValue.serverTimestamp() });

exports.teacherAssignmentChanged = onDocumentWritten(
  'schools/{schoolId}/branches/{branchId}/teacherAssignments/{assignmentId}',
  async (event) => {
    const { schoolId, branchId } = event.params;
    const ids = new Set();
    for (const snap of [event.data && event.data.before, event.data && event.data.after]) {
      if (snap && snap.exists && snap.data().teacherStaffId) ids.add(snap.data().teacherStaffId);
    }
    for (const staffId of ids) {
      try {
        await teacherAccess.refreshStaffAccess(accessCtx(), schoolId, branchId, staffId);
      } catch (e) {
        logger.error('teacherAccess refresh failed', { schoolId, branchId, staffId, error: String(e) });
        throw e; // let the platform retry
      }
    }
  },
);

exports.teacherStaffChanged = onDocumentWritten(
  'schools/{schoolId}/branches/{branchId}/staff/{staffId}',
  async (event) => {
    const { schoolId, branchId, staffId } = event.params;
    const before = event.data && event.data.before && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data && event.data.after && event.data.after.exists ? event.data.after.data() : null;
    const relevant = (s) => (s ? [s.userId, s.status, s.isTeacher] : null);
    if (JSON.stringify(relevant(before)) === JSON.stringify(relevant(after))) return; // unrelated edit
    if (before && before.userId && (!after || after.userId !== before.userId)) {
      await teacherAccess.removeAccessFor(db, schoolId, branchId, before.userId, staffId);
    }
    if (after) await teacherAccess.refreshStaffAccess(accessCtx(), schoolId, branchId, staffId);
  },
);

// Backfill / repair: rebuilds every teacher's access document in a branch.
// Run once after deploying (before the rules that require it), and any time
// "Check access" reports a missing or stale teacherAccess.
exports.refreshTeacherAccess = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const { schoolId, branchId } = request.data || {};
  if ([schoolId, branchId].some((v) => typeof v !== 'string' || !v)) fail({ error: 'INVALID_ARGUMENT' });
  const caller = await access.assertAdmin(db, a.uid, schoolId, branchId, a.token);
  if (!caller) fail({ error: 'PERMISSION_DENIED' });
  const out = await teacherAccess.refreshBranchAccess(accessCtx(), schoolId, branchId);
  logger.info('refreshTeacherAccess', { by: a.uid, ...out });
  return out;
});

// ---- currency lock (see currency_lock.js) ----------------------------------
// The first fee structure, invoice or payment of a school fixes its currency.
for (const [name, collection] of [
  ['lockCurrencyOnFeeStructure', 'feeStructures'],
  ['lockCurrencyOnInvoice', 'invoices'],
  ['lockCurrencyOnPayment', 'payments'],
]) {
  exports[name] = onDocumentCreated(`schools/{schoolId}/branches/{branchId}/${collection}/{docId}`, async (event) => {
    try {
      await currencyLock.lockCurrency(db, event.params.schoolId);
    } catch (e) {
      logger.error('currency lock failed', { category: errorCategory(e) });
      throw e; // let the platform retry
    }
  });
}

// ---- parentAccess index (see parent_access.js) -----------------------------
// Rebuilt when a parent link or a child's placement/status changes, so a
// family's class-level screens never depend on someone remembering to refresh.

exports.parentLinkChanged = onDocumentWritten(
  'schools/{schoolId}/branches/{branchId}/students/{studentId}/parentLinks/{parentId}',
  async (event) => {
    const { schoolId, branchId, parentId } = event.params;
    const before = event.data && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data && event.data.after.exists ? event.data.after.data() : null;
    if (!parentAccess.linkChanged(before, after)) return;
    try {
      await parentAccess.refreshParents(accessCtx(), schoolId, branchId, [parentId, before && before.parentId, after && after.parentId]);
    } catch (e) {
      logger.error('parentAccess refresh failed', { schoolId, branchId, parentId, error: String(e) });
      throw e; // let the platform retry
    }
  },
);

exports.parentStudentChanged = onDocumentWritten(
  'schools/{schoolId}/branches/{branchId}/students/{studentId}',
  async (event) => {
    const { schoolId, branchId, studentId } = event.params;
    const before = event.data && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data && event.data.after.exists ? event.data.after.data() : null;
    if (!parentAccess.placementChanged(before, after)) return;
    try {
      await parentAccess.refreshFamiliesOfStudent(accessCtx(), schoolId, branchId, studentId);
    } catch (e) {
      logger.error('parentAccess refresh failed', { schoolId, branchId, studentId, error: String(e) });
      throw e;
    }
  },
);

// Backfill / repair: rebuilds every family's index in a branch. Run once after
// deploying, for parents whose index was never built.
exports.refreshParentAccess = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const { schoolId, branchId } = request.data || {};
  if ([schoolId, branchId].some((v) => typeof v !== 'string' || !v)) fail({ error: 'INVALID_ARGUMENT' });
  const caller = await access.assertAdmin(db, a.uid, schoolId, branchId, a.token);
  if (!caller) fail({ error: 'PERMISSION_DENIED' });
  const out = await parentAccess.refreshBranchParents(accessCtx(), schoolId, branchId);
  logger.info('refreshParentAccess', { by: a.uid, ...out });
  return out;
});

// Every examination carries `sectionScope` (section id or 'ALL'): see exam_scope.js.
exports.examScopeStamp = onDocumentWritten(
  'schools/{schoolId}/branches/{branchId}/examinations/{examId}',
  async (event) => {
    const after = event.data && event.data.after.exists ? event.data.after : null;
    if (!after) return;
    try {
      await examScope.stampExam(after.ref, after.data());
    } catch (e) {
      logger.error('examScope stamp failed', { path: after.ref.path, error: String(e) });
      throw e; // let the platform retry
    }
  },
);

// A parent's own screens (leave for a child, results, homework, timetable) are
// authorised by their parentAccess index. The app calls this when it finds the
// index missing, so a family is never locked out waiting for an admin.
exports.refreshMyParentAccess = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await parentAccess.refreshOwnFamily(accessCtx(), a.uid);
  if (out.error) fail(out);
  return out;
});

// ---- Multi-branch staff ----------------------------------------------------

// A school admin grants / changes / revokes a staff login's role in ANOTHER
// branch (users.branchRoles — written only here; see branch_access.js).
exports.setBranchAccess = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await branchAccess.setBranchAccess(
    { db, now: FieldValue.serverTimestamp() },
    a.uid,
    request.data,
    a.token,
  );
  if (out.error) fail(out);
  logger.info('setBranchAccess', { by: a.uid, branchId: request.data.branchId, role: request.data.role });
  return { branchRoles: out.branchRoles };
});

// A per-branch role is only as good as the staff record behind it: when that
// record is deactivated (or unlinked) in the branch, the role is removed.
exports.staffBranchAccessSync = onDocumentWritten(
  'schools/{schoolId}/branches/{branchId}/staff/{staffId}',
  async (event) => {
    const { schoolId, branchId } = event.params;
    const before = event.data && event.data.before.exists ? event.data.before.data() : null;
    const after = event.data && event.data.after.exists ? event.data.after.data() : null;
    try {
      await branchAccess.revokeIfStaffInactive(
        { db, now: FieldValue.serverTimestamp() },
        { schoolId, branchId, before, after },
      );
    } catch (e) {
      logger.error('staffBranchAccessSync failed', { schoolId, branchId, message: String(e.message || e) });
    }
  },
);

// When an account stops being allowed to sign in (status no longer ACTIVE, or
// its login switched off) its phones stop receiving its notices at once,
// whichever screen or function made the change (NOTIF-1 / NOTIF-2).
exports.dropDevicesOnAccessLoss = onDocumentUpdated('users/{uid}', async (event) => {
  const before = event.data && event.data.before.data();
  const after = event.data && event.data.after.data();
  if (!deviceCleanup.lostAccess(before, after)) return;
  try {
    const n = await deviceCleanup.removeAllDevices(db, event.params.uid);
    logger.info('devices removed after access loss', { removed: n });
  } catch (e) {
    logger.error('device cleanup failed', { error: String(e.message || e) });
    throw e; // let the platform retry the trigger
  }
});

// ---- Account deletion requests ---------------------------------------------
// Records, verifies and reviews requests (docs/account-deletion.md). Nothing
// here deletes an account: executing an approved request is a separate step.

const deletionCtx = () => ({ db, now: () => new Date() });
// First hop of X-Forwarded-For (Cloud Run puts the client there), else the socket.
const clientIp = (request) => {
  const req = request.rawRequest;
  const fwd = req && req.headers && req.headers['x-forwarded-for'];
  return (typeof fwd === 'string' && fwd.split(',')[0].trim()) || (req && req.ip) || 'unknown';
};
const deletionLog = (what, out) => logger.info(what, { reference: out.result && out.result.reference, status: out.result && out.result.status });

exports.requestAccountDeletion = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await accountDeletion.requestOwn(deletionCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  deletionLog('account deletion requested', out);
  return { ...out.result, duplicate: out.duplicate === true };
});

exports.getMyDeletionRequests = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  return (await accountDeletion.listOwn(deletionCtx(), a.uid)).result;
});

exports.cancelAccountDeletion = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await accountDeletion.cancelOwn(deletionCtx(), a.uid, request.data);
  if (out.error) fail(out);
  deletionLog('account deletion cancelled', out);
  return out.result;
});

// Public (no sign-in): the web form. Same answer for any address; the e-mail
// link, not this call, proves ownership.
exports.requestAccountDeletionPublic = onCall(callOptions(), async (request) => {
  const out = await accountDeletion.requestPublic(deletionCtx(), request.data, clientIp(request));
  if (out.error) fail(out);
  deletionLog('public account deletion submitted', out);
  return out.result;
});

// Public: the category of a request, by its unguessable reference.
exports.getDeletionRequestStatus = onCall(callOptions(), async (request) => {
  const out = await accountDeletion.statusPublic(deletionCtx(), request.data);
  if (out.error) fail(out);
  return out.result;
});

// Signed in via the e-mail link: proves the address and opens the request.
exports.confirmAccountDeletionRequest = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  const out = await accountDeletion.confirmPublic(deletionCtx(), a.uid, a.token, request.data, getAuth());
  if (out.error) fail(out);
  deletionLog('public account deletion confirmed', out);
  return { ...out.result, duplicate: out.duplicate === true };
});

// Avail404 only: an ACTIVE platform admin with a second factor and the OWNER or
// COMPLIANCE platform role.
async function requireDeletionReviewer(a) {
  const c = await platformAdmin.platformCaller(db, a.uid, a.token, ['OWNER', 'COMPLIANCE']);
  if (c.error) throw new HttpsError('permission-denied', 'Not allowed.');
}

exports.listAccountDeletionRequests = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  await requireDeletionReviewer(a);
  const out = await accountDeletion.listForReview(deletionCtx(), a.uid, request.data);
  if (out.error) fail(out);
  return { requests: out.result };
});

exports.reviewAccountDeletion = onCall(callOptions(), async (request) => {
  const a = signedIn(request);
  await requireDeletionReviewer(a);
  const out = await accountDeletion.review(deletionCtx(), a.uid, request.data);
  if (out.error) fail(out);
  deletionLog('account deletion reviewed', out);
  return out.result;
});

exports.expireDeletionRequests = onSchedule(
  { schedule: 'every 24 hours', timeZone: 'Asia/Kolkata', timeoutSeconds: 120 },
  async () => {
    try {
      const n = await accountDeletion.expireUnverified(deletionCtx());
      logger.info('unverified deletion requests expired', { expired: n });
    } catch (e) {
      logger.error('expire deletion requests failed', { category: errorCategory(e) });
    }
  },
);

// ---- Carrying out approved requests -------------------------------------------
// Off unless ACCOUNT_DELETION_PROCESSING_ENABLED=true in the project's functions
// env. Deleting needs the pepper only to derive the non-identifying audit token.

const PROCESS_BUDGET_MS = 8 * 60 * 1000;
const processingCtx = () => ({
  db,
  auth: getAuth(),
  storage: bucketStorage(getStorage().bucket()),
  now: () => new Date(),
  key: OTP_PEPPER.value(),
  deadline: Date.now() + PROCESS_BUDGET_MS,
});

exports.processDeletionRequests = onSchedule(
  { schedule: 'every 60 minutes', timeZone: 'Asia/Kolkata', timeoutSeconds: 540, memory: '512MiB', secrets: [OTP_PEPPER] },
  async () => {
    try {
      const r = await deletionProcessor.sweep(processingCtx());
      logger.info('deletion sweep', r.skipped ? { skipped: true } : { processed: r.results.map((x) => ({ reference: x.reference, status: x.status })) });
    } catch (e) {
      logger.error('deletion sweep failed', { category: errorCategory(e) });
    }
  },
);

// Avail404 only: run one approved request now instead of waiting for the sweep.
exports.processAccountDeletion = onCall(
  callOptions({ secrets: [OTP_PEPPER], timeoutSeconds: 540, memory: '512MiB' }),
  async (request) => {
    const a = signedIn(request);
    await requireDeletionReviewer(a);
    const reference = request.data && request.data.reference;
    if (typeof reference !== 'string' || !/^DEL-[A-Z2-7]{16}$/.test(reference)) {
      throw new HttpsError('invalid-argument', 'INVALID_ARGUMENT', { reason: 'INVALID_ARGUMENT' });
    }
    const out = await deletionProcessor.processRequest(processingCtx(), reference);
    if (out.error) fail(out);
    logger.info('account deletion processed', { reference, status: out.status });
    return { reference, status: out.status, done: out.done === true };
  },
);

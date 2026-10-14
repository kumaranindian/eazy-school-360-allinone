'use strict';

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { setGlobalOptions } = require('firebase-functions/v2');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { FieldValue } = require('firebase-admin/firestore');
const logger = require('firebase-functions/logger');

const { broadcastRecipients, targetedRecipients } = require('./recipients');
const { pushToUsers } = require('./push');
const { defineSecret, defineString } = require('firebase-functions/params');
const { provisionLogins, ensureAuthUser, enablePortalLinks } = require('./provision');
const access = require('./access');
const { requestOtp, verifyOtp } = require('./otp');
const { createWhatsAppSender } = require('./whatsapp');

initializeApp();
// Must match the Firestore database region (Firestore triggers are regional).
setGlobalOptions({ region: process.env.FUNCTIONS_REGION || 'us-central1', maxInstances: 10 });

const db = getFirestore();
const messaging = getMessaging();

async function deliver(event, resolve) {
  const snap = event.data;
  if (!snap) return;
  const n = snap.data();
  const { schoolId, branchId } = event.params;
  const doc = { ...n, schoolId, branchId };
  try {
    const userIds = await resolve(doc);
    const sent = await pushToUsers({
      db,
      messaging,
      userIds,
      exclude: n.createdBy,
      type: n.type,
      title: n.title,
      body: n.body,
      data: { refType: n.refType || '', refId: n.refId || '' },
    });
    logger.info('push delivered', { path: snap.ref.path, type: n.type, recipients: userIds.size, sent });
  } catch (e) {
    // Retrying would risk duplicate pushes; the in-app feed is the record.
    logger.error('push failed', { path: snap.ref.path, error: String(e) });
  }
}

// Announcements, homework, results: audience-addressed notices.
exports.pushBroadcastNotice = onDocumentCreated(
  'schools/{schoolId}/branches/{branchId}/broadcastNotices/{noticeId}',
  (event) => deliver(event, (doc) => broadcastRecipients(db, doc)),
);

// Leave decisions, messages, timetable, etc.: per-user notifications.
exports.pushNotification = onDocumentCreated(
  'schools/{schoolId}/branches/{branchId}/notifications/{notificationId}',
  (event) => deliver(event, (doc) => targetedRecipients(db, doc)),
);

// Creates sign-in accounts for existing staff / parent records and links them.
// Callable by school/branch admins only (checked server-side).
exports.provisionLogins = onCall(async (request) => {
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
  });
  return out;
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
  UNAUTHENTICATED: 'unauthenticated',
  RATE_LIMITED: 'resource-exhausted',
  RESEND_COOLDOWN: 'resource-exhausted',
  DELIVERY_FAILED: 'unavailable',
  OTP_UNAVAILABLE: 'failed-precondition',
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
  ensureAuthUser,
  enablePortalLinks,
  configured: { phoneOtp: phoneOtpConfigured() },
});

exports.getLoginAccess = onCall(async (request) => {
  const a = signedIn(request);
  const out = await access.getLoginAccess(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  return out.result;
});

exports.setLoginAccess = onCall(async (request) => {
  const a = signedIn(request);
  const out = await access.setLoginAccess(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  logger.info('setLoginAccess', { by: a.uid, kind: request.data.kind, enabled: out.result.enabled });
  return out.result;
});

exports.getSchoolAuthSettings = onCall({ secrets: [META_WA_ACCESS_TOKEN, OTP_PEPPER] }, async (request) => {
  const a = signedIn(request);
  const out = await access.getSchoolAuthSettings(adminCtx(), a.uid, a.token, request.data);
  if (out.error) fail(out);
  return out.result;
});

exports.updateSchoolAuthSettings = onCall({ secrets: [META_WA_ACCESS_TOKEN, OTP_PEPPER] }, async (request) => {
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

exports.requestPhoneOtp = onCall({ secrets: [META_WA_ACCESS_TOKEN, OTP_PEPPER] }, async (request) => {
  if (!OTP_PEPPER.value()) throw new HttpsError('failed-precondition', 'OTP_UNAVAILABLE', { reason: 'OTP_UNAVAILABLE' });
  const d = request.data || {};
  const out = await requestOtp(otpCtx(), { phone: d.phone, ip: request.rawRequest && request.rawRequest.ip });
  if (out.error) {
    logger.warn('requestPhoneOtp refused', { reason: out.error, cause: out.reason });
    fail(out);
  }
  return out;
});

exports.verifyPhoneOtp = onCall({ secrets: [OTP_PEPPER] }, async (request) => {
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

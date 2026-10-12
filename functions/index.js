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
const { provisionLogins } = require('./provision');

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

'use strict';

// Detective enforcement for modules whose writes go straight from the app to Firestore (decision D6).
// The Firestore rules cannot hold a per-module clause (size limit), so the UI hides a disabled
// module and this trigger notices anyway: a document CREATED in a disabled module's collection is
// recorded in the platform audit log as FEATURE_ACCESS_DENIED (who, where, which module). It is
// deliberately NOT reverted: deleting a user's data automatically is a destructive decision
// (see the Phase 8 report); the record lets the platform team act on it.
// One deterministic audit id per document, so a retried trigger writes nothing new.

const crypto = require('node:crypto');
const features = require('./features');
const { own } = require('./ids');
const engine = require('./access_engine');

// branch collection -> catalogue feature
const MODULE_COLLECTIONS = Object.freeze({
  students: 'students',
  parents: 'parents',
  staff: 'staff',
  attendanceSessions: 'attendance',
  studentAttendance: 'attendance',
  staffAttendanceDays: 'attendance',
  feeStructures: 'fees',
  invoices: 'fees',
  payments: 'fees',
  leaveApplications: 'leave',
  timetables: 'timetable',
  substitutions: 'timetable',
  homework: 'homework',
  homeworkSubmissions: 'homework',
  announcements: 'announcements',
  examinations: 'exams',
  marksSheets: 'exams',
  conversations: 'messages',
});

const auditId = (path) => `fg-${crypto.createHash('sha256').update(path).digest('hex').slice(0, 32)}`;

/**
 * Called for every create in a guarded collection. Returns { flagged, feature } or { ok: true }.
 * Never throws for a missing school (a deleted school has nothing to guard).
 */
async function checkCreate(ctx, { schoolId, branchId, collection, docId, data }) {
  const feature = own(MODULE_COLLECTIONS, collection);
  if (!feature) return { ok: true };
  const school = (await ctx.db.collection('schools').doc(schoolId).get()).data();
  if (!school || features.usable(school.features, feature)) return { ok: true };
  const path = `schools/${schoolId}/branches/${branchId}/${collection}/${docId}`;
  const createdBy = data && typeof data.createdBy === 'string' ? data.createdBy : null;
  await ctx.db.collection('platformAuditLog').doc(auditId(path)).set({
    action: 'FEATURE_ACCESS_DENIED',
    actorUid: createdBy,
    actorEmail: null,
    actorPlatformRole: null,
    targetUid: null,
    targetEmail: null,
    schoolId,
    reason: null,
    result: 'FLAGGED',
    meta: { feature, collection, path, code: engine.CODES.FEATURE_DISABLED },
    source: 'TRIGGER',
    createdAt: ctx.now,
  });
  return { flagged: true, feature };
}

module.exports = { MODULE_COLLECTIONS, auditId, checkCreate };

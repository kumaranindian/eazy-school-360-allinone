'use strict';

// Admission notifications (docs/admission-management/, phase 10).
//
// Events are turned into `notifications` documents in the branch, the SAME
// collection the app and the push trigger already use, so there is one delivery
// path. Rules, as in notify_events.js:
//   * IDEMPOTENT: ids are derived from the event (type, enquiry, revision, person)
//     and written with create(); a retried trigger creates only what is missing.
//   * ONE EVENT, ONE NOTICE: driven by the immutable status-history entry (one per
//     status change) or the assignee change, not by every edit.
//   * NARROW RECIPIENTS, MINIMAL TEXT: the text names the enquiry NUMBER and what
//     happened. Never remarks, rejection reasons, phone numbers or document names.
//   * The person who did it is not told about it.
//   * Parents hear only that the admission is confirmed, and only once they have a
//     login (a parent record linked to an ACTIVE user of the school).
//   * Each kind can be switched off in the admission settings.

const a = require('./admission');
const { createOnce } = require('./notify_events');

const TYPES = {
  NEW: 'ADMISSION_ENQUIRY_NEW',
  ASSIGNED: 'ADMISSION_ASSIGNED',
  SUBMITTED: 'ADMISSION_APP_SUBMITTED',
  APPROVED: 'ADMISSION_APP_APPROVED',
  REJECTED: 'ADMISSION_APP_REJECTED',
  CONFIRMED: 'ADMISSION_CONFIRMED',
  PARENT_CONFIRMED: 'ADMISSION_CONFIRMED_PARENT',
};
const STAFF_TYPES = Object.values(TYPES).filter((t) => t !== TYPES.PARENT_CONFIRMED);

const activeUser = async (db, schoolId, uid) => {
  if (!a.isStr(uid)) return null;
  const u = (await db.collection('users').doc(uid).get()).data();
  return u && u.schoolId === schoolId && u.status === 'ACTIVE' ? u : null;
};

async function usersWithRole(db, schoolId, role) {
  const q = await db.collection('users').where('schoolId', '==', schoolId).where('role', '==', role).where('status', '==', 'ACTIVE').get();
  return q.docs.map((d) => ({ id: d.id, ...d.data() }));
}

/** The branch's administrators, else the school's (who is told about a new lead). */
async function adminsOf(db, schoolId, branchId) {
  const branch = (await usersWithRole(db, schoolId, 'BRANCH_ADMIN')).filter((u) => u.branchId === branchId).map((u) => u.id);
  if (branch.length) return branch;
  return (await usersWithRole(db, schoolId, 'SCHOOL_ADMIN')).map((u) => u.id);
}

/** Who decides applications: school admins, plus the branch's admins when the school allows it. */
async function decidersOf(db, schoolId, branchId, settings) {
  const owners = (await usersWithRole(db, schoolId, 'SCHOOL_ADMIN')).map((u) => u.id);
  if (!settings.branchAdminsMayApprove) return owners;
  const branch = (await usersWithRole(db, schoolId, 'BRANCH_ADMIN')).filter((u) => u.branchId === branchId).map((u) => u.id);
  return [...new Set([...owners, ...branch])];
}

/** The assignee, else the branch's administrators. */
async function ownersOf(db, schoolId, branchId, enquiry) {
  if (enquiry.assignedTo && (await activeUser(db, schoolId, enquiry.assignedTo))) return [enquiry.assignedTo];
  return adminsOf(db, schoolId, branchId);
}

async function send(ctx, { schoolId, branchId, type, id, recipients, title, body, refType = 'ENQUIRY', refId, skip }) {
  let created = 0;
  for (const uid of [...new Set(recipients)]) {
    if (!uid || uid === skip) continue;
    const ok = await createOnce(a.branchRef(ctx.db, schoolId, branchId).collection('notifications').doc(`${type}__${id}__${uid}`), {
      schoolId,
      branchId,
      audience: 'USER',
      recipientUserId: uid,
      type,
      title,
      body,
      refType,
      refId,
      createdBy: 'system',
      createdAt: ctx.now(),
      readAt: null,
    });
    if (ok) created++;
  }
  return created;
}

const PUBLIC = 'public-portal';

/**
 * One status-history entry was written. [data] is the entry
 * ({enquiryId, revision, from, to, actorId}).
 */
async function onStatusHistory(ctx, params, data) {
  if (!data || !a.isStr(data.enquiryId)) return { created: 0 };
  const { db } = ctx;
  const { schoolId, branchId } = params;
  const settings = await a.loadSettings(db, schoolId);
  if (!settings.enabled) return { created: 0 };
  const on = settings.notifications || {};
  const enquirySnap = await a.branchRef(db, schoolId, branchId).collection('admissionEnquiries').doc(data.enquiryId).get();
  if (!enquirySnap.exists) return { created: 0 };
  const e = enquirySnap.data();
  const n = e.enquiryNumber;
  const id = `${data.enquiryId}__${data.revision}`;
  const base = { schoolId, branchId, id, refId: data.enquiryId, skip: data.actorId };
  let created = 0;

  if (data.to === 'NEW' && !data.from) {
    if (e.assignedTo) {
      if (on.assignment !== false) created += await send(ctx, { ...base, type: TYPES.ASSIGNED, recipients: [e.assignedTo], title: 'Enquiry assigned to you', body: `Enquiry ${n} was assigned to you.` });
    } else if (on.newEnquiry !== false) {
      created += await send(ctx, { ...base, type: TYPES.NEW, recipients: await adminsOf(db, schoolId, branchId), title: 'New admission enquiry', body: e.channel === 'PUBLIC_PORTAL' ? `Enquiry ${n} was received from the website.` : `Enquiry ${n} was added.` });
    }
  } else if (data.to === 'APPLICATION_SUBMITTED' && on.applicationSubmitted !== false) {
    created += await send(ctx, { ...base, type: TYPES.SUBMITTED, recipients: await decidersOf(db, schoolId, branchId, settings), title: 'Application ready for review', body: `The application for enquiry ${n} was submitted.` });
  } else if ((data.to === 'APPROVED' || data.to === 'REJECTED') && on.decision !== false) {
    const approved = data.to === 'APPROVED';
    created += await send(ctx, { ...base, type: approved ? TYPES.APPROVED : TYPES.REJECTED, recipients: await ownersOf(db, schoolId, branchId, e), title: approved ? 'Application approved' : 'Application not approved', body: approved ? `The application for enquiry ${n} was approved.` : `The application for enquiry ${n} was not approved.` });
  } else if (data.to === 'ADMISSION_CONFIRMED') {
    if (on.confirmed !== false) {
      created += await send(ctx, { ...base, type: TYPES.CONFIRMED, recipients: await ownersOf(db, schoolId, branchId, e), title: 'Admission confirmed', body: `Enquiry ${n} was converted to a student.` });
    }
    if (on.parentConfirmed !== false) created += await notifyParents(ctx, { schoolId, branchId, enquiryId: data.enquiryId, id, enquiry: e });
  }
  return { created };
}

/** Tells the family (only parents who have a login) that the admission is confirmed. Nothing else. */
async function notifyParents(ctx, { schoolId, branchId, enquiryId, id, enquiry }) {
  const { db } = ctx;
  const conv = (await a.branchRef(db, schoolId, branchId).collection('admissionConversions').doc(enquiryId).get()).data();
  if (!conv) return 0;
  const recipients = [];
  for (const parentId of conv.parentIds || []) {
    const p = (await a.branchRef(db, schoolId, branchId).collection('parents').doc(parentId).get()).data();
    if (p && p.linkedUserId && (await activeUser(db, schoolId, p.linkedUserId))) recipients.push(p.linkedUserId);
  }
  const first = enquiry.student && enquiry.student.firstName ? enquiry.student.firstName : 'Your child';
  return send(ctx, {
    schoolId, branchId, id, refId: conv.studentId, refType: 'STUDENT', type: TYPES.PARENT_CONFIRMED, recipients,
    title: 'Admission confirmed', body: `${first}'s admission is confirmed. Admission number ${conv.admissionNumber}.`,
  });
}

/** The enquiry changed: tell a NEW assignee (not the person who assigned). */
async function onEnquiryUpdated(ctx, params, before, after) {
  if (!before || !after || before.assignedTo === after.assignedTo || !after.assignedTo) return { created: 0 };
  const { db } = ctx;
  const { schoolId, branchId } = params;
  const settings = await a.loadSettings(db, schoolId);
  if (!settings.enabled || (settings.notifications || {}).assignment === false) return { created: 0 };
  if (!(await activeUser(db, schoolId, after.assignedTo))) return { created: 0 };
  const created = await send(ctx, {
    schoolId, branchId, type: TYPES.ASSIGNED, id: `${params.enquiryId}__${after.revision}`, refId: params.enquiryId,
    recipients: [after.assignedTo], skip: after.updatedBy, title: 'Enquiry assigned to you', body: `Enquiry ${after.enquiryNumber} was assigned to you.`,
  });
  return { created };
}

module.exports = { TYPES, STAFF_TYPES, onStatusHistory, onEnquiryUpdated, adminsOf, decidersOf, ownersOf, notifyParents };

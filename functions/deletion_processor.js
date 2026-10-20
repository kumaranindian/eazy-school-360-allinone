'use strict';

// Carries out an APPROVED account-deletion request (docs/account-deletion.md,
// docs/account-deletion-data-matrix.md). Only runs when
// ACCOUNT_DELETION_PROCESSING_ENABLED=true; otherwise it does nothing.
//
// What it will never do:
//  * act on anything but the account stored on the request (never a uid, school
//    or role from a client);
//  * touch students, fee/invoice/payment/receipt/financial-audit records, or
//    any other person's data - it only matches documents that carry THIS
//    person's uid, and uids are unique to one person;
//  * delete the school.
//
// Every step is idempotent and re-runnable: documents it has handled stop
// matching its queries, so a retry simply continues. It works in small
// batches, remembers where it got to on the request, and stops cleanly at its
// time budget (FAILED_RETRYABLE) to be resumed by the next sweep.

const crypto = require('node:crypto');
const ad = require('./account_deletion');

const BATCH = 200;
const DELETED_NAME = 'Deleted user';

// Fields that hold a person's uid ("who did this"). Matched by equality.
const UID_FIELDS = [
  'actorId', 'applicantUserId', 'approvedBy', 'authorId', 'calculatedBy', 'changedBy',
  'concessionApprovedBy', 'createdBy', 'decidedBy', 'finalizedBy', 'flaggedBy', 'gradedBy',
  'linkedUserId', 'lockedBy', 'parentUserId', 'publishedBy', 'recipientUserId', 'reviewedBy',
  'reversedBy', 'senderUserId', 'submittedBy', 'supersededBy', 'teacherUserId', 'updatedBy',
  'uploadedBy', 'userId', 'voidedBy',
];

// A name stored next to a uid; replaced only when the document actually has it.
const NAME_FIELD = {
  actorId: 'actorName',
  applicantUserId: 'applicantName',
  approvedBy: 'approvedByName',
  authorId: 'authorName',
  changedBy: 'changedByName',
  createdBy: 'createdByName',
  decidedBy: 'decidedByName',
  finalizedBy: 'finalizedByName',
  gradedBy: 'gradedByName',
  lockedBy: 'lockedByName',
  parentUserId: 'parentName',
  publishedBy: 'publishedByName',
  reviewedBy: 'reviewedByName',
  senderUserId: 'senderName',
  submittedBy: 'submittedByName',
  teacherUserId: 'teacherName',
  updatedBy: 'updatedByName',
  uploadedBy: 'uploadedByName',
};

// Collections under schools/{s}/branches/{b} that are scanned for the uid fields.
const BRANCH_COLLECTIONS = [
  'academicYears', 'admissionNumbers', 'announcementHistory', 'announcements', 'assignmentSlots',
  'attendanceSessions', 'broadcastNotices', 'classSubjects', 'classes', 'conversationEvents',
  'conversations', 'departments', 'designations', 'examHistory', 'examRemarks', 'examinationSubjects',
  'examinations', 'gradingSchemes', 'holidays', 'homework', 'homeworkHistory', 'homeworkRevisions',
  'homeworkSubmissions', 'leaveApplications', 'leaveBalances', 'leaveCalendar', 'leaveDayLocks',
  'leaveHistory', 'leaveLedger', 'leaveSettings', 'leaveTypes', 'marksEntries', 'marksRevisions',
  'marksSheetHistory', 'marksSheets', 'messageContacts', 'parentAccess', 'parents', 'periodSets',
  'resultSummaries', 'settings', 'staff', 'staffAttendance', 'staffAttendanceDays', 'staffCodes',
  'studentAttendance', 'students', 'subjects', 'substitutionDays', 'substitutionHistory',
  'substitutions', 'teacherAccess', 'teacherAssignments', 'timetableCounters', 'timetableEntries',
  'timetableHistory', 'timetableLocks', 'timetables',
];

// Collections directly under schools/{s}.
const SCHOOL_COLLECTIONS = ['academicYears', 'authAudit', 'authSettings', 'branchAccessAudit', 'studentTransfers'];

// Nested collections, found with a collection-group query on a few fields each
// (single-field indexes for these are declared in firestore.indexes.json).
const NESTED_GROUPS = {
  academicRecords: ['createdBy', 'updatedBy'],
  documents: ['createdBy', 'updatedBy', 'uploadedBy'],
  history: ['changedBy', 'actorId', 'createdBy', 'updatedBy'],
  messages: ['senderUserId', 'createdBy'],
  parentLinks: ['createdBy', 'updatedBy'],
  sections: ['createdBy', 'updatedBy'],
};

// Retained unchanged on purpose (matrix C1/C2, decision D1: no retention period decided).
const FINANCIAL = [
  'feeCharges', 'feeCounters', 'feeStructures', 'financialAuditLogs', 'invoiceNumbers', 'invoices',
  'invoiceWaivers', 'paymentReversals', 'payments', 'receiptNumbers', 'receipts', 'studentFeeAssignments',
];

// Handled by dedicated steps, not the generic scan.
const SPECIAL = ['notifications'];

const USER_SUBCOLLECTIONS = ['devices', 'preferences', 'noticeReads'];

const STEPS = ['DISABLE', 'USER_DATA', 'NOTIFICATIONS', 'LINKED_RECORDS', 'SCRUB', 'STORAGE', 'PROFILE', 'AUTH'];

const enabled = (env = process.env) => String(env.ACCOUNT_DELETION_PROCESSING_ENABLED || '').toLowerCase() === 'true';

/** A stable, non-identifying replacement for a uid. Not reversible without the key. */
function tokenFor(key, uid) {
  const mac = crypto.createHmac('sha256', key).update(`account-deletion-token:${uid}`).digest('hex');
  return `deleted:${mac.slice(0, 16)}`;
}

const isStr = (v) => typeof v === 'string' && v.length > 0;

/** Runs [fn] over [items] with a small concurrency. */
async function pool(items, size, fn) {
  let i = 0;
  const workers = Array.from({ length: Math.min(size, items.length) }, async () => {
    while (i < items.length) {
      const item = items[i++];
      await fn(item);
    }
  });
  await Promise.all(workers);
}

class OutOfTime extends Error {}

// ---- helpers over a context ----------------------------------------------------

function guard(ctx) {
  if (ctx.deadline && Date.now() > ctx.deadline) throw new OutOfTime('time budget reached');
}

async function deleteAll(db, query) {
  let n = 0;
  for (;;) {
    const snap = await query.limit(BATCH).get();
    if (snap.docs.length === 0) return n;
    const batch = db.batch();
    for (const d of snap.docs) batch.delete(d.ref);
    await batch.commit();
    n += snap.docs.length;
  }
}

/** Storage paths to remove for attachments of a document. */
function attachmentPaths(data) {
  return (Array.isArray(data.attachments) ? data.attachments : [])
    .map((a) => (a && typeof a.path === 'string' ? a.path : null))
    .filter((p) => p && p.startsWith('schools/'));
}

/** Replaces the person's uid (and a paired name) in one document's data. */
function scrubbedFields(data, uid, token) {
  const out = {};
  for (const f of UID_FIELDS) {
    if (data[f] === uid) {
      out[f] = token;
      const name = NAME_FIELD[f];
      if (name && name in data) out[name] = DELETED_NAME;
    }
  }
  return out;
}

/**
 * Replaces this person's uid (and paired names) on every document the query
 * returns. [extra] may add field changes; attachment files of an affected
 * document are deleted BEFORE the document is updated, so an interrupted run
 * repeats the (idempotent) deletion instead of losing track of the files.
 */
async function scrubQuery(ctx, query, uid, token, extra) {
  let n = 0;
  for (;;) {
    guard(ctx);
    const snap = await query.limit(BATCH).get();
    if (snap.docs.length === 0) return n;
    const batch = ctx.db.batch();
    let changed = 0;
    for (const d of snap.docs) {
      const data = d.data();
      const changes = { ...scrubbedFields(data, uid, token), ...(extra ? extra(data) : {}) };
      if (Object.keys(changes).length === 0) continue;
      if (extra) for (const p of attachmentPaths(data)) await ctx.storage.deleteFile(p);
      batch.update(d.ref, changes);
      changed++;
    }
    if (changed === 0) return n; // nothing it can change: never loop on it
    await batch.commit();
    n += changed;
  }
}

// ---- steps ------------------------------------------------------------------------

async function branchIds(db, schoolId) {
  const snap = await db.collection('schools').doc(schoolId).collection('branches').get();
  return snap.docs.map((d) => d.id);
}

async function stepDisable(ctx, st) {
  await ctx.auth.updateUser(st.uid, { disabled: true }).catch((e) => {
    if (e && e.code === 'auth/user-not-found') return;
    throw e;
  });
  await ctx.auth.revokeRefreshTokens(st.uid).catch(() => undefined);
  const ref = ctx.db.collection('users').doc(st.uid);
  if ((await ref.get()).exists) await ref.update({ status: 'DISABLED' });
  return {};
}

async function stepUserData(ctx, st) {
  let n = 0;
  for (const sub of USER_SUBCOLLECTIONS) {
    n += await deleteAll(ctx.db, ctx.db.collection('users').doc(st.uid).collection(sub));
  }
  return { userDocs: n };
}

async function stepNotifications(ctx, st) {
  if (!st.schoolId) return {};
  let n = 0;
  for (const b of await branchIds(ctx.db, st.schoolId)) {
    guard(ctx);
    const col = ctx.db.collection('schools').doc(st.schoolId).collection('branches').doc(b).collection('notifications');
    n += await deleteAll(ctx.db, col.where('recipientUserId', '==', st.uid));
  }
  return { notifications: n };
}

async function stepLinkedRecords(ctx, st) {
  const { db } = ctx;
  if (!st.schoolId) return {};
  const counts = { parents: 0, staff: 0, access: 0 };
  const school = db.collection('schools').doc(st.schoolId);

  // Parent/guardian record (matrix B1, D2: contact details removed, record kept).
  if (st.linkedParentId && st.branchId) {
    const branch = school.collection('branches').doc(st.branchId);
    const pref = branch.collection('parents').doc(st.linkedParentId);
    if ((await pref.get()).exists) {
      await ctx.storage.deletePrefix(`schools/${st.schoolId}/branches/${st.branchId}/parents/${st.linkedParentId}/`);
      await pref.update({
        firstName: 'Deleted',
        middleName: null,
        lastName: 'guardian',
        displayName: 'Deleted guardian',
        displayNameLower: 'deleted guardian',
        phone: '',
        alternatePhone: null,
        email: null,
        occupation: null,
        photoUrl: null,
        addressLine1: null,
        addressLine2: null,
        city: null,
        state: null,
        country: null,
        postalCode: null,
        linkedUserId: null,
      });
      counts.parents++;
    }
    await branch.collection('parentAccess').doc(st.linkedParentId).delete();
    counts.access++;
  }

  for (const b of await branchIds(db, st.schoolId)) {
    guard(ctx);
    const branch = school.collection('branches').doc(b);
    // Staff record (matrix B2, D5: login unlinked, optional personal details removed,
    // employment facts kept until the school admin confirms).
    const staff = await branch.collection('staff').where('userId', '==', st.uid).get();
    for (const s of staff.docs) {
      // Photos only; staff documents (HR) belong to the employer and are left for the school.
      for (const path of await ctx.storage.list(`schools/${st.schoolId}/branches/${b}/staff/${s.id}/`)) {
        if (!path.includes('/documents/')) await ctx.storage.deleteFile(path);
      }
      await s.ref.update({
        userId: null,
        photoUrl: null,
        bloodGroup: null,
        alternatePhone: null,
        address: null,
        city: null,
        state: null,
        country: null,
        postalCode: null,
      });
      counts.staff++;
    }
    await branch.collection('teacherAccess').doc(st.uid).delete();
  }
  return counts;
}

/** Builds the list of scrub tasks once, so progress can be a simple index. */
async function scrubTasks(ctx, st) {
  const tasks = [];
  if (st.schoolId) {
    for (const c of SCHOOL_COLLECTIONS) tasks.push({ path: `schools/${st.schoolId}/${c}` });
    for (const b of await branchIds(ctx.db, st.schoolId)) {
      for (const c of BRANCH_COLLECTIONS) tasks.push({ path: `schools/${st.schoolId}/branches/${b}/${c}` });
      // Conversations also list their participants as an array of uids.
      tasks.push({ path: `schools/${st.schoolId}/branches/${b}/conversations`, participants: true });
    }
  }
  for (const [group, fields] of Object.entries(NESTED_GROUPS)) tasks.push({ group, fields });
  return tasks;
}

async function runScrubTask(ctx, st, task) {
  const token = ctx.token;
  if (task.participants) {
    let n = 0;
    for (;;) {
      guard(ctx);
      const snap = await ctx.db.collection(task.path).where('participants', 'array-contains', st.uid).limit(BATCH).get();
      if (snap.docs.length === 0) return n;
      const batch = ctx.db.batch();
      for (const d of snap.docs) {
        batch.update(d.ref, { participants: d.data().participants.map((x) => (x === st.uid ? token : x)) });
      }
      await batch.commit();
      n += snap.docs.length;
    }
  }
  if (task.path) {
    const leave = task.path.endsWith('/leaveApplications');
    let n = 0;
    for (const f of UID_FIELDS) {
      guard(ctx);
      // Free-text reasons and attached documents may hold health information.
      const extra = leave && f === 'applicantUserId' ? () => ({ reason: null, attachments: [] }) : null;
      n += await scrubQuery(ctx, ctx.db.collection(task.path).where(f, '==', st.uid), st.uid, token, extra);
    }
    return n;
  }
  if (task.group) {
    let n = 0;
    for (const f of task.fields) {
      guard(ctx);
      const extra = task.group === 'messages' && f === 'senderUserId' ? () => ({ attachments: [] }) : null;
      n += await scrubQuery(ctx, ctx.db.collectionGroup(task.group).where(f, '==', st.uid), st.uid, token, extra);
    }
    return n;
  }
  return 0;
}

async function stepScrub(ctx, st, checkpoint) {
  const tasks = await scrubTasks(ctx, st);
  let touched = 0;
  const start = Math.min(st.cursor || 0, tasks.length);
  for (let i = start; i < tasks.length; i++) {
    guard(ctx);
    touched += await runScrubTask(ctx, st, tasks[i]);
    if (i % 20 === 0) await checkpoint({ cursor: i + 1 });
  }
  await checkpoint({ cursor: 0 });
  return { scrubbed: touched };
}

async function stepStorage(ctx, st) {
  let n = 0;
  if (st.schoolId) {
    for (const b of await branchIds(ctx.db, st.schoolId)) {
      guard(ctx);
      n += await ctx.storage.deletePrefix(`schools/${st.schoolId}/branches/${b}/leaveDocs/${st.uid}/`);
    }
  }
  return { files: n };
}

async function stepProfile(ctx, st) {
  const ref = ctx.db.collection('users').doc(st.uid);
  if (!(await ref.get()).exists) return {};
  const now = ctx.now();
  // A stub: keeps the id and the school/role so references stay valid, and is
  // DISABLED (a status every screen already understands) with a deleted flag.
  await ref.set({
    schoolId: st.schoolId || null,
    branchId: st.branchId || null,
    role: st.role || null,
    status: 'DISABLED',
    deleted: true,
    name: DELETED_NAME,
    email: null,
    phone: null,
    photoUrl: null,
    login: null,
    linkedParentId: null,
    branchRoles: {},
    deletedAt: now,
    updatedAt: now,
  });
  return {};
}

async function stepAuth(ctx, st) {
  await ctx.auth.deleteUser(st.uid).catch((e) => {
    if (e && e.code === 'auth/user-not-found') return; // already gone: fine
    throw e;
  });
  return {};
}

const RUNNERS = {
  DISABLE: stepDisable,
  USER_DATA: stepUserData,
  NOTIFICATIONS: stepNotifications,
  LINKED_RECORDS: stepLinkedRecords,
  SCRUB: stepScrub,
  STORAGE: stepStorage,
  PROFILE: stepProfile,
  AUTH: stepAuth,
};

// ---- the request ---------------------------------------------------------------------

const RESUMABLE = [ad.STATUS.APPROVED, ad.STATUS.FAILED_RETRYABLE, ad.STATUS.PROCESSING];

/**
 * Processes one request. ctx: { db, auth, storage, now(), key, deadline?, enabled? }.
 * Returns { status, done, ... } and never throws for expected stops.
 */
async function processRequest(ctx, reference) {
  if (!(ctx.enabled === undefined ? enabled() : ctx.enabled)) return { error: 'PROCESSING_DISABLED' };
  const { db } = ctx;
  const ref = db.collection('accountDeletionRequests').doc(reference);
  const req = (await ref.get()).data();
  if (!req || !RESUMABLE.includes(req.status)) return { error: 'NOT_PROCESSABLE' };
  if (!req.uid) return { error: 'NOT_PROCESSABLE' };
  const uid = req.uid;
  const at = () => ctx.now();

  const user = (await db.collection('users').doc(uid).get()).data() || null;
  if (user && user.role === 'PLATFORM_ADMIN') return hold(ref, req, at(), ad.REASON.PLATFORM_ADMIN);
  if (user && (await ad.isSoleAdmin(db, uid, user))) return hold(ref, req, at(), ad.REASON.SOLE_ADMIN);

  if (req.status !== ad.STATUS.PROCESSING) {
    const next = ad.advance(req, ad.STATUS.PROCESSING, at());
    if (!next) return { error: 'NOT_PROCESSABLE' };
    await ref.set(next);
  }

  // The state the steps work from. Identity and tenant come from the stored
  // request and the server's own profile, never from a client.
  const progress = (await ref.get()).data().progress || { done: [], counts: {} };
  const st = {
    uid,
    schoolId: (user && user.schoolId) || req.schoolId || null,
    branchId: (user && user.branchId) || null,
    role: (user && user.role) || req.role || null,
    linkedParentId: (user && user.linkedParentId) || null,
    cursor: progress.cursor || 0,
  };
  ctx.token = tokenFor(ctx.key, uid);

  const save = async (patch) => {
    const cur = (await ref.get()).data();
    await ref.set({ ...cur, progress: { ...(cur.progress || { done: [], counts: {} }), ...patch }, updatedAt: at() });
  };
  const checkpoint = (patch) => save(patch);

  try {
    for (const name of STEPS) {
      if ((progress.done || []).includes(name)) continue;
      guard(ctx);
      // PROFILE reads the user doc; AUTH removes the login last, after all else.
      const counts = (await RUNNERS[name](ctx, st, checkpoint)) || {};
      progress.done = [...(progress.done || []), name];
      progress.counts = { ...(progress.counts || {}), ...counts };
      await save({ done: progress.done, counts: progress.counts });
    }
  } catch (e) {
    const cur = (await ref.get()).data();
    const failed = ad.advance(cur, ad.STATUS.FAILED_RETRYABLE, at());
    if (failed) await ref.set(failed);
    return { status: ad.STATUS.FAILED_RETRYABLE, done: false, outOfTime: e instanceof OutOfTime, error: e instanceof OutOfTime ? undefined : 'STEP_FAILED' };
  }

  const cur = (await ref.get()).data();
  const complete = ad.advance(cur, ad.STATUS.COMPLETED, at(), { completedAt: at() });
  await ref.set(complete);
  await ad.releaseLock(db, uid);
  return { status: ad.STATUS.COMPLETED, done: true, counts: progress.counts };
}

async function hold(ref, req, at, reason) {
  const next = ad.advance(req, ad.STATUS.ACTION_REQUIRED, at, { reason });
  if (next) await ref.set(next);
  return { status: ad.STATUS.ACTION_REQUIRED, done: false, reason };
}

/** Picks up approved or interrupted requests. Returns what it did. */
async function sweep(ctx, limit = 3) {
  if (!(ctx.enabled === undefined ? enabled() : ctx.enabled)) return { skipped: true };
  const results = [];
  const seen = new Set();
  for (const status of RESUMABLE) {
    const snap = await ctx.db.collection('accountDeletionRequests').where('status', '==', status).limit(limit).get();
    for (const d of snap.docs) {
      if (seen.has(d.id) || results.length >= limit) continue;
      seen.add(d.id);
      results.push({ reference: d.id, ...(await processRequest(ctx, d.id)) });
    }
  }
  return { results };
}

module.exports = {
  BRANCH_COLLECTIONS,
  SCHOOL_COLLECTIONS,
  NESTED_GROUPS,
  FINANCIAL,
  SPECIAL,
  UID_FIELDS,
  NAME_FIELD,
  STEPS,
  enabled,
  tokenFor,
  processRequest,
  sweep,
};

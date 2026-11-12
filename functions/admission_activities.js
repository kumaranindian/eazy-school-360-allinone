'use strict';

// Admission follow-up activities (docs/admission-management/, phase 4).
//
//   schools/{s}/branches/{b}/admissionActivities/{id}
//   schools/{s}/branches/{b}/admissionActivityHistory/{activityId}__{revision}   append-only
//
// An activity is one planned or finished contact with a family (call, WhatsApp,
// email, school visit, meeting, other). Rules give clients read access only;
// every change is a callable here. History is append-only: rescheduling,
// reassigning, completing or cancelling NEVER erases what came before — the
// activity keeps its own document and each change adds a history entry.
//
// The enquiry carries three derived fields kept in step inside the same
// transaction: `nextFollowUpDate` (earliest open activity), `openActivityCount`
// and `activityCount`. The enquiry's own `revision` is NOT bumped by activity
// changes, so logging a call never makes an open edit form stale.

const crypto = require('node:crypto');
const a = require('./admission');
const feeReminders = require('./fee_reminders');

// ---- constants -------------------------------------------------------------

const TYPES = ['PHONE_CALL', 'WHATSAPP', 'EMAIL', 'SCHOOL_VISIT', 'MEETING', 'OTHER'];
const TYPE_LABEL = {
  PHONE_CALL: 'Phone call',
  WHATSAPP: 'WhatsApp',
  EMAIL: 'Email',
  SCHOOL_VISIT: 'School visit',
  MEETING: 'Meeting',
  OTHER: 'Follow-up',
};
// School visits (phase 5) are activities of this type with a purpose. They have
// their own scheduling callable because they also move the enquiry's status.
const VISIT = 'SCHOOL_VISIT';
const PURPOSES = ['CAMPUS_TOUR', 'MEET_PRINCIPAL', 'ASSESSMENT', 'COUNSELLING', 'OTHER'];
// A visit can be booked while the enquiry is still a lead (or after an earlier visit).
const VISIT_START_STATUSES = ['NEW', 'CONTACTED', 'INTERESTED', 'VISIT_SCHEDULED', 'VISIT_COMPLETED'];
const SCHEDULED = 'SCHEDULED';
const COMPLETED = 'COMPLETED';
const CANCELLED = 'CANCELLED';
const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
// Overdue reminders look back this far, so a long-forgotten activity does not
// notify forever.
const OVERDUE_LOOKBACK_DAYS = 30;

const col = (db, s, b) => a.branchRef(db, s, b).collection('admissionActivities');
const histCol = (db, s, b) => a.branchRef(db, s, b).collection('admissionActivityHistory');

// ---- validation (pure) -----------------------------------------------------

/**
 * The schedulable part of an activity: { type, scheduledDate, scheduledTime?, remarks? }.
 * Returns { errors } or { value }. [today] (yyyy-mm-dd, school time) is the
 * earliest date allowed: nothing can be planned in the past.
 */
function validateSchedule(input, { today, allowVisit = false }) {
  const errors = {};
  const i = input || {};
  const type = a.trim(i.type);
  if (!TYPES.includes(type)) errors.type = 'is not an activity type';
  else if (type === VISIT && !allowVisit) errors.type = 'school visits are scheduled as visits';
  const purpose = a.trim(i.purpose);
  if (type === VISIT && allowVisit && !PURPOSES.includes(purpose)) errors.purpose = 'is required (campus tour, meet principal, assessment, counselling or other)';
  const date = i.scheduledDate;
  if (!a.validDate(date)) errors.scheduledDate = 'must be a date (yyyy-mm-dd)';
  else if (today && date < today) errors.scheduledDate = 'cannot be in the past';
  let time = null;
  if (i.scheduledTime !== undefined && i.scheduledTime !== null && i.scheduledTime !== '') {
    if (!a.isStr(i.scheduledTime) || !TIME.test(i.scheduledTime)) errors.scheduledTime = 'must be a time (hh:mm)';
    else time = i.scheduledTime;
  }
  const remarks = a.trim(i.remarks);
  if (remarks.length > 500) errors.remarks = 'up to 500 characters';
  if (Object.keys(errors).length) return { errors };
  return { value: { type, scheduledDate: date, scheduledTime: time, remarks: remarks || null, purpose: type === VISIT ? purpose : null } };
}

/** The completion record: { outcome (3-500), parentFeedback?, remarks? }. */
function validateCompletion(input) {
  const errors = {};
  const i = input || {};
  const outcome = a.trim(i.outcome);
  if (outcome.length < 3 || outcome.length > 500) errors.outcome = 'is required (3-500 characters)';
  const parentFeedback = a.trim(i.parentFeedback);
  if (parentFeedback.length > 500) errors.parentFeedback = 'up to 500 characters';
  const remarks = a.trim(i.remarks);
  if (remarks.length > 500) errors.remarks = 'up to 500 characters';
  if (Object.keys(errors).length) return { errors };
  return { value: { outcome, parentFeedback: parentFeedback || null, remarks: remarks || null } };
}

/** Earliest scheduled date among [dates] (yyyy-mm-dd), or null. */
function earliest(dates) {
  const d = dates.filter(Boolean).sort();
  return d.length ? d[0] : null;
}

/** Which bucket an OPEN activity falls in today: 'OVERDUE' | 'TODAY' | 'UPCOMING'. */
function bucketOf(scheduledDate, today) {
  if (scheduledDate < today) return 'OVERDUE';
  return scheduledDate === today ? 'TODAY' : 'UPCOMING';
}

// ---- shared transaction pieces ---------------------------------------------

async function context(ctx, uid, token, data) {
  const { db } = ctx;
  const { schoolId, branchId, enquiryId } = data || {};
  const caller = await a.authorize(db, uid, token, schoolId, branchId || null);
  if (!caller || !branchId) return { error: 'PERMISSION_DENIED' };
  const settings = await a.loadSettings(db, schoolId);
  if (!settings.enabled) return { error: 'FAILED_PRECONDITION', reason: 'admissions are not enabled for this school' };
  const today = a.civilToday(a.wall(ctx), await a.schoolZone(db, schoolId));
  return { db, schoolId, branchId, enquiryId, today };
}

async function openOf(tx, ctx, schoolId, branchId, enquiryId) {
  const snap = await tx.get(col(ctx.db, schoolId, branchId).where('enquiryId', '==', enquiryId).where('status', '==', SCHEDULED).limit(200));
  return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
}

function writeHistory(tx, ctx, activity, revision, event, extra, uid) {
  tx.set(histCol(ctx.db, activity.schoolId, activity.branchId).doc(`${activity.id}__${revision}`), {
    schoolId: activity.schoolId,
    branchId: activity.branchId,
    activityId: activity.id,
    enquiryId: activity.enquiryId,
    // what kind of activity this entry is about, so the timeline can say so
    type: activity.type || null,
    purpose: activity.purpose || null,
    revision,
    event,
    ...extra,
    actorId: uid,
    at: ctx.now,
  });
}

/** Updates the enquiry's derived follow-up fields (never its revision). */
function syncEnquiry(tx, ctx, enquiryRef, enquiry, { openDates, activityDelta }) {
  const open = openDates.length;
  tx.update(enquiryRef, {
    nextFollowUpDate: earliest(openDates),
    openActivityCount: open,
    activityCount: (Number.isInteger(enquiry.activityCount) ? enquiry.activityCount : 0) + activityDelta,
    lastActivityAt: ctx.now,
  });
}

function newActivityDoc(ctx, { schoolId, branchId, enquiryId, enquiry, value, assignedTo, uid }) {
  return {
    schoolId,
    branchId,
    enquiryId,
    enquiryNumber: enquiry.enquiryNumber,
    studentName: enquiry.studentName,
    type: value.type,
    purpose: value.purpose || null,
    scheduledDate: value.scheduledDate,
    scheduledTime: value.scheduledTime,
    assignedTo,
    status: SCHEDULED,
    remarks: value.remarks,
    outcome: null,
    parentFeedback: null,
    completedAt: null,
    completedBy: null,
    cancelReason: null,
    rescheduleCount: 0,
    revision: 1,
    createdAt: ctx.now,
    createdBy: uid,
    updatedAt: ctx.now,
    updatedBy: uid,
  };
}

// ---- callables -------------------------------------------------------------

/** The status a visit event moves the enquiry to, or null (pure). */
function visitStatusAfter({ event, status, otherOpenVisits, hasCompletedVisit }) {
  if (status !== 'VISIT_SCHEDULED' || otherOpenVisits > 0) return null;
  if (event === 'COMPLETED') return 'VISIT_COMPLETED';
  if (event === 'CANCELLED') return hasCompletedVisit ? 'VISIT_COMPLETED' : 'INTERESTED';
  return null;
}

/**
 * Plans an activity (or, with `visit`, a school visit) on an enquiry.
 * `requestId` (client-generated, optional) makes the call retry-safe: the same
 * id returns the activity already created. A visit also moves the enquiry to
 * VISIT_SCHEDULED, in the same transaction, when it is not there already.
 */
async function scheduleCore(ctx, uid, token, data, visit) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const input = visit ? { ...(data.visit || {}), type: VISIT } : data.activity;
  const parsed = validateSchedule(input, { today: c.today, allowVisit: visit });
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(parsed.errors) };
  const requestId = data.requestId;
  if (requestId !== undefined && !(a.isStr(requestId) && REQUEST_ID.test(requestId))) return { error: 'INVALID_ARGUMENT', reason: 'requestId: 8-64 letters, digits, - or _' };
  const id = requestId ? `${c.enquiryId}__${requestId}` : col(c.db, c.schoolId, c.branchId).doc().id;
  return c.db.runTransaction(async (tx) => {
    const cur = await a.loadEnquiry(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    if (!cur) return { error: 'NOT_FOUND' };
    const ref = col(c.db, c.schoolId, c.branchId).doc(id);
    const existing = await tx.get(ref);
    if (existing.exists) return { result: { id, duplicate: true } };
    if (a.TERMINAL.includes(cur.data.status)) return { error: 'FAILED_PRECONDITION', reason: visit ? 'a closed enquiry has no visits' : 'a closed enquiry has no follow-ups' };
    if (visit && !VISIT_START_STATUSES.includes(cur.data.status)) return { error: 'FAILED_PRECONDITION', reason: `a visit cannot be booked while the enquiry is ${cur.data.status}` };
    let assignedTo = cur.data.assignedTo || null;
    if (input && Object.prototype.hasOwnProperty.call(input, 'assignedTo')) {
      assignedTo = input.assignedTo ? await a.assignableUser(c.db, c.schoolId, c.branchId, input.assignedTo) : null;
      if (input.assignedTo && !assignedTo) return { error: 'INVALID_ARGUMENT', reason: 'assignedTo: that person cannot be assigned in this branch' };
    }
    const open = await openOf(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    const doc = newActivityDoc(ctx, { schoolId: c.schoolId, branchId: c.branchId, enquiryId: c.enquiryId, enquiry: cur.data, value: parsed.value, assignedTo, uid });
    tx.set(ref, doc);
    writeHistory(tx, ctx, { id, schoolId: c.schoolId, branchId: c.branchId, enquiryId: c.enquiryId, type: doc.type, purpose: doc.purpose }, 1, 'CREATED', { to: { scheduledDate: doc.scheduledDate, scheduledTime: doc.scheduledTime, assignedTo } }, uid);
    syncEnquiry(tx, ctx, cur.ref, cur.data, { openDates: [...open.map((o) => o.data.scheduledDate), doc.scheduledDate], activityDelta: 1 });
    if (visit && cur.data.status !== 'VISIT_SCHEDULED') a.applyStatus(tx, ctx, cur, { to: 'VISIT_SCHEDULED', reason: 'Visit scheduled', uid });
    return { result: { id, duplicate: false } };
  }, { maxAttempts: 10 });
}

const scheduleActivity = (ctx, uid, token, data) => scheduleCore(ctx, uid, token, data, false);
const scheduleVisit = (ctx, uid, token, data) => scheduleCore(ctx, uid, token, data, true);

async function loadActivity(tx, ctx, c, activityId) {
  if (!a.isStr(activityId) || !a.ID.test(activityId)) return null;
  const ref = col(c.db, c.schoolId, c.branchId).doc(activityId);
  const snap = await tx.get(ref);
  if (!snap.exists || snap.data().enquiryId !== c.enquiryId) return null;
  return { ref, data: snap.data(), id: activityId };
}

/** Shared shape of "change one open activity": checks, applies [mutate], syncs the enquiry, writes history. */
async function changeOpen(ctx, uid, token, data, { event, prepare }) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const prep = await prepare(c);
  if (prep && prep.error) return prep;
  return c.db.runTransaction(async (tx) => {
    const cur = await a.loadEnquiry(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    if (!cur) return { error: 'NOT_FOUND' };
    const act = await loadActivity(tx, ctx, c, data.activityId);
    if (!act) return { error: 'NOT_FOUND' };
    if (act.data.status !== SCHEDULED) return { error: 'FAILED_PRECONDITION', reason: 'only a scheduled activity can be changed' };
    if (data.baseRevision !== undefined && data.baseRevision !== act.data.revision) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    const open = await openOf(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    // Visits also move the enquiry's status. Everything that decides it is read
    // here, before the first write.
    const isVisit = act.data.type === VISIT;
    const otherOpenVisits = open.filter((o) => o.id !== act.id && o.data.type === VISIT).length;
    let hasCompletedVisit = false;
    if (isVisit && event === 'CANCELLED' && cur.data.status === 'VISIT_SCHEDULED' && otherOpenVisits === 0) {
      const done = await tx.get(col(c.db, c.schoolId, c.branchId).where('enquiryId', '==', c.enquiryId).where('type', '==', VISIT).where('status', '==', COMPLETED).limit(1));
      hasCompletedVisit = done.docs.length > 0;
    }
    const nextRev = act.data.revision + 1;
    const out = prep.apply({ tx, act, cur, nextRev, open });
    if (out.error) return out;
    tx.update(act.ref, { ...out.update, revision: nextRev, updatedAt: ctx.now, updatedBy: uid });
    writeHistory(tx, ctx, { id: act.id, schoolId: c.schoolId, branchId: c.branchId, enquiryId: c.enquiryId, type: act.data.type, purpose: act.data.purpose }, nextRev, event, out.history, uid);
    const others = open.filter((o) => o.id !== act.id).map((o) => o.data.scheduledDate);
    const openDates = [...others];
    if (out.stillOpen) openDates.push(out.update.scheduledDate || act.data.scheduledDate);
    if (out.extraOpenDate) openDates.push(out.extraOpenDate);
    syncEnquiry(tx, ctx, cur.ref, cur.data, { openDates, activityDelta: out.extraCreated ? 1 : 0 });
    if (out.after) out.after(tx, others);
    if (isVisit) {
      const to = visitStatusAfter({ event, status: cur.data.status, otherOpenVisits, hasCompletedVisit });
      if (to) a.applyStatus(tx, ctx, cur, { to, reason: event === 'COMPLETED' ? 'Visit completed' : 'Visit cancelled', uid });
    }
    return { result: { revision: nextRev, ...(out.result || {}) } };
  }, { maxAttempts: 10 });
}

/** Moves an open activity to another date/time. The old date stays in the history. */
function rescheduleActivity(ctx, uid, token, data) {
  return changeOpen(ctx, uid, token, data, {
    event: 'RESCHEDULED',
    prepare: async (c) => {
      const p = validateSchedule({ type: TYPES[0], scheduledDate: data.scheduledDate, scheduledTime: data.scheduledTime }, { today: c.today });
      if (p.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(p.errors) };
      const reason = a.trim(data.reason);
      if (reason.length > 200) return { error: 'INVALID_ARGUMENT', reason: 'reason: up to 200 characters' };
      return {
        apply: ({ act }) => ({
          update: { scheduledDate: data.scheduledDate, scheduledTime: a.trim(data.scheduledTime) || null, rescheduleCount: (act.data.rescheduleCount || 0) + 1 },
          history: { from: { scheduledDate: act.data.scheduledDate, scheduledTime: act.data.scheduledTime || null }, to: { scheduledDate: data.scheduledDate, scheduledTime: a.trim(data.scheduledTime) || null }, reason: reason || null },
          stillOpen: true,
        }),
      };
    },
  });
}

/** Hands an open activity to someone else (or to nobody). */
function reassignActivity(ctx, uid, token, data) {
  return changeOpen(ctx, uid, token, data, {
    event: 'REASSIGNED',
    prepare: async (c) => {
      let target = null;
      if (data.assignedTo !== null && data.assignedTo !== undefined) {
        target = await a.assignableUser(c.db, c.schoolId, c.branchId, data.assignedTo);
        if (!target) return { error: 'INVALID_ARGUMENT', reason: 'that person cannot be assigned in this branch' };
      }
      return {
        apply: ({ act }) => ({
          update: { assignedTo: target },
          history: { from: { assignedTo: act.data.assignedTo || null }, to: { assignedTo: target } },
          stillOpen: true,
        }),
      };
    },
  });
}

/** Cancels an open activity; a reason is required and kept. */
function cancelActivity(ctx, uid, token, data) {
  return changeOpen(ctx, uid, token, data, {
    event: 'CANCELLED',
    prepare: async () => {
      const reason = a.trim(data.reason);
      if (reason.length < 3 || reason.length > 200) return { error: 'INVALID_ARGUMENT', reason: 'reason: required (3-200 characters)' };
      return {
        apply: () => ({
          update: { status: CANCELLED, cancelReason: reason },
          history: { reason },
          stillOpen: false,
        }),
      };
    },
  });
}

/**
 * Records what happened. The outcome is required. Optionally plans the next
 * contact (`next`) in the same transaction, so the enquiry is never left
 * without a follow-up by a half-finished two-step save.
 */
function completeActivity(ctx, uid, token, data) {
  return changeOpen(ctx, uid, token, data, {
    event: 'COMPLETED',
    prepare: async (c) => {
      const done = validateCompletion(data.completion);
      if (done.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(done.errors) };
      let next = null;
      if (data.next) {
        const n = validateSchedule(data.next, { today: c.today });
        if (n.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(Object.fromEntries(Object.entries(n.errors).map(([k, v]) => [`next.${k}`, v]))) };
        next = n.value;
      }
      return {
        apply: ({ tx, act, cur, nextRev }) => {
          if (next && a.TERMINAL.includes(cur.data.status)) return { error: 'FAILED_PRECONDITION', reason: 'a closed enquiry has no follow-ups' };
          const out = {
            update: { status: COMPLETED, ...done.value, completedAt: ctx.now, completedBy: uid },
            history: { reason: null, to: { outcome: done.value.outcome } },
            stillOpen: false,
          };
          if (next) {
            const nid = col(c.db, c.schoolId, c.branchId).doc().id;
            out.extraCreated = true;
            out.result = { nextId: nid };
            out.after = (txx, others) => {
              const assigned = act.data.assignedTo || null;
              const doc = newActivityDoc(ctx, { schoolId: c.schoolId, branchId: c.branchId, enquiryId: c.enquiryId, enquiry: cur.data, value: next, assignedTo: assigned, uid });
              txx.set(col(c.db, c.schoolId, c.branchId).doc(nid), doc);
              writeHistory(txx, ctx, { id: nid, schoolId: c.schoolId, branchId: c.branchId, enquiryId: c.enquiryId, type: doc.type, purpose: doc.purpose }, 1, 'CREATED', { to: { scheduledDate: doc.scheduledDate, scheduledTime: doc.scheduledTime, assignedTo: assigned }, reason: null }, uid);
            };
            // the new activity is open too
            out.extraOpenDate = next.scheduledDate;
          }
          return out;
        },
      };
    },
  });
}

// ---- reminders -------------------------------------------------------------

const isAlreadyExists = (e) => e && (e.code === 6 || e.code === 'already-exists' || /already exists/i.test(String(e.message)));

async function createOnce(ref, doc) {
  try {
    await ref.create(doc);
    return true;
  } catch (e) {
    if (isAlreadyExists(e)) return false;
    throw e;
  }
}

/** Who is told about [activity]: its assignee, else the branch's administrators. */
async function recipientsOf(db, schoolId, branchId, activity) {
  const active = async (uid) => {
    const u = (await db.collection('users').doc(uid).get()).data();
    return u && u.schoolId === schoolId && u.status === 'ACTIVE' ? [uid] : [];
  };
  if (activity.assignedTo) return active(activity.assignedTo);
  const admins = await db.collection('users').where('schoolId', '==', schoolId).where('role', '==', 'BRANCH_ADMIN').where('status', '==', 'ACTIVE').get();
  const mine = admins.docs.filter((d) => d.data().branchId === branchId).map((d) => d.id);
  if (mine.length) return mine;
  const owners = await db.collection('users').where('schoolId', '==', schoolId).where('role', '==', 'SCHOOL_ADMIN').where('status', '==', 'ACTIVE').get();
  return owners.docs.map((d) => d.id);
}

/** Text names the enquiry NUMBER and the kind of contact, nothing private. */
function reminderMessage(kind, activity) {
  const what = TYPE_LABEL[activity.type] || 'Follow-up';
  return kind === 'OVERDUE'
    ? { title: 'Admission follow-up overdue', body: `${what} for enquiry ${activity.enquiryNumber} is overdue.` }
    : { title: 'Admission follow-up today', body: `${what} for enquiry ${activity.enquiryNumber} is due today.` };
}

/**
 * Hourly job. For every school with admissions and reminders on, once its local
 * time is within the reminder window: a DUE notice for each open activity dated
 * today, and one OVERDUE notice for each open activity dated earlier (up to
 * OVERDUE_LOOKBACK_DAYS back). Ids are derived from the activity, the date it
 * was scheduled for and the recipient and written with create(), so a re-run,
 * the next hour's retry, or a double invocation creates nothing new — and a
 * rescheduled activity (a new date) is allowed one fresh notice.
 */
async function runFollowUpReminders({ db, now, log = () => {} }, { today = new Date() } = {}) {
  let created = 0;
  let scanned = 0;
  let failed = 0;
  const schools = await db.collection('schools').get();
  for (const sd of schools.docs) {
    const schoolId = sd.id;
    try {
      const settings = await a.loadSettings(db, schoolId);
      if (!settings.enabled || settings.remindersEnabled === false) continue;
      const zone = typeof sd.data().timezone === 'string' && feeReminders.validZone(sd.data().timezone) ? sd.data().timezone : 'UTC';
      if (!feeReminders.inDeliveryWindow(today, zone, settings.reminderTime || '09:00')) continue;
      const todayKey = feeReminders.civilToday(today, zone);
      const oldest = feeReminders.addDays(todayKey, -OVERDUE_LOOKBACK_DAYS);
      const branches = await db.collection('schools').doc(schoolId).collection('branches').get();
      for (const bd of branches.docs) {
        const branchId = bd.id;
        const q = await col(db, schoolId, branchId).where('status', '==', SCHEDULED).where('scheduledDate', '<=', todayKey).get();
        for (const d of q.docs) {
          const act = d.data();
          if (act.scheduledDate < oldest) continue;
          scanned++;
          try {
            const kind = act.scheduledDate === todayKey ? 'DUE' : 'OVERDUE';
            const type = kind === 'DUE' ? 'ADMISSION_FOLLOWUP_DUE' : 'ADMISSION_FOLLOWUP_OVERDUE';
            const msg = reminderMessage(kind, act);
            for (const uid of await recipientsOf(db, schoolId, branchId, act)) {
              const id = `${type}__${d.id}__${act.scheduledDate}__${uid}`;
              const ok = await createOnce(a.branchRef(db, schoolId, branchId).collection('notifications').doc(id), {
                schoolId,
                branchId,
                audience: 'USER',
                recipientUserId: uid,
                type,
                title: msg.title,
                body: msg.body,
                refType: 'ENQUIRY',
                refId: act.enquiryId,
                activityId: d.id,
                createdBy: 'system',
                createdAt: now(),
                readAt: null,
              });
              if (ok) created++;
              else log('admission reminders: duplicate prevented', { schoolId, branchId });
            }
          } catch (e) {
            failed++;
            log('admission reminders: activity failed', { schoolId, branchId, category: String((e && e.code) || 'error') });
          }
        }
      }
    } catch (e) {
      failed++;
      log('admission reminders: school failed', { schoolId, category: String((e && e.code) || 'error') });
    }
  }
  const out = { created, scanned };
  if (failed) out.failed = failed;
  return out;
}

// ---- closing an enquiry ----------------------------------------------------

/**
 * Called by changeEnquiryStatus (inside its transaction) when the enquiry is
 * closing: reads the open activities now, returns `apply()` to cancel them
 * after the status write. Cancelling keeps each activity and its history.
 */
async function cancelOpenForClosed(tx, ctx, cur, uid) {
  const d = cur.data;
  const open = await openOf(tx, ctx, d.schoolId, d.branchId, cur.ref.id);
  return {
    apply() {
      for (const o of open) {
        const rev = (o.data.revision || 1) + 1;
        tx.update(col(ctx.db, d.schoolId, d.branchId).doc(o.id), {
          status: CANCELLED,
          cancelReason: 'Enquiry closed',
          revision: rev,
          updatedAt: ctx.now,
          updatedBy: uid,
        });
        writeHistory(tx, ctx, { id: o.id, schoolId: d.schoolId, branchId: d.branchId, enquiryId: cur.ref.id, type: o.data.type, purpose: o.data.purpose }, rev, 'CANCELLED', { reason: 'Enquiry closed' }, uid);
      }
      tx.update(cur.ref, { nextFollowUpDate: null, openActivityCount: 0 });
    },
  };
}

// short, non-reversible id for logs
const shortId = (s) => crypto.createHash('sha1').update(String(s)).digest('hex').slice(0, 10);

module.exports = {
  VISIT,
  PURPOSES,
  VISIT_START_STATUSES,
  visitStatusAfter,
  scheduleVisit,
  TYPES,
  TYPE_LABEL,
  SCHEDULED,
  COMPLETED,
  CANCELLED,
  OVERDUE_LOOKBACK_DAYS,
  validateSchedule,
  validateCompletion,
  earliest,
  bucketOf,
  reminderMessage,
  scheduleActivity,
  rescheduleActivity,
  reassignActivity,
  cancelActivity,
  completeActivity,
  runFollowUpReminders,
  cancelOpenForClosed,
  shortId,
};

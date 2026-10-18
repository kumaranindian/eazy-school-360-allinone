'use strict';

// Business events that notify people, resolved on the trusted side.
//
// Each handler turns one thing that happened (a payment recorded, a register
// finalised, a holiday changed, an invoice coming due) into notification
// documents in the SAME collections the app already reads
// (`notifications` for one person, `broadcastNotices` for an audience). The
// existing triggers (pushNotification / pushBroadcastNotice) then push them, so
// there is exactly one delivery path.
//
// Rules every handler follows:
//  * IDEMPOTENT. Document ids are derived from the event (never random) and
//    written with create(), so a retried or repeated trigger finds the
//    document and creates nothing. One business event, one notification.
//  * EVENT BOUNDARIES. Only the meaningful transition notifies: a register
//    becoming FINALIZED, not every edit of a draft; a holiday whose dates,
//    name, type or status actually changed, not any write.
//  * NARROW RECIPIENTS. A student's event goes to that student's linked
//    parents, who must be ACTIVE users of the same school — nobody else.
//  * MINIMAL CONTENT. Text names no amounts, no marks and no private details:
//    it says what happened and where to look. It is what appears on a lock
//    screen.

const crypto = require('node:crypto');

const SYSTEM = 'system';
const OPEN_INVOICE = new Set(['ISSUED', 'PARTIALLY_PAID']);
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);
const isAlreadyExists = (e) => e && (e.code === 6 || e.code === 'already-exists' || /already exists/i.test(String(e.message)));
const short = (s) => crypto.createHash('sha1').update(String(s)).digest('hex').slice(0, 16);

/** Creates [ref] unless it exists. True when this call created it. */
async function createOnce(ref, data) {
  try {
    await ref.create(data);
    return true;
  } catch (e) {
    if (isAlreadyExists(e)) return false;
    throw e;
  }
}

/** "3 Aug 2026" from a yyyy-MM-dd key. */
function dateText(key) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(key || ''));
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : String(key || '');
}

/** yyyy-MM-dd of a Firestore Timestamp / Date holding a UTC-midnight civil date. */
function civilKey(ts) {
  const d = ts && ts.toDate ? ts.toDate() : ts instanceof Date ? ts : null;
  return d ? d.toISOString().slice(0, 10) : null;
}

/** The ACTIVE users of this school who are linked parents of [studentId] with portal access. */
async function parentUserIdsOfStudent(db, schoolId, branchId, studentId) {
  if (!studentId) return [];
  const links = await branchRef(db, schoolId, branchId)
    .collection('students')
    .doc(studentId)
    .collection('parentLinks')
    .where('status', '==', 'ACTIVE')
    .get();
  const parentIds = [
    ...new Set(links.docs.map((l) => l.data()).filter((l) => l.canAccessPortal === true).map((l) => l.parentId)),
  ].filter(Boolean);
  if (parentIds.length === 0) return [];
  // A parent record is tied to a login by users.linkedParentId (the same link
  // the push recipients and security rules use). Only ACTIVE parent logins of
  // this school qualify.
  const userIds = new Set();
  for (const parentId of parentIds) {
    const users = await db
      .collection('users')
      .where('schoolId', '==', schoolId)
      .where('role', '==', 'PARENT')
      .where('status', '==', 'ACTIVE')
      .where('linkedParentId', '==', parentId)
      .get();
    users.docs.forEach((u) => userIds.add(u.id));
  }
  return [...userIds];
}

const targeted = ({ now, schoolId, branchId, uid, type, title, body, refType, refId }) => ({
  schoolId,
  branchId,
  audience: 'USER',
  recipientUserId: uid,
  type,
  title,
  body,
  refType,
  refId,
  createdBy: SYSTEM,
  createdAt: now(),
  readAt: null,
});

const notificationsOf = (db, s, b) => branchRef(db, s, b).collection('notifications');

// ---- a fee payment was recorded -------------------------------------------

/** A recorded (ACTIVE) payment notifies the student's linked parents, once each. */
async function onPaymentRecorded({ db, now }, { schoolId, branchId, paymentId }, payment) {
  if (!payment || payment.status !== 'ACTIVE') return { created: 0 };
  const uids = await parentUserIdsOfStudent(db, schoolId, branchId, payment.studentId);
  let created = 0;
  for (const uid of uids) {
    const ok = await createOnce(
      notificationsOf(db, schoolId, branchId).doc(`PAYMENT_RECORDED__${paymentId}__${uid}`),
      targeted({
        now,
        schoolId,
        branchId,
        uid,
        type: 'PAYMENT_RECORDED',
        title: 'Payment received',
        body: 'A fee payment was recorded. Open the receipt for details.',
        refType: 'RECEIPT',
        refId: paymentId,
      }),
    );
    if (ok) created++;
  }
  return { created };
}

// ---- a register was finalised: parents of absent students -------------------

/**
 * When a student register becomes FINALIZED (and only then), the linked parents
 * of every student marked ABSENT are told, once per student and day. A draft
 * being edited, or a finalised register being re-saved, does not notify.
 */
async function onRegisterFinalized({ db, now }, { schoolId, branchId }, before, after) {
  const becameFinal = after && after.status === 'FINALIZED' && !(before && before.status === 'FINALIZED');
  if (!becameFinal || !after.classId || !after.sectionId || !after.academicYearId || !after.dateKey) {
    return { created: 0 };
  }
  const marks = await branchRef(db, schoolId, branchId)
    .collection('studentAttendance')
    .where('academicYearId', '==', after.academicYearId)
    .where('classId', '==', after.classId)
    .where('sectionId', '==', after.sectionId)
    .where('dateKey', '==', after.dateKey)
    .get();
  const absent = marks.docs.map((d) => d.data()).filter((m) => m.status === 'ABSENT' && m.studentId);
  let created = 0;
  for (const m of absent) {
    const uids = await parentUserIdsOfStudent(db, schoolId, branchId, m.studentId);
    for (const uid of uids) {
      const ok = await createOnce(
        notificationsOf(db, schoolId, branchId).doc(`ATTENDANCE_ABSENT__${m.studentId}__${after.dateKey}__${uid}`),
        targeted({
          now,
          schoolId,
          branchId,
          uid,
          type: 'ATTENDANCE_ABSENT',
          title: 'Attendance update',
          body: `Your child was marked absent on ${dateText(after.dateKey)}.`,
          refType: 'ATTENDANCE',
          refId: m.studentId,
        }),
      );
      if (ok) created++;
    }
  }
  return { created, absent: absent.length };
}

// ---- a holiday was added, changed or cancelled ----------------------------

const holidaySignature = (h) =>
  [civilKey(h.date), civilKey(h.endDate) || '', String(h.name || ''), h.type || '', h.status || ''].join('|');

/** What kind of notice a holiday write deserves, or null when it deserves none. */
function holidayChange(before, after) {
  if (!after) return null;
  const was = before && before.status === 'ACTIVE';
  const is = after.status === 'ACTIVE';
  if (!before) return is ? 'HOLIDAY_ADDED' : null;
  if (holidaySignature(before) === holidaySignature(after)) return null; // nothing that matters changed
  if (!was && is) return 'HOLIDAY_ADDED';
  if (was && !is) return 'HOLIDAY_REMOVED';
  return is ? 'HOLIDAY_UPDATED' : null;
}

/** A holiday that is added, changes, or is cancelled is announced to the branch once. */
async function onHolidayWritten({ db, now }, { schoolId, branchId, holidayId }, before, after) {
  const type = holidayChange(before, after);
  if (!type) return { created: 0 };
  const first = civilKey(after.date);
  const last = civilKey(after.endDate);
  const when =
    last && last !== first ? `${dateText(first)} – ${dateText(last)}` : dateText(first);
  const title = { HOLIDAY_ADDED: 'Holiday added', HOLIDAY_UPDATED: 'Holiday updated', HOLIDAY_REMOVED: 'Holiday cancelled' }[type];
  const ok = await createOnce(
    branchRef(db, schoolId, branchId)
      .collection('broadcastNotices')
      .doc(`HOLIDAY__${holidayId}__${short(`${type}|${holidaySignature(after)}`)}`),
    {
      schoolId,
      branchId,
      type,
      audienceKind: 'BRANCH',
      classId: null,
      sectionId: null,
      title,
      body: `${after.name || 'Holiday'} · ${when}`,
      refType: 'HOLIDAY',
      refId: holidayId,
      revision: 1,
      createdBy: SYSTEM,
      createdAt: now(),
    },
  );
  return { created: ok ? 1 : 0, type };
}

// ---- an invoice is coming due ---------------------------------------------

/** yyyy-MM-dd in [timeZone] on the day [offsetDays] from [now]. */
function dueKeyFor(now, offsetDays, timeZone) {
  const t = new Date(now.getTime() + offsetDays * 24 * 3600 * 1000);
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(t);
}

// Paged, never cut off silently (SEC-4): a run reads at most this many pages
// per reminder day and reports `truncated` if there was more.
const INVOICE_PAGE = 500;
const MAX_INVOICE_PAGES = 200;

/**
 * Reminds the parents of open invoices that fall due [offset] days from now
 * (the default policy is 3 days before and on the day; set FEE_REMINDER_DAYS).
 * Once per invoice, offset and parent — running it twice, or twice a day,
 * sends nothing new. The text states no amount.
 */
async function runFeeDueReminders({ db, now }, { today = new Date(), offsets = [3, 0], timeZone = 'Asia/Kolkata' } = {}) {
  let created = 0;
  let scanned = 0;
  let truncated = false;
  for (const offset of offsets) {
    const dueKey = dueKeyFor(today, offset, timeZone);
    let after = null;
    for (let page = 0; ; page++) {
      if (page >= MAX_INVOICE_PAGES) {
        truncated = true;
        break;
      }
      let q = db.collectionGroup('invoices').where('dueDateKey', '==', dueKey).orderBy('__name__').limit(INVOICE_PAGE);
      if (after) q = q.startAfter(after);
      const snap = await q.get();
      for (const d of snap.docs) {
        const inv = d.data();
        if (!OPEN_INVOICE.has(inv.status) || !(inv.balanceMinor > 0)) continue;
        const m = /^schools\/([^/]+)\/branches\/([^/]+)\/invoices\/([^/]+)$/.exec(d.ref.path);
        if (!m || !inv.studentId) continue;
        scanned++;
        const [, schoolId, branchId, invoiceId] = m;
        const uids = await parentUserIdsOfStudent(db, schoolId, branchId, inv.studentId);
        for (const uid of uids) {
          const ok = await createOnce(
            notificationsOf(db, schoolId, branchId).doc(`FEE_DUE__${invoiceId}__${offset}__${uid}`),
            targeted({
              now,
              schoolId,
              branchId,
              uid,
              type: 'FEE_DUE_REMINDER',
              title: offset === 0 ? 'Fee due today' : 'Fee due soon',
              body: `A fee invoice is due on ${dateText(dueKey)}.`,
              refType: 'INVOICE',
              refId: invoiceId,
            }),
          );
          if (ok) created++;
        }
      }
      if (snap.docs.length < INVOICE_PAGE) break;
      after = snap.docs[snap.docs.length - 1];
    }
  }
  return truncated ? { created, scanned, truncated } : { created, scanned };
}

module.exports = {
  onPaymentRecorded,
  onRegisterFinalized,
  onHolidayWritten,
  runFeeDueReminders,
  holidayChange,
  parentUserIdsOfStudent,
  createOnce,
  dateText,
  dueKeyFor,
};

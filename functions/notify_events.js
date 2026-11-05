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
const feeReminders = require('./fee_reminders');

const SYSTEM = 'system';
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

// ---- an invoice is coming due, or is overdue ------------------------------

/**
 * yyyy-MM-dd of the calendar day [offsetDays] from [now], on [timeZone]'s
 * calendar. Calendar arithmetic, not 24-hour spans, so a DST change cannot move it.
 */
function dueKeyFor(now, offsetDays, timeZone) {
  return feeReminders.addDays(feeReminders.civilToday(now, timeZone), offsetDays);
}

// Paged, never cut off silently (SEC-4): a run reads at most this many pages
// per due date and reports `truncated` if there was more.
const INVOICE_PAGE = 500;
const MAX_INVOICE_PAGES = 200;

const DEFAULT_ZONE = 'Asia/Kolkata'; // schools that predate Regional settings

/** The hour (0-23) in [timeZone] at [now]. */
function localHour(now, timeZone) {
  const h = new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', hourCycle: 'h23' }).format(now);
  return Number(h);
}

const validZone = feeReminders.validZone;

/** One school's zone from its document (default for an unknown or invalid one). */
const zoneOfSchool = (data) => (data && typeof data.timezone === 'string' && validZone(data.timezone) ? data.timezone : DEFAULT_ZONE);

/**
 * Reminds the parents of open invoices, per each school's own policy
 * (`schools/{s}/feeReminderSettings/config`, defaults when absent): N days
 * before the due date, on it, and N days after it, **at the school's delivery
 * time in its own time zone**. Meant to run hourly: a school is handled while
 * its local time is within the 3 hours from its delivery time, so a missed run
 * is retried the next hour. Once per invoice, step and parent — running it
 * again sends nothing new.
 *
 * Isolation: one school or invoice failing is logged and skipped, never allowed
 * to stop the rest (the next hourly run retries it, and sent ones are not repeated).
 * [log] is an optional (event, fields) callback for structured logs; it is
 * given counts and ids only, never names, phone numbers or amounts.
 */
async function runFeeDueReminders({ db, now, log = () => {} }, { today = new Date() } = {}) {
  const schools = await db.collection('schools').get();
  // due key -> the reminder steps (per school) that look for it
  const wanted = new Map();
  const policy = new Map(); // schoolId -> effective settings of the schools being served now
  for (const sd of schools.docs) {
    const schoolId = sd.id;
    try {
      const zone = zoneOfSchool(sd.data());
      const stored = await feeReminders.settingsDoc(db, schoolId).get();
      const settings = feeReminders.effectiveSettings(stored.exists ? stored.data() : null);
      if (!settings.enabled) {
        log('fee reminders: school skipped', { schoolId, reason: 'disabled' });
        continue;
      }
      if (!feeReminders.inDeliveryWindow(today, zone, settings.deliveryTime)) continue;
      const steps = feeReminders.activeReminders(settings, feeReminders.civilToday(today, zone));
      if (steps.length === 0) {
        log('fee reminders: school skipped', { schoolId, reason: 'no active steps' });
        continue;
      }
      policy.set(schoolId, settings);
      log('fee reminders: school processing', { schoolId, steps: steps.length });
      for (const st of steps) {
        if (!wanted.has(st.dueKey)) wanted.set(st.dueKey, []);
        wanted.get(st.dueKey).push({ schoolId, kind: st.kind, days: st.days });
      }
    } catch (e) {
      log('fee reminders: school failed', { schoolId, category: String((e && e.code) || 'error') });
    }
  }

  let created = 0;
  let scanned = 0;
  let failed = 0;
  let truncated = false;
  for (const [dueKey, targets] of wanted) {
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
        const m = /^schools\/([^/]+)\/branches\/([^/]+)\/invoices\/([^/]+)$/.exec(d.ref.path);
        if (!m) continue;
        const [, schoolId, branchId, invoiceId] = m;
        // Only the steps THIS school's own policy is due for right now.
        const mine = targets.filter((t) => t.schoolId === schoolId);
        if (mine.length === 0 || !feeReminders.isRemindable(d.data()) || !d.data().studentId) continue;
        scanned++;
        try {
          // Payment sync: judge the invoice as it is NOW, not as the query saw it.
          const fresh = await d.ref.get();
          const inv = fresh.exists ? fresh.data() : null;
          if (!feeReminders.isRemindable(inv) || inv.dueDateKey !== dueKey || !inv.studentId) {
            log('fee reminders: invoice skipped', { schoolId, invoiceId, reason: 'no longer open' });
            continue;
          }
          const uids = await parentUserIdsOfStudent(db, schoolId, branchId, inv.studentId);
          for (const step of mine) {
            const overdue = step.kind === 'AFTER';
            const type = overdue ? 'FEE_OVERDUE_REMINDER' : 'FEE_DUE_REMINDER';
            const msg = feeReminders.buildMessage(step, inv, policy.get(schoolId));
            for (const uid of uids) {
              // Ids of the before-due steps are unchanged from the fixed-policy
              // version, so a rollout never repeats a reminder already sent.
              const id = `${overdue ? 'FEE_OVERDUE' : 'FEE_DUE'}__${invoiceId}__${step.days}__${uid}`;
              const ok = await createOnce(
                notificationsOf(db, schoolId, branchId).doc(id),
                {
                  ...targeted({
                    now,
                    schoolId,
                    branchId,
                    uid,
                    type,
                    title: msg.title,
                    body: msg.body,
                    refType: 'INVOICE',
                    refId: invoiceId,
                  }),
                  studentId: inv.studentId,
                  dueDateKey: dueKey,
                  reminderOffset: overdue ? -step.days : step.days,
                },
              );
              if (ok) created++;
              else log('fee reminders: duplicate prevented', { schoolId, invoiceId, step: id.split('__')[0] + step.days });
            }
          }
        } catch (e) {
          failed++;
          log('fee reminders: invoice failed', { schoolId, invoiceId, category: String((e && e.code) || 'error') });
        }
      }
      if (snap.docs.length < INVOICE_PAGE) break;
      after = snap.docs[snap.docs.length - 1];
    }
  }
  const out = { created, scanned };
  if (failed) out.failed = failed;
  if (truncated) out.truncated = true;
  return out;
}

module.exports = {
  onPaymentRecorded,
  onRegisterFinalized,
  onHolidayWritten,
  runFeeDueReminders,
  localHour,
  holidayChange,
  parentUserIdsOfStudent,
  createOnce,
  dateText,
  dueKeyFor,
};

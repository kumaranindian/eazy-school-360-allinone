'use strict';

// Admission enquiry management (docs/admission-management/).
//
//   schools/{s}/admissionSettings/config            school-wide settings
//   schools/{s}/branches/{b}/admissionEnquiries/{id}
//   schools/{s}/branches/{b}/admissionStatusHistory/{enquiryId}__{revision}   immutable
//   schools/{s}/branches/{b}/admissionSequences/{PREFIX-YEAR}                 { next }
//
// Every write goes through the callables below (Admin SDK); firestore.rules
// give clients read access only. That keeps validation, numbering, duplicate
// flagging and the status state machine in one testable place and means the
// UI hiding a button is never the only guard.

const { assertAdmin } = require('./access');
const feeReminders = require('./fee_reminders');

// ---- constants -------------------------------------------------------------

const STATUSES = [
  'NEW', 'CONTACTED', 'INTERESTED', 'VISIT_SCHEDULED', 'VISIT_COMPLETED',
  'APPLICATION_SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'ADMISSION_CONFIRMED',
  'ON_HOLD', 'REJECTED', 'WITHDRAWN', 'NOT_INTERESTED',
];

const DEFAULT_SOURCES = ['Walk-in', 'Phone call', 'Website', 'WhatsApp', 'Social media', 'Referral', 'Existing parent', 'Advertisement', 'Other'];
const GENDERS = ['MALE', 'FEMALE', 'OTHER'];
const REASON_REQUIRED = ['REJECTED', 'WITHDRAWN'];

// The lead-stage statuses a user may set directly. The rest (visit, application,
// review, approval, confirmation) are driven by their own workflows so a status
// can never be set without the work that justifies it.
const MANUAL_TARGETS = ['CONTACTED', 'INTERESTED', 'NOT_INTERESTED', 'ON_HOLD', 'REJECTED', 'WITHDRAWN'];

const OPEN_ALTERNATES = ['ON_HOLD', 'REJECTED', 'WITHDRAWN', 'NOT_INTERESTED'];
const TRANSITIONS = Object.freeze({
  NEW: ['CONTACTED', 'INTERESTED', 'VISIT_SCHEDULED', ...OPEN_ALTERNATES],
  CONTACTED: ['INTERESTED', 'VISIT_SCHEDULED', ...OPEN_ALTERNATES],
  INTERESTED: ['VISIT_SCHEDULED', 'APPLICATION_SUBMITTED', ...OPEN_ALTERNATES],
  VISIT_SCHEDULED: ['VISIT_COMPLETED', 'INTERESTED', ...OPEN_ALTERNATES],
  // A second (or later) visit is allowed after one was completed.
  VISIT_COMPLETED: ['APPLICATION_SUBMITTED', 'VISIT_SCHEDULED', 'INTERESTED', ...OPEN_ALTERNATES],
  APPLICATION_SUBMITTED: ['UNDER_REVIEW', 'ON_HOLD', 'REJECTED', 'WITHDRAWN'],
  UNDER_REVIEW: ['APPROVED', 'ON_HOLD', 'REJECTED', 'WITHDRAWN'],
  APPROVED: ['ADMISSION_CONFIRMED', 'ON_HOLD', 'REJECTED', 'WITHDRAWN'],
  // Resume goes back to the status the enquiry was on (heldFrom).
  ON_HOLD: ['__RESUME__', 'REJECTED', 'WITHDRAWN', 'NOT_INTERESTED'],
  NOT_INTERESTED: ['CONTACTED', 'INTERESTED'],
  REJECTED: [],
  WITHDRAWN: [],
  ADMISSION_CONFIRMED: [],
});

const TERMINAL = ['REJECTED', 'WITHDRAWN', 'ADMISSION_CONFIRMED'];

const ROLE_ASSIGNABLE = ['SCHOOL_ADMIN', 'BRANCH_ADMIN', 'TEACHER', 'FINANCE'];

// ---- small helpers ---------------------------------------------------------

const isStr = (v) => typeof v === 'string';
const trim = (v) => (isStr(v) ? v.trim() : '');
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const ID = /^[A-Za-z0-9_-]{1,128}$/;

function validDate(s) {
  if (!isStr(s) || !DATE.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

/** Digits only, without leading zeros / country prefix noise: the comparison key. */
function normalizeMobile(raw) {
  const digits = trim(raw).replace(/\D/g, '');
  return digits.length > 10 ? digits.slice(-10) : digits;
}

const normalizeName = (s) => trim(s).toLowerCase().replace(/\s+/g, ' ');

function civilToday(now, timeZone) {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  } catch (_) {
    return now.toISOString().slice(0, 10);
  }
}

const wall = (ctx) => (ctx.wall ? ctx.wall() : new Date());

async function schoolZone(db, schoolId) {
  const s = (await db.collection('schools').doc(schoolId).get()).data();
  return (s && s.timezone) || 'UTC';
}

const settingsRef = (db, schoolId) => db.collection('schools').doc(schoolId).collection('admissionSettings').doc('config');
const branchRef = (db, schoolId, branchId) => db.collection('schools').doc(schoolId).collection('branches').doc(branchId);
const enquiryCol = (db, schoolId, branchId) => branchRef(db, schoolId, branchId).collection('admissionEnquiries');
const historyCol = (db, schoolId, branchId) => branchRef(db, schoolId, branchId).collection('admissionStatusHistory');
const sequenceDoc = (db, schoolId, branchId, key) => branchRef(db, schoolId, branchId).collection('admissionSequences').doc(key);
const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');

// ---- state machine (pure) --------------------------------------------------

/** Whether [from] -> [to] is an allowed lifecycle step (ignoring who asks). */
function canTransition(from, to) {
  return Array.isArray(TRANSITIONS[from]) && TRANSITIONS[from].includes(to);
}

/**
 * The status a MANUAL change request ends on, or an error. `heldFrom` is the
 * status an ON_HOLD enquiry was on, used by `RESUME`.
 */
function resolveManualChange(from, to, { heldFrom, reason } = {}) {
  if (!STATUSES.includes(from)) return { error: 'INVALID_ARGUMENT', reason: 'unknown current status' };
  if (to === 'RESUME') {
    if (from !== 'ON_HOLD' || !STATUSES.includes(heldFrom)) return { error: 'FAILED_PRECONDITION', reason: 'only an enquiry on hold can be resumed' };
    return { to: heldFrom, resume: true };
  }
  if (!MANUAL_TARGETS.includes(to)) {
    return { error: 'FAILED_PRECONDITION', reason: `${to} is set by its own workflow, not directly` };
  }
  if (!canTransition(from, to)) return { error: 'FAILED_PRECONDITION', reason: `cannot move from ${from} to ${to}` };
  if (REASON_REQUIRED.includes(to) && trim(reason).length < 3) return { error: 'INVALID_ARGUMENT', reason: 'a reason is required' };
  return { to };
}

// ---- settings --------------------------------------------------------------

const DEFAULT_SETTINGS = Object.freeze({
  enabled: false,
  enquiryPrefix: 'ENQ',
  applicationPrefix: 'APP',
  sources: DEFAULT_SOURCES,
  followUpDays: 3,
  remindersEnabled: true,
  reminderTime: '09:00',
  academicYearIds: [],
  classIds: [],
});

const PREFIX = /^[A-Z]{2,6}$/;

/** Validates a settings payload; returns { errors } or { value }. */
function validateSettings(input) {
  const errors = {};
  const i = input || {};
  const enabled = i.enabled === true;
  if (i.enabled !== undefined && typeof i.enabled !== 'boolean') errors.enabled = 'must be true or false';
  const enquiryPrefix = i.enquiryPrefix === undefined ? DEFAULT_SETTINGS.enquiryPrefix : trim(i.enquiryPrefix).toUpperCase();
  const applicationPrefix = i.applicationPrefix === undefined ? DEFAULT_SETTINGS.applicationPrefix : trim(i.applicationPrefix).toUpperCase();
  if (!PREFIX.test(enquiryPrefix)) errors.enquiryPrefix = '2-6 capital letters';
  if (!PREFIX.test(applicationPrefix)) errors.applicationPrefix = '2-6 capital letters';
  if (!errors.enquiryPrefix && enquiryPrefix === applicationPrefix) errors.applicationPrefix = 'must differ from the enquiry prefix';

  let sources = DEFAULT_SOURCES;
  if (i.sources !== undefined) {
    if (!Array.isArray(i.sources) || i.sources.length < 1 || i.sources.length > 20) errors.sources = '1-20 sources';
    else {
      const cleaned = [...new Set(i.sources.map(trim))];
      if (cleaned.some((s) => s.length < 2 || s.length > 40)) errors.sources = 'each source is 2-40 characters';
      else sources = cleaned;
    }
  }
  const followUpDays = i.followUpDays === undefined ? DEFAULT_SETTINGS.followUpDays : i.followUpDays;
  if (!Number.isInteger(followUpDays) || followUpDays < 1 || followUpDays > 60) errors.followUpDays = 'a whole number of days, 1-60';
  const remindersEnabled = i.remindersEnabled === undefined ? DEFAULT_SETTINGS.remindersEnabled : i.remindersEnabled;
  if (typeof remindersEnabled !== 'boolean') errors.remindersEnabled = 'must be true or false';
  const reminderTime = i.reminderTime === undefined ? DEFAULT_SETTINGS.reminderTime : i.reminderTime;
  const reminderMinute = isStr(reminderTime) ? feeReminders.minutesOf(reminderTime) : null;
  if (reminderMinute === null || reminderMinute < 360 || reminderMinute > 1260) errors.reminderTime = 'a time between 06:00 and 21:00';
  const idList = (key) => {
    const v = i[key] === undefined ? [] : i[key];
    if (!Array.isArray(v) || v.length > 100 || v.some((x) => !isStr(x) || !ID.test(x))) {
      errors[key] = 'a list of up to 100 ids';
      return [];
    }
    return [...new Set(v)];
  };
  const academicYearIds = idList('academicYearIds');
  const classIds = idList('classIds');
  if (Object.keys(errors).length) return { errors };
  return { value: { enabled, enquiryPrefix, applicationPrefix, sources, followUpDays, remindersEnabled, reminderTime, academicYearIds, classIds } };
}

async function loadSettings(db, schoolId) {
  const d = (await settingsRef(db, schoolId).get()).data();
  return d ? { ...DEFAULT_SETTINGS, ...d } : { ...DEFAULT_SETTINGS };
}

/** The caller as a school admin (any branch), or branch admin of [branchId]. */
async function authorize(db, uid, token, schoolId, branchId) {
  if (!isStr(schoolId) || !ID.test(schoolId)) return null;
  if (branchId !== null && (!isStr(branchId) || !ID.test(branchId))) return null;
  return assertAdmin(db, uid, schoolId, branchId, token);
}

/** School-wide settings: school admins only. */
async function saveAdmissionSettings(ctx, uid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const caller = await authorize(db, uid, token, schoolId, null);
  if (!caller || caller.role !== 'SCHOOL_ADMIN') return { error: 'PERMISSION_DENIED' };
  const parsed = validateSettings(data.settings);
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
  const ref = settingsRef(db, schoolId);
  return db.runTransaction(async (tx) => {
    const prev = (await tx.get(ref)).data();
    const current = prev && Number.isInteger(prev.version) ? prev.version : 0;
    if (data.baseVersion !== undefined && data.baseVersion !== current) return { error: 'ABORTED', reason: 'settings changed by someone else; reload' };
    tx.set(ref, { schoolId, version: current + 1, ...parsed.value, updatedAt: now, updatedBy: uid });
    return { result: { version: current + 1 } };
  });
}

// ---- numbering -------------------------------------------------------------

/** `ENQ-2026-00001`. */
function formatNumber(prefix, year, n) {
  return `${prefix}-${year}-${String(n).padStart(5, '0')}`;
}

/**
 * The next number of one series, read and bumped inside [tx] so two concurrent
 * callers can never receive the same value (Firestore retries the loser).
 */
async function nextNumber(tx, ctx, schoolId, branchId, prefix, year) {
  const ref = sequenceDoc(ctx.db, schoolId, branchId, `${prefix}-${year}`);
  const cur = (await tx.get(ref)).data();
  const n = (cur && Number.isInteger(cur.next) ? cur.next : 0) + 1;
  tx.set(ref, { schoolId, branchId, prefix, year, next: n, updatedAt: ctx.now });
  return formatNumber(prefix, year, n);
}

// ---- enquiry input ---------------------------------------------------------

const lenOk = (s, max) => s.length <= max;

/** Validates the editable part of an enquiry. Returns { errors } or { value }. */
function validateEnquiry(input, settings, { today } = {}) {
  const errors = {};
  const i = input || {};
  const student = i.student || {};
  const firstName = trim(student.firstName);
  const lastName = trim(student.lastName);
  if (firstName.length < 1 || !lenOk(firstName, 60)) errors['student.firstName'] = 'is required (up to 60 characters)';
  if (!lenOk(lastName, 60)) errors['student.lastName'] = 'up to 60 characters';
  let dateOfBirth = null;
  if (student.dateOfBirth !== undefined && student.dateOfBirth !== null && student.dateOfBirth !== '') {
    if (!validDate(student.dateOfBirth)) errors['student.dateOfBirth'] = 'must be a date (yyyy-mm-dd)';
    else if (today && student.dateOfBirth > today) errors['student.dateOfBirth'] = 'cannot be in the future';
    else dateOfBirth = student.dateOfBirth;
  }
  const gender = student.gender === undefined || student.gender === null || student.gender === '' ? null : student.gender;
  if (gender !== null && !GENDERS.includes(gender)) errors['student.gender'] = 'is not a valid gender';

  const academicYearId = trim(i.academicYearId);
  if (!ID.test(academicYearId)) errors.academicYearId = 'is required';
  else if (settings.academicYearIds.length && !settings.academicYearIds.includes(academicYearId)) errors.academicYearId = 'is not open for admissions';
  const classId = trim(i.interestedClassId);
  if (!ID.test(classId)) errors.interestedClassId = 'is required';
  else if (settings.classIds.length && !settings.classIds.includes(classId)) errors.interestedClassId = 'is not open for admissions';

  const source = trim(i.source);
  if (!settings.sources.includes(source)) errors.source = 'is not an available source';

  const guardians = Array.isArray(i.guardians) ? i.guardians : [];
  if (guardians.length < 1 || guardians.length > 4) errors.guardians = '1-4 guardians';
  const cleanGuardians = [];
  guardians.slice(0, 4).forEach((g, idx) => {
    const name = trim(g && g.name);
    const phone = normalizeMobile(g && g.phone);
    const email = trim(g && g.email);
    if (name.length < 2 || !lenOk(name, 80)) errors[`guardians.${idx}.name`] = 'is required (2-80 characters)';
    if (phone.length < 7 || phone.length > 15) errors[`guardians.${idx}.phone`] = 'must be a valid mobile number';
    if (email && (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 120)) errors[`guardians.${idx}.email`] = 'is not a valid email';
    const alt = trim(g && g.alternatePhone) ? normalizeMobile(g.alternatePhone) : '';
    if (alt && (alt.length < 7 || alt.length > 15)) errors[`guardians.${idx}.alternatePhone`] = 'must be a valid mobile number';
    cleanGuardians.push({
      name,
      relationship: trim(g && g.relationship).slice(0, 30) || null,
      phone,
      alternatePhone: alt || null,
      email: email || null,
      primary: idx === 0,
    });
  });

  const text = (key, max) => {
    const v = trim(i[key]);
    if (!lenOk(v, max)) errors[key] = `up to ${max} characters`;
    return v || null;
  };
  const addr = i.address || {};
  const address = {
    line1: trim(addr.line1).slice(0, 120) || null,
    city: trim(addr.city).slice(0, 60) || null,
    state: trim(addr.state).slice(0, 60) || null,
    country: trim(addr.country).slice(0, 60) || null,
  };
  const previousSchool = text('previousSchool', 120);
  const previousClass = text('previousClass', 60);
  const specialRequirements = text('specialRequirements', 500);
  const remarks = text('remarks', 1000);

  let nextFollowUpDate = null;
  if (i.nextFollowUpDate !== undefined && i.nextFollowUpDate !== null && i.nextFollowUpDate !== '') {
    if (!validDate(i.nextFollowUpDate)) errors.nextFollowUpDate = 'must be a date (yyyy-mm-dd)';
    else nextFollowUpDate = i.nextFollowUpDate;
  }
  let enquiryDate = null;
  if (i.enquiryDate !== undefined && i.enquiryDate !== null && i.enquiryDate !== '') {
    if (!validDate(i.enquiryDate)) errors.enquiryDate = 'must be a date (yyyy-mm-dd)';
    else if (today && i.enquiryDate > today) errors.enquiryDate = 'cannot be in the future';
    else enquiryDate = i.enquiryDate;
  }
  if (nextFollowUpDate && (enquiryDate || today) && nextFollowUpDate < (enquiryDate || today)) errors.nextFollowUpDate = 'cannot be before the enquiry date';

  if (Object.keys(errors).length) return { errors };
  return {
    value: {
      student: { firstName, lastName, dateOfBirth, gender },
      studentName: [firstName, lastName].filter(Boolean).join(' '),
      studentNameLower: normalizeName([firstName, lastName].filter(Boolean).join(' ')),
      academicYearId,
      interestedClassId: classId,
      source,
      guardians: cleanGuardians,
      primaryPhone: cleanGuardians[0].phone,
      primaryGuardianName: cleanGuardians[0].name,
      address,
      previousSchool,
      previousClass,
      specialRequirements,
      remarks,
      nextFollowUpDate,
      enquiryDate,
    },
  };
}

/** Possible duplicates among [candidates] (same mobile + year already matched by the query). */
function duplicateMatches(value, candidates) {
  const out = [];
  for (const c of candidates) {
    const d = c.data;
    if (d.studentNameLower === value.studentNameLower
      && (d.student && d.student.dateOfBirth) === value.student.dateOfBirth) out.push(c.id);
  }
  return out.slice(0, 5);
}

// ---- callables -------------------------------------------------------------

async function assertEnabled(db, schoolId) {
  const settings = await loadSettings(db, schoolId);
  return settings.enabled ? settings : null;
}

/** Creates an enquiry with a server-generated number; flags possible duplicates. */
async function createEnquiry(ctx, uid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  const caller = await authorize(db, uid, token, schoolId, branchId === undefined ? undefined : branchId);
  if (!caller || !branchId) return { error: 'PERMISSION_DENIED' };
  if (!(await branchRef(db, schoolId, branchId).get()).exists) return { error: 'NOT_FOUND' };
  const settings = await assertEnabled(db, schoolId);
  if (!settings) return { error: 'FAILED_PRECONDITION', reason: 'admissions are not enabled for this school' };

  const zone = await schoolZone(db, schoolId);
  const today = civilToday(wall(ctx), zone);
  const parsed = validateEnquiry(data.enquiry, settings, { today });
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
  const value = parsed.value;
  const enquiryDate = value.enquiryDate || today;
  const year = enquiryDate.slice(0, 4);

  let assignedTo = null;
  if (data.assignedTo) {
    assignedTo = await assignableUser(db, schoolId, branchId, data.assignedTo);
    if (!assignedTo) return { error: 'INVALID_ARGUMENT', reason: 'assignedTo: that person cannot be assigned in this branch' };
  }

  // Possible duplicates: same primary mobile and academic year, then the same
  // name and date of birth. Flagged for a person to review; never merged.
  const near = await enquiryCol(db, schoolId, branchId)
    .where('primaryPhone', '==', value.primaryPhone)
    .where('academicYearId', '==', value.academicYearId)
    .limit(25)
    .get();
  const duplicateOf = duplicateMatches(value, near.docs.map((d) => ({ id: d.id, data: d.data() })));

  const ref = enquiryCol(db, schoolId, branchId).doc();
  const histRef = historyCol(db, schoolId, branchId).doc(`${ref.id}__1`);
  const out = await db.runTransaction(async (tx) => {
    const enquiryNumber = await nextNumber(tx, ctx, schoolId, branchId, settings.enquiryPrefix, year);
    tx.set(ref, {
      schoolId,
      branchId,
      enquiryNumber,
      ...value,
      enquiryDate,
      assignedTo,
      status: 'NEW',
      heldFrom: null,
      statusReason: null,
      duplicateOf,
      activityCount: 0,
      openActivityCount: 0,
      revision: 1,
      createdAt: now,
      createdBy: uid,
      updatedAt: now,
      updatedBy: uid,
    });
    tx.set(histRef, { schoolId, branchId, enquiryId: ref.id, revision: 1, from: null, to: 'NEW', reason: null, actorId: uid, at: now });
    return { result: { id: ref.id, enquiryNumber, duplicateOf } };
  }, { maxAttempts: 10 }); // several staff may log walk-ins at once; the series document is the contention point
  return out;
}

async function assignableUser(db, schoolId, branchId, userId) {
  if (!isStr(userId) || !ID.test(userId)) return null;
  const u = (await db.collection('users').doc(userId).get()).data();
  if (!u || u.schoolId !== schoolId || u.status !== 'ACTIVE' || !ROLE_ASSIGNABLE.includes(u.role)) return null;
  const inBranch = u.role === 'SCHOOL_ADMIN' || u.branchId === branchId || Boolean((u.branchRoles || {})[branchId]);
  return inBranch ? userId : null;
}

async function loadEnquiry(tx, ctx, schoolId, branchId, enquiryId) {
  if (!isStr(enquiryId) || !ID.test(enquiryId)) return null;
  const ref = enquiryCol(ctx.db, schoolId, branchId).doc(enquiryId);
  const snap = await tx.get(ref);
  if (!snap.exists) return null;
  return { ref, data: snap.data() };
}

/** Edits the details of an enquiry (not its status). */
async function updateEnquiry(ctx, uid, token, data) {
  const { db, now } = ctx;
  const { schoolId, branchId, enquiryId } = data || {};
  const caller = await authorize(db, uid, token, schoolId, branchId || null);
  if (!caller || !branchId) return { error: 'PERMISSION_DENIED' };
  const settings = await loadSettings(db, schoolId);
  const zone = await schoolZone(db, schoolId);
  const today = civilToday(wall(ctx), zone);
  const parsed = validateEnquiry(data.enquiry, settings, { today });
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
  return db.runTransaction(async (tx) => {
    const cur = await loadEnquiry(tx, ctx, schoolId, branchId, enquiryId);
    if (!cur) return { error: 'NOT_FOUND' };
    if (TERMINAL.includes(cur.data.status)) return { error: 'FAILED_PRECONDITION', reason: 'a closed enquiry cannot be edited' };
    if (data.baseRevision !== undefined && data.baseRevision !== cur.data.revision) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    const { enquiryDate, ...rest } = parsed.value;
    // Once follow-up activities exist the next date is derived from them
    // (admission_activities.js); an edit form never overwrites it.
    if (Number.isInteger(cur.data.activityCount) && cur.data.activityCount > 0) rest.nextFollowUpDate = cur.data.nextFollowUpDate || null;
    tx.update(cur.ref, {
      ...rest,
      // The number and enquiry date are the enquiry's identity; they stay.
      revision: cur.data.revision + 1,
      updatedAt: now,
      updatedBy: uid,
    });
    return { result: { revision: cur.data.revision + 1 } };
  });
}

/** Assigns (or, with null, unassigns) the staff member responsible. */
async function assignEnquiry(ctx, uid, token, data) {
  const { db, now } = ctx;
  const { schoolId, branchId, enquiryId } = data || {};
  const caller = await authorize(db, uid, token, schoolId, branchId || null);
  if (!caller || !branchId) return { error: 'PERMISSION_DENIED' };
  let target = null;
  if (data.assignedTo !== null && data.assignedTo !== undefined) {
    target = await assignableUser(db, schoolId, branchId, data.assignedTo);
    if (!target) return { error: 'INVALID_ARGUMENT', reason: 'that person cannot be assigned in this branch' };
  }
  return db.runTransaction(async (tx) => {
    const cur = await loadEnquiry(tx, ctx, schoolId, branchId, enquiryId);
    if (!cur) return { error: 'NOT_FOUND' };
    if (TERMINAL.includes(cur.data.status)) return { error: 'FAILED_PRECONDITION', reason: 'a closed enquiry cannot be reassigned' };
    tx.update(cur.ref, { assignedTo: target, revision: cur.data.revision + 1, updatedAt: now, updatedBy: uid });
    return { result: { revision: cur.data.revision + 1 } };
  });
}

/**
 * Applies a status change and writes the immutable history entry in the same
 * transaction. Shared by the manual callable and the later workflows.
 */
function applyStatus(tx, ctx, cur, { to, reason, uid, resume }) {
  const { db, now } = ctx;
  const d = cur.data;
  const rev = d.revision + 1;
  tx.update(cur.ref, {
    status: to,
    heldFrom: to === 'ON_HOLD' ? d.status : null,
    statusReason: trim(reason) || null,
    revision: rev,
    updatedAt: now,
    updatedBy: uid,
  });
  tx.set(historyCol(db, d.schoolId, d.branchId).doc(`${cur.ref.id}__${rev}`), {
    schoolId: d.schoolId,
    branchId: d.branchId,
    enquiryId: cur.ref.id,
    revision: rev,
    from: d.status,
    to,
    reason: trim(reason) || null,
    resumed: resume === true,
    actorId: uid,
    at: now,
  });
  return rev;
}

/** The manual lead-stage status change (see MANUAL_TARGETS). */
async function changeEnquiryStatus(ctx, uid, token, data) {
  const { db } = ctx;
  const { schoolId, branchId, enquiryId } = data || {};
  const caller = await authorize(db, uid, token, schoolId, branchId || null);
  if (!caller || !branchId) return { error: 'PERMISSION_DENIED' };
  const target = isStr(data.status) ? data.status : '';
  return db.runTransaction(async (tx) => {
    const cur = await loadEnquiry(tx, ctx, schoolId, branchId, enquiryId);
    if (!cur) return { error: 'NOT_FOUND' };
    if (data.baseRevision !== undefined && data.baseRevision !== cur.data.revision) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    const step = resolveManualChange(cur.data.status, target, { heldFrom: cur.data.heldFrom, reason: data.reason });
    if (step.error) return step;
    // Closing an enquiry also closes its open follow-ups (read before any write).
    const closing = TERMINAL.includes(step.to) ? await require('./admission_activities').cancelOpenForClosed(tx, ctx, cur, uid) : null;
    const rev = applyStatus(tx, ctx, cur, { to: step.to, reason: data.reason, uid, resume: step.resume });
    if (closing) closing.apply();
    return { result: { status: step.to, revision: rev } };
  });
}

module.exports = {
  // helpers shared with admission_activities.js
  ID,
  isStr,
  trim,
  validDate,
  civilToday,
  wall,
  schoolZone,
  reasonOf,
  authorize,
  assignableUser,
  loadEnquiry,
  loadSettings,
  branchRef,
  enquiryCol,
  STATUSES,
  MANUAL_TARGETS,
  TRANSITIONS,
  TERMINAL,
  DEFAULT_SETTINGS,
  DEFAULT_SOURCES,
  normalizeMobile,
  canTransition,
  resolveManualChange,
  validateSettings,
  validateEnquiry,
  duplicateMatches,
  formatNumber,
  nextNumber,
  applyStatus,
  saveAdmissionSettings,
  createEnquiry,
  updateEnquiry,
  assignEnquiry,
  changeEnquiryStatus,
};

'use strict';

// Admission fees (docs/admission-management/, phase 7).
//
// An applicant is not a student yet, so the student-keyed invoices of the Fees
// module cannot hold these amounts. Instead a small applicant-level record is
// kept per enquiry and per fee category, and it uses the SAME money rules and
// the SAME receipt-number series as the Fees module:
//
//   branches/{b}/admissionFees/{enquiryId}__{CATEGORY}   what is asked (amount, optional fee structure)
//   branches/{b}/admissionFeePayments/{enquiryId}__{requestId}   append-only: PAYMENT (with an RCT number) or REFUND
//
// Receipt numbers come from feeCounters/receipt_{academicYearId} and are
// reserved in receiptNumbers/{number}, exactly as the Fees module does, so a
// number is never issued twice across the two. Money is integer minor units;
// the currency is the school's. Nothing is ever "paid" except by a recorded
// payment; there is no gateway. At conversion (phase 8) the net paid amounts are
// carried into the new student's fee records.

const a = require('./admission');
const { loginAllowed } = require('./access');

const CATEGORIES = ['APPLICATION', 'REGISTRATION', 'ADMISSION', 'CONFIRMATION'];
const METHODS = ['CASH', 'CHEQUE', 'BANK_TRANSFER', 'UPI', 'CARD', 'OTHER'];
const MAX_MINOR = 100000000000; // 1e11 minor units, far above any real fee
const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const CLOSED_ENQUIRY = ['REJECTED', 'WITHDRAWN', 'NOT_INTERESTED'];

const feeCol = (db, s, b) => a.branchRef(db, s, b).collection('admissionFees');
const payCol = (db, s, b) => a.branchRef(db, s, b).collection('admissionFeePayments');
const feeId = (enquiryId, category) => `${enquiryId}__${category}`;

// ---- pure helpers ----------------------------------------------------------

const isMinor = (n) => Number.isInteger(n) && n > 0 && n <= MAX_MINOR;

/** DUE / PARTIAL / PAID / WAIVED / CANCELLED from the stored amounts. */
function statusOf({ amountMinor, waivedMinor = 0, paidMinor = 0, refundedMinor = 0, cancelled = false }) {
  if (cancelled) return 'CANCELLED';
  const due = amountMinor - waivedMinor;
  const net = paidMinor - refundedMinor;
  if (due <= 0) return 'WAIVED';
  if (net >= due) return 'PAID';
  return net > 0 ? 'PARTIAL' : 'DUE';
}

const netPaid = (f) => (f.paidMinor || 0) - (f.refundedMinor || 0);
const balanceOf = (f) => (f.status === 'CANCELLED' ? 0 : Math.max(0, f.amountMinor - (f.waivedMinor || 0) - netPaid(f)));

/** Totals over an enquiry's fee records (what the Fees tab and conversion use). */
function summarize(fees) {
  const live = fees.filter((f) => f.status !== 'CANCELLED');
  const sum = (k) => live.reduce((t, f) => t + (f[k] || 0), 0);
  return {
    amountMinor: sum('amountMinor'),
    waivedMinor: sum('waivedMinor'),
    paidMinor: sum('paidMinor'),
    refundedMinor: sum('refundedMinor'),
    netPaidMinor: live.reduce((t, f) => t + netPaid(f), 0),
    balanceMinor: live.reduce((t, f) => t + balanceOf(f), 0),
  };
}

function validatePayment(input, { today, balance }) {
  const errors = {};
  if (!isMinor(input.amountMinor)) errors.amountMinor = 'must be a positive whole number of minor units';
  else if (input.amountMinor > balance) errors.amountMinor = 'is more than the balance due';
  if (!METHODS.includes(input.method)) errors.method = 'is not a valid payment method';
  const ref = a.trim(input.referenceNo);
  if (ref.length > 60) errors.referenceNo = 'up to 60 characters';
  if (['CHEQUE', 'BANK_TRANSFER', 'UPI', 'CARD'].includes(input.method) && !ref) errors.referenceNo = 'is required for this method';
  const date = input.paymentDate === undefined || input.paymentDate === null || input.paymentDate === '' ? today : input.paymentDate;
  if (typeof date !== 'string' || !DATE.test(date) || Number.isNaN(Date.parse(date))) errors.paymentDate = 'must be a date (yyyy-mm-dd)';
  else if (date > today) errors.paymentDate = 'cannot be in the future';
  const notes = a.trim(input.notes);
  if (notes.length > 300) errors.notes = 'up to 300 characters';
  if (Object.keys(errors).length) return { errors };
  return { value: { amountMinor: input.amountMinor, method: input.method, referenceNo: ref || null, paymentDate: date, notes: notes || null } };
}

// ---- plumbing --------------------------------------------------------------

/**
 * Administrators of the school/branch, and (only when [financeOk]) the branch's
 * active FINANCE staff, who may record payments but nothing else here.
 */
async function authorizeFees(db, uid, token, schoolId, branchId, financeOk) {
  const admin = await a.authorize(db, uid, token, schoolId, branchId || null);
  if (admin) return admin;
  if (!financeOk || !branchId || !a.isStr(schoolId) || !a.ID.test(schoolId) || !a.ID.test(branchId)) return null;
  const u = (await db.collection('users').doc(uid).get()).data();
  if (!u || u.schoolId !== schoolId || u.status !== 'ACTIVE' || !loginAllowed(u, token)) return null;
  const here = u.branchId === branchId ? u.role : (u.branchRoles || {})[branchId];
  if (here !== 'FINANCE') return null;
  if (!(await require('./access').schoolGate(db, schoolId, 'admission')).allowed) return null;
  return { ...u, role: 'FINANCE' };
}

async function context(ctx, uid, token, data, { financeOk = false } = {}) {
  const { db } = ctx;
  const { schoolId, branchId, enquiryId } = data || {};
  const caller = await authorizeFees(db, uid, token, schoolId, branchId, financeOk);
  if (!caller || !branchId) return { error: 'PERMISSION_DENIED' };
  const settings = await a.loadSettings(db, schoolId);
  if (!settings.enabled) return { error: 'FAILED_PRECONDITION', reason: 'admissions are not enabled for this school' };
  if (!a.isStr(enquiryId) || !a.ID.test(enquiryId)) return { error: 'INVALID_ARGUMENT', reason: 'enquiryId is required' };
  const schoolSnap = await db.collection('schools').doc(schoolId).get();
  const school = schoolSnap.exists ? schoolSnap.data() : {};
  const today = a.civilToday(a.wall(ctx), school.timezone || 'UTC');
  return { db, schoolId, branchId, enquiryId, caller, settings, today, currency: school.currency || 'INR' };
}

const categoryOf = (data) => (CATEGORIES.includes(data && data.category) ? data.category : null);

async function loadFee(tx, c, category) {
  const ref = feeCol(c.db, c.schoolId, c.branchId).doc(feeId(c.enquiryId, category));
  const snap = await tx.get(ref);
  return snap.exists ? { ref, data: snap.data() } : null;
}

// ---- callables -------------------------------------------------------------

/**
 * Sets (creates or changes) the amount asked for one fee category of an
 * enquiry. An optional [feeStructureId] must be an ACTIVE fee structure of the
 * branch; its category is ADMISSION and its amount is the default.
 */
async function setAdmissionFee(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const category = categoryOf(data);
  if (!category) return { error: 'INVALID_ARGUMENT', reason: 'category is not valid' };
  const { db, now } = ctx;
  const structureId = a.trim(data.feeStructureId) || null;
  if (structureId && !a.ID.test(structureId)) return { error: 'INVALID_ARGUMENT', reason: 'feeStructureId is not valid' };
  const dueDate = data.dueDate === undefined || data.dueDate === null || data.dueDate === '' ? null : data.dueDate;
  if (dueDate !== null && (typeof dueDate !== 'string' || !DATE.test(dueDate) || Number.isNaN(Date.parse(dueDate)))) {
    return { error: 'INVALID_ARGUMENT', reason: 'dueDate must be a date (yyyy-mm-dd)' };
  }
  const note = a.trim(data.note);
  if (note.length > 300) return { error: 'INVALID_ARGUMENT', reason: 'note: up to 300 characters' };
  return db.runTransaction(async (tx) => {
    const enquiry = await a.loadEnquiry(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    if (!enquiry) return { error: 'NOT_FOUND' };
    if (CLOSED_ENQUIRY.includes(enquiry.data.status) || enquiry.data.status === 'ADMISSION_CONFIRMED') {
      return { error: 'FAILED_PRECONDITION', reason: `fees cannot be changed while the enquiry is ${enquiry.data.status}` };
    }
    let amountMinor = data.amountMinor;
    if (structureId) {
      const s = await tx.get(a.branchRef(db, c.schoolId, c.branchId).collection('feeStructures').doc(structureId));
      if (!s.exists || s.data().status !== 'ACTIVE') return { error: 'FAILED_PRECONDITION', reason: 'the fee structure is not available' };
      if (s.data().category !== 'ADMISSION') return { error: 'FAILED_PRECONDITION', reason: 'only an ADMISSION fee structure can be used' };
      if (amountMinor === undefined || amountMinor === null) amountMinor = s.data().amountMinor;
    }
    if (!isMinor(amountMinor)) return { error: 'INVALID_ARGUMENT', reason: 'amountMinor must be a positive whole number of minor units' };
    const cur = await loadFee(tx, c, category);
    if (!cur) {
      tx.set(feeCol(db, c.schoolId, c.branchId).doc(feeId(c.enquiryId, category)), {
        schoolId: c.schoolId,
        branchId: c.branchId,
        enquiryId: c.enquiryId,
        // The only enquiry detail Finance sees: its number.
        enquiryNumber: enquiry.data.enquiryNumber || null,
        category,
        currency: c.currency,
        amountMinor,
        waivedMinor: 0,
        paidMinor: 0,
        refundedMinor: 0,
        feeStructureId: structureId,
        dueDate,
        note: note || null,
        status: 'DUE',
        revision: 1,
        createdAt: now,
        createdBy: uid,
        updatedAt: now,
        updatedBy: uid,
      });
      return { result: { id: feeId(c.enquiryId, category), created: true } };
    }
    const f = cur.data;
    if (f.status === 'CANCELLED') return { error: 'FAILED_PRECONDITION', reason: 'this fee was cancelled' };
    if (data.baseRevision !== undefined && data.baseRevision !== f.revision) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    if (amountMinor < (f.waivedMinor || 0) + netPaid(f)) return { error: 'FAILED_PRECONDITION', reason: 'the amount cannot be lower than what is already paid or waived' };
    tx.update(cur.ref, {
      amountMinor,
      feeStructureId: structureId,
      dueDate,
      note: note || null,
      status: statusOf({ ...f, amountMinor }),
      revision: f.revision + 1,
      updatedAt: now,
      updatedBy: uid,
    });
    return { result: { id: cur.ref.id, created: false } };
  }, { maxAttempts: 10 });
}

/** Cancels a fee nobody paid (or whose payments were fully refunded). */
async function cancelAdmissionFee(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const category = categoryOf(data);
  if (!category) return { error: 'INVALID_ARGUMENT', reason: 'category is not valid' };
  const reason = a.trim(data.reason);
  if (reason.length < 3 || reason.length > 300) return { error: 'INVALID_ARGUMENT', reason: 'a reason of 3 to 300 characters is required' };
  const { db, now } = ctx;
  return db.runTransaction(async (tx) => {
    const cur = await loadFee(tx, c, category);
    if (!cur) return { error: 'NOT_FOUND' };
    if (cur.data.status === 'CANCELLED') return { result: { id: cur.ref.id, duplicate: true } };
    if (netPaid(cur.data) !== 0) return { error: 'FAILED_PRECONDITION', reason: 'money is still held for this fee; refund it first' };
    tx.update(cur.ref, { status: 'CANCELLED', cancelReason: reason, revision: cur.data.revision + 1, updatedAt: now, updatedBy: uid });
    return { result: { id: cur.ref.id, duplicate: false } };
  }, { maxAttempts: 10 });
}

/** Waives what is still unpaid. Needs the approval authority (a waiver is money). */
async function waiveAdmissionFee(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  if (c.caller.role !== 'SCHOOL_ADMIN' && c.caller.role !== 'PLATFORM_ADMIN') return { error: 'PERMISSION_DENIED' };
  const category = categoryOf(data);
  if (!category) return { error: 'INVALID_ARGUMENT', reason: 'category is not valid' };
  const reason = a.trim(data.reason);
  if (reason.length < 3 || reason.length > 300) return { error: 'INVALID_ARGUMENT', reason: 'a reason of 3 to 300 characters is required' };
  const { db, now } = ctx;
  return db.runTransaction(async (tx) => {
    const cur = await loadFee(tx, c, category);
    if (!cur) return { error: 'NOT_FOUND' };
    const f = cur.data;
    if (f.status === 'CANCELLED') return { error: 'FAILED_PRECONDITION', reason: 'this fee was cancelled' };
    const open = balanceOf(f);
    if (open <= 0) return { result: { id: cur.ref.id, waivedMinor: f.waivedMinor || 0, duplicate: true } };
    const waivedMinor = (f.waivedMinor || 0) + open;
    tx.update(cur.ref, { waivedMinor, waiveReason: reason, status: statusOf({ ...f, waivedMinor }), revision: f.revision + 1, updatedAt: now, updatedBy: uid });
    return { result: { id: cur.ref.id, waivedMinor, duplicate: false } };
  }, { maxAttempts: 10 });
}

/** Year in the receipt number: the start year of the enquiry's academic year. */
async function receiptYear(tx, c, academicYearId, today) {
  if (!academicYearId) return Number(today.slice(0, 4));
  const snap = await tx.get(a.branchRef(c.db, c.schoolId, c.branchId).collection('academicYears').doc(academicYearId));
  const start = snap.exists ? snap.data().startDate : null;
  const d = start && typeof start.toDate === 'function' ? start.toDate() : start ? new Date(start) : null;
  return d && !Number.isNaN(d.getTime()) ? d.getUTCFullYear() : Number(today.slice(0, 4));
}

/**
 * Records ONE manual payment against a fee and issues a receipt number from the
 * Fees module's series. [requestId] makes a retry return the same payment. The
 * amount may not exceed the balance. No money is "received" any other way.
 */
async function recordAdmissionFeePayment(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data, { financeOk: true });
  if (c.error) return c;
  const category = categoryOf(data);
  if (!category) return { error: 'INVALID_ARGUMENT', reason: 'category is not valid' };
  if (!a.isStr(data.requestId) || !REQUEST_ID.test(data.requestId)) return { error: 'INVALID_ARGUMENT', reason: 'requestId is required' };
  const { db, now } = ctx;
  const payRef = payCol(db, c.schoolId, c.branchId).doc(`${c.enquiryId}__${data.requestId}`);
  return db.runTransaction(async (tx) => {
    const already = await tx.get(payRef);
    const enquiry = await a.loadEnquiry(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    if (already.exists) return { result: { id: payRef.id, receiptNumber: already.data().receiptNumber, duplicate: true } };
    if (!enquiry) return { error: 'NOT_FOUND' };
    if (CLOSED_ENQUIRY.includes(enquiry.data.status) || enquiry.data.status === 'ADMISSION_CONFIRMED') {
      return { error: 'FAILED_PRECONDITION', reason: `payments cannot be recorded while the enquiry is ${enquiry.data.status}` };
    }
    const cur = await loadFee(tx, c, category);
    if (!cur) return { error: 'NOT_FOUND' };
    const f = cur.data;
    if (f.status === 'CANCELLED') return { error: 'FAILED_PRECONDITION', reason: 'this fee was cancelled' };
    const parsed = validatePayment(data, { today: c.today, balance: balanceOf(f) });
    if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(parsed.errors) };
    const v = parsed.value;
    const ayId = enquiry.data.academicYearId || 'none';
    const year = await receiptYear(tx, c, enquiry.data.academicYearId, c.today);
    const counterRef = a.branchRef(db, c.schoolId, c.branchId).collection('feeCounters').doc(`receipt_${ayId}`);
    const counter = await tx.get(counterRef);
    const seq = (counter.exists && Number.isInteger(counter.data().last) ? counter.data().last : 0) + 1;
    const receiptNumber = `RCT-${year}-${String(seq).padStart(6, '0')}`;
    tx.set(payRef, {
      schoolId: c.schoolId,
      branchId: c.branchId,
      enquiryId: c.enquiryId,
      feeId: cur.ref.id,
      category,
      kind: 'PAYMENT',
      currency: f.currency,
      amountMinor: v.amountMinor,
      method: v.method,
      referenceNo: v.referenceNo,
      paymentDate: v.paymentDate,
      notes: v.notes,
      receiptNumber,
      numberSeq: seq,
      balanceAfterMinor: balanceOf(f) - v.amountMinor,
      recordedBy: uid,
      recordedAt: now,
    });
    tx.set(a.branchRef(db, c.schoolId, c.branchId).collection('receiptNumbers').doc(receiptNumber), { schoolId: c.schoolId, branchId: c.branchId, academicYearId: ayId, numberSeq: seq, source: 'ADMISSION' });
    if (counter.exists) tx.update(counterRef, { last: seq, updatedAt: now, updatedBy: uid });
    else tx.set(counterRef, { schoolId: c.schoolId, branchId: c.branchId, last: seq, updatedAt: now, updatedBy: uid });
    const paidMinor = (f.paidMinor || 0) + v.amountMinor;
    tx.update(cur.ref, { paidMinor, status: statusOf({ ...f, paidMinor }), lastReceiptNumber: receiptNumber, revision: f.revision + 1, updatedAt: now, updatedBy: uid });
    return { result: { id: payRef.id, receiptNumber, duplicate: false } };
  }, { maxAttempts: 10 });
}

/**
 * Records a refund of money already paid (needs the approval authority and a
 * reason). A refund has no receipt number; it points at the fee, not a payment.
 */
async function refundAdmissionFee(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  if (c.caller.role !== 'SCHOOL_ADMIN' && c.caller.role !== 'PLATFORM_ADMIN') return { error: 'PERMISSION_DENIED' };
  const category = categoryOf(data);
  if (!category) return { error: 'INVALID_ARGUMENT', reason: 'category is not valid' };
  if (!a.isStr(data.requestId) || !REQUEST_ID.test(data.requestId)) return { error: 'INVALID_ARGUMENT', reason: 'requestId is required' };
  const reason = a.trim(data.reason);
  if (reason.length < 3 || reason.length > 300) return { error: 'INVALID_ARGUMENT', reason: 'a reason of 3 to 300 characters is required' };
  if (!METHODS.includes(data.method)) return { error: 'INVALID_ARGUMENT', reason: 'method is not a valid payment method' };
  const { db, now } = ctx;
  const payRef = payCol(db, c.schoolId, c.branchId).doc(`${c.enquiryId}__${data.requestId}`);
  return db.runTransaction(async (tx) => {
    const already = await tx.get(payRef);
    if (already.exists) return { result: { id: payRef.id, duplicate: true } };
    const cur = await loadFee(tx, c, category);
    if (!cur) return { error: 'NOT_FOUND' };
    const f = cur.data;
    if (!isMinor(data.amountMinor)) return { error: 'INVALID_ARGUMENT', reason: 'amountMinor must be a positive whole number of minor units' };
    if (data.amountMinor > netPaid(f)) return { error: 'FAILED_PRECONDITION', reason: 'a refund cannot be more than the amount held' };
    tx.set(payRef, {
      schoolId: c.schoolId,
      branchId: c.branchId,
      enquiryId: c.enquiryId,
      feeId: cur.ref.id,
      category,
      kind: 'REFUND',
      currency: f.currency,
      amountMinor: data.amountMinor,
      method: data.method,
      referenceNo: a.trim(data.referenceNo) || null,
      paymentDate: c.today,
      notes: reason,
      receiptNumber: null,
      recordedBy: uid,
      recordedAt: now,
    });
    const refundedMinor = (f.refundedMinor || 0) + data.amountMinor;
    tx.update(cur.ref, { refundedMinor, status: statusOf({ ...f, refundedMinor }), revision: f.revision + 1, updatedAt: now, updatedBy: uid });
    return { result: { id: payRef.id, duplicate: false } };
  }, { maxAttempts: 10 });
}

module.exports = {
  authorizeFees,
  CATEGORIES,
  METHODS,
  statusOf,
  netPaid,
  balanceOf,
  summarize,
  validatePayment,
  feeId,
  setAdmissionFee,
  cancelAdmissionFee,
  waiveAdmissionFee,
  recordAdmissionFeePayment,
  refundAdmissionFee,
};

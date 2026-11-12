'use strict';

// Admission applications and their documents (docs/admission-management/, phase 6).
//
//   branches/{b}/admissionApplications/{enquiryId}            one application per enquiry (the id IS the enquiry id)
//   branches/{b}/admissionApplicationHistory/{enquiryId}__{revision}   append-only: status changes, comments, document events
//   branches/{b}/admissionDocuments/{id}                      metadata of one uploaded file
//   Storage: schools/{s}/branches/{b}/admissionDocs/{enquiryId}/{docId}/document.{ext}
//
// Clients read these (rules) but write nothing: every change is a callable. A
// file is uploaded in three steps so the server stays in charge:
//   1. requestAdmissionDocumentUpload  validates type, content type and size, then
//      records an UPLOADING document whose path/size/type the Storage rules check;
//   2. the client puts the bytes at exactly that path (create-only);
//   3. confirmAdmissionDocumentUpload  reads the stored object with admin rights and
//      only then marks it UPLOADED. Uploads never confirmed are cleaned up.
// The application's status also drives the enquiry's status (submitted, under
// review, approved, rejected) in the same transaction.

const a = require('./admission');

// ---- constants -------------------------------------------------------------

const DRAFT = 'DRAFT';
const SUBMITTED = 'SUBMITTED';
const UNDER_REVIEW = 'UNDER_REVIEW';
const APPROVED = 'APPROVED';
const REJECTED = 'REJECTED';
const WITHDRAWN = 'WITHDRAWN';
const OPEN_APPLICATION = [DRAFT, SUBMITTED, UNDER_REVIEW];
const CLOSABLE = [DRAFT, SUBMITTED, UNDER_REVIEW, APPROVED];
// An application can be started while the enquiry is at one of these.
const APPLY_FROM = ['INTERESTED', 'VISIT_SCHEDULED', 'VISIT_COMPLETED'];

const UPLOADING = 'UPLOADING';
const UPLOADED = 'UPLOADED';
const VERIFIED = 'VERIFIED';
const DOC_REJECTED = 'REJECTED';
const REMOVED = 'REMOVED';
const ABANDONED = 'ABANDONED';

const MAX_BYTES = 5 * 1024 * 1024;
const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];
const FILE_TYPES = ['application/pdf', ...IMAGE_TYPES];
const PHOTO_DOCUMENTS = ['STUDENT_PHOTO', 'PARENT_PHOTO'];
const EXTENSION = { 'application/pdf': '.pdf', 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' };
const MAX_DOCUMENTS = 40;
const UPLOAD_WINDOW_MS = 24 * 60 * 60 * 1000;
const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;

const branchRef = a.branchRef;
const appCol = (db, s, b) => branchRef(db, s, b).collection('admissionApplications');
const docCol = (db, s, b) => branchRef(db, s, b).collection('admissionDocuments');
const histCol = (db, s, b) => branchRef(db, s, b).collection('admissionApplicationHistory');

// ---- pure helpers ----------------------------------------------------------

/** Storage path of a document (also what the Storage rules compare against). */
function storagePathOf(schoolId, branchId, enquiryId, docId, contentType) {
  return `schools/${schoolId}/branches/${branchId}/admissionDocs/${enquiryId}/${docId}/document${EXTENSION[contentType]}`;
}

/** Validates an upload request. Returns { errors } or { value }. */
function validateUploadRequest(input, settings) {
  const errors = {};
  const i = input || {};
  const types = a.documentTypesOf(settings);
  const type = a.trim(i.type);
  if (!Object.prototype.hasOwnProperty.call(types, type)) errors.type = 'is not a document type of this school';
  const fileName = a.trim(i.fileName);
  if (fileName.length < 1 || fileName.length > 120 || /[\\/\u0000-\u001f]/.test(fileName)) errors.fileName = 'is required (up to 120 characters, no slashes)';
  const contentType = a.trim(i.contentType).toLowerCase();
  const allowed = PHOTO_DOCUMENTS.includes(type) ? IMAGE_TYPES : FILE_TYPES;
  if (!allowed.includes(contentType)) errors.contentType = PHOTO_DOCUMENTS.includes(type) ? 'must be a JPEG, PNG or WebP image' : 'must be a PDF, JPEG, PNG or WebP file';
  const size = i.sizeBytes;
  if (!Number.isInteger(size) || size < 1) errors.sizeBytes = 'must be the size of the file in bytes';
  else if (size > MAX_BYTES) errors.sizeBytes = 'a file can be at most 5 MB';
  if (Object.keys(errors).length) return { errors };
  return { value: { type, label: types[type], fileName, contentType, sizeBytes: size } };
}

/** The required document types that no VERIFIED document covers. */
function missingRequired(settings, verifiedDocs) {
  const have = new Set(verifiedDocs.map((d) => d.type));
  return (settings.requiredDocumentTypes || []).filter((t) => !have.has(t));
}

/** Whether [caller] (from assertAdmin) may approve or reject. */
function mayDecide(caller, settings) {
  return Boolean(caller) && (caller.role === 'SCHOOL_ADMIN' || (caller.role === 'BRANCH_ADMIN' && settings.branchAdminsMayApprove === true));
}

// ---- shared plumbing -------------------------------------------------------

async function context(ctx, uid, token, data) {
  const { db } = ctx;
  const { schoolId, branchId, enquiryId } = data || {};
  const caller = await a.authorize(db, uid, token, schoolId, branchId || null);
  if (!caller || !branchId) return { error: 'PERMISSION_DENIED' };
  const settings = await a.loadSettings(db, schoolId);
  if (!settings.enabled) return { error: 'FAILED_PRECONDITION', reason: 'admissions are not enabled for this school' };
  const today = a.civilToday(a.wall(ctx), await a.schoolZone(db, schoolId));
  return { db, schoolId, branchId, enquiryId, caller, settings, today };
}

async function loadApplication(tx, c) {
  if (!a.isStr(c.enquiryId) || !a.ID.test(c.enquiryId)) return null;
  const ref = appCol(c.db, c.schoolId, c.branchId).doc(c.enquiryId);
  const snap = await tx.get(ref);
  return snap.exists ? { ref, data: snap.data() } : null;
}

/** Appends a history entry and bumps the application's revision (the entry id). */
function logEvent(tx, ctx, app, event, extra, uid) {
  const rev = app.data.revision + 1;
  tx.set(histCol(ctx.db, app.data.schoolId, app.data.branchId).doc(`${app.ref.id}__${rev}`), {
    schoolId: app.data.schoolId,
    branchId: app.data.branchId,
    enquiryId: app.ref.id,
    applicationId: app.ref.id,
    revision: rev,
    event,
    ...extra,
    actorId: uid,
    at: ctx.now,
  });
  return rev;
}

// ---- application: create / edit / submit -----------------------------------

/** Starts the application of an enquiry (one per enquiry; repeating returns it). */
async function createApplication(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const { db, now } = ctx;
  return db.runTransaction(async (tx) => {
    const cur = await a.loadEnquiry(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    if (!cur) return { error: 'NOT_FOUND' };
    const existing = await loadApplication(tx, c);
    if (existing) return { result: { id: c.enquiryId, applicationNumber: existing.data.applicationNumber, duplicate: true } };
    const e = cur.data;
    if (!APPLY_FROM.includes(e.status)) return { error: 'FAILED_PRECONDITION', reason: `an application cannot be started while the enquiry is ${e.status}` };
    const applicationNumber = await a.nextNumber(tx, ctx, c.schoolId, c.branchId, c.settings.applicationPrefix, c.today.slice(0, 4));
    const doc = {
      schoolId: c.schoolId,
      branchId: c.branchId,
      enquiryId: c.enquiryId,
      enquiryNumber: e.enquiryNumber,
      applicationNumber,
      status: DRAFT,
      student: e.student,
      studentName: e.studentName,
      source: e.source,
      academicYearId: e.academicYearId,
      classId: e.interestedClassId,
      guardians: e.guardians,
      primaryPhone: e.primaryPhone,
      address: e.address,
      previousSchool: e.previousSchool || null,
      previousClass: e.previousClass || null,
      specialRequirements: e.specialRequirements || null,
      submissionNotes: null,
      submittedAt: null,
      submittedBy: null,
      reviewStartedAt: null,
      reviewStartedBy: null,
      decidedAt: null,
      decidedBy: null,
      decisionComment: null,
      revision: 1,
      createdAt: now,
      createdBy: uid,
      updatedAt: now,
      updatedBy: uid,
    };
    tx.set(appCol(db, c.schoolId, c.branchId).doc(c.enquiryId), doc);
    tx.set(histCol(db, c.schoolId, c.branchId).doc(`${c.enquiryId}__1`), { schoolId: c.schoolId, branchId: c.branchId, enquiryId: c.enquiryId, applicationId: c.enquiryId, revision: 1, event: 'CREATED', from: null, to: DRAFT, comment: null, actorId: uid, at: now });
    tx.update(cur.ref, { applicationId: c.enquiryId, applicationNumber });
    return { result: { id: c.enquiryId, applicationNumber, duplicate: false } };
  }, { maxAttempts: 10 });
}

/** Edits a DRAFT application. The enquiry's own details are not touched. */
async function updateApplication(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const { db, now } = ctx;
  const input = data.application || {};
  return db.runTransaction(async (tx) => {
    const app = await loadApplication(tx, c);
    if (!app) return { error: 'NOT_FOUND' };
    if (app.data.status !== DRAFT) return { error: 'FAILED_PRECONDITION', reason: 'only a draft application can be edited' };
    if (data.baseRevision !== undefined && data.baseRevision !== app.data.revision) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    // Same field rules as an enquiry; the source is carried over, not edited.
    const keepSource = { ...c.settings, sources: [a.trim(app.data.source) || 'Other'] };
    const parsed = a.validateEnquiry({ ...input, source: keepSource.sources[0], remarks: null }, keepSource, { today: c.today });
    if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(parsed.errors) };
    const v = parsed.value;
    const notes = a.trim(input.submissionNotes);
    if (notes.length > 1000) return { error: 'INVALID_ARGUMENT', reason: 'submissionNotes: up to 1000 characters' };
    const rev = app.data.revision + 1;
    tx.update(app.ref, {
      student: v.student,
      studentName: v.studentName,
      academicYearId: v.academicYearId,
      classId: v.interestedClassId,
      guardians: v.guardians,
      primaryPhone: v.primaryPhone,
      address: v.address,
      previousSchool: v.previousSchool,
      previousClass: v.previousClass,
      specialRequirements: v.specialRequirements,
      submissionNotes: notes || null,
      revision: rev,
      updatedAt: now,
      updatedBy: uid,
    });
    return { result: { revision: rev } };
  });
}

/** The things an application must have before it can be submitted. */
function submissionProblems(app) {
  const problems = {};
  if (!app.student || !app.student.firstName) problems.student = 'the student\'s name is required';
  if (!app.student || !app.student.dateOfBirth) problems.dateOfBirth = 'the date of birth is required';
  if (!app.academicYearId) problems.academicYearId = 'the academic year is required';
  if (!app.classId) problems.classId = 'the class is required';
  const g = (app.guardians || [])[0];
  if (!g || !g.name || !g.phone) problems.guardian = 'a parent or guardian with a mobile number is required';
  return problems;
}

/** DRAFT → SUBMITTED, and the enquiry moves to APPLICATION_SUBMITTED. */
async function submitApplication(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const { db, now } = ctx;
  return db.runTransaction(async (tx) => {
    const cur = await a.loadEnquiry(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    const app = await loadApplication(tx, c);
    if (!cur || !app) return { error: 'NOT_FOUND' };
    if (app.data.status !== DRAFT) return { error: 'FAILED_PRECONDITION', reason: 'only a draft application can be submitted' };
    if (data.baseRevision !== undefined && data.baseRevision !== app.data.revision) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    const problems = submissionProblems(app.data);
    if (Object.keys(problems).length) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(problems) };
    if (!a.canTransition(cur.data.status, 'APPLICATION_SUBMITTED')) return { error: 'FAILED_PRECONDITION', reason: `the enquiry is ${cur.data.status}; resume or reopen it before submitting` };
    const rev = logEvent(tx, ctx, app, 'SUBMITTED', { from: DRAFT, to: SUBMITTED, comment: null }, uid);
    tx.update(app.ref, { status: SUBMITTED, submittedAt: now, submittedBy: uid, revision: rev, updatedAt: now, updatedBy: uid });
    a.applyStatus(tx, ctx, cur, { to: 'APPLICATION_SUBMITTED', reason: 'Application submitted', uid });
    return { result: { revision: rev, status: SUBMITTED } };
  }, { maxAttempts: 10 });
}

// ---- review ----------------------------------------------------------------

/** SUBMITTED → UNDER_REVIEW (action START), or an internal comment (COMMENT). */
async function reviewApplication(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const { db, now } = ctx;
  const action = a.trim(data.action);
  const comment = a.trim(data.comment);
  if (!['START', 'COMMENT'].includes(action)) return { error: 'INVALID_ARGUMENT', reason: 'action: START or COMMENT' };
  if (comment.length > 500) return { error: 'INVALID_ARGUMENT', reason: 'comment: up to 500 characters' };
  if (action === 'COMMENT' && comment.length < 2) return { error: 'INVALID_ARGUMENT', reason: 'comment: required' };
  return db.runTransaction(async (tx) => {
    const cur = await a.loadEnquiry(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    const app = await loadApplication(tx, c);
    if (!cur || !app) return { error: 'NOT_FOUND' };
    if (data.baseRevision !== undefined && data.baseRevision !== app.data.revision) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    if (action === 'COMMENT') {
      if (![SUBMITTED, UNDER_REVIEW].includes(app.data.status)) return { error: 'FAILED_PRECONDITION', reason: 'comments are added once the application is submitted' };
      const rev = logEvent(tx, ctx, app, 'COMMENTED', { comment }, uid);
      tx.update(app.ref, { revision: rev, updatedAt: now, updatedBy: uid });
      return { result: { revision: rev } };
    }
    if (app.data.status !== SUBMITTED) return { error: 'FAILED_PRECONDITION', reason: 'only a submitted application can be taken into review' };
    if (!a.canTransition(cur.data.status, 'UNDER_REVIEW')) return { error: 'FAILED_PRECONDITION', reason: `the enquiry is ${cur.data.status}` };
    const rev = logEvent(tx, ctx, app, 'REVIEW_STARTED', { from: SUBMITTED, to: UNDER_REVIEW, comment: comment || null }, uid);
    tx.update(app.ref, { status: UNDER_REVIEW, reviewStartedAt: now, reviewStartedBy: uid, revision: rev, updatedAt: now, updatedBy: uid });
    a.applyStatus(tx, ctx, cur, { to: 'UNDER_REVIEW', reason: 'Review started', uid });
    return { result: { revision: rev, status: UNDER_REVIEW } };
  }, { maxAttempts: 10 });
}

/**
 * UNDER_REVIEW → APPROVED or REJECTED. School admins decide; branch admins only
 * when the school has switched that on. Approving needs every required document
 * VERIFIED; rejecting needs a comment and closes the enquiry (its follow-ups too).
 */
async function decideApplication(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  if (!mayDecide(c.caller, c.settings)) return { error: 'PERMISSION_DENIED', reason: 'only a school administrator (or a branch administrator where the school allows it) can decide' };
  const { db, now } = ctx;
  const decision = a.trim(data.decision);
  const comment = a.trim(data.comment);
  if (!['APPROVE', 'REJECT'].includes(decision)) return { error: 'INVALID_ARGUMENT', reason: 'decision: APPROVE or REJECT' };
  if (comment.length > 500) return { error: 'INVALID_ARGUMENT', reason: 'comment: up to 500 characters' };
  if (decision === 'REJECT' && comment.length < 3) return { error: 'INVALID_ARGUMENT', reason: 'comment: a reason is required to reject' };
  return db.runTransaction(async (tx) => {
    const cur = await a.loadEnquiry(tx, ctx, c.schoolId, c.branchId, c.enquiryId);
    const app = await loadApplication(tx, c);
    if (!cur || !app) return { error: 'NOT_FOUND' };
    if (app.data.status !== UNDER_REVIEW) return { error: 'FAILED_PRECONDITION', reason: 'only an application under review can be decided' };
    if (data.baseRevision !== undefined && data.baseRevision !== app.data.revision) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    const to = decision === 'APPROVE' ? 'APPROVED' : 'REJECTED';
    if (!a.canTransition(cur.data.status, to)) return { error: 'FAILED_PRECONDITION', reason: `the enquiry is ${cur.data.status}` };
    let closing = null;
    if (decision === 'APPROVE') {
      const verified = await tx.get(docCol(db, c.schoolId, c.branchId).where('applicationId', '==', c.enquiryId).where('status', '==', VERIFIED).limit(200));
      const missing = missingRequired(c.settings, verified.docs.map((d) => d.data()));
      if (missing.length) {
        const types = a.documentTypesOf(c.settings);
        return { error: 'FAILED_PRECONDITION', reason: `required documents are not verified: ${missing.map((t) => types[t] || t).join(', ')}` };
      }
    } else {
      closing = await require('./admission_activities').cancelOpenForClosed(tx, ctx, cur, uid);
    }
    const rev = logEvent(tx, ctx, app, decision === 'APPROVE' ? 'APPROVED' : 'REJECTED', { from: UNDER_REVIEW, to, comment: comment || null }, uid);
    tx.update(app.ref, { status: to, decidedAt: now, decidedBy: uid, decisionComment: comment || null, revision: rev, updatedAt: now, updatedBy: uid });
    a.applyStatus(tx, ctx, cur, { to, reason: decision === 'APPROVE' ? 'Application approved' : comment, uid });
    if (closing) closing.apply();
    return { result: { revision: rev, status: to } };
  }, { maxAttempts: 10 });
}

/**
 * Called by changeEnquiryStatus (inside its transaction, before any write) when an
 * enquiry closes: the application follows it (REJECTED with the enquiry, otherwise
 * WITHDRAWN). Returns `apply()` or null.
 */
async function closeForEnquiry(tx, ctx, cur, to, reason, uid) {
  const d = cur.data;
  const ref = appCol(ctx.db, d.schoolId, d.branchId).doc(cur.ref.id);
  const snap = await tx.get(ref);
  if (!snap.exists || !CLOSABLE.includes(snap.data().status)) return null;
  const app = { ref, data: snap.data() };
  return {
    apply() {
      const status = to === 'REJECTED' ? REJECTED : WITHDRAWN;
      const rev = logEvent(tx, ctx, app, 'CLOSED_WITH_ENQUIRY', { from: app.data.status, to: status, comment: a.trim(reason) || null }, uid);
      tx.update(ref, { status, decisionComment: a.trim(reason) || 'Enquiry closed', revision: rev, updatedAt: ctx.now, updatedBy: uid });
    },
  };
}

// ---- documents -------------------------------------------------------------

async function loadDocument(tx, c, docId) {
  if (!a.isStr(docId) || !a.ID.test(docId)) return null;
  const ref = docCol(c.db, c.schoolId, c.branchId).doc(docId);
  const snap = await tx.get(ref);
  if (!snap.exists || snap.data().enquiryId !== c.enquiryId) return null;
  return { ref, data: snap.data() };
}

/** Step 1: validate and record the intent to upload; returns the path to put the bytes at. */
async function requestDocumentUpload(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const { db, now } = ctx;
  const parsed = validateUploadRequest(data.document, c.settings);
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(parsed.errors) };
  const requestId = data.requestId;
  if (requestId !== undefined && !(a.isStr(requestId) && REQUEST_ID.test(requestId))) return { error: 'INVALID_ARGUMENT', reason: 'requestId: 8-64 letters, digits, - or _' };
  const id = requestId ? `${c.enquiryId}__${requestId}` : docCol(db, c.schoolId, c.branchId).doc().id;
  const v = parsed.value;
  return db.runTransaction(async (tx) => {
    const app = await loadApplication(tx, c);
    if (!app) return { error: 'NOT_FOUND' };
    const ref = docCol(db, c.schoolId, c.branchId).doc(id);
    const existing = await tx.get(ref);
    if (existing.exists) {
      const e = existing.data();
      return { result: { id, storagePath: e.storagePath, status: e.status, duplicate: true } };
    }
    if (!OPEN_APPLICATION.includes(app.data.status)) return { error: 'FAILED_PRECONDITION', reason: 'documents can only be added while the application is open' };
    const mine = await tx.get(docCol(db, c.schoolId, c.branchId).where('applicationId', '==', c.enquiryId).limit(MAX_DOCUMENTS + 1));
    if (mine.docs.filter((d) => d.data().status !== REMOVED && d.data().status !== ABANDONED).length >= MAX_DOCUMENTS) return { error: 'FAILED_PRECONDITION', reason: `an application can hold at most ${MAX_DOCUMENTS} documents` };
    const storagePath = storagePathOf(c.schoolId, c.branchId, c.enquiryId, id, v.contentType);
    tx.set(ref, {
      schoolId: c.schoolId,
      branchId: c.branchId,
      enquiryId: c.enquiryId,
      applicationId: c.enquiryId,
      type: v.type,
      label: v.label,
      fileName: v.fileName,
      contentType: v.contentType,
      sizeBytes: v.sizeBytes,
      storagePath,
      status: UPLOADING,
      expiresAt: new Date(a.wall(ctx).getTime() + UPLOAD_WINDOW_MS),
      uploadedAt: null,
      verifiedAt: null,
      verifiedBy: null,
      rejectionReason: null,
      revision: 1,
      createdAt: now,
      createdBy: uid,
      updatedAt: now,
      updatedBy: uid,
    });
    return { result: { id, storagePath, status: UPLOADING, duplicate: false } };
  }, { maxAttempts: 10 });
}

/** Step 3: check what is really stored, then mark the document UPLOADED. */
async function confirmDocumentUpload(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const { db, now } = ctx;
  if (!ctx.storage) return { error: 'FAILED_PRECONDITION', reason: 'file storage is not available' };
  if (!a.isStr(data.documentId) || !a.ID.test(data.documentId)) return { error: 'NOT_FOUND' };
  // Read the stored object first (a network call, so outside the transaction).
  const snap = await docCol(db, c.schoolId, c.branchId).doc(data.documentId).get();
  if (!snap.exists || snap.data().enquiryId !== c.enquiryId) return { error: 'NOT_FOUND' };
  const pre = snap.data();
  if (pre.status === UPLOADED || pre.status === VERIFIED) return { result: { id: snap.id, status: pre.status } };
  if (pre.status !== UPLOADING) return { error: 'FAILED_PRECONDITION', reason: `this upload is ${pre.status}; start a new one` };
  const stat = await ctx.storage.stat(pre.storagePath);
  return db.runTransaction(async (tx) => {
    const app = await loadApplication(tx, c);
    const doc = await loadDocument(tx, c, data.documentId);
    if (!app || !doc) return { error: 'NOT_FOUND' };
    if (doc.data.status !== UPLOADING) return { result: { id: doc.ref.id, status: doc.data.status } };
    if (!stat.exists) return { error: 'FAILED_PRECONDITION', reason: 'the file was not found in storage; upload it again' };
    if (stat.size !== doc.data.sizeBytes || stat.contentType !== doc.data.contentType) {
      // What arrived is not what was announced: keep nothing.
      tx.update(doc.ref, { status: ABANDONED, rejectionReason: 'the uploaded file did not match the request', revision: doc.data.revision + 1, updatedAt: now, updatedBy: uid });
      await ctx.storage.deleteFile(doc.data.storagePath);
      return { error: 'FAILED_PRECONDITION', reason: 'the uploaded file did not match its declared type or size; upload it again' };
    }
    const rev = logEvent(tx, ctx, app, 'DOCUMENT_UPLOADED', { documentType: doc.data.type, documentId: doc.ref.id }, uid);
    tx.update(app.ref, { revision: rev, updatedAt: now, updatedBy: uid });
    tx.update(doc.ref, { status: UPLOADED, uploadedAt: now, revision: doc.data.revision + 1, updatedAt: now, updatedBy: uid });
    return { result: { id: doc.ref.id, status: UPLOADED } };
  }, { maxAttempts: 10 });
}

/** Verifies or rejects an uploaded document (a rejection needs a reason). */
async function verifyDocument(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const { db, now } = ctx;
  const decision = a.trim(data.decision);
  const reason = a.trim(data.reason);
  if (!['VERIFY', 'REJECT'].includes(decision)) return { error: 'INVALID_ARGUMENT', reason: 'decision: VERIFY or REJECT' };
  if (decision === 'REJECT' && (reason.length < 3 || reason.length > 200)) return { error: 'INVALID_ARGUMENT', reason: 'reason: required to reject (3-200 characters)' };
  return db.runTransaction(async (tx) => {
    const app = await loadApplication(tx, c);
    const doc = await loadDocument(tx, c, data.documentId);
    if (!app || !doc) return { error: 'NOT_FOUND' };
    if (!OPEN_APPLICATION.includes(app.data.status)) return { error: 'FAILED_PRECONDITION', reason: 'documents are verified while the application is open' };
    if (doc.data.status !== UPLOADED) return { error: 'FAILED_PRECONDITION', reason: 'only an uploaded document can be verified or rejected' };
    if (data.baseRevision !== undefined && data.baseRevision !== doc.data.revision) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    const ok = decision === 'VERIFY';
    const rev = logEvent(tx, ctx, app, ok ? 'DOCUMENT_VERIFIED' : 'DOCUMENT_REJECTED', { documentType: doc.data.type, documentId: doc.ref.id, comment: ok ? null : reason }, uid);
    tx.update(app.ref, { revision: rev, updatedAt: now, updatedBy: uid });
    tx.update(doc.ref, { status: ok ? VERIFIED : DOC_REJECTED, verifiedAt: now, verifiedBy: uid, rejectionReason: ok ? null : reason, revision: doc.data.revision + 1, updatedAt: now, updatedBy: uid });
    return { result: { status: ok ? VERIFIED : DOC_REJECTED, revision: doc.data.revision + 1 } };
  }, { maxAttempts: 10 });
}

/** Takes a document out of use (kept for the record; the stored file is not deleted). */
async function removeDocument(ctx, uid, token, data) {
  const c = await context(ctx, uid, token, data);
  if (c.error) return c;
  const { db, now } = ctx;
  const reason = a.trim(data.reason);
  if (reason.length > 200) return { error: 'INVALID_ARGUMENT', reason: 'reason: up to 200 characters' };
  return db.runTransaction(async (tx) => {
    const app = await loadApplication(tx, c);
    const doc = await loadDocument(tx, c, data.documentId);
    if (!app || !doc) return { error: 'NOT_FOUND' };
    if (!OPEN_APPLICATION.includes(app.data.status)) return { error: 'FAILED_PRECONDITION', reason: 'documents can be removed while the application is open' };
    if (![UPLOADED, VERIFIED, DOC_REJECTED].includes(doc.data.status)) return { error: 'FAILED_PRECONDITION', reason: `a ${doc.data.status} document cannot be removed` };
    const rev = logEvent(tx, ctx, app, 'DOCUMENT_REMOVED', { documentType: doc.data.type, documentId: doc.ref.id, comment: reason || null }, uid);
    tx.update(app.ref, { revision: rev, updatedAt: now, updatedBy: uid });
    tx.update(doc.ref, { status: REMOVED, rejectionReason: reason || doc.data.rejectionReason || null, revision: doc.data.revision + 1, updatedAt: now, updatedBy: uid });
    return { result: { status: REMOVED } };
  }, { maxAttempts: 10 });
}

/**
 * Daily job: an upload that was requested but never confirmed within the window
 * is abandoned — its stored object (if the bytes did arrive) is deleted and the
 * record kept, marked ABANDONED. Never touches uploaded or verified documents.
 */
async function cleanupAbandonedUploads({ db, storage, now, log = () => {} }, { at = new Date() } = {}) {
  let abandoned = 0;
  let failed = 0;
  const schools = await db.collection('schools').get();
  for (const sd of schools.docs) {
    const branches = await db.collection('schools').doc(sd.id).collection('branches').get();
    for (const bd of branches.docs) {
      try {
        const stale = await docCol(db, sd.id, bd.id).where('status', '==', UPLOADING).limit(200).get();
        for (const d of stale.docs) {
          const x = d.data();
          const expires = x.expiresAt && x.expiresAt.toDate ? x.expiresAt.toDate() : x.expiresAt;
          if (!(expires instanceof Date) || expires.getTime() > at.getTime()) continue;
          try {
            await storage.deleteFile(x.storagePath);
            await d.ref.update({ status: ABANDONED, rejectionReason: 'the upload was never confirmed', revision: (x.revision || 1) + 1, updatedAt: now(), updatedBy: 'system' });
            abandoned++;
          } catch (e) {
            failed++;
            log('admission documents: cleanup failed', { schoolId: sd.id, branchId: bd.id, category: String((e && e.code) || 'error') });
          }
        }
      } catch (e) {
        failed++;
        log('admission documents: branch failed', { schoolId: sd.id, branchId: bd.id, category: String((e && e.code) || 'error') });
      }
    }
  }
  const out = { abandoned };
  if (failed) out.failed = failed;
  return out;
}

module.exports = {
  DRAFT,
  SUBMITTED,
  UNDER_REVIEW,
  APPROVED,
  REJECTED,
  WITHDRAWN,
  APPLY_FROM,
  UPLOADING,
  UPLOADED,
  VERIFIED,
  DOC_REJECTED,
  REMOVED,
  ABANDONED,
  MAX_BYTES,
  FILE_TYPES,
  IMAGE_TYPES,
  PHOTO_DOCUMENTS,
  storagePathOf,
  validateUploadRequest,
  missingRequired,
  mayDecide,
  submissionProblems,
  createApplication,
  updateApplication,
  submitApplication,
  reviewApplication,
  decideApplication,
  closeForEnquiry,
  requestDocumentUpload,
  confirmDocumentUpload,
  verifyDocument,
  removeDocument,
  cleanupAbandonedUploads,
};

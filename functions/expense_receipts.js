'use strict';

// Expense receipts (docs/expense-management/, phase E3): a receipt is a PDF or image attached to a DRAFT
// expense. Same three-step flow as admission documents, so the browser never writes anything the server
// did not approve:
//   1. requestExpenseReceiptUpload  -> the server validates type/size, records an UPLOADING receipt and
//      returns the exact storage path. storage.rules accept ONE create at exactly that path, size and type.
//   2. the app uploads the bytes straight to Storage.
//   3. confirmExpenseReceiptUpload  -> the server reads what is really stored (size, type AND the file's
//      own signature), then marks it UPLOADED and counts it on the expense.
// A receipt is never replaced or deleted from a client. Removing one only marks it REMOVED (the record is
// kept); uploads never confirmed are marked ABANDONED and their object deleted by the daily sweep.
//
//   schools/{s}/branches/{b}/expenseReceipts/{receiptId}
//   storage: schools/{s}/branches/{b}/expenseReceipts/{expenseId}/{receiptId}/receipt.{ext}

const { authorize, expenseCollection } = require('./expenses');
const { matchesSignature } = require('./admission_applications');
const { validId } = require('./ids');

const UPLOADING = 'UPLOADING';
const UPLOADED = 'UPLOADED';
const REMOVED = 'REMOVED';
const ABANDONED = 'ABANDONED';
const MAX_BYTES = 5 * 1024 * 1024;
const FILE_TYPES = Object.freeze(['application/pdf', 'image/jpeg', 'image/png']);
const EXTENSION = Object.freeze({ 'application/pdf': '.pdf', 'image/jpeg': '.jpg', 'image/png': '.png' });
const MAX_RECEIPTS = 3;
const UPLOAD_WINDOW_MS = 24 * 60 * 60 * 1000;
const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;
const ADMINS = ['SCHOOL_ADMIN', 'BRANCH_ADMIN'];

const isStr = (v) => typeof v === 'string';
const trim = (v) => (isStr(v) ? v.trim() : '');
const wall = (ctx) => (ctx.wall ? ctx.wall() : ctx.nowDate ? ctx.nowDate() : new Date());
const receiptCol = (db, schoolId, branchId) => db.collection('schools').doc(schoolId).collection('branches').doc(branchId).collection('expenseReceipts');

const storagePathOf = (schoolId, branchId, expenseId, receiptId, contentType) =>
  `schools/${schoolId}/branches/${branchId}/expenseReceipts/${expenseId}/${receiptId}/receipt${EXTENSION[contentType]}`;

/** Validates an upload request. Returns { errors } or { value }. */
function validateUploadRequest(input) {
  const errors = {};
  const i = input && typeof input === 'object' ? input : {};
  const fileName = trim(i.fileName);
  if (fileName.length < 1 || fileName.length > 120 || /[\\/\u0000-\u001f]/.test(fileName)) errors.fileName = 'is required (up to 120 characters, no slashes)';
  const contentType = trim(i.contentType).toLowerCase();
  if (!FILE_TYPES.includes(contentType)) errors.contentType = 'must be a PDF, JPEG or PNG file';
  const size = i.sizeBytes;
  if (!Number.isInteger(size) || size < 1) errors.sizeBytes = 'must be the size of the file in bytes';
  else if (size > MAX_BYTES) errors.sizeBytes = 'a file can be at most 5 MB';
  if (Object.keys(errors).length) return { errors };
  return { value: { fileName, contentType, sizeBytes: size } };
}
const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');

/**
 * The caller and the DRAFT expense they may attach to: the creator, or a school/branch admin of the branch.
 * Returns { caller, expenseRef } or { error }.
 */
async function draftContext(ctx, uid, token, data, tx) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !validId(data.expenseId)) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, 'create');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const expenseRef = expenseCollection(db, schoolId, branchId).doc(data.expenseId);
  if (tx) {
    const e = (await tx.get(expenseRef)).data();
    if (!e) return { error: 'NOT_FOUND', reason: 'that expense does not exist' };
    if (e.status !== 'DRAFT') return { error: 'FAILED_PRECONDITION', reason: 'receipts can only be changed while the expense is a draft' };
    if (e.createdBy !== uid && !ADMINS.includes(caller.role)) return { error: 'PERMISSION_DENIED' };
    return { caller, expenseRef, expense: e, schoolId, branchId };
  }
  return { caller, expenseRef, schoolId, branchId };
}

/** Step 1: records an UPLOADING receipt and returns the one storage path the browser may write. */
async function requestUpload(ctx, uid, token, data) {
  const { db, now } = ctx;
  const parsed = validateUploadRequest(data && data.receipt);
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
  if (data.requestId !== undefined && !(isStr(data.requestId) && REQUEST_ID.test(data.requestId))) return { error: 'INVALID_ARGUMENT', reason: 'requestId: 8-64 letters, digits, - or _' };
  const pre = await draftContext(ctx, uid, token, data);
  if (pre.error) return pre;
  const { schoolId, branchId } = pre;
  const id = data.requestId ? `${data.expenseId}__${data.requestId}` : receiptCol(db, schoolId, branchId).doc().id;
  const v = parsed.value;
  return db.runTransaction(async (tx) => {
    const c = await draftContext(ctx, uid, token, data, tx);
    if (c.error) return c;
    const ref = receiptCol(db, schoolId, branchId).doc(id);
    const existing = await tx.get(ref);
    if (existing.exists) {
      const e = existing.data();
      if (e.expenseId !== data.expenseId || e.createdBy !== uid) return { error: 'PERMISSION_DENIED' };
      return { result: { id, storagePath: e.storagePath, status: e.status, duplicate: true } };
    }
    const at = wall(ctx).getTime();
    const mine = await tx.get(receiptCol(db, schoolId, branchId).where('expenseId', '==', data.expenseId).limit(MAX_RECEIPTS + 10));
    const active = mine.docs.filter((d) => {
      const x = d.data();
      if (x.status === UPLOADED) return true;
      if (x.status !== UPLOADING) return false;
      const exp = x.expiresAt && x.expiresAt.toDate ? x.expiresAt.toDate() : x.expiresAt;
      return !(exp instanceof Date) || exp.getTime() > at; // an expired, unconfirmed upload does not count
    });
    if (active.length >= MAX_RECEIPTS) return { error: 'FAILED_PRECONDITION', reason: `an expense can hold at most ${MAX_RECEIPTS} receipts` };
    const storagePath = storagePathOf(schoolId, branchId, data.expenseId, id, v.contentType);
    tx.set(ref, {
      schoolId, branchId, expenseId: data.expenseId, ...v, storagePath, status: UPLOADING,
      expiresAt: new Date(at + UPLOAD_WINDOW_MS), uploadedAt: null, revision: 1,
      createdAt: now, createdBy: uid, updatedAt: now, updatedBy: uid,
    });
    return { result: { id, storagePath, status: UPLOADING, duplicate: false } };
  }, { maxAttempts: 10 });
}

/** Step 3: checks what is really stored, then marks the receipt UPLOADED and counts it on the expense. */
async function confirmUpload(ctx, uid, token, data) {
  const { db, now } = ctx;
  if (!ctx.storage) return { error: 'FAILED_PRECONDITION', reason: 'file storage is not available' };
  const pre = await draftContext(ctx, uid, token, data);
  if (pre.error) return pre;
  const { schoolId, branchId } = pre;
  if (!validId(data.receiptId)) return { error: 'NOT_FOUND' };
  const snap = await receiptCol(db, schoolId, branchId).doc(data.receiptId).get();
  if (!snap.exists || snap.data().expenseId !== data.expenseId) return { error: 'NOT_FOUND' };
  const first = snap.data();
  if (first.status === UPLOADED) return { result: { id: snap.id, status: UPLOADED } };
  if (first.status !== UPLOADING) return { error: 'FAILED_PRECONDITION', reason: `this upload is ${first.status}; start a new one` };
  // Read the stored object first (a network call, so outside the transaction).
  const stat = await ctx.storage.stat(first.storagePath);
  const head = stat.exists ? await ctx.storage.head(first.storagePath, 12) : null;
  let cleanup = null;
  const out = await db.runTransaction(async (tx) => {
    cleanup = null;
    const c = await draftContext(ctx, uid, token, data, tx);
    if (c.error) return c;
    const rec = (await tx.get(receiptCol(db, schoolId, branchId).doc(data.receiptId))).data();
    if (!rec) return { error: 'NOT_FOUND' };
    if (rec.status !== UPLOADING) return { result: { id: data.receiptId, status: rec.status } };
    if (!stat.exists) return { error: 'FAILED_PRECONDITION', reason: 'the file was not found in storage; upload it again' };
    const bad = stat.size !== rec.sizeBytes || stat.contentType !== rec.contentType
      ? 'the uploaded file did not match its declared type or size; upload it again'
      : !matchesSignature(rec.contentType, head) ? 'the file is not a valid PDF or image of the declared type; upload it again' : null;
    if (bad) {
      tx.update(receiptCol(db, schoolId, branchId).doc(data.receiptId), { status: ABANDONED, revision: rec.revision + 1, updatedAt: now, updatedBy: uid });
      cleanup = rec.storagePath;
      return { error: 'FAILED_PRECONDITION', reason: bad };
    }
    tx.update(receiptCol(db, schoolId, branchId).doc(data.receiptId), { status: UPLOADED, uploadedAt: now, revision: rec.revision + 1, updatedAt: now, updatedBy: uid });
    tx.update(c.expenseRef, { receiptCount: (Number.isInteger(c.expense.receiptCount) ? c.expense.receiptCount : 0) + 1 });
    return { result: { id: data.receiptId, status: UPLOADED } };
  }, { maxAttempts: 10 });
  if (cleanup) await ctx.storage.deleteFile(cleanup);
  return out;
}

/** Takes a receipt out of use. The record is kept (marked REMOVED); a draft's count drops. */
async function removeReceipt(ctx, uid, token, data) {
  const { db, now } = ctx;
  if (!validId(data && data.receiptId)) return { error: 'NOT_FOUND' };
  const pre = await draftContext(ctx, uid, token, data);
  if (pre.error) return pre;
  const { schoolId, branchId } = pre;
  return db.runTransaction(async (tx) => {
    const c = await draftContext(ctx, uid, token, data, tx);
    if (c.error) return c;
    const ref = receiptCol(db, schoolId, branchId).doc(data.receiptId);
    const rec = (await tx.get(ref)).data();
    if (!rec || rec.expenseId !== data.expenseId) return { error: 'NOT_FOUND' };
    if (rec.status !== UPLOADED) return { error: 'FAILED_PRECONDITION', reason: `a ${rec.status} receipt cannot be removed` };
    tx.update(ref, { status: REMOVED, revision: rec.revision + 1, updatedAt: now, updatedBy: uid });
    tx.update(c.expenseRef, { receiptCount: Math.max(0, (Number.isInteger(c.expense.receiptCount) ? c.expense.receiptCount : 0) - 1) });
    return { result: { status: REMOVED } };
  }, { maxAttempts: 10 });
}

/** The receipts in use on an expense (anyone who can see expenses in the branch). */
async function listReceipts(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !validId(data.expenseId)) return { error: 'PERMISSION_DENIED' };
  if (!(await authorize(db, uid, token, schoolId, branchId, 'view'))) return { error: 'PERMISSION_DENIED' };
  const snap = await receiptCol(db, schoolId, branchId).where('expenseId', '==', data.expenseId).get();
  const receipts = snap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((r) => r.status === UPLOADED)
    .sort((a, b) => String(a.id).localeCompare(String(b.id)))
    .map((r) => ({ id: r.id, fileName: r.fileName, contentType: r.contentType, sizeBytes: r.sizeBytes, storagePath: r.storagePath }));
  return { result: { receipts } };
}

/**
 * Daily: an upload requested but never confirmed within the window is abandoned: its object (if the bytes
 * arrived) is deleted and the record kept, marked ABANDONED. Never touches UPLOADED receipts.
 */
async function cleanupAbandonedUploads({ db, storage, now, log = () => {} }, { at = new Date() } = {}) {
  let abandoned = 0;
  let failed = 0;
  const schools = await db.collection('schools').get();
  for (const sd of schools.docs) {
    const branches = await db.collection('schools').doc(sd.id).collection('branches').get();
    for (const bd of branches.docs) {
      try {
        const stale = await receiptCol(db, sd.id, bd.id).where('status', '==', UPLOADING).limit(200).get();
        for (const d of stale.docs) {
          const x = d.data();
          const expires = x.expiresAt && x.expiresAt.toDate ? x.expiresAt.toDate() : x.expiresAt;
          if (!(expires instanceof Date) || expires.getTime() > at.getTime()) continue;
          try {
            await storage.deleteFile(x.storagePath);
            await d.ref.update({ status: ABANDONED, revision: (x.revision || 1) + 1, updatedAt: now(), updatedBy: 'system' });
            abandoned++;
          } catch (e) {
            failed++;
            log('expense receipts: cleanup failed', { schoolId: sd.id, branchId: bd.id, category: String((e && e.code) || 'error') });
          }
        }
      } catch (e) {
        failed++;
        log('expense receipts: branch failed', { schoolId: sd.id, branchId: bd.id, category: String((e && e.code) || 'error') });
      }
    }
  }
  const out = { abandoned };
  if (failed) out.failed = failed;
  return out;
}

module.exports = {
  UPLOADING, UPLOADED, REMOVED, ABANDONED, MAX_BYTES, MAX_RECEIPTS, FILE_TYPES, UPLOAD_WINDOW_MS,
  validateUploadRequest, storagePathOf,
  requestUpload, confirmUpload, removeReceipt, listReceipts, cleanupAbandonedUploads,
};

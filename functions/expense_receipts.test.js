'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const x = require('./expenses');
const r = require('./expense_receipts');

const now = 'TS';
const NOW = new Date('2026-11-15T10:00:00Z');
const T = {};
const PDF = Buffer.from('%PDF-1.4 hello');
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
const JPG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0]);

const env = (extra = {}) => {
  const db = fakeDb({
    'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
    'schools/sA/branches/b1': { name: 'Main' },
    'schools/sA/branches/b2': { name: 'Second' },
    'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
    'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
    'users/ba2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
    'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
    'users/fin2': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
    'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
    ...extra,
  });
  const objects = new Map();
  const deleted = [];
  const storage = {
    stat: async (p) => (objects.has(p) ? { exists: true, size: objects.get(p).bytes.length, contentType: objects.get(p).contentType } : { exists: false }),
    head: async (p, n) => objects.get(p).bytes.subarray(0, n),
    deleteFile: async (p) => { deleted.push(p); objects.delete(p); },
  };
  const ctx = { db, now, wall: () => NOW, nowDate: () => NOW, storage };
  return { db, ctx, objects, deleted };
};
const draft = async (ctx, uid = 'fin') => {
  await x.listExpenseCategories(ctx, 'owner', T, { schoolId: 'sA' });
  return (await x.createExpense(ctx, uid, T, { schoolId: 'sA', branchId: 'b1', expense: { categoryId: 'cat_other', amountMinor: 5000, expenseDate: '2026-11-10' } })).result.id;
};
const base = (expenseId, o = {}) => ({ schoolId: 'sA', branchId: 'b1', expenseId, ...o });
const spec = (o = {}) => ({ fileName: 'bill.pdf', contentType: 'application/pdf', sizeBytes: PDF.length, ...o });
const request = (ctx, uid, id, o = {}, rec = {}) => r.requestUpload(ctx, uid, T, base(id, { receipt: spec(rec), ...o }));
const put = (env_, path, bytes, contentType) => env_.objects.set(path, { bytes, contentType });
const fullFlow = async (e, id, uid = 'fin', bytes = PDF, contentType = 'application/pdf', extra = {}) => {
  const q = await request(e.ctx, uid, id, extra, { contentType, sizeBytes: bytes.length });
  put(e, q.result.storagePath, bytes, contentType);
  const c = await r.confirmUpload(e.ctx, uid, T, base(id, { receiptId: q.result.id }));
  return { q, c };
};

test('validateUploadRequest: type, size and name', () => {
  assert.ok(r.validateUploadRequest(spec()).value);
  for (const bad of [{ contentType: 'image/webp' }, { contentType: 'text/html' }, { contentType: 'application/x-msdownload' }, { sizeBytes: 0 }, { sizeBytes: 5 * 1024 * 1024 + 1 }, { sizeBytes: 1.5 }, { fileName: '' }, { fileName: 'a/b.pdf' }, { fileName: '..\\x.pdf' }, { fileName: 'x'.repeat(121) }]) {
    assert.ok(r.validateUploadRequest(spec(bad)).errors, JSON.stringify(bad));
  }
  assert.ok(r.validateUploadRequest(spec({ sizeBytes: 5 * 1024 * 1024 })).value, 'exactly 5 MB is allowed');
  assert.ok(r.validateUploadRequest(null).errors);
});

test('the storage path is fixed by the server: tenant, expense, receipt id and extension by type', () => {
  assert.equal(r.storagePathOf('sA', 'b1', 'e1', 'r1', 'image/jpeg'), 'schools/sA/branches/b1/expenseReceipts/e1/r1/receipt.jpg');
  assert.equal(r.storagePathOf('sA', 'b1', 'e1', 'r1', 'application/pdf'), 'schools/sA/branches/b1/expenseReceipts/e1/r1/receipt.pdf');
});

test('the happy path: request, upload, confirm; the expense counts it and the list returns it', async () => {
  const e = env();
  const id = await draft(e.ctx);
  const { q, c } = await fullFlow(e, id);
  assert.equal(q.result.status, 'UPLOADING');
  assert.match(q.result.storagePath, new RegExp(`^schools/sA/branches/b1/expenseReceipts/${id}/[^/]+/receipt\\.pdf$`));
  assert.equal(c.result.status, 'UPLOADED');
  assert.equal(e.db.store.get(`schools/sA/branches/b1/expenses/${id}`).receiptCount, 1);
  assert.equal((await x.getExpense(e.ctx, 'fin', T, base(id))).result.expense.receiptCount, 1);
  const list = await r.listReceipts(e.ctx, 'ba1', T, base(id));
  assert.deepEqual(list.result.receipts.map((v) => [v.fileName, v.contentType, v.sizeBytes]), [['bill.pdf', 'application/pdf', PDF.length]]);
  assert.equal(list.result.receipts[0].storagePath, q.result.storagePath);
  assert.equal(e.db.store.get(`schools/sA/branches/b1/expenses/${id}`).version, 1, 'a receipt does not change the expense version');
});

test('confirm is idempotent and a repeated request id returns the first upload', async () => {
  const e = env();
  const id = await draft(e.ctx);
  const a = await request(e.ctx, 'fin', id, { requestId: 'req-12345678' });
  const b = await request(e.ctx, 'fin', id, { requestId: 'req-12345678' });
  assert.equal(b.result.id, a.result.id);
  assert.equal(b.result.duplicate, true);
  put(e, a.result.storagePath, PDF, 'application/pdf');
  await r.confirmUpload(e.ctx, 'fin', T, base(id, { receiptId: a.result.id }));
  await r.confirmUpload(e.ctx, 'fin', T, base(id, { receiptId: a.result.id }));
  assert.equal(e.db.store.get(`schools/sA/branches/b1/expenses/${id}`).receiptCount, 1, 'a second confirm does not count twice');
  assert.equal((await request(e.ctx, 'fin2', id, { requestId: 'req-12345678' })).error, 'PERMISSION_DENIED', "another person cannot reuse someone's request id");
  assert.equal((await request(e.ctx, 'fin', id, { requestId: 'short' })).error, 'INVALID_ARGUMENT');
});

test('who may attach: the creator or an admin of the branch; never another finance user, a teacher or another branch', async () => {
  const e = env();
  const id = await draft(e.ctx, 'fin');
  assert.equal((await request(e.ctx, 'fin2', id)).error, 'PERMISSION_DENIED');
  assert.equal((await request(e.ctx, 'teacher', id)).error, 'PERMISSION_DENIED');
  assert.equal((await request(e.ctx, 'ba2', id)).error, 'PERMISSION_DENIED');
  assert.ok((await request(e.ctx, 'ba1', id)).result.id);
  assert.ok((await request(e.ctx, 'owner', id)).result.id);
  assert.equal((await r.requestUpload(e.ctx, 'fin', T, { schoolId: 'sA', branchId: '../x', expenseId: id, receipt: spec() })).error, 'PERMISSION_DENIED');
  assert.equal((await r.requestUpload(e.ctx, 'fin', T, base('../x', { receipt: spec() }))).error, 'PERMISSION_DENIED');
  assert.equal((await request(e.ctx, 'fin', 'ghost')).error, 'NOT_FOUND');
  const mine = await request(e.ctx, 'fin', id);
  assert.equal((await r.confirmUpload(e.ctx, 'fin2', T, base(id, { receiptId: mine.result.id }))).error, 'PERMISSION_DENIED', "another finance user cannot confirm someone else's upload");
});

test('only a draft takes receipts', async () => {
  const e = env();
  const id = await draft(e.ctx);
  const { q } = await fullFlow(e, id);
  const key = `schools/sA/branches/b1/expenses/${id}`;
  e.db.store.set(key, { ...e.db.store.get(key), status: 'SUBMITTED' });
  assert.equal((await request(e.ctx, 'fin', id)).error, 'FAILED_PRECONDITION');
  assert.equal((await r.removeReceipt(e.ctx, 'fin', T, base(id, { receiptId: q.result.id }))).error, 'FAILED_PRECONDITION');
});

test('at most three receipts; an expired unconfirmed upload does not count', async () => {
  const e = env();
  const id = await draft(e.ctx);
  for (let i = 0; i < 3; i++) await fullFlow(e, id);
  assert.equal((await request(e.ctx, 'fin', id)).error, 'FAILED_PRECONDITION');
  const e2 = env();
  const id2 = await draft(e2.ctx);
  const stale = await request(e2.ctx, 'fin', id2);
  for (let i = 0; i < 2; i++) await fullFlow(e2, id2);
  const key = `schools/sA/branches/b1/expenseReceipts/${stale.result.id}`;
  e2.db.store.set(key, { ...e2.db.store.get(key), expiresAt: new Date(NOW.getTime() - 1000) });
  assert.ok((await request(e2.ctx, 'fin', id2)).result.id, 'the stale upload no longer holds a slot');
});

test('confirm refuses what was not really uploaded: missing, wrong size, wrong type, and a file that is not what it claims', async () => {
  const e = env();
  const id = await draft(e.ctx);
  const q1 = await request(e.ctx, 'fin', id);
  assert.equal((await r.confirmUpload(e.ctx, 'fin', T, base(id, { receiptId: q1.result.id }))).error, 'FAILED_PRECONDITION', 'nothing was uploaded');
  put(e, q1.result.storagePath, Buffer.from('%PDF-1.4 hello but longer'), 'application/pdf');
  const wrongSize = await r.confirmUpload(e.ctx, 'fin', T, base(id, { receiptId: q1.result.id }));
  assert.equal(wrongSize.error, 'FAILED_PRECONDITION');
  assert.deepEqual(e.deleted, [q1.result.storagePath], 'the mismatching object is deleted');
  assert.equal(e.db.store.get(`schools/sA/branches/b1/expenseReceipts/${q1.result.id}`).status, 'ABANDONED');
  // a PDF that is really an HTML page
  const html = Buffer.from('<html><script>alert(1)</script></html>');
  const q2 = await request(e.ctx, 'fin', id, {}, { sizeBytes: html.length });
  put(e, q2.result.storagePath, html, 'application/pdf');
  const fake = await r.confirmUpload(e.ctx, 'fin', T, base(id, { receiptId: q2.result.id }));
  assert.match(fake.reason, /not a valid PDF or image/);
  // a declared PNG that is a JPEG
  const q3 = await request(e.ctx, 'fin', id, {}, { contentType: 'image/png', sizeBytes: JPG.length, fileName: 'x.png' });
  put(e, q3.result.storagePath, JPG, 'image/png');
  assert.equal((await r.confirmUpload(e.ctx, 'fin', T, base(id, { receiptId: q3.result.id }))).error, 'FAILED_PRECONDITION');
  assert.equal(e.db.store.get(`schools/sA/branches/b1/expenses/${id}`).receiptCount || 0, 0, 'none of them counted');
  assert.equal((await r.confirmUpload(e.ctx, 'fin', T, base(id, { receiptId: q1.result.id }))).error, 'FAILED_PRECONDITION', 'an abandoned upload cannot be confirmed later');
  assert.equal((await r.confirmUpload(e.ctx, 'fin', T, base(id, { receiptId: 'ghost' }))).error, 'NOT_FOUND');
  const other = await draft(e.ctx, 'fin');
  assert.equal((await r.confirmUpload(e.ctx, 'fin', T, base(other, { receiptId: q1.result.id }))).error, 'NOT_FOUND', "a receipt of another expense is not found");
});

test('real images and PDFs of each allowed type pass', async () => {
  const e = env();
  const id = await draft(e.ctx);
  assert.equal((await fullFlow(e, id, 'fin', PNG, 'image/png')).c.result.status, 'UPLOADED');
  assert.equal((await fullFlow(e, id, 'fin', JPG, 'image/jpeg')).c.result.status, 'UPLOADED');
  assert.equal(e.db.store.get(`schools/sA/branches/b1/expenses/${id}`).receiptCount, 2);
});

test('remove: marks the receipt removed, keeps the record and the file, drops the count; the list hides it', async () => {
  const e = env();
  const id = await draft(e.ctx);
  const { q } = await fullFlow(e, id);
  assert.equal((await r.removeReceipt(e.ctx, 'fin2', T, base(id, { receiptId: q.result.id }))).error, 'PERMISSION_DENIED');
  assert.equal((await r.removeReceipt(e.ctx, 'fin', T, base(id, { receiptId: q.result.id }))).result.status, 'REMOVED');
  const rec = e.db.store.get(`schools/sA/branches/b1/expenseReceipts/${q.result.id}`);
  assert.equal(rec.status, 'REMOVED');
  assert.equal(e.deleted.length, 0, 'the stored file is kept');
  assert.equal(e.db.store.get(`schools/sA/branches/b1/expenses/${id}`).receiptCount, 0);
  assert.deepEqual((await r.listReceipts(e.ctx, 'fin', T, base(id))).result.receipts, []);
  assert.equal((await r.removeReceipt(e.ctx, 'fin', T, base(id, { receiptId: q.result.id }))).error, 'FAILED_PRECONDITION', 'twice');
  assert.equal((await r.removeReceipt(e.ctx, 'fin', T, base(id, { receiptId: 'ghost' }))).error, 'NOT_FOUND');
  assert.equal((await r.removeReceipt(e.ctx, 'fin', T, base(id, { receiptId: '../x' }))).error, 'NOT_FOUND');
});

test('list: anyone who can see expenses in that branch, nobody else', async () => {
  const e = env();
  const id = await draft(e.ctx);
  await fullFlow(e, id);
  for (const uid of ['fin', 'fin2', 'ba1', 'owner']) assert.equal((await r.listReceipts(e.ctx, uid, T, base(id))).result.receipts.length, 1, uid);
  for (const uid of ['teacher', 'ba2']) assert.equal((await r.listReceipts(e.ctx, uid, T, base(id))).error, 'PERMISSION_DENIED', uid);
});

test('the module switch and school state apply', async () => {
  const e = env({ 'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'UTC', features: { expenses: false } } });
  assert.equal((await r.requestUpload(e.ctx, 'owner', T, base('x', { receipt: spec() }))).error, 'PERMISSION_DENIED');
});

test('the daily cleanup abandons only stale unconfirmed uploads and deletes their objects', async () => {
  const e = env();
  const id = await draft(e.ctx);
  const done = await fullFlow(e, id);
  const stale = await request(e.ctx, 'fin', id);
  const fresh = await request(e.ctx, 'fin', id);
  put(e, stale.result.storagePath, PDF, 'application/pdf');
  const key = (rid) => `schools/sA/branches/b1/expenseReceipts/${rid}`;
  e.db.store.set(key(stale.result.id), { ...e.db.store.get(key(stale.result.id)), expiresAt: new Date(NOW.getTime() - 1000) });
  const out = await r.cleanupAbandonedUploads({ db: e.db, storage: e.ctx.storage, now: () => NOW }, { at: NOW });
  assert.deepEqual(out, { abandoned: 1 });
  assert.equal(e.db.store.get(key(stale.result.id)).status, 'ABANDONED');
  assert.equal(e.db.store.get(key(fresh.result.id)).status, 'UPLOADING');
  assert.equal(e.db.store.get(key(done.q.result.id)).status, 'UPLOADED');
  assert.ok(e.deleted.includes(stale.result.storagePath));
  assert.ok(!e.deleted.includes(done.q.result.storagePath), 'a confirmed receipt is never touched');
});

test('the receipt callables and the cleanup job are wired', () => {
  const m = require('./index.js');
  for (const n of ['requestExpenseReceiptUpload', 'confirmExpenseReceiptUpload', 'removeExpenseReceipt', 'listExpenseReceipts']) assert.ok(m[n], n);
  assert.ok(m.masterScheduler, 'masterScheduler');
  assert.ok(require('./scheduled_jobs').PLAN.some((t) => t.name === 'expenseReceiptCleanup' && t.cadence === 'daily'), 'cleanup runs daily');
});

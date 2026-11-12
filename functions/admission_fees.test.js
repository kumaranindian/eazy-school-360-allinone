'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const a = require('./admission');
const f = require('./admission_fees');

const now = new Date('2026-11-07T10:00:00Z');
const wall = () => now;
const ctx = (db) => ({ db, now, wall });
const seed = () => ({
  'schools/sA': { name: 'A', timezone: 'Asia/Kolkata', currency: 'INR' },
  'schools/sA/branches/b1': { name: 'Main' },
  'schools/sA/branches/b1/academicYears/ay1': { name: '2026-27', startDate: new Date('2026-04-01T00:00:00Z') },
  'schools/sA/branches/b1/feeStructures/adm1': { status: 'ACTIVE', category: 'ADMISSION', amountMinor: 50000 },
  'schools/sA/branches/b1/feeStructures/tut1': { status: 'ACTIVE', category: 'TUITION', amountMinor: 90000 },
  'schools/sA/branches/b1/feeStructures/old1': { status: 'INACTIVE', category: 'ADMISSION', amountMinor: 10000 },
  'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1 },
  'users/adminA': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/branch1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
});
const input = { student: { firstName: 'Asha', lastName: 'Nair' }, academicYearId: 'ay1', interestedClassId: 'c1', source: 'Walk-in', guardians: [{ name: 'Meena', phone: '9876543210' }] };
const base = (id, over = {}) => ({ schoolId: 'sA', branchId: 'b1', enquiryId: id, ...over });

async function setup() {
  const db = fakeDb(seed());
  const made = await a.createEnquiry(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiry: input });
  return { db, id: made.result.id };
}
const branch = (db) => db.collection('schools').doc('sA').collection('branches').doc('b1');
const fee = (db, id, cat = 'APPLICATION') => branch(db).collection('admissionFees').doc(`${id}__${cat}`).get().then((s) => s.data());

test('statusOf and balance follow the money', () => {
  assert.equal(f.statusOf({ amountMinor: 1000 }), 'DUE');
  assert.equal(f.statusOf({ amountMinor: 1000, paidMinor: 400 }), 'PARTIAL');
  assert.equal(f.statusOf({ amountMinor: 1000, paidMinor: 1000 }), 'PAID');
  assert.equal(f.statusOf({ amountMinor: 1000, paidMinor: 1000, refundedMinor: 1000 }), 'DUE');
  assert.equal(f.statusOf({ amountMinor: 1000, waivedMinor: 1000 }), 'WAIVED');
  assert.equal(f.statusOf({ amountMinor: 1000, cancelled: true }), 'CANCELLED');
  assert.equal(f.balanceOf({ amountMinor: 1000, paidMinor: 300, waivedMinor: 100 }), 600);
  assert.deepEqual(f.summarize([{ amountMinor: 1000, paidMinor: 300 }, { amountMinor: 500, status: 'CANCELLED' }]).balanceMinor, 700);
});

test('set a fee: from a structure, manual, and the amount rules', async () => {
  const { db, id } = await setup();
  const r = await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'ADMISSION', feeStructureId: 'adm1' }));
  assert.equal(r.result.created, true);
  assert.equal((await fee(db, id, 'ADMISSION')).amountMinor, 50000);
  assert.equal((await fee(db, id, 'ADMISSION')).currency, 'INR');
  for (const bad of [{ amountMinor: 0 }, { amountMinor: 1.5 }, { amountMinor: -5 }, {}, { feeStructureId: 'tut1' }, { feeStructureId: 'old1' }, { feeStructureId: 'missing' }, { category: 'X', amountMinor: 5 }]) {
    const out = await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', ...bad }));
    assert.ok(out.error, JSON.stringify(bad));
  }
  assert.equal((await f.setAdmissionFee(ctx(db), 'teacher1', undefined, base(id, { category: 'APPLICATION', amountMinor: 100 }))).error, 'PERMISSION_DENIED');
});

test('a payment issues a receipt number from the shared series, is idempotent, and caps at the balance', async () => {
  const { db, id } = await setup();
  await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', amountMinor: 1000 }));
  const pay = (over) => f.recordAdmissionFeePayment(ctx(db), 'branch1', undefined, base(id, { category: 'APPLICATION', requestId: 'req-00000001', amountMinor: 400, method: 'CASH', ...over }));
  const p1 = await pay();
  assert.equal(p1.result.receiptNumber, 'RCT-2026-000001');
  const again = await pay();
  assert.equal(again.result.duplicate, true);
  assert.equal(again.result.receiptNumber, 'RCT-2026-000001');
  assert.equal((await fee(db, id)).paidMinor, 400);
  assert.equal((await fee(db, id)).status, 'PARTIAL');
  const p2 = await pay({ requestId: 'req-00000002', amountMinor: 600 });
  assert.equal(p2.result.receiptNumber, 'RCT-2026-000002');
  assert.equal((await fee(db, id)).status, 'PAID');
  assert.equal((await pay({ requestId: 'req-00000003', amountMinor: 1 })).error, 'INVALID_ARGUMENT');
  const counter = (await branch(db).collection('feeCounters').doc('receipt_ay1').get()).data();
  assert.equal(counter.last, 2);
  assert.ok((await branch(db).collection('receiptNumbers').doc('RCT-2026-000002').get()).exists);
});

test('payment validation: method reference, future date, bad request id, unknown fee', async () => {
  const { db, id } = await setup();
  await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', amountMinor: 1000 }));
  const pay = (over) => f.recordAdmissionFeePayment(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', requestId: 'req-00000009', amountMinor: 100, method: 'CASH', ...over }));
  assert.equal((await pay({ method: 'UPI' })).error, 'INVALID_ARGUMENT');
  assert.equal((await pay({ method: 'BITCOIN' })).error, 'INVALID_ARGUMENT');
  assert.equal((await pay({ paymentDate: '2030-01-01' })).error, 'INVALID_ARGUMENT');
  assert.equal((await pay({ requestId: 'x' })).error, 'INVALID_ARGUMENT');
  assert.equal((await pay({ category: 'REGISTRATION' })).error, 'NOT_FOUND');
  assert.equal((await pay({ method: 'UPI', referenceNo: 'UTR1' })).result.duplicate, false);
});

test('concurrent payments never reuse a receipt number', async () => {
  const { db, id } = await setup();
  await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', amountMinor: 10000 }));
  const out = await Promise.all([1, 2, 3, 4].map((n) => f.recordAdmissionFeePayment(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', requestId: `req-0000000${n}`, amountMinor: 100, method: 'CASH' }))));
  const numbers = out.map((o) => o.result.receiptNumber);
  assert.equal(new Set(numbers).size, 4);
  assert.equal((await fee(db, id)).paidMinor, 400);
});

test('refund: school admin only, bounded by what is held, idempotent; the balance reopens', async () => {
  const { db, id } = await setup();
  await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', amountMinor: 1000 }));
  await f.recordAdmissionFeePayment(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', requestId: 'req-00000001', amountMinor: 1000, method: 'CASH' }));
  const refund = (uid, over) => f.refundAdmissionFee(ctx(db), uid, undefined, base(id, { category: 'APPLICATION', requestId: 'ref-00000001', amountMinor: 400, method: 'CASH', reason: 'withdrawn', ...over }));
  assert.equal((await refund('branch1')).error, 'PERMISSION_DENIED');
  assert.equal((await refund('adminA', { amountMinor: 1001 })).error, 'FAILED_PRECONDITION');
  assert.equal((await refund('adminA', { reason: '' })).error, 'INVALID_ARGUMENT');
  assert.equal((await refund('adminA')).result.duplicate, false);
  assert.equal((await refund('adminA')).result.duplicate, true);
  const cur = await fee(db, id);
  assert.equal(cur.refundedMinor, 400);
  assert.equal(cur.status, 'PARTIAL');
});

test('waive and cancel: waiving needs the school admin; cancelling needs nothing held', async () => {
  const { db, id } = await setup();
  await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'REGISTRATION', amountMinor: 1000 }));
  const w = (uid) => f.waiveAdmissionFee(ctx(db), uid, undefined, base(id, { category: 'REGISTRATION', reason: 'staff child' }));
  assert.equal((await w('branch1')).error, 'PERMISSION_DENIED');
  assert.equal((await w('adminA')).result.waivedMinor, 1000);
  assert.equal((await fee(db, id, 'REGISTRATION')).status, 'WAIVED');
  await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'CONFIRMATION', amountMinor: 500 }));
  await f.recordAdmissionFeePayment(ctx(db), 'adminA', undefined, base(id, { category: 'CONFIRMATION', requestId: 'req-00000001', amountMinor: 500, method: 'CASH' }));
  assert.equal((await f.cancelAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'CONFIRMATION', reason: 'oops' }))).error, 'FAILED_PRECONDITION');
  await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', amountMinor: 500 }));
  assert.equal((await f.cancelAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', reason: 'not needed' }))).result.duplicate, false);
  assert.equal((await fee(db, id)).status, 'CANCELLED');
  assert.equal((await f.recordAdmissionFeePayment(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', requestId: 'req-00000009', amountMinor: 1, method: 'CASH' }))).error, 'FAILED_PRECONDITION');
});

test('the amount cannot drop below what is paid; closed enquiries take no new fees or payments', async () => {
  const { db, id } = await setup();
  await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', amountMinor: 1000 }));
  await f.recordAdmissionFeePayment(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', requestId: 'req-00000001', amountMinor: 600, method: 'CASH' }));
  assert.equal((await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', amountMinor: 500 }))).error, 'FAILED_PRECONDITION');
  assert.equal((await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', amountMinor: 800 }))).result.created, false);
  await a.changeEnquiryStatus(ctx(db), 'adminA', undefined, base(id, { status: 'NOT_INTERESTED' }));
  assert.equal((await f.recordAdmissionFeePayment(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', requestId: 'req-00000002', amountMinor: 10, method: 'CASH' }))).error, 'FAILED_PRECONDITION');
  assert.equal((await f.setAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'REGISTRATION', amountMinor: 10 }))).error, 'FAILED_PRECONDITION');
  // a refund is still possible after closing
  assert.equal((await f.refundAdmissionFee(ctx(db), 'adminA', undefined, base(id, { category: 'APPLICATION', requestId: 'ref-00000001', amountMinor: 600, method: 'CASH', reason: 'closed' }))).result.duplicate, false);
});

test('another school or branch cannot touch the fee', async () => {
  const { db, id } = await setup();
  const out = await f.setAdmissionFee(ctx(db), 'adminA', undefined, { schoolId: 'sB', branchId: 'b1', enquiryId: id, category: 'APPLICATION', amountMinor: 5 });
  assert.equal(out.error, 'PERMISSION_DENIED');
});

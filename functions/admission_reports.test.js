'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const a = require('./admission');
const r = require('./admission_reports');

const now = new Date('2026-11-07T10:00:00Z');
const ctx = (db) => ({ db, now, wall: () => now });
const enq = (b, id, over = {}) => [`schools/sA/branches/${b}/admissionEnquiries/${id}`, { schoolId: 'sA', branchId: b, status: 'NEW', source: 'Walk-in', interestedClassId: 'c1', academicYearId: 'ay1', enquiryDate: '2026-10-05', assignedTo: null, studentName: 'SECRET NAME', primaryPhone: '9999999999', remarks: 'SECRET REMARK', ...over }];
const seed = () => Object.fromEntries([
  ['schools/sA', { name: 'A', timezone: 'Asia/Kolkata', currency: 'INR' }],
  ['schools/sA/branches/b1', { name: 'Main' }],
  ['schools/sA/branches/b2', { name: 'Second' }],
  ['schools/sA/admissionSettings/config', { ...a.DEFAULT_SETTINGS, enabled: true, version: 1 }],
  ['users/owner', { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN', name: 'Owner' }],
  ['users/ba1', { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN', name: 'Branch One' }],
  ['users/ba2', { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'BRANCH_ADMIN', name: 'Branch Two' }],
  ['users/teacher', { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' }],
  ['users/staff1', { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN', name: 'Ravi' }],
  enq('b1', 'e1', { status: 'ADMISSION_CONFIRMED', source: 'Website', assignedTo: 'staff1' }),
  enq('b1', 'e2', { status: 'NOT_INTERESTED', statusReason: 'Fees too high', source: 'Website' }),
  enq('b1', 'e3', { status: 'REJECTED', statusReason: 'fees too high ', interestedClassId: 'c2' }),
  enq('b1', 'e4', { status: 'INTERESTED', enquiryDate: '2026-11-02', assignedTo: 'staff1' }),
  enq('b1', 'e5', { status: 'WITHDRAWN', statusReason: 'Moved city', academicYearId: 'ay2' }),
  enq('b2', 'f1', { status: 'ADMISSION_CONFIRMED', source: 'Referral' }),
  enq('b2', 'f2', { status: 'NEW', source: 'Referral' }),
  ['schools/sA/branches/b1/academicYears/ay1/classes/c1', { name: 'Class One' }],
  ['schools/sA/branches/b1/academicYears/ay1/classes/c2', { name: 'Class Two' }],
  ['schools/sA/branches/b1/admissionActivities/a1', { enquiryId: 'e4', status: 'SCHEDULED', scheduledDate: '2026-11-01' }],
  ['schools/sA/branches/b1/admissionActivities/a2', { enquiryId: 'e4', status: 'COMPLETED', scheduledDate: '2026-10-20' }],
  ['schools/sA/branches/b1/admissionActivities/a3', { enquiryId: 'e1', status: 'CANCELLED', scheduledDate: '2026-10-20' }],
  ['schools/sA/branches/b1/admissionActivities/a4', { enquiryId: 'e4', status: 'SCHEDULED', scheduledDate: '2026-11-20' }],
  ['schools/sA/branches/b1/admissionFees/e1__APPLICATION', { enquiryId: 'e1', category: 'APPLICATION', amountMinor: 1000, paidMinor: 1000, refundedMinor: 0, waivedMinor: 0, status: 'PAID' }],
  ['schools/sA/branches/b1/admissionFees/e4__APPLICATION', { enquiryId: 'e4', category: 'APPLICATION', amountMinor: 1000, paidMinor: 300, refundedMinor: 100, waivedMinor: 0, status: 'PARTIAL' }],
  ['schools/sA/branches/b1/admissionFees/e4__REGISTRATION', { enquiryId: 'e4', category: 'REGISTRATION', amountMinor: 500, paidMinor: 0, refundedMinor: 0, waivedMinor: 0, status: 'CANCELLED' }],
  ['schools/sA/branches/b2/admissionFees/f1__ADMISSION', { enquiryId: 'f1', category: 'ADMISSION', amountMinor: 5000, paidMinor: 2000, refundedMinor: 0, waivedMinor: 0, status: 'PARTIAL' }],
]);
const run = (db, uid, data) => r.getAdmissionReport(ctx(db), uid, undefined, { schoolId: 'sA', ...data });

test('a branch report: counts, conversion, sources, classes, months, staff', async () => {
  const { result: x } = await run(fakeDb(seed()), 'ba1', { branchId: 'b1' });
  assert.equal(x.total, 5);
  assert.equal(x.scope, 'BRANCH');
  assert.deepEqual(x.conversion, { confirmed: 1, total: 5, ratePercent: 20 });
  assert.equal(x.byStatus.NOT_INTERESTED, 1);
  assert.deepEqual(x.bySource.find((s) => s.source === 'Website'), { source: 'Website', count: 2, confirmed: 1, ratePercent: 50 });
  assert.equal(x.byClass.find((c) => c.classId === 'c2').count, 1);
  assert.deepEqual(x.byMonth.map((m) => [m.month, m.count]), [['2026-10', 4], ['2026-11', 1]]);
  assert.deepEqual(x.byAssignee.find((s) => s.userId === 'staff1'), { userId: 'staff1', name: 'Ravi', count: 2, confirmed: 1, ratePercent: 50 });
  assert.equal(x.byAssignee.find((s) => s.userId === null).name, 'Unassigned');
});

test('class names are resolved on the server', async () => {
  const { result: x } = await run(fakeDb(seed()), 'ba1', { branchId: 'b1' });
  assert.deepEqual(x.classNames, { c1: 'Class One', c2: 'Class Two' });
});

test('lost enquiries: by kind, with reasons grouped case-insensitively', async () => {
  const { result: x } = await run(fakeDb(seed()), 'ba1', { branchId: 'b1' });
  assert.equal(x.lost.total, 3);
  assert.equal(x.lost.NOT_INTERESTED, 1);
  assert.deepEqual(x.lost.reasons[0], { reason: 'fees too high', count: 2 });
  assert.deepEqual(x.lost.reasons[1], { reason: 'moved city', count: 1 });
});

test('follow-up performance counts only the filtered enquiries', async () => {
  const { result: x } = await run(fakeDb(seed()), 'ba1', { branchId: 'b1' });
  assert.deepEqual(x.followUps, { total: 4, completed: 1, cancelled: 1, open: 2, overdueOpen: 1, completionRatePercent: 25 });
});

test('fees: net of refunds, cancelled fees ignored, per category', async () => {
  const { result: x } = await run(fakeDb(seed()), 'ba1', { branchId: 'b1' });
  assert.equal(x.fees.currency, 'INR');
  assert.equal(x.fees.amountMinor, 2000);
  assert.equal(x.fees.netPaidMinor, 1200);
  assert.equal(x.fees.balanceMinor, 800);
  assert.deepEqual(x.fees.byCategory, [{ category: 'APPLICATION', amountMinor: 2000, netPaidMinor: 1200, balanceMinor: 800 }]);
});

test('the school report covers every branch, with a per-branch table', async () => {
  const { result: x } = await run(fakeDb(seed()), 'owner', { branchId: null });
  assert.equal(x.scope, 'SCHOOL');
  assert.equal(x.total, 7);
  assert.deepEqual(x.byBranch.map((b) => [b.name, b.count, b.confirmed]), [['Main', 5, 1], ['Second', 2, 1]]);
  assert.equal(x.fees.amountMinor, 7000);
  assert.equal(x.conversion.ratePercent, 28.6);
});

test('filters: academic year and enquiry date range', async () => {
  const db = fakeDb(seed());
  assert.equal((await run(db, 'ba1', { branchId: 'b1', academicYearId: 'ay2' })).result.total, 1);
  assert.equal((await run(db, 'ba1', { branchId: 'b1', from: '2026-11-01' })).result.total, 1);
  assert.equal((await run(db, 'ba1', { branchId: 'b1', to: '2026-10-31' })).result.total, 4);
  assert.equal((await run(db, 'ba1', { branchId: 'b1', from: '2026-10-05', to: '2026-10-05' })).result.total, 4);
  assert.equal((await run(db, 'ba1', { branchId: 'b1', from: '2027-01-01' })).result.total, 0);
});

test('invalid filters are refused', async () => {
  const db = fakeDb(seed());
  for (const bad of [{ from: 'x' }, { to: '2026-13-45' }, { from: '2026-11-02', to: '2026-11-01' }, { academicYearId: '../x' }]) {
    assert.equal((await run(db, 'owner', { branchId: 'b1', ...bad })).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
});

test('who may see what: branch admins their branch only; teachers and other schools nothing; all-branches is for the school admin', async () => {
  const db = fakeDb(seed());
  assert.equal((await run(db, 'ba2', { branchId: 'b1' })).error, 'PERMISSION_DENIED');
  assert.equal((await run(db, 'ba1', { branchId: null })).error, 'PERMISSION_DENIED');
  assert.equal((await run(db, 'teacher', { branchId: 'b1' })).error, 'PERMISSION_DENIED');
  assert.equal((await r.getAdmissionReport(ctx(db), 'owner', undefined, { schoolId: 'sB', branchId: 'b1' })).error, 'PERMISSION_DENIED');
  assert.ok((await run(db, 'owner', { branchId: 'b2' })).result);
});

test('only aggregates leave: no names, phones or remarks', async () => {
  const text = JSON.stringify((await run(fakeDb(seed()), 'owner', { branchId: null })).result);
  for (const secret of ['SECRET NAME', '9999999999', 'SECRET REMARK']) assert.equal(text.includes(secret), false, secret);
});

test('an empty branch gives zeros, not errors; admissions off is refused', async () => {
  const s = seed();
  for (const k of Object.keys(s)) if (k.includes('/admission') && !k.includes('Settings')) delete s[k];
  const { result: x } = await run(fakeDb(s), 'owner', { branchId: 'b1' });
  assert.equal(x.total, 0);
  assert.equal(x.conversion.ratePercent, 0);
  assert.equal(x.followUps.completionRatePercent, 0);
  const off = seed();
  off['schools/sA/admissionSettings/config'] = { ...a.DEFAULT_SETTINGS, enabled: false };
  assert.equal((await run(fakeDb(off), 'owner', { branchId: 'b1' })).error, 'FAILED_PRECONDITION');
});

test('a scan cut short says so, and the totals are of what was read', async () => {
  const db = fakeDb(seed());
  const cut = (await r.getAdmissionReport({ ...ctx(db), maxEnquiries: 3 }, 'owner', undefined, { schoolId: 'sA', branchId: 'b1' })).result;
  assert.equal(cut.truncated, true);
  assert.equal(cut.total, 3);
  assert.equal((await run(db, 'owner', { branchId: 'b1' })).result.truncated, false);
});

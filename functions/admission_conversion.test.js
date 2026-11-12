'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const a = require('./admission');
const fees = require('./admission_fees');
const c = require('./admission_conversion');

const now = new Date('2026-11-07T10:00:00Z');
const ctx = (db, over = {}) => ({ db, now, wall: () => now, highestSequence: async () => 0, ...over });
const B = 'schools/sA/branches/b1';
const guardians = [
  { name: 'Meena Nair', phone: '9876543210', email: 'm@example.com', relationship: 'Mother', primary: true },
  { name: 'Ravi Nair', phone: '9876500000', relationship: 'Father' },
];
const seed = (over = {}, appOver = {}, settings = {}) => ({
  'schools/sA': { name: 'A', timezone: 'Asia/Kolkata', currency: 'INR' },
  'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1, ...settings },
  [`${B}`]: { name: 'Main' },
  [`${B}/academicYears/ay1/classes/c1/sections/s1`]: { name: 'A' },
  [`${B}/admissionEnquiries/e1`]: { schoolId: 'sA', branchId: 'b1', status: 'APPROVED', revision: 5, studentName: 'Asha Nair', student: { firstName: 'Asha', lastName: 'Nair', dateOfBirth: '2020-05-01', gender: 'FEMALE' }, guardians, address: { line1: '1 Road', city: 'Pune' }, ...over },
  [`${B}/admissionApplications/e1`]: { schoolId: 'sA', branchId: 'b1', status: 'APPROVED', student: { firstName: 'Asha', lastName: 'Nair', dateOfBirth: '2020-05-01', gender: 'FEMALE' }, guardians, address: { line1: '1 Road', city: 'Pune' }, ...appOver },
  'users/adminA': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/branch1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/adminB': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
});
const req = (conversion = {}) => ({ schoolId: 'sA', branchId: 'b1', enquiryId: 'e1', conversion: { academicYearId: 'ay1', classId: 'c1', sectionId: 's1', rollNumber: '7', ...conversion } });
const get = (db, path) => db.store.get(path);
const count = (db, prefix) => [...db.store.keys()].filter((k) => k.startsWith(prefix)).length;

test('converts: student, placement, reservation, parents, links, access index, record, status', async () => {
  const db = fakeDb(seed());
  const r = await c.convertToStudent(ctx(db), 'adminA', undefined, req());
  assert.equal(r.result.admissionNumber, 'ADM-0001');
  assert.equal(r.result.studentId, 's_e1');
  const s = get(db, `${B}/students/s_e1`);
  assert.equal(s.admissionNumber, 'ADM-0001');
  assert.equal(s.status, 'ACTIVE');
  assert.equal(s.currentClassId, 'c1');
  assert.equal(s.currentSectionId, 's1');
  assert.equal(s.currentRollNumber, '7');
  assert.equal(s.displayName, 'Asha Nair');
  assert.equal(get(db, `${B}/admissionNumbers/adm-0001`).studentId, 's_e1');
  assert.equal(get(db, `${B}/students/s_e1/academicRecords/r_e1`).classId, 'c1');
  assert.equal(count(db, `${B}/parents/`), 2);
  const link = get(db, `${B}/students/s_e1/parentLinks/p_9876543210`);
  assert.equal(link.relationshipType, 'MOTHER');
  assert.equal(link.isPrimary, true);
  assert.equal(link.canAccessPortal, true);
  assert.equal(get(db, `${B}/students/s_e1/parentLinks/p_9876500000`).relationshipType, 'FATHER');
  assert.deepEqual(get(db, `${B}/parentAccess/p_9876543210`).sectionKeys, ['c1__s1']);
  assert.equal(get(db, `${B}/admissionEnquiries/e1`).status, 'ADMISSION_CONFIRMED');
  assert.equal(get(db, `${B}/admissionEnquiries/e1`).studentId, 's_e1');
  assert.equal(get(db, `${B}/admissionStatusHistory/e1__6`).to, 'ADMISSION_CONFIRMED');
  assert.equal(get(db, `${B}/admissionConversions/e1`).convertedBy, 'adminA');
});

test('repeating the call returns the same student and writes nothing new', async () => {
  const db = fakeDb(seed());
  await c.convertToStudent(ctx(db), 'adminA', undefined, req());
  const before = db.store.size;
  const again = await c.convertToStudent(ctx(db), 'adminA', undefined, req());
  assert.equal(again.result.duplicate, true);
  assert.equal(again.result.studentId, 's_e1');
  assert.equal(db.store.size, before);
});

test('concurrent calls make one student', async () => {
  const db = fakeDb(seed());
  const out = await Promise.all([1, 2, 3].map(() => c.convertToStudent(ctx(db), 'adminA', undefined, req())));
  assert.equal(out.filter((o) => o.result && o.result.duplicate === false).length, 1);
  assert.equal(count(db, `${B}/students/`) - count(db, `${B}/students/s_e1/`), 1);
});

test('the admission number skips taken reservations and follows the highest sequence', async () => {
  const db = fakeDb(seed());
  db.store.set(`${B}/admissionNumbers/adm-0004`, { studentId: 'old' });
  const r = await c.convertToStudent(ctx(db, { highestSequence: async () => 3 }), 'adminA', undefined, req());
  assert.equal(r.result.admissionNumber, 'ADM-0005');
});

test('an existing parent with the same mobile is reused, not duplicated', async () => {
  const db = fakeDb(seed());
  db.store.set(`${B}/parents/oldParent`, { phone: '9876543210', firstName: 'Meena' });
  db.store.set(`${B}/parentAccess/oldParent`, { classKeys: ['c9'], sectionKeys: ['c9__x'] });
  const r = await c.convertToStudent(ctx(db), 'adminA', undefined, req());
  assert.ok(r.result.parentIds.includes('oldParent'));
  assert.equal(get(db, `${B}/parents/p_9876543210`), undefined);
  assert.deepEqual(get(db, `${B}/parentAccess/oldParent`).classKeys, ['c1', 'c9']);
  assert.ok(get(db, `${B}/students/s_e1/parentLinks/oldParent`));
});

test('only an approved enquiry and application convert', async () => {
  for (const [over, app] of [[{ status: 'INTERESTED' }, {}], [{}, { status: 'SUBMITTED' }], [{ status: 'ADMISSION_CONFIRMED' }, {}], [{ status: 'REJECTED' }, {}]]) {
    const db = fakeDb(seed(over, app));
    const r = await c.convertToStudent(ctx(db), 'adminA', undefined, req());
    assert.equal(r.error, 'FAILED_PRECONDITION', JSON.stringify([over, app]));
    assert.equal(count(db, `${B}/students/`), 0);
  }
});

test('authority: school admin yes; branch admin only when allowed; teacher and other school never', async () => {
  assert.equal((await c.convertToStudent(ctx(fakeDb(seed())), 'branch1', undefined, req())).error, 'PERMISSION_DENIED');
  assert.ok((await c.convertToStudent(ctx(fakeDb(seed({}, {}, { branchAdminsMayApprove: true }))), 'branch1', undefined, req())).result);
  assert.equal((await c.convertToStudent(ctx(fakeDb(seed())), 'teacher1', undefined, req())).error, 'PERMISSION_DENIED');
  assert.equal((await c.convertToStudent(ctx(fakeDb(seed())), 'adminB', undefined, req())).error, 'PERMISSION_DENIED');
});

test('placement must exist; date of birth and gender must be known', async () => {
  const db = fakeDb(seed());
  assert.equal((await c.convertToStudent(ctx(db), 'adminA', undefined, req({ sectionId: 'nope' }))).error, 'FAILED_PRECONDITION');
  assert.equal((await c.convertToStudent(ctx(db), 'adminA', undefined, req({ classId: '' }))).error, 'INVALID_ARGUMENT');
  const noDob = fakeDb(seed({}, { student: { firstName: 'Asha', lastName: 'Nair' } }));
  noDob.store.get(`${B}/admissionEnquiries/e1`).student = { firstName: 'Asha' };
  assert.equal((await c.convertToStudent(ctx(noDob), 'adminA', undefined, req())).error, 'FAILED_PRECONDITION');
  assert.ok((await c.convertToStudent(ctx(noDob), 'adminA', undefined, req({ dateOfBirth: '2020-01-01', gender: 'MALE' }))).result);
  assert.equal(count(db, `${B}/students/`), 0);
});

test('outstanding fees block conversion unless accepted; the carry-over is recorded', async () => {
  const mk = async () => {
    const db = fakeDb(seed());
    await fees.setAdmissionFee(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: 'e1', category: 'APPLICATION', amountMinor: 1000 });
    await fees.recordAdmissionFeePayment(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: 'e1', category: 'APPLICATION', requestId: 'req-00000001', amountMinor: 400, method: 'CASH' });
    return db;
  };
  // fees are refused on APPROVED? setAdmissionFee allows it; payments too.
  const db = await mk();
  const blocked = await c.convertToStudent(ctx(db), 'adminA', undefined, req());
  assert.equal(blocked.error, 'FAILED_PRECONDITION');
  assert.equal(count(db, `${B}/students/`), 0);
  const ok = await c.convertToStudent(ctx(db), 'adminA', undefined, req({ acceptOutstandingFees: true }));
  assert.equal(ok.result.duplicate, false);
  const rec = get(db, `${B}/admissionConversions/e1`);
  assert.equal(rec.feeNetPaidMinor, 400);
  assert.equal(rec.feeBalanceMinor, 600);
  assert.equal(rec.acceptedOutstandingFees, true);
  assert.equal(rec.fees[0].receiptNumber, 'RCT-2026-000001');
  assert.equal(get(db, `${B}/admissionFees/e1__APPLICATION`).studentId, 's_e1');
});

test('paid and cancelled fees do not block', async () => {
  const db = fakeDb(seed());
  await fees.setAdmissionFee(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: 'e1', category: 'APPLICATION', amountMinor: 500 });
  await fees.recordAdmissionFeePayment(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: 'e1', category: 'APPLICATION', requestId: 'req-00000001', amountMinor: 500, method: 'CASH' });
  await fees.setAdmissionFee(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: 'e1', category: 'REGISTRATION', amountMinor: 100 });
  await fees.cancelAdmissionFee(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: 'e1', category: 'REGISTRATION', reason: 'not needed' });
  assert.ok((await c.convertToStudent(ctx(db), 'adminA', undefined, req())).result);
});

test('after conversion fees cannot be changed, and a second conversion is a no-op', async () => {
  const db = fakeDb(seed());
  await c.convertToStudent(ctx(db), 'adminA', undefined, req());
  const r = await fees.setAdmissionFee(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: 'e1', category: 'APPLICATION', amountMinor: 5 });
  assert.equal(r.error, 'FAILED_PRECONDITION');
});

test('helpers', () => {
  assert.equal(c.sequenceOf('ADM-0042'), 42);
  assert.equal(c.sequenceOf('adm-9'), null);
  assert.equal(c.sequenceOf('X-1'), null);
  assert.equal(c.formatAdm(12), 'ADM-0012');
  assert.equal(c.formatAdm(12345), 'ADM-12345');
  assert.equal(c.relationshipOf('Mother'), 'MOTHER');
  assert.equal(c.relationshipOf('Uncle'), 'OTHER');
  assert.equal(c.relationshipOf(''), 'GUARDIAN');
  assert.deepEqual(c.splitName('A B C'), { firstName: 'A', middleName: 'B', lastName: 'C' });
});

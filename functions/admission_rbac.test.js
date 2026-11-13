'use strict';
// One table that proves the access rules of EVERY admission callable (phase 13).
// Rows are callables; columns are who calls. A callable added later without a row
// here fails the coverage test at the bottom, so no entry point can be forgotten.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { fakeDb } = require('./test_support');
const a = require('./admission');
const act = require('./admission_activities');
const app = require('./admission_applications');
const fees = require('./admission_fees');
const conv = require('./admission_conversion');
const rep = require('./admission_reports');

const now = new Date('2026-11-07T10:00:00Z');
const ctx = (db) => ({ db, now, wall: () => now, storage: { stat: async () => ({ exists: false }), head: async () => Buffer.alloc(12), deleteFile: async () => {} }, highestSequence: async () => 0 });

const users = {
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/ba2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/baOff': { schoolId: 'sA', branchId: 'b1', status: 'INACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/finance': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  'users/parent': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  'users/otherOwner': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
};
const seed = () => ({
  'schools/sA': { name: 'A', timezone: 'Asia/Kolkata', currency: 'INR' },
  'schools/sA/branches/b1': { name: 'Main' },
  'schools/sA/branches/b2': { name: 'Second' },
  'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1 },
  ...users,
});

const T = { schoolId: 'sA', branchId: 'b1', enquiryId: 'e1' };
// name → [function, payload, who is allowed (the rest are refused), module key for coverage]
const TABLE = [
  ['createEnquiry', a.createEnquiry, { ...T, enquiry: {} }, ['owner', 'ba1']],
  ['updateEnquiry', a.updateEnquiry, { ...T, enquiry: {} }, ['owner', 'ba1']],
  ['assignEnquiry', a.assignEnquiry, { ...T }, ['owner', 'ba1']],
  ['changeEnquiryStatus', a.changeEnquiryStatus, { ...T, status: 'CONTACTED' }, ['owner', 'ba1']],
  ['saveAdmissionSettings', a.saveAdmissionSettings, { schoolId: 'sA', settings: {} }, ['owner']],
  ['scheduleActivity', act.scheduleActivity, { ...T, activity: {} }, ['owner', 'ba1']],
  ['scheduleVisit', act.scheduleVisit, { ...T, visit: {} }, ['owner', 'ba1']],
  ['rescheduleActivity', act.rescheduleActivity, { ...T, activityId: 'x' }, ['owner', 'ba1']],
  ['reassignActivity', act.reassignActivity, { ...T, activityId: 'x' }, ['owner', 'ba1']],
  ['completeActivity', act.completeActivity, { ...T, activityId: 'x' }, ['owner', 'ba1']],
  ['cancelActivity', act.cancelActivity, { ...T, activityId: 'x' }, ['owner', 'ba1']],
  ['createApplication', app.createApplication, { ...T }, ['owner', 'ba1']],
  ['updateApplication', app.updateApplication, { ...T, application: {} }, ['owner', 'ba1']],
  ['submitApplication', app.submitApplication, { ...T }, ['owner', 'ba1']],
  ['reviewApplication', app.reviewApplication, { ...T, action: 'START' }, ['owner', 'ba1']],
  ['decideApplication', app.decideApplication, { ...T, decision: 'APPROVE' }, ['owner']], // branch admins only when the setting is on
  ['requestDocumentUpload', app.requestDocumentUpload, { ...T }, ['owner', 'ba1']],
  ['confirmDocumentUpload', app.confirmDocumentUpload, { ...T, documentId: 'x' }, ['owner', 'ba1']],
  ['verifyDocument', app.verifyDocument, { ...T, documentId: 'x', decision: 'VERIFY' }, ['owner', 'ba1']],
  ['removeDocument', app.removeDocument, { ...T, documentId: 'x' }, ['owner', 'ba1']],
  ['setAdmissionFee', fees.setAdmissionFee, { ...T, category: 'APPLICATION', amountMinor: 5 }, ['owner', 'ba1']],
  ['cancelAdmissionFee', fees.cancelAdmissionFee, { ...T, category: 'APPLICATION', reason: 'abc' }, ['owner', 'ba1']],
  ['waiveAdmissionFee', fees.waiveAdmissionFee, { ...T, category: 'APPLICATION', reason: 'abc' }, ['owner']],
  ['recordAdmissionFeePayment', fees.recordAdmissionFeePayment, { ...T, category: 'APPLICATION', requestId: 'req-rbac-0001', amountMinor: 1, method: 'CASH' }, ['owner', 'ba1', 'finance']],
  ['refundAdmissionFee', fees.refundAdmissionFee, { ...T, category: 'APPLICATION', requestId: 'ref-rbac-0001', amountMinor: 1, method: 'CASH', reason: 'abc' }, ['owner']],
  ['convertToStudent', conv.convertToStudent, { ...T, conversion: {} }, ['owner']], // branch admins only when the setting is on
  ['getAdmissionReport', rep.getAdmissionReport, { schoolId: 'sA', branchId: 'b1' }, ['owner', 'ba1']],
];
const CALLERS = ['owner', 'ba1', 'ba2', 'baOff', 'teacher', 'finance', 'parent', 'otherOwner', 'ghost'];

for (const [name, fn, data, allowed] of TABLE) {
  test(`${name}: allowed for ${allowed.join(', ')}; refused for everyone else`, async () => {
    for (const who of CALLERS) {
      const out = await fn(ctx(fakeDb(seed())), who, undefined, data);
      const denied = out && out.error === 'PERMISSION_DENIED';
      assert.equal(denied, !allowed.includes(who), `${name} as ${who}: ${JSON.stringify(out)}`);
    }
  });
}

test('signed-out callers (no uid) are refused everywhere', async () => {
  for (const [name, fn, data] of TABLE) {
    for (const uid of [undefined, null, '']) {
      let out;
      try { out = await fn(ctx(fakeDb(seed())), uid, undefined, data); } catch (_) { out = { error: 'PERMISSION_DENIED' }; }
      assert.equal(out && out.error, 'PERMISSION_DENIED', `${name} with uid ${JSON.stringify(uid)}`);
    }
  }
});

test('malformed ids cannot be used to reach another tenant', async () => {
  for (const bad of [{ schoolId: '../sB' }, { schoolId: 'sA', branchId: '../b2' }, { schoolId: ['sA'] }, { schoolId: { $ne: 1 } }]) {
    const out = await a.createEnquiry(ctx(fakeDb(seed())), 'owner', undefined, { ...T, enquiry: {}, ...bad });
    assert.ok(out.error === 'PERMISSION_DENIED' || out.error === 'NOT_FOUND' || out.error === 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
});

test('a branch administrator may decide and convert only when the school allows it', async () => {
  const s = seed();
  s['schools/sA/admissionSettings/config'] = { ...a.DEFAULT_SETTINGS, enabled: true, version: 1, branchAdminsMayApprove: true };
  for (const [fn, data] of [[app.decideApplication, { ...T, decision: 'APPROVE' }], [conv.convertToStudent, { ...T, conversion: {} }]]) {
    assert.notEqual((await fn(ctx(fakeDb(s)), 'ba1', undefined, data)).error, 'PERMISSION_DENIED');
    assert.equal((await fn(ctx(fakeDb(s)), 'ba2', undefined, data)).error, 'PERMISSION_DENIED', 'not another branch');
    assert.equal((await fn(ctx(fakeDb(s)), 'teacher', undefined, data)).error, 'PERMISSION_DENIED');
  }
});

test('all-branches reports are for school administrators only', async () => {
  for (const who of CALLERS) {
    const out = await rep.getAdmissionReport(ctx(fakeDb(seed())), who, undefined, { schoolId: 'sA', branchId: null });
    assert.equal(out.error === 'PERMISSION_DENIED', who !== 'owner', who);
  }
});

test('coverage: every exported admission callable has a row in the table', () => {
  const index = fs.readFileSync(path.join(__dirname, 'index.js'), 'utf8');
  const exported = [...index.matchAll(/admissionCall\('(\w+)'/g)].map((m) => m[1]);
  // Name in index.js (…Admission…) → function in the table.
  const alias = {
    saveAdmissionSettings: 'saveAdmissionSettings', createAdmissionEnquiry: 'createEnquiry', updateAdmissionEnquiry: 'updateEnquiry', assignAdmissionEnquiry: 'assignEnquiry',
    changeAdmissionEnquiryStatus: 'changeEnquiryStatus', scheduleAdmissionActivity: 'scheduleActivity', scheduleAdmissionVisit: 'scheduleVisit', rescheduleAdmissionActivity: 'rescheduleActivity',
    reassignAdmissionActivity: 'reassignActivity', completeAdmissionActivity: 'completeActivity', cancelAdmissionActivity: 'cancelActivity', createAdmissionApplication: 'createApplication',
    updateAdmissionApplication: 'updateApplication', submitAdmissionApplication: 'submitApplication', reviewAdmissionApplication: 'reviewApplication', decideAdmissionApplication: 'decideApplication',
    requestAdmissionDocumentUpload: 'requestDocumentUpload', confirmAdmissionDocumentUpload: 'confirmDocumentUpload', verifyAdmissionDocument: 'verifyDocument', removeAdmissionDocument: 'removeDocument',
    setAdmissionFee: 'setAdmissionFee', cancelAdmissionFee: 'cancelAdmissionFee', waiveAdmissionFee: 'waiveAdmissionFee', recordAdmissionFeePayment: 'recordAdmissionFeePayment',
    refundAdmissionFee: 'refundAdmissionFee', convertAdmissionToStudent: 'convertToStudent', getAdmissionReport: 'getAdmissionReport',
  };
  const inTable = new Set(TABLE.map((r) => r[0]));
  assert.ok(exported.length >= 27, `found ${exported.length} admission callables in index.js`);
  for (const name of exported) {
    assert.ok(alias[name], `${name} is exported but not mapped in this test: add it to the table`);
    assert.ok(inTable.has(alias[name]), `${name} has no row in the access table`);
  }
});

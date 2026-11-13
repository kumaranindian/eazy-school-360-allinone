'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const a = require('./admission');

const now = new Date('2026-11-07T10:00:00Z');
const wall = () => new Date('2026-11-07T10:00:00Z');
const seed = (extra = {}) => ({
  'schools/sA': { name: 'A', timezone: 'Asia/Kolkata' },
  'schools/sB': { name: 'B' },
  'schools/sA/branches/b1': { name: 'Main' },
  'schools/sA/branches/b2': { name: 'Second' },
  'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1 },
  'users/adminA': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/adminB': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/branch1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/teacher2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'TEACHER' },
  'users/parentA': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  ...extra,
});
const ctx = (db) => ({ db, now, wall });
const enquiry = (over = {}) => ({
  student: { firstName: 'Asha', lastName: 'Nair', dateOfBirth: '2020-05-01', gender: 'FEMALE' },
  academicYearId: 'ay1',
  interestedClassId: 'c1',
  source: 'Walk-in',
  guardians: [{ name: 'Meena Nair', relationship: 'Mother', phone: '+91 98765 43210', email: 'meena@example.com' }],
  address: { city: 'Kochi' },
  ...over,
});
const create = (db, uid = 'adminA', data = {}, branchId = 'b1') =>
  a.createEnquiry(ctx(db), uid, undefined, { schoolId: 'sA', branchId, enquiry: enquiry(), ...data });
const doc = (db, id) => db.store.get(`schools/sA/branches/b1/admissionEnquiries/${id}`);

// ---- state machine ---------------------------------------------------------

test('every status has a transition entry and only names known statuses', () => {
  for (const s of a.STATUSES) assert.ok(Array.isArray(a.TRANSITIONS[s]), s);
  for (const [from, tos] of Object.entries(a.TRANSITIONS)) {
    for (const to of tos) assert.ok(to === '__RESUME__' || a.STATUSES.includes(to), `${from} -> ${to}`);
  }
});

test('terminal statuses have no way out', () => {
  for (const s of a.TERMINAL) assert.deepStrictEqual(a.TRANSITIONS[s], []);
});

test('the primary lifecycle is a legal path', () => {
  const path = ['NEW', 'CONTACTED', 'INTERESTED', 'VISIT_SCHEDULED', 'VISIT_COMPLETED', 'APPLICATION_SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'ADMISSION_CONFIRMED'];
  for (let i = 0; i < path.length - 1; i++) assert.ok(a.canTransition(path[i], path[i + 1]), `${path[i]} -> ${path[i + 1]}`);
});

test('manual changes are limited to lead stages, and jumps are refused', () => {
  assert.deepStrictEqual(a.resolveManualChange('NEW', 'CONTACTED'), { to: 'CONTACTED' });
  assert.strictEqual(a.resolveManualChange('NEW', 'APPROVED').error, 'FAILED_PRECONDITION');
  assert.strictEqual(a.resolveManualChange('INTERESTED', 'ADMISSION_CONFIRMED').error, 'FAILED_PRECONDITION');
  assert.strictEqual(a.resolveManualChange('NEW', 'VISIT_SCHEDULED').error, 'FAILED_PRECONDITION');
  assert.strictEqual(a.resolveManualChange('REJECTED', 'CONTACTED').error, 'FAILED_PRECONDITION');
  assert.strictEqual(a.resolveManualChange('APPLICATION_SUBMITTED', 'CONTACTED').error, 'FAILED_PRECONDITION');
});

test('rejection and withdrawal need a reason; hold and resume restore the prior status', () => {
  assert.strictEqual(a.resolveManualChange('INTERESTED', 'REJECTED').error, 'INVALID_ARGUMENT');
  assert.strictEqual(a.resolveManualChange('INTERESTED', 'WITHDRAWN', { reason: ' ' }).error, 'INVALID_ARGUMENT');
  assert.deepStrictEqual(a.resolveManualChange('INTERESTED', 'REJECTED', { reason: 'Fees' }), { to: 'REJECTED' });
  assert.deepStrictEqual(a.resolveManualChange('ON_HOLD', 'RESUME', { heldFrom: 'INTERESTED' }), { to: 'INTERESTED', resume: true });
  assert.strictEqual(a.resolveManualChange('NEW', 'RESUME', { heldFrom: 'NEW' }).error, 'FAILED_PRECONDITION');
});

// The same table is pinned in test/admission/admission_domain_test.dart
// (AdmissionStatus.manualOptions): what the UI offers must match this machine.
test('the manual options per status match the table the app offers', () => {
  const alt = ['NOT_INTERESTED', 'ON_HOLD', 'REJECTED', 'WITHDRAWN'];
  const expected = {
    NEW: ['CONTACTED', 'INTERESTED', ...alt],
    CONTACTED: ['INTERESTED', ...alt],
    INTERESTED: alt,
    VISIT_SCHEDULED: ['INTERESTED', ...alt],
    VISIT_COMPLETED: ['INTERESTED', ...alt],
    APPLICATION_SUBMITTED: ['ON_HOLD', 'REJECTED', 'WITHDRAWN'],
    UNDER_REVIEW: ['ON_HOLD', 'REJECTED', 'WITHDRAWN'],
    APPROVED: ['ON_HOLD', 'REJECTED', 'WITHDRAWN'],
    ON_HOLD: ['RESUME', 'NOT_INTERESTED', 'REJECTED', 'WITHDRAWN'],
    NOT_INTERESTED: ['CONTACTED', 'INTERESTED'],
    REJECTED: [],
    WITHDRAWN: [],
    ADMISSION_CONFIRMED: [],
  };
  for (const from of a.STATUSES) {
    const reachable = [];
    for (const to of [...a.MANUAL_TARGETS, 'RESUME']) {
      const r = a.resolveManualChange(from, to, { heldFrom: 'INTERESTED', reason: 'because' });
      if (!r.error) reachable.push(to);
    }
    assert.deepStrictEqual(reachable.sort(), [...expected[from]].sort(), from);
  }
});

// ---- settings --------------------------------------------------------------

test('settings: defaults are valid; bad prefixes, equal prefixes and bad ids are refused', () => {
  assert.ok(a.validateSettings({ enabled: true }).value);
  assert.ok(a.validateSettings({ enquiryPrefix: 'e' }).errors.enquiryPrefix);
  assert.ok(a.validateSettings({ enquiryPrefix: 'ABC', applicationPrefix: 'abc' }).errors.applicationPrefix);
  assert.ok(a.validateSettings({ followUpDays: 0 }).errors.followUpDays);
  assert.ok(a.validateSettings({ classIds: ['ok', 'no good/..'] }).errors.classIds);
  assert.ok(a.validateSettings({ sources: [] }).errors.sources);
});

test('only a school admin saves settings; versions grow; a stale base version is refused', async () => {
  const db = fakeDb(seed());
  const save = (uid, data) => a.saveAdmissionSettings(ctx(db), uid, undefined, { schoolId: 'sA', ...data });
  assert.strictEqual((await save('branch1', { settings: { enabled: true } })).error, 'PERMISSION_DENIED');
  assert.strictEqual((await save('adminB', { settings: { enabled: true } })).error, 'PERMISSION_DENIED');
  assert.strictEqual((await save('teacher1', { settings: { enabled: true } })).error, 'PERMISSION_DENIED');
  const ok = await save('adminA', { settings: { enabled: true, enquiryPrefix: 'enq' }, baseVersion: 1 });
  assert.deepStrictEqual(ok.result, { version: 2 });
  assert.strictEqual(db.store.get('schools/sA/admissionSettings/config').enquiryPrefix, 'ENQ');
  assert.strictEqual((await save('adminA', { settings: { enabled: true }, baseVersion: 1 })).error, 'ABORTED');
  assert.strictEqual((await save('adminA', { settings: { enabled: 'yes' } })).error, 'INVALID_ARGUMENT');
});

// ---- creating enquiries ----------------------------------------------------

test('creates an enquiry with a server number, NEW status, history and normalised phone', async () => {
  const db = fakeDb(seed());
  const r = await create(db);
  assert.strictEqual(r.result.enquiryNumber, 'ENQ-2026-00001');
  const d = doc(db, r.result.id);
  assert.strictEqual(d.status, 'NEW');
  assert.strictEqual(d.primaryPhone, '9876543210');
  assert.strictEqual(d.studentNameLower, 'asha nair');
  assert.strictEqual(d.schoolId, 'sA');
  assert.strictEqual(d.branchId, 'b1');
  assert.strictEqual(d.createdBy, 'adminA');
  assert.strictEqual(d.enquiryDate, '2026-11-07');
  assert.strictEqual(d.revision, 1);
  const h = db.store.get(`schools/sA/branches/b1/admissionStatusHistory/${r.result.id}__1`);
  assert.deepStrictEqual([h.from, h.to, h.actorId], [null, 'NEW', 'adminA']);
});

test('numbers are sequential per branch and year, and never repeat under concurrency', async () => {
  const db = fakeDb(seed());
  const results = await Promise.all(Array.from({ length: 6 }, () => create(db)));
  const numbers = results.map((r) => r.result.enquiryNumber).sort();
  assert.strictEqual(new Set(numbers).size, 6);
  assert.strictEqual(numbers[0], 'ENQ-2026-00001');
  assert.strictEqual(numbers[5], 'ENQ-2026-00006');
  const other = await create(db, 'adminA', {}, 'b2');
  assert.strictEqual(other.result.enquiryNumber, 'ENQ-2026-00001', 'each branch has its own series');
});

test('the enquiry year follows the supplied enquiry date, not a client counter', async () => {
  const db = fakeDb(seed());
  const r = await create(db, 'adminA', { enquiry: enquiry({ enquiryDate: '2025-12-30' }) });
  assert.strictEqual(r.result.enquiryNumber, 'ENQ-2025-00001');
});

test('admissions must be enabled', async () => {
  const db = fakeDb(seed({ 'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: false, version: 1 } }));
  assert.strictEqual((await create(db)).error, 'FAILED_PRECONDITION');
  const none = fakeDb(seed());
  none.store.delete('schools/sA/admissionSettings/config');
  assert.strictEqual((await create(none)).error, 'FAILED_PRECONDITION');
});

test('who may create: school admin and the branch admin of that branch only', async () => {
  const db = fakeDb(seed());
  assert.ok((await create(db, 'adminA')).result);
  assert.ok((await create(db, 'branch1')).result);
  for (const uid of ['teacher1', 'parentA', 'adminB', 'nobody']) {
    assert.strictEqual((await create(db, uid)).error, 'PERMISSION_DENIED', uid);
  }
  assert.strictEqual((await create(db, 'branch1', {}, 'b2')).error, 'PERMISSION_DENIED', 'a branch admin cannot write another branch');
  assert.strictEqual((await a.createEnquiry(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'missing', enquiry: enquiry() })).error, 'NOT_FOUND');
});

test('cross-school: a school admin of B cannot create or change anything in A', async () => {
  const db = fakeDb(seed());
  const made = await create(db);
  const t = (fn, data) => fn(ctx(db), 'adminB', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: made.result.id, ...data });
  assert.strictEqual((await t(a.updateEnquiry, { enquiry: enquiry() })).error, 'PERMISSION_DENIED');
  assert.strictEqual((await t(a.changeEnquiryStatus, { status: 'CONTACTED' })).error, 'PERMISSION_DENIED');
  assert.strictEqual((await t(a.assignEnquiry, { assignedTo: 'teacher1' })).error, 'PERMISSION_DENIED');
  assert.strictEqual(doc(db, made.result.id).status, 'NEW');
});

test('validation: required fields, dates, sources and class/year restrictions', async () => {
  const db = fakeDb(seed({
    'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1, classIds: ['c1'], academicYearIds: ['ay1'] },
  }));
  const bad = async (over) => (await create(db, 'adminA', { enquiry: enquiry(over) })).error;
  assert.strictEqual(await bad({ student: { firstName: '' } }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ student: { firstName: 'A', dateOfBirth: '2099-01-01' } }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ student: { firstName: 'A', dateOfBirth: '2020-02-31' } }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ source: 'Carrier pigeon' }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ interestedClassId: 'c9' }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ academicYearId: 'ay9' }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ guardians: [] }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ guardians: [{ name: 'M', phone: '12' }] }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ guardians: [{ name: 'Meena', phone: '9876543210', email: 'nope' }] }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ nextFollowUpDate: '2020-01-01' }), 'INVALID_ARGUMENT');
  assert.strictEqual(await bad({ enquiryDate: '2099-01-01' }), 'INVALID_ARGUMENT');
  assert.ok((await create(db)).result);
});

test('client-supplied identity fields are ignored: school/branch ids, status, number and audit come from the server', async () => {
  const db = fakeDb(seed());
  const r = await create(db, 'adminA', {
    enquiry: { ...enquiry(), schoolId: 'sB', branchId: 'b2', status: 'APPROVED', enquiryNumber: 'HACK-1', createdBy: 'someoneElse', revision: 99 },
  });
  const d = doc(db, r.result.id);
  assert.deepStrictEqual([d.schoolId, d.branchId, d.status, d.createdBy, d.revision], ['sA', 'b1', 'NEW', 'adminA', 1]);
  assert.notStrictEqual(d.enquiryNumber, 'HACK-1');
});

test('possible duplicates (same mobile, name, date of birth, year) are flagged, never merged or blocked', async () => {
  const db = fakeDb(seed());
  const first = await create(db);
  const second = await create(db, 'adminA', { enquiry: enquiry({ guardians: [{ name: 'Meena', phone: '098765 43210' }] }) });
  assert.deepStrictEqual(second.result.duplicateOf, [first.result.id]);
  assert.ok(doc(db, second.result.id), 'the second enquiry still exists');
  const sameMobileOtherChild = await create(db, 'adminA', { enquiry: enquiry({ student: { firstName: 'Ravi', lastName: 'Nair', dateOfBirth: '2019-01-01' } }) });
  assert.deepStrictEqual(sameMobileOtherChild.result.duplicateOf, []);
});

// ---- editing, assigning, status --------------------------------------------

test('editing keeps number/date, bumps the revision, and rejects stale or closed enquiries', async () => {
  const db = fakeDb(seed());
  const { result } = await create(db);
  const edit = (over = {}, extra = {}) => a.updateEnquiry(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: result.id, enquiry: enquiry(over), ...extra });
  assert.deepStrictEqual((await edit({ remarks: 'Call after 5' })).result, { revision: 2 });
  const d = doc(db, result.id);
  assert.strictEqual(d.remarks, 'Call after 5');
  assert.strictEqual(d.enquiryNumber, 'ENQ-2026-00001');
  assert.strictEqual((await edit({}, { baseRevision: 1 })).error, 'ABORTED');
  await a.changeEnquiryStatus(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: result.id, status: 'WITHDRAWN', reason: 'Moved city' });
  assert.strictEqual((await edit({ remarks: 'x' })).error, 'FAILED_PRECONDITION');
});

test('assignment: only an active member of the branch; unassign with null', async () => {
  const db = fakeDb(seed());
  const { result } = await create(db);
  const assign = (assignedTo) => a.assignEnquiry(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: result.id, assignedTo });
  assert.ok((await assign('teacher1')).result);
  assert.strictEqual(doc(db, result.id).assignedTo, 'teacher1');
  assert.strictEqual((await assign('teacher2')).error, 'INVALID_ARGUMENT', 'a teacher of another branch');
  assert.strictEqual((await assign('parentA')).error, 'INVALID_ARGUMENT', 'a parent');
  assert.strictEqual((await assign('ghost')).error, 'INVALID_ARGUMENT');
  assert.ok((await assign(null)).result);
  assert.strictEqual(doc(db, result.id).assignedTo, null);
});

test('status changes write immutable, ordered history; hold/resume works; jumps are refused', async () => {
  const db = fakeDb(seed());
  const { result } = await create(db);
  const change = (status, extra = {}) => a.changeEnquiryStatus(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: result.id, status, ...extra });
  assert.ok((await change('CONTACTED')).result);
  assert.ok((await change('INTERESTED')).result);
  assert.strictEqual((await change('APPROVED')).error, 'FAILED_PRECONDITION');
  assert.ok((await change('ON_HOLD', { reason: 'Parent travelling' })).result);
  assert.strictEqual(doc(db, result.id).heldFrom, 'INTERESTED');
  assert.strictEqual((await change('CONTACTED')).error, 'FAILED_PRECONDITION', 'must resume, not jump');
  assert.deepStrictEqual((await change('RESUME')).result.status, 'INTERESTED');
  assert.strictEqual((await change('REJECTED')).error, 'INVALID_ARGUMENT');
  assert.ok((await change('REJECTED', { reason: 'Seats full' })).result);
  assert.strictEqual((await change('CONTACTED')).error, 'FAILED_PRECONDITION', 'rejected is final');

  const base = `schools/sA/branches/b1/admissionStatusHistory/${result.id}__`;
  const chain = [1, 2, 3, 4, 5, 6].map((n) => db.store.get(`${base}${n}`)).map((h) => `${h.from}>${h.to}`);
  assert.deepStrictEqual(chain, ['null>NEW', 'NEW>CONTACTED', 'CONTACTED>INTERESTED', 'INTERESTED>ON_HOLD', 'ON_HOLD>INTERESTED', 'INTERESTED>REJECTED']);
  assert.strictEqual(db.store.get(`${base}4`).reason, 'Parent travelling');
  assert.strictEqual(db.store.get(`${base}6`).actorId, 'adminA');
});

test('concurrent status changes: the stale base revision loses with ABORTED', async () => {
  const db = fakeDb(seed());
  const { result } = await create(db);
  const change = (status, baseRevision) => a.changeEnquiryStatus(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: result.id, status, baseRevision });
  assert.ok((await change('CONTACTED', 1)).result);
  assert.strictEqual((await change('INTERESTED', 1)).error, 'ABORTED');
});

test('a branch admin changes status only in their own branch', async () => {
  const db = fakeDb(seed());
  const { result } = await create(db);
  const own = await a.changeEnquiryStatus(ctx(db), 'branch1', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: result.id, status: 'CONTACTED' });
  assert.ok(own.result);
  const other = await a.changeEnquiryStatus(ctx(db), 'branch1', undefined, { schoolId: 'sA', branchId: 'b2', enquiryId: result.id, status: 'INTERESTED' });
  assert.strictEqual(other.error, 'PERMISSION_DENIED');
  const missing = await a.changeEnquiryStatus(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiryId: 'nope', status: 'CONTACTED' });
  assert.strictEqual(missing.error, 'NOT_FOUND');
});

test('formatNumber pads to five digits and grows beyond', () => {
  assert.strictEqual(a.formatNumber('ENQ', 2026, 7), 'ENQ-2026-00007');
  assert.strictEqual(a.formatNumber('APP', 2026, 123456), 'APP-2026-123456');
});

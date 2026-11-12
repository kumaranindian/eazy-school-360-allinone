'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const a = require('./admission');
const f = require('./admission_applications');

const now = new Date('2026-11-07T10:00:00Z');
let clock = new Date('2026-11-07T10:00:00Z');
const wall = () => clock;
const seed = (settings = {}, extra = {}) => ({
  'schools/sA': { name: 'A', timezone: 'Asia/Kolkata' },
  'schools/sB': { name: 'B' },
  'schools/sA/branches/b1': { name: 'Main' },
  'schools/sA/branches/b2': { name: 'Second' },
  'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1, ...settings },
  'users/adminA': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/adminB': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/branch1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/parentA': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  ...extra,
});

// a tiny stand-in for the storage adapter
function fakeStorage() {
  const files = new Map();
  return {
    files,
    stat: async (p) => (files.has(p) ? { exists: true, ...files.get(p) } : { exists: false }),
    deleteFile: async (p) => void files.delete(p),
  };
}
const ctx = (db, storage) => ({ db, now, wall, storage });
const input = (over = {}) => ({
  student: { firstName: 'Asha', lastName: 'Nair', dateOfBirth: '2020-05-01', gender: 'FEMALE' },
  academicYearId: 'ay1',
  interestedClassId: 'c1',
  source: 'Walk-in',
  guardians: [{ name: 'Meena Nair', phone: '9876543210', email: 'm@example.com' }],
  ...over,
});
const base = (id, over = {}) => ({ schoolId: 'sA', branchId: 'b1', enquiryId: id, ...over });

async function setup(settings = {}, status = 'INTERESTED') {
  const db = fakeDb(seed(settings));
  const storage = fakeStorage();
  const made = await a.createEnquiry(ctx(db, storage), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiry: input() });
  const id = made.result.id;
  if (status !== 'NEW') await a.changeEnquiryStatus(ctx(db, storage), 'adminA', undefined, base(id, { status }));
  return { db, storage, id };
}
const C = (db, storage) => ctx(db, storage);
const enquiry = (db, id) => db.store.get(`schools/sA/branches/b1/admissionEnquiries/${id}`);
const app = (db, id) => db.store.get(`schools/sA/branches/b1/admissionApplications/${id}`);
const docOf = (db, id) => db.store.get(`schools/sA/branches/b1/admissionDocuments/${id}`);
const appHist = (db, id) =>
  [...db.store.keys()]
    .filter((k) => k.startsWith(`schools/sA/branches/b1/admissionApplicationHistory/${id}__`))
    .sort((x, y) => Number(x.split('__').pop()) - Number(y.split('__').pop()))
    .map((k) => db.store.get(k));
const create = (db, st, id, uid = 'adminA') => f.createApplication(C(db, st), uid, undefined, base(id));
const submit = (db, st, id, uid = 'adminA', extra = {}) => f.submitApplication(C(db, st), uid, undefined, base(id, extra));
const review = (db, st, id, action = 'START', extra = {}, uid = 'adminA') => f.reviewApplication(C(db, st), uid, undefined, base(id, { action, ...extra }));
const decide = (db, st, id, decision, comment, uid = 'adminA') => f.decideApplication(C(db, st), uid, undefined, base(id, { decision, comment }));
const request = (db, st, id, doc = {}, extra = {}, uid = 'adminA') =>
  f.requestDocumentUpload(C(db, st), uid, undefined, base(id, { document: { type: 'BIRTH_CERTIFICATE', fileName: 'birth.pdf', contentType: 'application/pdf', sizeBytes: 1000, ...doc }, ...extra }));
const confirm = (db, st, id, documentId, uid = 'adminA') => f.confirmDocumentUpload(C(db, st), uid, undefined, base(id, { documentId }));
const verify = (db, st, id, documentId, decision = 'VERIFY', reason, uid = 'adminA') => f.verifyDocument(C(db, st), uid, undefined, base(id, { documentId, decision, reason }));

/** Requests, "uploads" and confirms one document; returns its id. */
async function addDocument(db, st, id, doc = {}) {
  const r = await request(db, st, id, doc);
  assert.ok(r.result, JSON.stringify(r));
  st.files.set(r.result.storagePath, { size: doc.sizeBytes || 1000, contentType: doc.contentType || 'application/pdf' });
  const c = await confirm(db, st, id, r.result.id);
  assert.ok(c.result, JSON.stringify(c));
  return r.result.id;
}
/** Takes an application through submit + start review. */
async function underReview(settings = {}, status = 'INTERESTED') {
  const w = await setup(settings, status);
  await create(w.db, w.storage, w.id);
  await submit(w.db, w.storage, w.id);
  await review(w.db, w.storage, w.id);
  return w;
}

// ---- pure ------------------------------------------------------------------

test('upload validation: type, name, content type, size; photographs must be images', () => {
  const s = a.DEFAULT_SETTINGS;
  const ok = f.validateUploadRequest({ type: 'BIRTH_CERTIFICATE', fileName: 'b.pdf', contentType: 'application/pdf', sizeBytes: 100 }, s);
  assert.deepStrictEqual(ok.value, { type: 'BIRTH_CERTIFICATE', label: 'Birth certificate', fileName: 'b.pdf', contentType: 'application/pdf', sizeBytes: 100 });
  const bad = (over) => f.validateUploadRequest({ type: 'BIRTH_CERTIFICATE', fileName: 'b.pdf', contentType: 'application/pdf', sizeBytes: 100, ...over }, s).errors || {};
  assert.ok(bad({ type: 'PASSPORT' }).type);
  assert.ok(bad({ fileName: '' }).fileName);
  assert.ok(bad({ fileName: '../x.pdf' }).fileName);
  assert.ok(bad({ fileName: 'a\\b.pdf' }).fileName);
  assert.ok(bad({ contentType: 'application/zip' }).contentType);
  assert.ok(bad({ contentType: 'text/html' }).contentType);
  assert.ok(bad({ sizeBytes: 0 }).sizeBytes);
  assert.ok(bad({ sizeBytes: 5 * 1024 * 1024 + 1 }).sizeBytes);
  assert.ok(bad({ sizeBytes: 1.5 }).sizeBytes);
  assert.ok(!bad({ sizeBytes: 5 * 1024 * 1024 }).sizeBytes, '5 MB exactly is allowed');
  assert.ok(bad({ type: 'STUDENT_PHOTO' }).contentType, 'a photograph cannot be a PDF');
  assert.ok(!f.validateUploadRequest({ type: 'STUDENT_PHOTO', fileName: 'p.png', contentType: 'image/png', sizeBytes: 9 }, s).errors);
  const custom = { ...s, customDocumentTypes: [{ id: 'CASTE_CERT', label: 'Caste certificate' }] };
  assert.ok(f.validateUploadRequest({ type: 'CASTE_CERT', fileName: 'c.pdf', contentType: 'application/pdf', sizeBytes: 9 }, custom).value, 'a school-defined type');
});

test('the storage path is tenant-scoped and ends in a fixed, type-derived name', () => {
  assert.strictEqual(f.storagePathOf('sA', 'b1', 'e1', 'd1', 'image/jpeg'), 'schools/sA/branches/b1/admissionDocs/e1/d1/document.jpg');
  assert.strictEqual(f.storagePathOf('sA', 'b1', 'e1', 'd1', 'application/pdf'), 'schools/sA/branches/b1/admissionDocs/e1/d1/document.pdf');
});

test('required documents: which are not yet verified; who may decide', () => {
  const s = { requiredDocumentTypes: ['BIRTH_CERTIFICATE', 'STUDENT_PHOTO'] };
  assert.deepStrictEqual(f.missingRequired(s, []), ['BIRTH_CERTIFICATE', 'STUDENT_PHOTO']);
  assert.deepStrictEqual(f.missingRequired(s, [{ type: 'BIRTH_CERTIFICATE' }]), ['STUDENT_PHOTO']);
  assert.deepStrictEqual(f.missingRequired(s, [{ type: 'BIRTH_CERTIFICATE' }, { type: 'STUDENT_PHOTO' }, { type: 'ADDRESS_PROOF' }]), []);
  assert.deepStrictEqual(f.missingRequired({ requiredDocumentTypes: [] }, []), []);
  assert.ok(f.mayDecide({ role: 'SCHOOL_ADMIN' }, {}));
  assert.ok(!f.mayDecide({ role: 'BRANCH_ADMIN' }, { branchAdminsMayApprove: false }));
  assert.ok(f.mayDecide({ role: 'BRANCH_ADMIN' }, { branchAdminsMayApprove: true }));
  assert.ok(!f.mayDecide({ role: 'TEACHER' }, { branchAdminsMayApprove: true }));
  assert.ok(!f.mayDecide(null, {}));
});

test('settings: document types and the approval switch are validated', () => {
  assert.deepStrictEqual(a.validateSettings({}).value.requiredDocumentTypes, ['BIRTH_CERTIFICATE', 'STUDENT_PHOTO']);
  assert.strictEqual(a.validateSettings({}).value.branchAdminsMayApprove, false);
  const ok = a.validateSettings({ customDocumentTypes: [{ id: 'caste_cert', label: ' Caste certificate ' }], requiredDocumentTypes: ['CASTE_CERT', 'ADDRESS_PROOF'], branchAdminsMayApprove: true });
  assert.deepStrictEqual(ok.value.customDocumentTypes, [{ id: 'CASTE_CERT', label: 'Caste certificate' }]);
  assert.deepStrictEqual(ok.value.requiredDocumentTypes, ['CASTE_CERT', 'ADDRESS_PROOF']);
  assert.ok(a.validateSettings({ requiredDocumentTypes: ['PASSPORT'] }).errors.requiredDocumentTypes);
  assert.ok(a.validateSettings({ customDocumentTypes: [{ id: 'BIRTH_CERTIFICATE', label: 'dup' }] }).errors.customDocumentTypes, 'cannot shadow a built-in');
  assert.ok(a.validateSettings({ customDocumentTypes: [{ id: 'X', label: 'short id' }] }).errors.customDocumentTypes);
  assert.ok(a.validateSettings({ customDocumentTypes: [{ id: 'ABC', label: 'x' }, { id: 'ABC', label: 'dupe id' }] }).errors.customDocumentTypes);
  assert.ok(a.validateSettings({ branchAdminsMayApprove: 'yes' }).errors.branchAdminsMayApprove);
});

// ---- creating and editing --------------------------------------------------

test('an application is started from an interested enquiry with a server number; repeating returns the same one', async () => {
  const { db, storage, id } = await setup();
  const r = await create(db, storage, id);
  assert.deepStrictEqual([r.result.id, r.result.applicationNumber, r.result.duplicate], [id, 'APP-2026-00001', false]);
  const d = app(db, id);
  assert.deepStrictEqual([d.status, d.studentName, d.classId, d.academicYearId, d.schoolId, d.branchId, d.revision, d.createdBy], ['DRAFT', 'Asha Nair', 'c1', 'ay1', 'sA', 'b1', 1, 'adminA']);
  assert.strictEqual(d.guardians[0].phone, '9876543210');
  assert.strictEqual(enquiry(db, id).applicationNumber, 'APP-2026-00001');
  assert.strictEqual(enquiry(db, id).status, 'INTERESTED', 'a draft does not move the enquiry');
  const again = await create(db, storage, id);
  assert.deepStrictEqual([again.result.applicationNumber, again.result.duplicate], ['APP-2026-00001', true]);
  assert.strictEqual(appHist(db, id).length, 1);
});

test('application numbers are consecutive and distinct under concurrency', async () => {
  const db = fakeDb(seed());
  const storage = fakeStorage();
  const ids = [];
  for (let n = 0; n < 4; n++) {
    const made = await a.createEnquiry(ctx(db, storage), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiry: input({ student: { firstName: `Kid${n}`, lastName: 'X', dateOfBirth: '2020-05-01' }, guardians: [{ name: 'Parent X', phone: `98765432${10 + n}` }] }) });
    await a.changeEnquiryStatus(ctx(db, storage), 'adminA', undefined, base(made.result.id, { status: 'INTERESTED' }));
    ids.push(made.result.id);
  }
  const rs = await Promise.all(ids.map((id) => create(db, storage, id)));
  assert.deepStrictEqual(rs.map((r) => r.result.applicationNumber).sort(), ['APP-2026-00001', 'APP-2026-00002', 'APP-2026-00003', 'APP-2026-00004']);
});

test('an application can be started from interested, visit scheduled or visit completed; not from NEW, on hold or closed', async () => {
  for (const status of ['INTERESTED']) assert.ok((await create(...(await (async () => { const w = await setup({}, status); return [w.db, w.storage, w.id]; })()))).result, status);
  for (const [status, extra] of [['NEW', {}], ['CONTACTED', {}], ['ON_HOLD', { reason: 'away' }], ['NOT_INTERESTED', {}], ['WITHDRAWN', { reason: 'moved' }]]) {
    const db = fakeDb(seed());
    const storage = fakeStorage();
    const made = await a.createEnquiry(ctx(db, storage), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiry: input() });
    if (status !== 'NEW') await a.changeEnquiryStatus(ctx(db, storage), 'adminA', undefined, base(made.result.id, { status, ...extra }));
    assert.strictEqual((await create(db, storage, made.result.id)).error, 'FAILED_PRECONDITION', status);
  }
  const visit = await setup({}, 'INTERESTED');
  await require('./admission_activities').scheduleVisit(ctx(visit.db, visit.storage), 'adminA', undefined, base(visit.id, { visit: { purpose: 'CAMPUS_TOUR', scheduledDate: '2026-11-10' } }));
  assert.strictEqual(enquiry(visit.db, visit.id).status, 'VISIT_SCHEDULED');
  assert.ok((await create(visit.db, visit.storage, visit.id)).result, 'a family may apply before the visit');
});

test('who may work on applications: school admin and the branch admin of that branch; module must be on', async () => {
  const { db, storage, id } = await setup();
  for (const uid of ['teacher1', 'parentA', 'adminB', 'nobody']) assert.strictEqual((await create(db, storage, id, uid)).error, 'PERMISSION_DENIED', uid);
  assert.strictEqual((await f.createApplication(C(db, storage), 'branch1', undefined, { schoolId: 'sA', branchId: 'b2', enquiryId: id })).error, 'PERMISSION_DENIED');
  assert.ok((await create(db, storage, id, 'branch1')).result);
  db.store.set('schools/sA/admissionSettings/config', { ...a.DEFAULT_SETTINGS, enabled: false, version: 3 });
  assert.strictEqual((await submit(db, storage, id)).error, 'FAILED_PRECONDITION');
  assert.strictEqual((await create(db, storage, 'missing')).error, 'FAILED_PRECONDITION', 'module off is reported before the lookup');
});

test('editing a draft keeps the enquiry intact; locked after submission; stale revisions and bad input refused', async () => {
  const { db, storage, id } = await setup();
  await create(db, storage, id);
  const edit = (over = {}, extra = {}) => f.updateApplication(C(db, storage), 'adminA', undefined, base(id, { application: input({ submissionNotes: 'Sibling already studies here', ...over }), ...extra }));
  const r = await edit({ student: { firstName: 'Asha', lastName: 'Nair-Menon', dateOfBirth: '2020-05-01' }, previousSchool: 'Tiny Tots' });
  assert.deepStrictEqual(r.result, { revision: 2 });
  const d = app(db, id);
  assert.deepStrictEqual([d.studentName, d.previousSchool, d.submissionNotes], ['Asha Nair-Menon', 'Tiny Tots', 'Sibling already studies here']);
  assert.strictEqual(enquiry(db, id).studentName, 'Asha Nair', 'the enquiry is not rewritten');
  assert.strictEqual((await edit({}, { baseRevision: 1 })).error, 'ABORTED');
  assert.strictEqual((await edit({ student: { firstName: '' } })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await edit({ submissionNotes: 'x'.repeat(1001) })).error, 'INVALID_ARGUMENT');
  await submit(db, storage, id);
  assert.strictEqual((await edit()).error, 'FAILED_PRECONDITION');
});

// ---- submit / review / decide ----------------------------------------------

test('submitting needs the essentials, then moves the application and the enquiry together', async () => {
  const { db, storage, id } = await setup();
  await create(db, storage, id);
  app(db, id).student.dateOfBirth = null;
  const r = await submit(db, storage, id);
  assert.strictEqual(r.error, 'INVALID_ARGUMENT');
  assert.match(r.reason, /date of birth/);
  assert.strictEqual(app(db, id).status, 'DRAFT');
  app(db, id).student.dateOfBirth = '2020-05-01';
  const ok = await submit(db, storage, id);
  assert.strictEqual(ok.result.status, 'SUBMITTED');
  assert.strictEqual(app(db, id).status, 'SUBMITTED');
  assert.ok(app(db, id).submittedAt);
  assert.strictEqual(enquiry(db, id).status, 'APPLICATION_SUBMITTED');
  assert.strictEqual(a.TRANSITIONS.INTERESTED.includes('APPLICATION_SUBMITTED'), true);
  assert.strictEqual((await submit(db, storage, id)).error, 'FAILED_PRECONDITION', 'cannot submit twice');
  const events = appHist(db, id).map((h) => h.event);
  assert.deepStrictEqual(events, ['CREATED', 'SUBMITTED']);
});

test('submitting is refused while the enquiry is on hold (resume first)', async () => {
  const { db, storage, id } = await setup();
  await create(db, storage, id);
  await a.changeEnquiryStatus(C(db, storage), 'adminA', undefined, base(id, { status: 'ON_HOLD', reason: 'Parent away' }));
  assert.strictEqual((await submit(db, storage, id)).error, 'FAILED_PRECONDITION');
  assert.strictEqual(app(db, id).status, 'DRAFT');
});

test('starting review moves both to UNDER_REVIEW; comments are internal history', async () => {
  const { db, storage, id } = await setup();
  await create(db, storage, id);
  assert.strictEqual((await review(db, storage, id)).error, 'FAILED_PRECONDITION', 'not submitted yet');
  assert.strictEqual((await review(db, storage, id, 'COMMENT', { comment: 'Looks fine' })).error, 'FAILED_PRECONDITION', 'comments start at submission');
  await submit(db, storage, id);
  assert.strictEqual((await review(db, storage, id, 'COMMENT', { comment: ' ' })).error, 'INVALID_ARGUMENT');
  assert.ok((await review(db, storage, id, 'COMMENT', { comment: 'Parent called to confirm the class' })).result);
  const r = await review(db, storage, id, 'START', { comment: 'Taking this up' });
  assert.strictEqual(r.result.status, 'UNDER_REVIEW');
  assert.strictEqual(enquiry(db, id).status, 'UNDER_REVIEW');
  assert.strictEqual((await review(db, storage, id, 'START')).error, 'FAILED_PRECONDITION');
  assert.ok((await review(db, storage, id, 'COMMENT', { comment: 'Fees discussed' })).result);
  assert.deepStrictEqual(appHist(db, id).map((h) => h.event), ['CREATED', 'SUBMITTED', 'COMMENTED', 'REVIEW_STARTED', 'COMMENTED']);
  assert.strictEqual(appHist(db, id)[2].comment, 'Parent called to confirm the class');
  assert.strictEqual((await review(db, storage, id, 'JUMP')).error, 'INVALID_ARGUMENT');
});

test('approval needs every required document VERIFIED; then both become APPROVED', async () => {
  const { db, storage, id } = await underReview();
  const refused = await decide(db, storage, id, 'APPROVE');
  assert.strictEqual(refused.error, 'FAILED_PRECONDITION');
  assert.match(refused.reason, /Birth certificate, Student photograph/);
  const birth = await addDocument(db, storage, id, { type: 'BIRTH_CERTIFICATE' });
  const photo = await addDocument(db, storage, id, { type: 'STUDENT_PHOTO', contentType: 'image/jpeg', fileName: 'p.jpg' });
  assert.match((await decide(db, storage, id, 'APPROVE')).reason, /Birth certificate, Student photograph/, 'uploaded is not verified');
  await verify(db, storage, id, birth);
  assert.match((await decide(db, storage, id, 'APPROVE')).reason, /Student photograph/);
  await verify(db, storage, id, photo);
  const r = await decide(db, storage, id, 'APPROVE', 'All in order');
  assert.strictEqual(r.result.status, 'APPROVED');
  assert.strictEqual(app(db, id).status, 'APPROVED');
  assert.deepStrictEqual([app(db, id).decidedBy, app(db, id).decisionComment], ['adminA', 'All in order']);
  assert.strictEqual(enquiry(db, id).status, 'APPROVED');
  assert.strictEqual((await decide(db, storage, id, 'APPROVE')).error, 'FAILED_PRECONDITION', 'decided once');
});

test('what is required is the school\'s choice', async () => {
  const none = await underReview({ requiredDocumentTypes: [] });
  assert.strictEqual((await decide(none.db, none.storage, none.id, 'APPROVE')).result.status, 'APPROVED');
  const custom = await underReview({ customDocumentTypes: [{ id: 'CASTE_CERT', label: 'Caste certificate' }], requiredDocumentTypes: ['CASTE_CERT'] });
  assert.match((await decide(custom.db, custom.storage, custom.id, 'APPROVE')).reason, /Caste certificate/);
  const d = await addDocument(custom.db, custom.storage, custom.id, { type: 'CASTE_CERT' });
  await verify(custom.db, custom.storage, custom.id, d);
  assert.ok((await decide(custom.db, custom.storage, custom.id, 'APPROVE')).result);
});

test('a rejected or removed document does not count; a replacement does', async () => {
  const { db, storage, id } = await underReview({ requiredDocumentTypes: ['BIRTH_CERTIFICATE'] });
  const bad = await addDocument(db, storage, id, { type: 'BIRTH_CERTIFICATE' });
  await verify(db, storage, id, bad, 'REJECT', 'Blurred');
  assert.match((await decide(db, storage, id, 'APPROVE')).reason, /Birth certificate/);
  const good = await addDocument(db, storage, id, { type: 'BIRTH_CERTIFICATE', fileName: 'birth2.pdf' });
  await verify(db, storage, id, good);
  assert.ok((await decide(db, storage, id, 'APPROVE')).result);
});

test('rejecting needs a reason, closes the enquiry and its follow-ups, and the application', async () => {
  const { db, storage, id } = await underReview();
  const fu = await require('./admission_activities').scheduleActivity(C(db, storage), 'adminA', undefined, base(id, { activity: { type: 'PHONE_CALL', scheduledDate: '2026-11-10' } }));
  assert.strictEqual((await decide(db, storage, id, 'REJECT', ' ')).error, 'INVALID_ARGUMENT');
  const r = await decide(db, storage, id, 'REJECT', 'Documents do not match the application');
  assert.strictEqual(r.result.status, 'REJECTED');
  assert.strictEqual(app(db, id).status, 'REJECTED');
  const e = enquiry(db, id);
  assert.deepStrictEqual([e.status, e.statusReason, e.openActivityCount, e.nextFollowUpDate], ['REJECTED', 'Documents do not match the application', 0, null]);
  assert.strictEqual(db.store.get(`schools/sA/branches/b1/admissionActivities/${fu.result.id}`).status, 'CANCELLED');
});

test('deciding: school admin always; branch admin only when the school allows it; nobody else; only under review', async () => {
  const off = await underReview();
  assert.strictEqual((await decide(off.db, off.storage, off.id, 'REJECT', 'No seats', 'branch1')).error, 'PERMISSION_DENIED');
  for (const uid of ['teacher1', 'parentA', 'adminB']) assert.strictEqual((await decide(off.db, off.storage, off.id, 'REJECT', 'No seats', uid)).error, 'PERMISSION_DENIED', uid);
  assert.strictEqual(app(off.db, off.id).status, 'UNDER_REVIEW');
  const on = await underReview({ branchAdminsMayApprove: true, requiredDocumentTypes: [] });
  assert.strictEqual((await decide(on.db, on.storage, on.id, 'APPROVE', '', 'branch1')).result.status, 'APPROVED');
  const early = await setup({ requiredDocumentTypes: [] });
  await create(early.db, early.storage, early.id);
  assert.strictEqual((await decide(early.db, early.storage, early.id, 'APPROVE')).error, 'FAILED_PRECONDITION', 'a draft cannot be decided');
});

test('closing the enquiry by hand withdraws (or rejects) its open application, keeping the record', async () => {
  const w = await setup();
  await create(w.db, w.storage, w.id);
  await a.changeEnquiryStatus(C(w.db, w.storage), 'adminA', undefined, base(w.id, { status: 'WITHDRAWN', reason: 'Moved city' }));
  assert.strictEqual(app(w.db, w.id).status, 'WITHDRAWN');
  assert.strictEqual(app(w.db, w.id).decisionComment, 'Moved city');
  assert.deepStrictEqual(appHist(w.db, w.id).map((h) => h.event), ['CREATED', 'CLOSED_WITH_ENQUIRY']);

  const r = await underReview();
  await a.changeEnquiryStatus(C(r.db, r.storage), 'adminA', undefined, base(r.id, { status: 'REJECTED', reason: 'Seats full' }));
  assert.strictEqual(app(r.db, r.id).status, 'REJECTED');
  const ap = await underReview({ requiredDocumentTypes: [] });
  await decide(ap.db, ap.storage, ap.id, 'APPROVE');
  await a.changeEnquiryStatus(C(ap.db, ap.storage), 'adminA', undefined, base(ap.id, { status: 'WITHDRAWN', reason: 'Joined elsewhere' }));
  assert.strictEqual(app(ap.db, ap.id).status, 'WITHDRAWN', 'an approved application follows a withdrawal');
  const none = await setup();
  assert.ok((await a.changeEnquiryStatus(C(none.db, none.storage), 'adminA', undefined, base(none.id, { status: 'REJECTED', reason: 'x y z' }))).result, 'an enquiry with no application still closes');
});

test('the lifecycle allows applying from VISIT_SCHEDULED, and still not by hand', () => {
  assert.ok(a.canTransition('VISIT_SCHEDULED', 'APPLICATION_SUBMITTED'));
  assert.strictEqual(a.resolveManualChange('INTERESTED', 'APPLICATION_SUBMITTED').error, 'FAILED_PRECONDITION');
});

// ---- documents -------------------------------------------------------------

test('requesting an upload records an UPLOADING document with a tenant path, a deadline and the declared size', async () => {
  const { db, storage, id } = await setup();
  await create(db, storage, id);
  const r = await request(db, storage, id, { sizeBytes: 2048 });
  assert.strictEqual(r.result.status, 'UPLOADING');
  assert.strictEqual(r.result.storagePath, `schools/sA/branches/b1/admissionDocs/${id}/${r.result.id}/document.pdf`);
  const d = docOf(db, r.result.id);
  assert.deepStrictEqual([d.status, d.type, d.sizeBytes, d.contentType, d.enquiryId, d.schoolId, d.branchId, d.createdBy], ['UPLOADING', 'BIRTH_CERTIFICATE', 2048, 'application/pdf', id, 'sA', 'b1', 'adminA']);
  assert.ok(d.expiresAt.getTime() > clock.getTime());
});

test('documents need an application, and only while it is open', async () => {
  const { db, storage, id } = await setup();
  assert.strictEqual((await request(db, storage, id)).error, 'NOT_FOUND', 'no application yet');
  await create(db, storage, id);
  assert.ok((await request(db, storage, id)).result);
  await a.changeEnquiryStatus(C(db, storage), 'adminA', undefined, base(id, { status: 'WITHDRAWN', reason: 'Moved city' }));
  assert.strictEqual((await request(db, storage, id)).error, 'FAILED_PRECONDITION');
});

test('upload requests: bad input, roles, tenant, idempotent key, and a cap on documents', async () => {
  const { db, storage, id } = await setup();
  await create(db, storage, id);
  assert.strictEqual((await request(db, storage, id, { contentType: 'application/x-msdownload' })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await request(db, storage, id, { sizeBytes: 6 * 1024 * 1024 })).error, 'INVALID_ARGUMENT');
  for (const uid of ['teacher1', 'parentA', 'adminB']) assert.strictEqual((await request(db, storage, id, {}, {}, uid)).error, 'PERMISSION_DENIED', uid);
  assert.strictEqual((await f.requestDocumentUpload(C(db, storage), 'branch1', undefined, { schoolId: 'sA', branchId: 'b2', enquiryId: id, document: { type: 'BIRTH_CERTIFICATE', fileName: 'a.pdf', contentType: 'application/pdf', sizeBytes: 5 } })).error, 'PERMISSION_DENIED');
  const one = await request(db, storage, id, {}, { requestId: 'req-doc-0001' });
  const two = await request(db, storage, id, {}, { requestId: 'req-doc-0001' });
  assert.strictEqual(one.result.id, two.result.id);
  assert.strictEqual(two.result.duplicate, true);
  assert.strictEqual((await request(db, storage, id, {}, { requestId: 'bad id' })).error, 'INVALID_ARGUMENT');
  for (let n = 0; n < 39; n++) assert.ok((await request(db, storage, id)).result);
  assert.strictEqual((await request(db, storage, id)).error, 'FAILED_PRECONDITION', 'the 41st is refused');
});

test('confirming checks what is really stored: missing, wrong size and wrong type are all refused', async () => {
  const { db, storage, id } = await setup();
  await create(db, storage, id);
  const r = await request(db, storage, id, { sizeBytes: 500 });
  const missing = await confirm(db, storage, id, r.result.id);
  assert.strictEqual(missing.error, 'FAILED_PRECONDITION');
  assert.strictEqual(docOf(db, r.result.id).status, 'UPLOADING', 'a missing file can still be uploaded');

  storage.files.set(r.result.storagePath, { size: 501, contentType: 'application/pdf' });
  assert.strictEqual((await confirm(db, storage, id, r.result.id)).error, 'FAILED_PRECONDITION');
  assert.strictEqual(docOf(db, r.result.id).status, 'ABANDONED');
  assert.ok(!storage.files.has(r.result.storagePath), 'the mismatching object is deleted');

  const r2 = await request(db, storage, id, { sizeBytes: 500 });
  storage.files.set(r2.result.storagePath, { size: 500, contentType: 'image/png' });
  assert.strictEqual((await confirm(db, storage, id, r2.result.id)).error, 'FAILED_PRECONDITION');
  assert.ok(!storage.files.has(r2.result.storagePath));

  const r3 = await request(db, storage, id, { sizeBytes: 500 });
  storage.files.set(r3.result.storagePath, { size: 500, contentType: 'application/pdf' });
  const ok = await confirm(db, storage, id, r3.result.id);
  assert.deepStrictEqual([ok.result.status, docOf(db, r3.result.id).status], ['UPLOADED', 'UPLOADED']);
  assert.ok(docOf(db, r3.result.id).uploadedAt);
  assert.strictEqual((await confirm(db, storage, id, r3.result.id)).result.status, 'UPLOADED', 'confirming again is harmless');
  assert.strictEqual((await confirm(db, storage, id, r.result.id)).error, 'FAILED_PRECONDITION', 'an abandoned upload cannot be revived');
  assert.strictEqual((await confirm(db, storage, id, 'nope')).error, 'NOT_FOUND');
  assert.strictEqual((await confirm(db, storage, id, '../x')).error, 'NOT_FOUND');
});

test('a document belongs to one enquiry: it cannot be confirmed or verified through another', async () => {
  const w = await setup();
  await create(w.db, w.storage, w.id);
  const made = await a.createEnquiry(C(w.db, w.storage), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiry: input({ student: { firstName: 'Ravi', lastName: 'Menon', dateOfBirth: '2019-01-01' }, guardians: [{ name: 'X Menon', phone: '9123456780' }] }) });
  await a.changeEnquiryStatus(C(w.db, w.storage), 'adminA', undefined, base(made.result.id, { status: 'INTERESTED' }));
  await create(w.db, w.storage, made.result.id);
  const d = await addDocument(w.db, w.storage, w.id);
  assert.strictEqual((await verify(w.db, w.storage, made.result.id, d)).error, 'NOT_FOUND');
  assert.strictEqual(docOf(w.db, d).status, 'UPLOADED');
});

test('verifying: an uploaded document is verified or rejected (reason required); the verifier and time are recorded', async () => {
  const { db, storage, id } = await underReview();
  const d = await addDocument(db, storage, id);
  assert.strictEqual((await verify(db, storage, id, d, 'REJECT', '')).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await verify(db, storage, id, d, 'MAYBE')).error, 'INVALID_ARGUMENT');
  const ok = await verify(db, storage, id, d, 'VERIFY');
  assert.strictEqual(ok.result.status, 'VERIFIED');
  const x = docOf(db, d);
  assert.deepStrictEqual([x.status, x.verifiedBy, x.rejectionReason], ['VERIFIED', 'adminA', null]);
  assert.ok(x.verifiedAt);
  assert.strictEqual((await verify(db, storage, id, d, 'VERIFY')).error, 'FAILED_PRECONDITION', 'decided once');
  const bad = await addDocument(db, storage, id, { type: 'ADDRESS_PROOF', fileName: 'a.pdf' });
  await verify(db, storage, id, bad, 'REJECT', 'Not legible');
  assert.deepStrictEqual([docOf(db, bad).status, docOf(db, bad).rejectionReason], ['REJECTED', 'Not legible']);
  const events = appHist(db, id).filter((h) => h.event.startsWith('DOCUMENT_')).map((h) => `${h.event}:${h.documentType}`);
  assert.deepStrictEqual(events, ['DOCUMENT_UPLOADED:BIRTH_CERTIFICATE', 'DOCUMENT_VERIFIED:BIRTH_CERTIFICATE', 'DOCUMENT_UPLOADED:ADDRESS_PROOF', 'DOCUMENT_REJECTED:ADDRESS_PROOF']);
  const roles = await verify(db, storage, id, bad, 'VERIFY', undefined, 'teacher1');
  assert.strictEqual(roles.error, 'PERMISSION_DENIED');
});

test('an UPLOADING document cannot be verified; a stale revision loses', async () => {
  const { db, storage, id } = await underReview();
  const r = await request(db, storage, id);
  assert.strictEqual((await verify(db, storage, id, r.result.id)).error, 'FAILED_PRECONDITION');
  const d = await addDocument(db, storage, id);
  const stale = await f.verifyDocument(C(db, storage), 'adminA', undefined, base(id, { documentId: d, decision: 'VERIFY', baseRevision: 1 }));
  assert.strictEqual(stale.error, 'ABORTED');
});

test('removing a document keeps the record and the stored file, and it stops counting', async () => {
  const { db, storage, id } = await underReview({ requiredDocumentTypes: ['BIRTH_CERTIFICATE'] });
  const d = await addDocument(db, storage, id);
  await verify(db, storage, id, d);
  const path = docOf(db, d).storagePath;
  const rm = await f.removeDocument(C(db, storage), 'adminA', undefined, base(id, { documentId: d, reason: 'Wrong child' }));
  assert.strictEqual(rm.result.status, 'REMOVED');
  assert.strictEqual(docOf(db, d).status, 'REMOVED');
  assert.ok(storage.files.has(path), 'the object is kept for the record');
  assert.match((await decide(db, storage, id, 'APPROVE')).reason, /Birth certificate/);
  assert.strictEqual((await f.removeDocument(C(db, storage), 'adminA', undefined, base(id, { documentId: d }))).error, 'FAILED_PRECONDITION');
  const up = await request(db, storage, id);
  assert.strictEqual((await f.removeDocument(C(db, storage), 'adminA', undefined, base(id, { documentId: up.result.id }))).error, 'FAILED_PRECONDITION', 'an upload in flight is not removable');
});

test('after approval documents are frozen', async () => {
  const { db, storage, id } = await underReview({ requiredDocumentTypes: [] });
  const d = await addDocument(db, storage, id);
  await decide(db, storage, id, 'APPROVE');
  assert.strictEqual((await request(db, storage, id)).error, 'FAILED_PRECONDITION');
  assert.strictEqual((await verify(db, storage, id, d)).error, 'FAILED_PRECONDITION');
  assert.strictEqual((await f.removeDocument(C(db, storage), 'adminA', undefined, base(id, { documentId: d }))).error, 'FAILED_PRECONDITION');
});

// ---- abandoned uploads -----------------------------------------------------

test('uploads never confirmed are abandoned after the window and their object removed; finished ones are untouched', async () => {
  const { db, storage, id } = await underReview();
  const stale = await request(db, storage, id, {}, { requestId: 'stale-upload-1' });
  storage.files.set(stale.result.storagePath, { size: 1000, contentType: 'application/pdf' });
  const fresh = await request(db, storage, id, {}, { requestId: 'fresh-upload-1' });
  const done = await addDocument(db, storage, id, { type: 'ADDRESS_PROOF', fileName: 'a.pdf' });
  clock = new Date(clock.getTime() + 23 * 60 * 60 * 1000);
  assert.deepStrictEqual(await f.cleanupAbandonedUploads({ db, storage, now: () => now }, { at: clock }), { abandoned: 0 }, 'inside the window');
  await request(db, storage, id, {}, { requestId: 'late-upload-01' });
  clock = new Date(clock.getTime() + 2 * 60 * 60 * 1000);
  const r = await f.cleanupAbandonedUploads({ db, storage, now: () => now }, { at: clock });
  assert.strictEqual(r.abandoned >= 2, true);
  assert.strictEqual(docOf(db, stale.result.id).status, 'ABANDONED');
  assert.ok(!storage.files.has(stale.result.storagePath));
  assert.strictEqual(docOf(db, fresh.result.id).status, 'ABANDONED');
  assert.strictEqual(docOf(db, done).status, 'UPLOADED', 'a confirmed upload is never cleaned');
  assert.strictEqual((await f.cleanupAbandonedUploads({ db, storage, now: () => now }, { at: clock })).abandoned, 0, 'idempotent');
  clock = new Date('2026-11-07T10:00:00Z');
});

test('one failing branch or object does not stop the cleanup of the others', async () => {
  const { db, storage, id } = await underReview();
  const r = await request(db, storage, id, {}, { requestId: 'stale-upload-2' });
  const logs = [];
  const orig = storage.deleteFile;
  let calls = 0;
  storage.deleteFile = async (p) => { calls++; if (calls === 1) throw Object.assign(new Error('boom'), { code: 'unavailable' }); return orig(p); };
  const later = new Date(clock.getTime() + 48 * 60 * 60 * 1000);
  const first = await f.cleanupAbandonedUploads({ db, storage, now: () => now, log: (e) => logs.push(e) }, { at: later });
  assert.deepStrictEqual([first.abandoned, first.failed], [0, 1]);
  assert.strictEqual(docOf(db, r.result.id).status, 'UPLOADING', 'left for the next run');
  const second = await f.cleanupAbandonedUploads({ db, storage, now: () => now }, { at: later });
  assert.strictEqual(second.abandoned, 1);
});

test('personal data stays out of the application history comments of document events', async () => {
  const { db, storage, id } = await underReview();
  await addDocument(db, storage, id);
  const text = JSON.stringify(appHist(db, id));
  for (const secret of ['9876543210', 'm@example.com']) assert.ok(!text.includes(secret), secret);
});

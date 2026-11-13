'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const a = require('./admission');
const n = require('./admission_notify');

const now = new Date('2026-11-07T10:00:00Z');
const ctx = (db) => ({ db, now: () => now });
const B = 'schools/sA/branches/b1';
const P = { schoolId: 'sA', branchId: 'b1' };
const seed = (settings = {}, enquiry = {}) => ({
  'schools/sA': { name: 'A' },
  'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1, ...settings },
  [`${B}/admissionEnquiries/e1`]: { enquiryNumber: 'ENQ-2026-00001', status: 'NEW', student: { firstName: 'Asha' }, assignedTo: null, revision: 1, remarks: 'secret remark', primaryPhone: '9876543210', ...enquiry },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/ba2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/staff': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/gone': { schoolId: 'sA', branchId: 'b1', status: 'INACTIVE', role: 'BRANCH_ADMIN' },
  'users/other': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
});
const notices = (db) => [...db.store.entries()].filter(([k]) => k.startsWith(`${B}/notifications/`));
const to = (db, type) => notices(db).filter(([, v]) => v.type === type).map(([, v]) => v.recipientUserId).sort();
const hist = (over) => ({ enquiryId: 'e1', revision: 1, from: null, to: 'NEW', actorId: 'owner', ...over });

test('a new unassigned enquiry tells the branch administrators (not another branch, inactive or other school)', async () => {
  const db = fakeDb(seed());
  const r = await n.onStatusHistory(ctx(db), P, hist({ actorId: 'public-portal' }));
  assert.equal(r.created, 1);
  assert.deepEqual(to(db, 'ADMISSION_ENQUIRY_NEW'), ['ba1']);
});

test('with no branch administrator the school administrators are told', async () => {
  const s = seed();
  delete s['users/ba1'];
  const db = fakeDb(s);
  await n.onStatusHistory(ctx(db), P, hist({ actorId: 'public-portal' }));
  assert.deepEqual(to(db, 'ADMISSION_ENQUIRY_NEW'), ['owner']);
});

test('a website enquiry says so; staff-created ones do not tell their creator', async () => {
  const db = fakeDb(seed({}, { channel: 'PUBLIC_PORTAL' }));
  await n.onStatusHistory(ctx(db), P, hist({ actorId: 'public-portal' }));
  assert.match(notices(db)[0][1].body, /website/);
  const db2 = fakeDb(seed());
  await n.onStatusHistory(ctx(db2), P, hist({ actorId: 'ba1' }));
  assert.equal(notices(db2).length, 0, 'the creator is the only branch admin and is skipped');
});

test('an enquiry created with an assignee tells that person', async () => {
  const db = fakeDb(seed({}, { assignedTo: 'staff' }));
  await n.onStatusHistory(ctx(db), P, hist({ actorId: 'owner' }));
  assert.deepEqual(to(db, 'ADMISSION_ASSIGNED'), ['staff']);
});

test('assigning later tells the new assignee, not the assigner, once per change', async () => {
  const db = fakeDb(seed({}, { assignedTo: 'staff', revision: 2, updatedBy: 'owner' }));
  const before = { assignedTo: null, revision: 1 };
  const after = { assignedTo: 'staff', revision: 2, updatedBy: 'owner', enquiryNumber: 'ENQ-2026-00001' };
  assert.equal((await n.onEnquiryUpdated(ctx(db), { ...P, enquiryId: 'e1' }, before, after)).created, 1);
  assert.equal((await n.onEnquiryUpdated(ctx(db), { ...P, enquiryId: 'e1' }, before, after)).created, 0, 'a retry creates nothing');
  assert.equal((await n.onEnquiryUpdated(ctx(db), { ...P, enquiryId: 'e1' }, { assignedTo: 'staff' }, { ...after, revision: 3 })).created, 0, 'no change in assignee');
  assert.equal((await n.onEnquiryUpdated(ctx(db), { ...P, enquiryId: 'e1' }, before, { ...after, assignedTo: 'owner', updatedBy: 'owner' })).created, 0, 'assigning to yourself');
  assert.equal((await n.onEnquiryUpdated(ctx(db), { ...P, enquiryId: 'e1' }, before, { ...after, assignedTo: 'gone' })).created, 0, 'inactive assignee');
  assert.equal((await n.onEnquiryUpdated(ctx(db), { ...P, enquiryId: 'e1' }, before, { ...after, assignedTo: null })).created, 0, 'unassigning');
});

test('a submitted application goes to the deciders only', async () => {
  let db = fakeDb(seed());
  await n.onStatusHistory(ctx(db), P, hist({ revision: 4, from: 'VISIT_COMPLETED', to: 'APPLICATION_SUBMITTED', actorId: 'ba1' }));
  assert.deepEqual(to(db, 'ADMISSION_APP_SUBMITTED'), ['owner']);
  db = fakeDb(seed({ branchAdminsMayApprove: true }));
  await n.onStatusHistory(ctx(db), P, hist({ revision: 4, from: 'VISIT_COMPLETED', to: 'APPLICATION_SUBMITTED', actorId: 'owner' }));
  assert.deepEqual(to(db, 'ADMISSION_APP_SUBMITTED'), ['ba1']);
});

test('approve and reject tell the owner of the enquiry without the reason', async () => {
  const db = fakeDb(seed({}, { assignedTo: 'staff' }));
  await n.onStatusHistory(ctx(db), P, hist({ revision: 7, from: 'UNDER_REVIEW', to: 'REJECTED', actorId: 'owner', reason: 'Fees problem, see remarks' }));
  await n.onStatusHistory(ctx(db), P, hist({ revision: 8, from: 'UNDER_REVIEW', to: 'APPROVED', actorId: 'owner' }));
  assert.deepEqual(to(db, 'ADMISSION_APP_REJECTED'), ['staff']);
  assert.deepEqual(to(db, 'ADMISSION_APP_APPROVED'), ['staff']);
  const text = JSON.stringify(notices(db));
  for (const secret of ['Fees problem', 'secret remark', '9876543210']) assert.equal(text.includes(secret), false, secret);
});

test('a retry of the same history entry creates nothing; each revision is its own event', async () => {
  const db = fakeDb(seed({}, { assignedTo: 'staff' }));
  const h = hist({ revision: 8, from: 'UNDER_REVIEW', to: 'APPROVED', actorId: 'owner' });
  assert.equal((await n.onStatusHistory(ctx(db), P, h)).created, 1);
  assert.equal((await n.onStatusHistory(ctx(db), P, h)).created, 0);
  assert.equal(notices(db).length, 1);
});

test('confirmation: staff are told, and parents with a login — no one else', async () => {
  const db = fakeDb({
    ...seed({}, { assignedTo: 'staff' }),
    [`${B}/admissionConversions/e1`]: { studentId: 's_e1', admissionNumber: 'ADM-0007', parentIds: ['p1', 'p2', 'p3'] },
    [`${B}/parents/p1`]: { linkedUserId: 'pu1' },
    [`${B}/parents/p2`]: { linkedUserId: null },
    [`${B}/parents/p3`]: { linkedUserId: 'pu3' },
    'users/pu1': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
    'users/pu3': { schoolId: 'sB', status: 'ACTIVE', role: 'PARENT' },
  });
  await n.onStatusHistory(ctx(db), P, hist({ revision: 9, from: 'APPROVED', to: 'ADMISSION_CONFIRMED', actorId: 'owner' }));
  assert.deepEqual(to(db, 'ADMISSION_CONFIRMED'), ['staff']);
  assert.deepEqual(to(db, 'ADMISSION_CONFIRMED_PARENT'), ['pu1']);
  const parent = notices(db).find(([, v]) => v.type === 'ADMISSION_CONFIRMED_PARENT')[1];
  assert.equal(parent.refType, 'STUDENT');
  assert.equal(parent.refId, 's_e1');
  assert.match(parent.body, /Asha.*ADM-0007/);
  assert.equal(/ENQ-|remark|phone/i.test(parent.body), false, 'no internal numbers or remarks for parents');
});

test('each kind can be switched off; admissions off means nothing', async () => {
  const off = (k) => seed({ notifications: { ...a.DEFAULT_SETTINGS.notifications, [k]: false } });
  let db = fakeDb(off('newEnquiry'));
  assert.equal((await n.onStatusHistory(ctx(db), P, hist({ actorId: 'public-portal' }))).created, 0);
  db = fakeDb(off('decision'));
  assert.equal((await n.onStatusHistory(ctx(db), P, hist({ to: 'APPROVED', revision: 3 }))).created, 0);
  db = fakeDb(off('applicationSubmitted'));
  assert.equal((await n.onStatusHistory(ctx(db), P, hist({ to: 'APPLICATION_SUBMITTED', revision: 3, actorId: 'x' }))).created, 0);
  db = fakeDb({ ...off('assignment'), [`${B}/admissionEnquiries/e1`]: { enquiryNumber: 'E', assignedTo: 'staff', student: {} } });
  assert.equal((await n.onStatusHistory(ctx(db), P, hist())).created, 0);
  db = fakeDb(seed({ enabled: false }));
  assert.equal((await n.onStatusHistory(ctx(db), P, hist({ actorId: 'public-portal' }))).created, 0);
});

test('a missing enquiry or malformed event is ignored', async () => {
  const db = fakeDb(seed());
  assert.equal((await n.onStatusHistory(ctx(db), P, hist({ enquiryId: 'nope' }))).created, 0);
  assert.equal((await n.onStatusHistory(ctx(db), P, undefined)).created, 0);
  assert.equal((await n.onStatusHistory(ctx(db), P, {})).created, 0);
});

test('settings: the notification switches validate and default on', () => {
  assert.equal(a.validateSettings({}).value.notifications.newEnquiry, true);
  assert.equal(a.validateSettings({ notifications: { decision: false } }).value.notifications.decision, false);
  assert.ok(a.validateSettings({ notifications: { bogus: true } }).errors);
  assert.ok(a.validateSettings({ notifications: { decision: 'no' } }).errors);
  assert.ok(a.validateSettings({ notifications: [] }).errors);
});

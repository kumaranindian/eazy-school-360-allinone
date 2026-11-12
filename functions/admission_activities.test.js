'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const a = require('./admission');
const f = require('./admission_activities');

// "now": 7 Nov 2026 15:30 in Asia/Kolkata (school date 2026-11-07).
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
  'users/branch1b': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/teacher2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'TEACHER' },
  'users/gone': { schoolId: 'sA', branchId: 'b1', status: 'INACTIVE', role: 'TEACHER' },
  'users/parentA': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  ...extra,
});
const ctx = (db) => ({ db, now, wall });
const enquiryInput = (over = {}) => ({
  student: { firstName: 'Asha', lastName: 'Nair', dateOfBirth: '2020-05-01' },
  academicYearId: 'ay1',
  interestedClassId: 'c1',
  source: 'Walk-in',
  guardians: [{ name: 'Meena Nair', phone: '9876543210' }],
  ...over,
});
async function setup(extra = {}, enquiryOver = {}) {
  const db = fakeDb(seed(extra));
  const made = await a.createEnquiry(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiry: enquiryInput(enquiryOver) });
  return { db, id: made.result.id };
}
const base = (id, over = {}) => ({ schoolId: 'sA', branchId: 'b1', enquiryId: id, ...over });
const enquiry = (db, id) => db.store.get(`schools/sA/branches/b1/admissionEnquiries/${id}`);
const act = (db, id) => db.store.get(`schools/sA/branches/b1/admissionActivities/${id}`);
const schedule = (db, id, activity = {}, uid = 'adminA', extra = {}) =>
  f.scheduleActivity(ctx(db), uid, undefined, base(id, { activity: { type: 'PHONE_CALL', scheduledDate: '2026-11-10', ...activity }, ...extra }));
const histOf = (db, activityId) =>
  [...db.store.keys()]
    .filter((k) => k.startsWith(`schools/sA/branches/b1/admissionActivityHistory/${activityId}__`))
    .sort()
    .map((k) => db.store.get(k));

// ---- pure ------------------------------------------------------------------

test('schedule validation: type, date, time, no past dates', () => {
  const ok = f.validateSchedule({ type: 'EMAIL', scheduledDate: '2026-11-07', scheduledTime: '09:30', remarks: ' hi ' }, { today: '2026-11-07' });
  assert.deepStrictEqual(ok.value, { type: 'EMAIL', scheduledDate: '2026-11-07', scheduledTime: '09:30', remarks: 'hi' });
  assert.ok(f.validateSchedule({ type: 'FAX', scheduledDate: '2026-11-08' }, { today: '2026-11-07' }).errors.type);
  assert.ok(f.validateSchedule({ type: 'EMAIL', scheduledDate: '2026-11-06' }, { today: '2026-11-07' }).errors.scheduledDate);
  assert.ok(f.validateSchedule({ type: 'EMAIL', scheduledDate: '2026-02-31' }, { today: '2026-01-01' }).errors.scheduledDate);
  assert.ok(f.validateSchedule({ type: 'EMAIL', scheduledDate: '2026-11-08', scheduledTime: '25:00' }, { today: '2026-11-07' }).errors.scheduledTime);
  assert.ok(f.validateSchedule({ type: 'EMAIL', scheduledDate: '2026-11-08', remarks: 'x'.repeat(501) }, { today: '2026-11-07' }).errors.remarks);
});

test('completion validation needs an outcome', () => {
  assert.ok(f.validateCompletion({ outcome: ' ' }).errors.outcome);
  assert.ok(f.validateCompletion({}).errors.outcome);
  assert.deepStrictEqual(f.validateCompletion({ outcome: 'Will visit Friday', parentFeedback: 'Keen' }).value, { outcome: 'Will visit Friday', parentFeedback: 'Keen', remarks: null });
});

test('earliest date and buckets', () => {
  assert.strictEqual(f.earliest(['2026-11-12', null, '2026-11-09']), '2026-11-09');
  assert.strictEqual(f.earliest([]), null);
  assert.strictEqual(f.bucketOf('2026-11-06', '2026-11-07'), 'OVERDUE');
  assert.strictEqual(f.bucketOf('2026-11-07', '2026-11-07'), 'TODAY');
  assert.strictEqual(f.bucketOf('2026-11-08', '2026-11-07'), 'UPCOMING');
});

// ---- scheduling ------------------------------------------------------------

test('scheduling stores the activity, history, and updates the enquiry', async () => {
  const { db, id } = await setup();
  const r = await schedule(db, id, { scheduledTime: '10:00', remarks: 'Ask about transport' });
  assert.strictEqual(r.result.duplicate, false);
  const d = act(db, r.result.id);
  assert.deepStrictEqual([d.status, d.type, d.scheduledDate, d.scheduledTime, d.enquiryId, d.schoolId, d.branchId], ['SCHEDULED', 'PHONE_CALL', '2026-11-10', '10:00', id, 'sA', 'b1']);
  assert.strictEqual(d.enquiryNumber, 'ENQ-2026-00001');
  assert.strictEqual(d.createdBy, 'adminA');
  const e = enquiry(db, id);
  assert.deepStrictEqual([e.nextFollowUpDate, e.openActivityCount, e.activityCount], ['2026-11-10', 1, 1]);
  assert.strictEqual(e.revision, 1, 'logging a call never makes an open edit form stale');
  assert.deepStrictEqual(histOf(db, r.result.id).map((h) => h.event), ['CREATED']);
});

test('the enquiry shows the EARLIEST open follow-up', async () => {
  const { db, id } = await setup();
  await schedule(db, id, { scheduledDate: '2026-11-20' });
  await schedule(db, id, { scheduledDate: '2026-11-09' });
  await schedule(db, id, { scheduledDate: '2026-11-15' });
  const e = enquiry(db, id);
  assert.deepStrictEqual([e.nextFollowUpDate, e.openActivityCount, e.activityCount], ['2026-11-09', 3, 3]);
});

test('an activity defaults to the enquiry assignee, or the one named', async () => {
  const { db, id } = await setup();
  await a.assignEnquiry(ctx(db), 'adminA', undefined, base(id, { assignedTo: 'teacher1' }));
  const inherited = await schedule(db, id);
  assert.strictEqual(act(db, inherited.result.id).assignedTo, 'teacher1');
  const named = await schedule(db, id, { assignedTo: 'branch1' });
  assert.strictEqual(act(db, named.result.id).assignedTo, 'branch1');
  const none = await schedule(db, id, { assignedTo: null });
  assert.strictEqual(act(db, none.result.id).assignedTo, null);
  assert.strictEqual((await schedule(db, id, { assignedTo: 'teacher2' })).error, 'INVALID_ARGUMENT', 'other branch');
  assert.strictEqual((await schedule(db, id, { assignedTo: 'gone' })).error, 'INVALID_ARGUMENT', 'inactive');
});

test('nothing can be planned in the past, or on a closed enquiry', async () => {
  const { db, id } = await setup();
  assert.strictEqual((await schedule(db, id, { scheduledDate: '2026-11-06' })).error, 'INVALID_ARGUMENT');
  assert.ok((await schedule(db, id, { scheduledDate: '2026-11-07' })).result, 'today is allowed');
  await a.changeEnquiryStatus(ctx(db), 'adminA', undefined, base(id, { status: 'WITHDRAWN', reason: 'Moved away' }));
  assert.strictEqual((await schedule(db, id)).error, 'FAILED_PRECONDITION');
});

test('who may schedule: school admin, and the branch admin of that branch; module must be on', async () => {
  const { db, id } = await setup();
  assert.ok((await schedule(db, id, {}, 'branch1')).result);
  for (const uid of ['teacher1', 'parentA', 'adminB', 'nobody']) assert.strictEqual((await schedule(db, id, {}, uid)).error, 'PERMISSION_DENIED', uid);
  const other = await f.scheduleActivity(ctx(db), 'branch1', undefined, { schoolId: 'sA', branchId: 'b2', enquiryId: id, activity: { type: 'EMAIL', scheduledDate: '2026-11-10' } });
  assert.strictEqual(other.error, 'PERMISSION_DENIED', 'a branch admin cannot act in another branch');
  db.store.set('schools/sA/admissionSettings/config', { ...a.DEFAULT_SETTINGS, enabled: false, version: 2 });
  assert.strictEqual((await schedule(db, id)).error, 'FAILED_PRECONDITION');
});

test('an unknown enquiry is not found; the client cannot name a school or branch inside the activity', async () => {
  const { db } = await setup();
  assert.strictEqual((await schedule(db, 'nope')).error, 'NOT_FOUND');
  const { id } = await setup();
  const r = await schedule(db, id, { schoolId: 'sB', branchId: 'b2', status: 'COMPLETED', createdBy: 'x', outcome: 'done' });
  const d = act(db, r.result.id);
  assert.deepStrictEqual([d.schoolId, d.branchId, d.status, d.createdBy, d.outcome], ['sA', 'b1', 'SCHEDULED', 'adminA', null]);
});

test('a retried request (same requestId) creates one activity', async () => {
  const { db, id } = await setup();
  const first = await schedule(db, id, {}, 'adminA', { requestId: 'req-12345678' });
  const again = await schedule(db, id, {}, 'adminA', { requestId: 'req-12345678' });
  assert.strictEqual(first.result.id, again.result.id);
  assert.strictEqual(again.result.duplicate, true);
  assert.strictEqual(enquiry(db, id).activityCount, 1);
  assert.strictEqual(histOf(db, first.result.id).length, 1);
  assert.strictEqual((await schedule(db, id, {}, 'adminA', { requestId: 'bad id!' })).error, 'INVALID_ARGUMENT');
});

test('concurrent scheduling keeps the derived counts right', async () => {
  const { db, id } = await setup();
  const rs = await Promise.all([1, 2, 3, 4].map((n) => schedule(db, id, { scheduledDate: `2026-11-${10 + n}` })));
  assert.ok(rs.every((r) => r.result));
  const e = enquiry(db, id);
  assert.deepStrictEqual([e.activityCount, e.openActivityCount, e.nextFollowUpDate], [4, 4, '2026-11-11']);
});

// ---- change: reschedule / reassign / cancel / complete ---------------------

test('rescheduling moves the date, counts it, keeps the old date in history, and recomputes the next date', async () => {
  const { db, id } = await setup();
  const first = await schedule(db, id, { scheduledDate: '2026-11-10' });
  await schedule(db, id, { scheduledDate: '2026-11-12' });
  const r = await f.rescheduleActivity(ctx(db), 'adminA', undefined, base(id, { activityId: first.result.id, scheduledDate: '2026-11-14', scheduledTime: '11:15', reason: 'Parent travelling' }));
  assert.deepStrictEqual(r.result, { revision: 2 });
  const d = act(db, first.result.id);
  assert.deepStrictEqual([d.scheduledDate, d.scheduledTime, d.rescheduleCount, d.status], ['2026-11-14', '11:15', 1, 'SCHEDULED']);
  assert.strictEqual(enquiry(db, id).nextFollowUpDate, '2026-11-12');
  const h = histOf(db, first.result.id);
  assert.deepStrictEqual(h.map((x) => x.event), ['CREATED', 'RESCHEDULED']);
  assert.strictEqual(h[1].from.scheduledDate, '2026-11-10');
  assert.strictEqual(h[1].to.scheduledDate, '2026-11-14');
  assert.strictEqual(h[1].reason, 'Parent travelling');
  assert.strictEqual(h[1].actorId, 'adminA');
});

test('rescheduling: past date, stale revision, closed activity are refused', async () => {
  const { db, id } = await setup();
  const { result } = await schedule(db, id);
  const move = (over) => f.rescheduleActivity(ctx(db), 'adminA', undefined, base(id, { activityId: result.id, scheduledDate: '2026-11-12', ...over }));
  assert.strictEqual((await move({ scheduledDate: '2026-11-01' })).error, 'INVALID_ARGUMENT');
  assert.ok((await move({ baseRevision: 1 })).result);
  assert.strictEqual((await move({ baseRevision: 1 })).error, 'ABORTED');
  await f.cancelActivity(ctx(db), 'adminA', undefined, base(id, { activityId: result.id, reason: 'Not needed' }));
  assert.strictEqual((await move({})).error, 'FAILED_PRECONDITION');
  assert.strictEqual((await f.rescheduleActivity(ctx(db), 'adminA', undefined, base(id, { activityId: 'ghost', scheduledDate: '2026-11-12' }))).error, 'NOT_FOUND');
});

test('an activity of one enquiry cannot be changed through another enquiry', async () => {
  const { db, id } = await setup();
  const other = await a.createEnquiry(ctx(db), 'adminA', undefined, { schoolId: 'sA', branchId: 'b1', enquiry: enquiryInput({ student: { firstName: 'Ravi', lastName: 'Menon' }, guardians: [{ name: 'X Menon', phone: '9123456780' }] }) });
  const { result } = await schedule(db, id);
  const r = await f.cancelActivity(ctx(db), 'adminA', undefined, base(other.result.id, { activityId: result.id, reason: 'Nope' }));
  assert.strictEqual(r.error, 'NOT_FOUND');
  assert.strictEqual(act(db, result.id).status, 'SCHEDULED');
});

test('reassigning records who it moved from and to; unknown people are refused', async () => {
  const { db, id } = await setup();
  const { result } = await schedule(db, id, { assignedTo: 'teacher1' });
  const re = (assignedTo) => f.reassignActivity(ctx(db), 'adminA', undefined, base(id, { activityId: result.id, assignedTo }));
  assert.ok((await re('branch1')).result);
  assert.strictEqual(act(db, result.id).assignedTo, 'branch1');
  assert.strictEqual((await re('teacher2')).error, 'INVALID_ARGUMENT');
  assert.ok((await re(null)).result);
  const h = histOf(db, result.id).filter((x) => x.event === 'REASSIGNED');
  assert.deepStrictEqual(h.map((x) => [x.from.assignedTo, x.to.assignedTo]), [['teacher1', 'branch1'], ['branch1', null]]);
});

test('cancelling needs a reason, keeps the activity, and recomputes the next date', async () => {
  const { db, id } = await setup();
  const a1 = await schedule(db, id, { scheduledDate: '2026-11-09' });
  await schedule(db, id, { scheduledDate: '2026-11-16' });
  const cancel = (reason) => f.cancelActivity(ctx(db), 'adminA', undefined, base(id, { activityId: a1.result.id, reason }));
  assert.strictEqual((await cancel('')).error, 'INVALID_ARGUMENT');
  assert.ok((await cancel('Family withdrew interest')).result);
  const d = act(db, a1.result.id);
  assert.deepStrictEqual([d.status, d.cancelReason], ['CANCELLED', 'Family withdrew interest']);
  const e = enquiry(db, id);
  assert.deepStrictEqual([e.nextFollowUpDate, e.openActivityCount, e.activityCount], ['2026-11-16', 1, 2]);
});

test('completing needs an outcome, records who and when, and cannot be repeated', async () => {
  const { db, id } = await setup();
  const { result } = await schedule(db, id);
  const done = (completion) => f.completeActivity(ctx(db), 'adminA', undefined, base(id, { activityId: result.id, completion }));
  assert.strictEqual((await done({ outcome: '' })).error, 'INVALID_ARGUMENT');
  assert.ok((await done({ outcome: 'Spoke to mother; wants a visit', parentFeedback: 'Likes the campus', remarks: 'Hot lead' })).result);
  const d = act(db, result.id);
  assert.deepStrictEqual([d.status, d.outcome, d.parentFeedback, d.remarks, d.completedBy], ['COMPLETED', 'Spoke to mother; wants a visit', 'Likes the campus', 'Hot lead', 'adminA']);
  assert.ok(d.completedAt);
  assert.strictEqual((await done({ outcome: 'again' })).error, 'FAILED_PRECONDITION');
  const e = enquiry(db, id);
  assert.deepStrictEqual([e.nextFollowUpDate, e.openActivityCount, e.activityCount], [null, 0, 1]);
});

test('completing can plan the next contact atomically', async () => {
  const { db, id } = await setup();
  const { result } = await schedule(db, id, { assignedTo: 'teacher1' });
  const r = await f.completeActivity(ctx(db), 'adminA', undefined, base(id, {
    activityId: result.id,
    completion: { outcome: 'Asked to call back' },
    next: { type: 'WHATSAPP', scheduledDate: '2026-11-17' },
  }));
  assert.ok(r.result.nextId);
  const n = act(db, r.result.nextId);
  assert.deepStrictEqual([n.type, n.scheduledDate, n.status, n.assignedTo], ['WHATSAPP', '2026-11-17', 'SCHEDULED', 'teacher1']);
  const e = enquiry(db, id);
  assert.deepStrictEqual([e.nextFollowUpDate, e.openActivityCount, e.activityCount], ['2026-11-17', 1, 2]);
  assert.deepStrictEqual(histOf(db, r.result.nextId).map((h) => h.event), ['CREATED']);
});

test('a bad next contact fails the whole completion (nothing half-saved)', async () => {
  const { db, id } = await setup();
  const { result } = await schedule(db, id);
  const r = await f.completeActivity(ctx(db), 'adminA', undefined, base(id, { activityId: result.id, completion: { outcome: 'Done call' }, next: { type: 'WHATSAPP', scheduledDate: '2020-01-01' } }));
  assert.strictEqual(r.error, 'INVALID_ARGUMENT');
  assert.strictEqual(act(db, result.id).status, 'SCHEDULED');
});

test('history is append-only: every change adds an entry and the activity survives', async () => {
  const { db, id } = await setup();
  const { result } = await schedule(db, id);
  const c = (fn, extra) => fn(ctx(db), 'adminA', undefined, base(id, { activityId: result.id, ...extra }));
  await c(f.rescheduleActivity, { scheduledDate: '2026-11-12' });
  await c(f.reassignActivity, { assignedTo: 'teacher1' });
  await c(f.completeActivity, { completion: { outcome: 'Visited campus' } });
  const h = histOf(db, result.id);
  assert.deepStrictEqual(h.map((x) => x.event), ['CREATED', 'RESCHEDULED', 'REASSIGNED', 'COMPLETED']);
  assert.deepStrictEqual(h.map((x) => x.revision), [1, 2, 3, 4]);
  assert.strictEqual(act(db, result.id).revision, 4);
});

// ---- the enquiry and its activities ----------------------------------------

test('closing the enquiry cancels its open follow-ups but keeps them', async () => {
  const { db, id } = await setup();
  const x = await schedule(db, id, { scheduledDate: '2026-11-09' });
  const y = await schedule(db, id, { scheduledDate: '2026-11-10' });
  await f.completeActivity(ctx(db), 'adminA', undefined, base(id, { activityId: y.result.id, completion: { outcome: 'Spoke briefly' } }));
  const r = await a.changeEnquiryStatus(ctx(db), 'adminA', undefined, base(id, { status: 'REJECTED', reason: 'Seats full' }));
  assert.ok(r.result);
  assert.deepStrictEqual([act(db, x.result.id).status, act(db, x.result.id).cancelReason], ['CANCELLED', 'Enquiry closed']);
  assert.strictEqual(act(db, y.result.id).status, 'COMPLETED', 'finished work is untouched');
  const e = enquiry(db, id);
  assert.deepStrictEqual([e.status, e.nextFollowUpDate, e.openActivityCount, e.activityCount], ['REJECTED', null, 0, 2]);
  assert.deepStrictEqual(histOf(db, x.result.id).map((h) => h.event), ['CREATED', 'CANCELLED']);
});

test('a non-closing status change leaves follow-ups alone', async () => {
  const { db, id } = await setup();
  const x = await schedule(db, id);
  await a.changeEnquiryStatus(ctx(db), 'adminA', undefined, base(id, { status: 'ON_HOLD', reason: 'Parent away' }));
  assert.strictEqual(act(db, x.result.id).status, 'SCHEDULED');
  assert.strictEqual(enquiry(db, id).openActivityCount, 1);
});

test('editing an enquiry never overwrites a derived follow-up date; without activities the manual date is kept', async () => {
  const { db, id } = await setup();
  const edit = (over) => a.updateEnquiry(ctx(db), 'adminA', undefined, base(id, { enquiry: enquiryInput(over) }));
  await edit({ nextFollowUpDate: '2026-11-25' });
  assert.strictEqual(enquiry(db, id).nextFollowUpDate, '2026-11-25');
  await schedule(db, id, { scheduledDate: '2026-11-10' });
  await edit({ nextFollowUpDate: '2026-12-30', remarks: 'edited' });
  const e = enquiry(db, id);
  assert.strictEqual(e.nextFollowUpDate, '2026-11-10');
  assert.strictEqual(e.remarks, 'edited');
});

// ---- reminders -------------------------------------------------------------

// 9:30 in Kolkata on 7 Nov 2026 = 04:00Z (inside the 09:00 window).
const morning = new Date('2026-11-07T04:00:00Z');
const run = (db, when = morning, log) => f.runFollowUpReminders({ db, now: () => now, log }, { today: when });
const notices = (db) => [...db.store.entries()].filter(([k]) => k.startsWith('schools/sA/branches/b1/notifications/')).map(([k, v]) => ({ id: k.split('/').pop(), ...v }));

test('a follow-up due today notifies its assignee once; a re-run sends nothing new', async () => {
  const { db, id } = await setup();
  const s = await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  const first = await run(db);
  assert.strictEqual(first.created, 1);
  const [n] = notices(db);
  assert.strictEqual(n.type, 'ADMISSION_FOLLOWUP_DUE');
  assert.strictEqual(n.recipientUserId, 'teacher1');
  assert.deepStrictEqual([n.refType, n.refId, n.activityId, n.audience, n.readAt], ['ENQUIRY', id, s.result.id, 'USER', null]);
  assert.strictEqual(n.id, `ADMISSION_FOLLOWUP_DUE__${s.result.id}__2026-11-07__teacher1`);
  assert.strictEqual((await run(db)).created, 0, 'idempotent');
  assert.strictEqual((await run(db)).created, 0);
  assert.strictEqual(notices(db).length, 1);
});

test('the text names the enquiry number and kind of contact, never the family', async () => {
  const { db, id } = await setup();
  await schedule(db, id, { scheduledDate: '2026-11-07', type: 'SCHOOL_VISIT', assignedTo: 'teacher1' });
  await run(db);
  const text = JSON.stringify(notices(db)[0]);
  assert.match(text, /School visit for enquiry ENQ-2026-00001 is due today/);
  for (const secret of ['Asha', 'Nair', 'Meena', '9876543210']) assert.ok(!text.includes(secret), secret);
});

test('an earlier open follow-up gets one OVERDUE notice, not one per run', async () => {
  const { db, id } = await setup();
  const s = await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  db.store.get(`schools/sA/branches/b1/admissionActivities/${s.result.id}`).scheduledDate = '2026-11-05';
  assert.strictEqual((await run(db)).created, 1);
  assert.strictEqual(notices(db)[0].type, 'ADMISSION_FOLLOWUP_OVERDUE');
  assert.strictEqual((await run(db)).created, 0);
  // the next day it is still overdue, but already told
  const nextMorning = new Date('2026-11-08T04:00:00Z');
  assert.strictEqual((await run(db, nextMorning)).created, 0);
});

test('a rescheduled follow-up is allowed one fresh notice for its new date', async () => {
  const { db, id } = await setup();
  const s = await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  await run(db);
  await f.rescheduleActivity(ctx(db), 'adminA', undefined, base(id, { activityId: s.result.id, scheduledDate: '2026-11-08' }));
  assert.strictEqual((await run(db, new Date('2026-11-08T04:00:00Z'))).created, 1);
  assert.strictEqual(notices(db).length, 2);
});

test('completed, cancelled and future activities are not reminded', async () => {
  const { db, id } = await setup();
  const done = await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  const cancelled = await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  await schedule(db, id, { scheduledDate: '2026-11-09', assignedTo: 'teacher1' });
  await f.completeActivity(ctx(db), 'adminA', undefined, base(id, { activityId: done.result.id, completion: { outcome: 'Spoke today' } }));
  await f.cancelActivity(ctx(db), 'adminA', undefined, base(id, { activityId: cancelled.result.id, reason: 'No longer needed' }));
  assert.strictEqual((await run(db)).created, 0);
});

test('very old overdue activities stop notifying', async () => {
  const { db, id } = await setup();
  const s = await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  db.store.get(`schools/sA/branches/b1/admissionActivities/${s.result.id}`).scheduledDate = '2026-09-01';
  assert.strictEqual((await run(db)).created, 0);
});

test('unassigned follow-ups go to the branch administrators of THAT branch', async () => {
  const { db, id } = await setup();
  await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: null });
  assert.strictEqual((await run(db)).created, 2);
  assert.deepStrictEqual(notices(db).map((n) => n.recipientUserId).sort(), ['branch1', 'branch1b']);
});

test('an inactive assignee is not notified', async () => {
  const { db, id } = await setup();
  const s = await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  db.store.get('users/teacher1').status = 'INACTIVE';
  assert.strictEqual((await run(db)).created, 0);
  assert.ok(act(db, s.result.id));
});

test('reminders wait for the school\'s own local reminder time and respect the switches', async () => {
  const { db, id } = await setup();
  await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  // 15:30 Kolkata is outside the 09:00 window
  assert.strictEqual((await run(db, now)).created, 0);
  // 05:00 UTC = 10:30 Kolkata is inside (window is hours long)
  assert.strictEqual((await run(db, new Date('2026-11-07T05:00:00Z'))).created, 1);

  const off = await setup({ 'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, remindersEnabled: false, version: 1 } });
  await schedule(off.db, off.id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  assert.strictEqual((await run(off.db)).created, 0);

  const disabled = await setup({ 'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1 } });
  await schedule(disabled.db, disabled.id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  disabled.db.store.set('schools/sA/admissionSettings/config', { ...a.DEFAULT_SETTINGS, enabled: false, version: 2 });
  assert.strictEqual((await run(disabled.db)).created, 0);
});

test('a school-specific reminder time is used', async () => {
  const { db, id } = await setup({ 'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, reminderTime: '18:00', version: 1 } });
  await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  assert.strictEqual((await run(db)).created, 0, '09:30 is before 18:00');
  assert.strictEqual((await run(db, new Date('2026-11-07T12:45:00Z'))).created, 1, '18:15 Kolkata');
});

test('one failing school does not stop the others', async () => {
  const { db, id } = await setup({ 'schools/broken/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1 } });
  await schedule(db, id, { scheduledDate: '2026-11-07', assignedTo: 'teacher1' });
  const logs = [];
  const orig = db.collection;
  db.collection = (p) => {
    if (p === 'schools') {
      const c = orig(p);
      const get = c.get;
      c.get = async () => {
        const r = await get();
        return { docs: [{ id: 'broken', data: () => { throw new Error('boom'); } }, ...r.docs] };
      };
      return c;
    }
    return orig(p);
  };
  const r = await run(db, morning, (event) => logs.push(event));
  assert.strictEqual(r.created, 1);
  assert.strictEqual(r.failed, 1);
  assert.ok(logs.includes('admission reminders: school failed'));
});

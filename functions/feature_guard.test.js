'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const G = require('./feature_guard');
const F = require('./features');
const E = require('./access_engine');

const ctxOf = (db) => ({ db, now: 'NOW', nowDate: () => new Date() });
const world = () => fakeDb({
  'schools/off': { name: 'Off', status: 'ACTIVE', features: { homework: false, fees: false, feeReminders: false } },
  'schools/on': { name: 'On', status: 'ACTIVE' },
  'schools/legacy': { name: 'Legacy', status: 'ACTIVE', features: { admission: false } },
});
const audits = async (db) => (await db.collection('platformAuditLog').get()).docs.map((d) => ({ id: d.id, ...d.data() }));
const create = (db, over) => G.checkCreate(ctxOf(db), { schoolId: 'off', branchId: 'b1', collection: 'homework', docId: 'h1', data: { createdBy: 'teacher1' }, ...over });

test('every guarded collection maps to a real catalogue feature', () => {
  for (const [col, f] of Object.entries(G.MODULE_COLLECTIONS)) assert.ok(F.BY_KEY[f], `${col} -> ${f}`);
});

test('a create in a disabled module is recorded with who, where and which module', async () => {
  const db = world();
  const r = await create(db);
  assert.deepEqual(r, { flagged: true, feature: 'homework' });
  const [a] = await audits(db);
  assert.equal(a.action, 'FEATURE_ACCESS_DENIED');
  assert.equal(a.schoolId, 'off');
  assert.equal(a.actorUid, 'teacher1');
  assert.equal(a.source, 'TRIGGER');
  assert.deepEqual(a.meta, { feature: 'homework', collection: 'homework', path: 'schools/off/branches/b1/homework/h1', code: E.CODES.FEATURE_DISABLED });
});

test('the document itself is left alone (detective, never destructive)', async () => {
  const db = world();
  await db.collection('schools').doc('off').collection('branches').doc('b1').collection('homework').doc('h1').set({ title: 'x', createdBy: 'teacher1' });
  await create(db);
  assert.equal((await db.collection('schools').doc('off').collection('branches').doc('b1').collection('homework').doc('h1').get()).data().title, 'x');
});

test('a retry writes nothing new (deterministic id)', async () => {
  const db = world();
  await create(db);
  await create(db);
  assert.equal((await audits(db)).length, 1);
  await create(db, { docId: 'h2' });
  assert.equal((await audits(db)).length, 2);
});

test('enabled modules, other schools and unguarded collections are never flagged', async () => {
  const db = world();
  assert.deepEqual(await create(db, { schoolId: 'on' }), { ok: true });
  assert.deepEqual(await create(db, { collection: 'exams' }), { ok: true }, 'not a guarded collection name');
  assert.deepEqual(await create(db, { collection: 'attendanceSessions' }), { ok: true }, 'attendance is on for this school');
  assert.deepEqual(await create(db, { schoolId: 'ghost' }), { ok: true }, 'a deleted school has nothing to guard');
  assert.equal((await audits(db)).length, 0);
});

test('a dependant of a disabled module is also guarded (fees off -> invoices flagged)', async () => {
  const db = world();
  assert.equal((await create(db, { collection: 'invoices', docId: 'i1' })).feature, 'fees');
  assert.equal((await create(db, { collection: 'payments', docId: 'p1' })).flagged, true);
});

test('a missing createdBy is recorded as unknown, not invented', async () => {
  const db = world();
  await create(db, { data: {} });
  assert.equal((await audits(db))[0].actorUid, null);
});

test('engine: a disabled dependency disables the dependant even on a legacy school', async () => {
  const db = world();
  assert.equal(E.featureOff({ features: { admission: false } }, 'publicAdmission'), true, 'legacy: admission off, public never switched');
  assert.equal(E.featureOff({ features: { admission: false } }, 'fees'), false);
  assert.equal((await E.schoolUsable(db, 'legacy', 'publicAdmission')).code, E.CODES.FEATURE_DISABLED);
  assert.equal((await E.schoolUsable(db, 'off', 'feeReminders')).code, E.CODES.FEATURE_DISABLED);
  assert.equal((await E.schoolUsable(db, 'off', 'attendance')).allowed, true);
  assert.equal((await E.schoolUsable(db, 'on', 'fees')).allowed, true);
});

test('callables: the fee-reminder settings call refuses when the module is off', async () => {
  const fr = require('./fee_reminders');
  const store = fakeDb({ 'schools/off': { name: 'Off', status: 'ACTIVE', features: { fees: false, feeReminders: false } }, 'users/a': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 'off' } });
  const out = await fr.updateFeeReminderSettings({ db: store, now: 'N' }, 'a', { firebase: { sign_in_provider: 'password' } }, { schoolId: 'off', settings: {} });
  assert.deepEqual([out.error, out.reason], ['FAILED_PRECONDITION', 'FEATURE_DISABLED']);
});

test('scheduled reminders skip a school whose fee reminders are off', async () => {
  const notify = require('./notify_events');
  const db = world();
  const r = await notify.runFeeDueReminders({ db, now: 'N' }, { today: new Date('2026-01-01T09:00:00Z') });
  assert.equal((r.created || 0) + (r.sent || 0), 0);
});

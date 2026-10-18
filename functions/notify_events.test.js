'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const ev = require('./notify_events');

const B = 'schools/s1/branches/b1';
const T = (iso) => ({ toDate: () => new Date(iso) }); // a Firestore Timestamp
const now = () => new Date('2026-08-03T10:00:00Z');
const ctx = (db) => ({ db, now });
const ids = { schoolId: 's1', branchId: 'b1' };

/** st1's parents: pu1 (valid), plus every way a link must NOT notify. */
const family = () => ({
  [`${B}/students/st1/parentLinks/p1`]: { parentId: 'p1', status: 'ACTIVE', canAccessPortal: true },
  [`${B}/students/st1/parentLinks/p2`]: { parentId: 'p2', status: 'ACTIVE', canAccessPortal: false }, // no portal
  [`${B}/students/st1/parentLinks/p3`]: { parentId: 'p3', status: 'ACTIVE', canAccessPortal: true }, // inactive login
  [`${B}/students/st1/parentLinks/p4`]: { parentId: 'p4', status: 'ACTIVE', canAccessPortal: true }, // other school
  [`${B}/students/st1/parentLinks/p5`]: { parentId: 'p5', status: 'INACTIVE', canAccessPortal: true }, // link switched off
  [`${B}/students/st1/parentLinks/p6`]: { parentId: 'p6', status: 'ACTIVE', canAccessPortal: true }, // no login at all
  'users/pu1': { schoolId: 's1', status: 'ACTIVE', role: 'PARENT', linkedParentId: 'p1' },
  'users/pu2': { schoolId: 's1', status: 'ACTIVE', role: 'PARENT', linkedParentId: 'p2' },
  'users/pu3': { schoolId: 's1', status: 'DISABLED', role: 'PARENT', linkedParentId: 'p3' },
  'users/pu4': { schoolId: 's2', status: 'ACTIVE', role: 'PARENT', linkedParentId: 'p4' },
  'users/pu5': { schoolId: 's1', status: 'ACTIVE', role: 'PARENT', linkedParentId: 'p5' },
  'users/staff': { schoolId: 's1', status: 'ACTIVE', role: 'TEACHER', linkedParentId: 'p1' }, // not a parent login
});
const docsIn = (db, prefix) => [...db.store.keys()].filter((k) => k.startsWith(prefix));

test('only the active, portal-enabled parents of the same school are recipients', async () => {
  const db = fakeDb(family());
  assert.deepStrictEqual(await ev.parentUserIdsOfStudent(db, 's1', 'b1', 'st1'), ['pu1']);
  assert.deepStrictEqual(await ev.parentUserIdsOfStudent(db, 's1', 'b1', 'nobody'), []);
  assert.deepStrictEqual(await ev.parentUserIdsOfStudent(db, 's1', 'b1', undefined), []);
});

// ---- payments -------------------------------------------------------------

test('a recorded payment notifies the parent once, with no amount in the text', async () => {
  const db = fakeDb(family());
  const pay = { status: 'ACTIVE', studentId: 'st1', amountMinor: 123456, invoiceNumber: 'INV-1' };
  const r = await ev.onPaymentRecorded(ctx(db), { ...ids, paymentId: 'pay-1' }, pay);
  assert.deepStrictEqual(r, { created: 1 });
  const n = db.store.get(`${B}/notifications/PAYMENT_RECORDED__pay-1__pu1`);
  assert.deepStrictEqual(
    { a: n.audience, to: n.recipientUserId, t: n.type, ref: n.refType, id: n.refId, by: n.createdBy, read: n.readAt, s: n.schoolId },
    { a: 'USER', to: 'pu1', t: 'PAYMENT_RECORDED', ref: 'RECEIPT', id: 'pay-1', by: 'system', read: null, s: 's1' },
  );
  assert.ok(!/\d{3,}/.test(`${n.title} ${n.body}`), 'no amounts or numbers in the text');
  assert.strictEqual(docsIn(db, `${B}/notifications/`).length, 1);
});

test('the same payment event again (retry) creates nothing new', async () => {
  const db = fakeDb(family());
  const pay = { status: 'ACTIVE', studentId: 'st1' };
  await ev.onPaymentRecorded(ctx(db), { ...ids, paymentId: 'pay-1' }, pay);
  assert.deepStrictEqual(await ev.onPaymentRecorded(ctx(db), { ...ids, paymentId: 'pay-1' }, pay), { created: 0 });
  assert.strictEqual(docsIn(db, `${B}/notifications/`).length, 1);
  await ev.onPaymentRecorded(ctx(db), { ...ids, paymentId: 'pay-2' }, pay); // another payment is another event
  assert.strictEqual(docsIn(db, `${B}/notifications/`).length, 2);
});

test('a reversed payment, a missing document or an unlinked student notifies nobody', async () => {
  const db = fakeDb(family());
  assert.deepStrictEqual(await ev.onPaymentRecorded(ctx(db), { ...ids, paymentId: 'x' }, { status: 'REVERSED', studentId: 'st1' }), { created: 0 });
  assert.deepStrictEqual(await ev.onPaymentRecorded(ctx(db), { ...ids, paymentId: 'x' }, undefined), { created: 0 });
  assert.deepStrictEqual(await ev.onPaymentRecorded(ctx(db), { ...ids, paymentId: 'x' }, { status: 'ACTIVE', studentId: 'loner' }), { created: 0 });
});

// ---- attendance -----------------------------------------------------------

const register = (status) => ({ status, academicYearId: 'y1', classId: 'c1', sectionId: 'sa', dateKey: '2026-08-03' });
const marks = () => ({
  [`${B}/studentAttendance/m1`]: { academicYearId: 'y1', classId: 'c1', sectionId: 'sa', dateKey: '2026-08-03', studentId: 'st1', status: 'ABSENT' },
  [`${B}/studentAttendance/m2`]: { academicYearId: 'y1', classId: 'c1', sectionId: 'sa', dateKey: '2026-08-03', studentId: 'st2', status: 'PRESENT' },
  [`${B}/studentAttendance/m3`]: { academicYearId: 'y1', classId: 'c1', sectionId: 'sa', dateKey: '2026-08-04', studentId: 'st1', status: 'ABSENT' }, // another day
  [`${B}/studentAttendance/m4`]: { academicYearId: 'y1', classId: 'c1', sectionId: 'sb', dateKey: '2026-08-03', studentId: 'st1', status: 'ABSENT' }, // another section
});

test('finalising a register tells the parent of each absent student, once', async () => {
  const db = fakeDb({ ...family(), ...marks() });
  const r = await ev.onRegisterFinalized(ctx(db), ids, register('DRAFT'), register('FINALIZED'));
  assert.deepStrictEqual(r, { created: 1, absent: 1 });
  const n = db.store.get(`${B}/notifications/ATTENDANCE_ABSENT__st1__2026-08-03__pu1`);
  assert.strictEqual(n.recipientUserId, 'pu1');
  assert.strictEqual(n.type, 'ATTENDANCE_ABSENT');
  assert.strictEqual(n.body, 'Your child was marked absent on 3 Aug 2026.'); // no name, no more
  assert.strictEqual(docsIn(db, `${B}/notifications/`).length, 1);
});

test('only the move to FINALIZED notifies: drafts, re-saves and staff days do not', async () => {
  const db = fakeDb({ ...family(), ...marks() });
  const none = { created: 0 };
  assert.deepStrictEqual(await ev.onRegisterFinalized(ctx(db), ids, register('DRAFT'), register('DRAFT')), none);
  assert.deepStrictEqual(await ev.onRegisterFinalized(ctx(db), ids, register('FINALIZED'), register('FINALIZED')), none);
  assert.deepStrictEqual(await ev.onRegisterFinalized(ctx(db), ids, undefined, undefined), none);
  const staffDay = { status: 'FINALIZED', dateKey: '2026-08-03', academicYearId: null, classId: null, sectionId: null };
  assert.deepStrictEqual(await ev.onRegisterFinalized(ctx(db), ids, { status: 'DRAFT' }, staffDay), none);
  assert.strictEqual(docsIn(db, `${B}/notifications/`).length, 0);
});

test('reopening and finalising again does not repeat the absence notice', async () => {
  const db = fakeDb({ ...family(), ...marks() });
  await ev.onRegisterFinalized(ctx(db), ids, register('DRAFT'), register('FINALIZED'));
  const again = await ev.onRegisterFinalized(ctx(db), ids, register('DRAFT'), register('FINALIZED'));
  assert.strictEqual(again.created, 0);
  assert.strictEqual(docsIn(db, `${B}/notifications/`).length, 1);
});

// ---- holidays -------------------------------------------------------------

const hol = (o = {}) => ({ date: T('2026-08-12T00:00:00Z'), endDate: null, name: 'Founders day', type: 'SCHOOL', status: 'ACTIVE', ...o });
const notices = (db) => docsIn(db, `${B}/broadcastNotices/`).map((k) => db.store.get(k));

test('a new holiday is announced to the whole branch, once', async () => {
  const db = fakeDb();
  const p = { ...ids, holidayId: 'h1' };
  assert.deepStrictEqual(await ev.onHolidayWritten(ctx(db), p, undefined, hol()), { created: 1, type: 'HOLIDAY_ADDED' });
  const [n] = notices(db);
  assert.deepStrictEqual(
    { t: n.type, a: n.audienceKind, title: n.title, body: n.body, ref: n.refType, id: n.refId, by: n.createdBy },
    { t: 'HOLIDAY_ADDED', a: 'BRANCH', title: 'Holiday added', body: 'Founders day · 12 Aug 2026', ref: 'HOLIDAY', id: 'h1', by: 'system' },
  );
  // the very same event delivered again
  assert.strictEqual((await ev.onHolidayWritten(ctx(db), p, undefined, hol())).created, 0);
  assert.strictEqual(notices(db).length, 1);
});

test('a vacation is announced with its range', async () => {
  const db = fakeDb();
  await ev.onHolidayWritten(ctx(db), { ...ids, holidayId: 'h2' }, undefined, hol({ name: 'Winter break', endDate: T('2026-12-31T00:00:00Z'), date: T('2026-12-24T00:00:00Z') }));
  assert.strictEqual(notices(db)[0].body, 'Winter break · 24 Dec 2026 – 31 Dec 2026');
});

test('only a change that matters notifies; an identical re-save does not', async () => {
  const db = fakeDb();
  const p = { ...ids, holidayId: 'h1' };
  assert.strictEqual(ev.holidayChange(hol(), hol()), null);
  assert.strictEqual(ev.holidayChange(hol(), hol({ description: 'edited text only' })), null);
  assert.strictEqual((await ev.onHolidayWritten(ctx(db), p, hol(), hol())).created, 0);
  assert.strictEqual(ev.holidayChange(hol(), hol({ date: T('2026-08-13T00:00:00Z') })), 'HOLIDAY_UPDATED');
  assert.strictEqual(ev.holidayChange(hol(), hol({ name: 'Renamed' })), 'HOLIDAY_UPDATED');
  assert.strictEqual(ev.holidayChange(hol(), hol({ type: 'FESTIVAL' })), 'HOLIDAY_UPDATED');
  assert.strictEqual(ev.holidayChange(hol(), hol({ endDate: T('2026-08-14T00:00:00Z') })), 'HOLIDAY_UPDATED');
});

test('removing a holiday says it is cancelled; restoring it is announced as added again', async () => {
  assert.strictEqual(ev.holidayChange(hol(), hol({ status: 'INACTIVE' })), 'HOLIDAY_REMOVED');
  assert.strictEqual(ev.holidayChange(hol({ status: 'INACTIVE' }), hol()), 'HOLIDAY_ADDED');
  assert.strictEqual(ev.holidayChange(undefined, hol({ status: 'INACTIVE' })), null); // never announce something not in force
  assert.strictEqual(ev.holidayChange(hol(), undefined), null);
  const db = fakeDb();
  await ev.onHolidayWritten(ctx(db), { ...ids, holidayId: 'h1' }, hol(), hol({ status: 'INACTIVE' }));
  assert.strictEqual(notices(db)[0].title, 'Holiday cancelled');
});

test('two different edits of one holiday are two notices, not one', async () => {
  const db = fakeDb();
  const p = { ...ids, holidayId: 'h1' };
  await ev.onHolidayWritten(ctx(db), p, hol(), hol({ date: T('2026-08-13T00:00:00Z') }));
  await ev.onHolidayWritten(ctx(db), p, hol({ date: T('2026-08-13T00:00:00Z') }), hol({ date: T('2026-08-14T00:00:00Z') }));
  assert.strictEqual(notices(db).length, 2);
});

// ---- fee due reminders ----------------------------------------------------

const inv = (o = {}) => ({ studentId: 'st1', status: 'ISSUED', balanceMinor: 50000, dueDateKey: '2026-08-06', ...o });
const run = (db, extra = {}) => ev.runFeeDueReminders(ctx(db), { today: new Date('2026-08-03T04:00:00Z'), timeZone: 'Asia/Kolkata', ...extra });

test('an invoice due in three days reminds its parent, without an amount', async () => {
  const db = fakeDb({ ...family(), [`${B}/invoices/i1`]: inv() });
  const r = await run(db);
  assert.deepStrictEqual(r, { created: 1, scanned: 1 });
  const n = db.store.get(`${B}/notifications/FEE_DUE__i1__3__pu1`);
  assert.deepStrictEqual(
    { to: n.recipientUserId, type: n.type, title: n.title, body: n.body, ref: n.refType, id: n.refId },
    { to: 'pu1', type: 'FEE_DUE_REMINDER', title: 'Fee due soon', body: 'A fee invoice is due on 6 Aug 2026.', ref: 'INVOICE', id: 'i1' },
  );
  assert.ok(!/50000|500/.test(`${n.title} ${n.body}`));
});

test('an invoice due today gets the "today" reminder', async () => {
  const db = fakeDb({ ...family(), [`${B}/invoices/i1`]: inv({ dueDateKey: '2026-08-03' }) });
  await run(db);
  assert.strictEqual(db.store.get(`${B}/notifications/FEE_DUE__i1__0__pu1`).title, 'Fee due today');
});

test('running the job again, or twice a day, sends nothing new', async () => {
  const db = fakeDb({ ...family(), [`${B}/invoices/i1`]: inv() });
  await run(db);
  assert.deepStrictEqual(await run(db), { created: 0, scanned: 1 });
  assert.strictEqual(docsIn(db, `${B}/notifications/`).length, 1);
});

test('paid, void, settled and not-yet-due invoices are not reminded', async () => {
  const db = fakeDb({
    ...family(),
    [`${B}/invoices/paid`]: inv({ status: 'PAID', balanceMinor: 0 }),
    [`${B}/invoices/void`]: inv({ status: 'VOID' }),
    [`${B}/invoices/zero`]: inv({ balanceMinor: 0 }),
    [`${B}/invoices/later`]: inv({ dueDateKey: '2026-08-20' }),
    [`${B}/invoices/past`]: inv({ dueDateKey: '2026-07-01' }),
  });
  assert.deepStrictEqual(await run(db), { created: 0, scanned: 0 });
});

test('a partly paid invoice is still reminded; the reminder goes only to that student\'s parents', async () => {
  const db = fakeDb({
    ...family(),
    [`${B}/invoices/part`]: inv({ status: 'PARTIALLY_PAID', balanceMinor: 100 }),
    [`${B}/invoices/other`]: inv({ studentId: 'stranger' }),
  });
  const r = await run(db);
  assert.strictEqual(r.created, 1);
  assert.deepStrictEqual(docsIn(db, `${B}/notifications/`), [`${B}/notifications/FEE_DUE__part__3__pu1`]);
});

test('the date is the school\'s day, not UTC\'s', () => {
  // 20:00 UTC on 2 Aug is already 3 Aug 01:30 in India
  assert.strictEqual(ev.dueKeyFor(new Date('2026-08-02T20:00:00Z'), 0, 'Asia/Kolkata'), '2026-08-03');
  assert.strictEqual(ev.dueKeyFor(new Date('2026-08-02T20:00:00Z'), 0, 'UTC'), '2026-08-02');
  assert.strictEqual(ev.dueKeyFor(new Date('2026-08-30T10:00:00Z'), 3, 'UTC'), '2026-09-02'); // month boundary
});

test('SEC-4: more invoices than one page are all reminded, none skipped', async () => {
  const seed = { ...family() };
  for (let i = 0; i < 1200; i++) seed[`${B}/invoices/i${String(i).padStart(4, '0')}`] = inv();
  const db = fakeDb(seed);
  const r = await run(db, { offsets: [3] });
  assert.deepStrictEqual(r, { created: 1200, scanned: 1200 });
});

// ---- multi-country: reminders follow each school's own time zone -----------

/** Two schools, same due date, different zones; each with one parent. */
function twoSchools(zones = {}) {
  const fam = (sid) => ({
    [`schools/${sid}/branches/b1/students/st1/parentLinks/p1`]: { parentId: 'p1', status: 'ACTIVE', canAccessPortal: true },
    [`users/pu-${sid}`]: { schoolId: sid, status: 'ACTIVE', role: 'PARENT', linkedParentId: 'p1' },
    [`schools/${sid}/branches/b1/invoices/i1`]: inv({ dueDateKey: '2026-08-06' }),
  });
  return fakeDb({
    'schools/dxb': { name: 'Dubai', timezone: 'Asia/Dubai', ...zones.dxb },
    'schools/nyc': { name: 'New York', timezone: 'America/New_York', ...zones.nyc },
    ...fam('dxb'),
    ...fam('nyc'),
  });
}
const sent = (db) => docsIn(db, 'schools/').filter((k) => k.includes('/notifications/FEE_DUE__')).map((k) => k.split('/')[1]).sort();
const at = (iso) => ({ today: new Date(iso) });

test('each school is reminded at 08:00 in its own zone, not at one fixed hour', async () => {
  const db = twoSchools();
  // 04:30Z = 08:30 in Dubai, 00:30 in New York: only Dubai is due.
  assert.deepStrictEqual(await ev.runFeeDueReminders(ctx(db), at('2026-08-03T04:30:00Z')), { created: 1, scanned: 1 });
  assert.deepStrictEqual(sent(db), ['dxb']);
  // 12:30Z = 08:30 in New York (UTC-4): now New York is due; Dubai is not repeated.
  assert.deepStrictEqual(await ev.runFeeDueReminders(ctx(db), at('2026-08-03T12:30:00Z')), { created: 1, scanned: 1 });
  assert.deepStrictEqual(sent(db), ['dxb', 'nyc']);
});

test('the due date is judged on the school\'s own calendar day', async () => {
  // New York 2026-08-02 23:30 (03:30Z on the 3rd) is still the 2nd there: its
  // "3 days before 6 Aug" is the 3rd, not the 2nd. Nothing is due in that hour
  // (also outside 08:00), so nothing is sent for either school.
  const db = twoSchools();
  assert.deepStrictEqual(await ev.runFeeDueReminders(ctx(db), at('2026-08-03T03:30:00Z')), { created: 0, scanned: 0 });
  assert.deepStrictEqual(sent(db), []);
});

test('a missed run is retried within the window, and a repeat sends nothing new', async () => {
  const db = twoSchools();
  await ev.runFeeDueReminders(ctx(db), at('2026-08-03T05:30:00Z')); // Dubai 09:30, a retry hour
  assert.deepStrictEqual(sent(db), ['dxb']);
  assert.strictEqual((await ev.runFeeDueReminders(ctx(db), at('2026-08-03T06:30:00Z'))).created, 0); // 10:30, repeat
  assert.deepStrictEqual(await ev.runFeeDueReminders(ctx(db), at('2026-08-03T08:30:00Z')), { created: 0, scanned: 0 }); // 12:30, window over
});

test('a school without a zone (created before Regional settings) keeps the Indian schedule', async () => {
  const db = twoSchools({ dxb: { timezone: undefined } });
  // 03:00Z = 08:30 IST: the zone-less school is reminded; Dubai (07:00 there) would not be.
  await ev.runFeeDueReminders(ctx(db), at('2026-08-03T03:00:00Z'));
  assert.deepStrictEqual(sent(db), ['dxb']);
});

test('localHour', () => {
  assert.strictEqual(ev.localHour(new Date('2026-08-03T04:30:00Z'), 'Asia/Dubai'), 8);
  assert.strictEqual(ev.localHour(new Date('2026-08-03T04:30:00Z'), 'America/New_York'), 0);
  assert.strictEqual(ev.localHour(new Date('2026-01-03T05:30:00Z'), 'America/New_York'), 0); // standard time
});

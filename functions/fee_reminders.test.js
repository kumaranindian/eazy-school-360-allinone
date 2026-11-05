'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const fr = require('./fee_reminders');
const ev = require('./notify_events');

const B = 'schools/s1/branches/b1';
const SET = 'schools/s1/feeReminderSettings/config';
const now = () => new Date('2026-08-03T10:00:00Z');
const at = (iso) => ({ today: new Date(iso) });
const NOON = '2026-08-03T04:00:00Z'; // 09:30 in India: inside the 08:00 window
const family = (sid = 's1', student = 'st1', parent = 'p1', uid = 'pu1') => ({
  [`schools/${sid}/branches/b1/students/${student}/parentLinks/${parent}`]: { parentId: parent, status: 'ACTIVE', canAccessPortal: true },
  [`users/${uid}`]: { schoolId: sid, status: 'ACTIVE', role: 'PARENT', linkedParentId: parent },
});
const inv = (o = {}) => ({ studentId: 'st1', studentName: 'Asha Rao', invoiceNumber: 'INV-7', currency: 'INR', status: 'ISSUED', balanceMinor: 150000, dueDateKey: '2026-08-06', ...o });
const base = (extra = {}) => ({ 'schools/s1': { name: 'S', timezone: 'Asia/Kolkata' }, ...family(), ...extra });
const notes = (db) => [...db.store.keys()].filter((k) => k.includes('/notifications/')).map((k) => k.split('/notifications/')[1]).sort();
const run = (db, when = NOON, log) => ev.runFeeDueReminders({ db, now, log }, at(when));
const custom = (o) => ({ ...fr.defaults(), ...o });

// ---- A. configuration -----------------------------------------------------

test('a school without settings gets the defaults (3 and 0 before; 1, 7, 15 after; 08:00; no amount)', () => {
  const s = fr.effectiveSettings(undefined);
  assert.deepStrictEqual(s.beforeDue.offsets.map((o) => o.days), [3, 0]);
  assert.deepStrictEqual(s.afterDue.offsets.map((o) => o.days), [1, 7, 15]);
  assert.strictEqual(s.deliveryTime, '08:00');
  assert.strictEqual(s.enabled, true);
  assert.strictEqual(s.includeAmount, false);
});

test('custom steps are accepted and sorted; each can be switched off', () => {
  const r = fr.validateSettings(custom({
    beforeDue: { enabled: true, offsets: [{ days: 1, enabled: true }, { days: 10, enabled: false }] },
    afterDue: { enabled: true, offsets: [{ days: 30, enabled: true }, { days: 2, enabled: true }] },
  }));
  assert.deepStrictEqual(r.value.beforeDue.offsets.map((o) => o.days), [10, 1]);
  assert.deepStrictEqual(r.value.afterDue.offsets.map((o) => o.days), [2, 30]);
});

test('invalid, duplicate and out-of-range steps, bad times and wrong types are rejected', () => {
  const bad = (patch) => fr.validateSettings(custom(patch)).errors;
  assert.ok(bad({ beforeDue: { enabled: true, offsets: [{ days: -1, enabled: true }] } }).beforeDue);
  assert.ok(bad({ beforeDue: { enabled: true, offsets: [{ days: 61, enabled: true }] } }).beforeDue);
  assert.ok(bad({ beforeDue: { enabled: true, offsets: [{ days: 2.5, enabled: true }] } }).beforeDue);
  assert.ok(bad({ beforeDue: { enabled: true, offsets: [{ days: '3', enabled: true }] } }).beforeDue);
  assert.match(bad({ afterDue: { enabled: true, offsets: [{ days: 7, enabled: true }, { days: 7, enabled: false }] } }).afterDue, /twice/);
  assert.ok(bad({ afterDue: { enabled: true, offsets: [{ days: 0, enabled: true }] } }).afterDue); // overdue starts at 1
  assert.ok(bad({ afterDue: { enabled: true, offsets: Array.from({ length: 11 }, (_, i) => ({ days: i + 1, enabled: true })) } }).afterDue);
  assert.ok(bad({ deliveryTime: '8am' }).deliveryTime);
  assert.ok(bad({ deliveryTime: '25:00' }).deliveryTime);
  assert.ok(bad({ deliveryTime: '22:00' }).deliveryTime); // the retry window must end before midnight
  assert.ok(bad({ enabled: 'yes' }).enabled);
  assert.ok(fr.validateSettings(null).errors.settings);
  assert.ok(fr.validateSettings([]).errors.settings);
});

test('stored settings that fail validation fall back to the defaults, never to silence', () => {
  assert.deepStrictEqual(fr.effectiveSettings({ enabled: true, deliveryTime: 'junk' }), fr.defaults());
});

test('an invalid time zone on the school falls back to India; a valid one is used', () => {
  assert.strictEqual(fr.validZone('Nowhere/Land'), false);
  assert.strictEqual(fr.validZone('Asia/Dubai'), true);
});

// ---- B. date arithmetic ---------------------------------------------------

test('calendar days: month end, year end, leap year', () => {
  assert.strictEqual(fr.addDays('2026-08-31', 1), '2026-09-01');
  assert.strictEqual(fr.addDays('2026-12-30', 3), '2027-01-02');
  assert.strictEqual(fr.addDays('2028-02-28', 1), '2028-02-29');
  assert.strictEqual(fr.addDays('2027-02-28', 1), '2027-03-01');
  assert.strictEqual(fr.addDays('2026-01-05', -15), '2025-12-21');
  assert.strictEqual(fr.daysBetween('2026-02-27', '2026-03-02'), 3);
});

test('steps look for the right due dates: 3 before, the day, 1 / 7 / 15 after', () => {
  const steps = fr.activeReminders(fr.defaults(), '2026-08-20');
  assert.deepStrictEqual(steps.map((s) => `${s.kind}${s.days}:${s.dueKey}`), [
    'BEFORE3:2026-08-23', 'BEFORE0:2026-08-20', 'AFTER1:2026-08-19', 'AFTER7:2026-08-13', 'AFTER15:2026-08-05',
  ]);
});

test('"today" is the school\'s day, and a DST change does not move the calendar', () => {
  // 03:30Z on 2026-03-08 is 23:30 on the 7th in New York (EST); the clocks go forward that morning.
  assert.strictEqual(fr.civilToday(new Date('2026-03-08T03:30:00Z'), 'America/New_York'), '2026-03-07');
  assert.strictEqual(fr.addDays(fr.civilToday(new Date('2026-03-07T13:00:00Z'), 'America/New_York'), 3), '2026-03-10');
  // 08:00 local the day after spring-forward is 12:00Z (EDT) and still the 8th
  assert.strictEqual(fr.localMinutes(new Date('2026-03-08T12:00:00Z'), 'America/New_York'), 8 * 60);
  assert.strictEqual(fr.civilToday(new Date('2026-11-01T11:00:00Z'), 'America/New_York'), '2026-11-01'); // fall back
});

test('the delivery window opens at the configured time and lasts three hours', () => {
  const z = 'Asia/Kolkata'; // UTC+5:30
  assert.strictEqual(fr.inDeliveryWindow(new Date('2026-08-03T02:00:00Z'), z, '08:00'), false); // 07:30
  assert.strictEqual(fr.inDeliveryWindow(new Date('2026-08-03T02:30:00Z'), z, '08:00'), true); // 08:00
  assert.strictEqual(fr.inDeliveryWindow(new Date('2026-08-03T05:00:00Z'), z, '08:00'), true); // 10:30
  assert.strictEqual(fr.inDeliveryWindow(new Date('2026-08-03T05:30:00Z'), z, '08:00'), false); // 11:00
  assert.strictEqual(fr.inDeliveryWindow(new Date('2026-08-03T05:30:00Z'), z, '10:30'), true); // custom 10:30 (11:00 local)
});

// ---- C. invoice eligibility -----------------------------------------------

test('eligibility: only live, issued, unsettled invoices with a due date', () => {
  assert.strictEqual(fr.isRemindable(inv()), true);
  assert.strictEqual(fr.isRemindable(inv({ status: 'PARTIALLY_PAID', balanceMinor: 100 })), true);
  for (const bad of [
    inv({ status: 'PAID', balanceMinor: 0 }), inv({ status: 'CANCELLED' }), inv({ status: 'VOID' }), inv({ status: 'DRAFT' }),
    inv({ balanceMinor: 0 }), inv({ balanceMinor: -5 }), inv({ dueDateKey: '' }), inv({ dueDateKey: undefined }), inv({ dueDateKey: '6/8/2026' }), null,
  ]) assert.strictEqual(fr.isRemindable(bad), false, JSON.stringify(bad));
});

// ---- message text ---------------------------------------------------------

test('messages: before, today, overdue; amount and invoice number only when switched on', () => {
  const on = custom({ includeAmount: true, includeInvoiceNumber: true });
  const off = fr.defaults();
  assert.strictEqual(
    fr.buildMessage({ kind: 'BEFORE', days: 3 }, inv(), on).body,
    'Dear Parent, the fee invoice for Asha Rao (invoice INV-7) is due on 6 Aug 2026. Amount: ₹1,500.00. Please complete the payment on time.',
  );
  assert.strictEqual(fr.buildMessage({ kind: 'BEFORE', days: 0 }, inv(), on).body,
    'Dear Parent, the fee payment for Asha Rao (invoice INV-7) is due today. Amount: ₹1,500.00.');
  const over = fr.buildMessage({ kind: 'AFTER', days: 7 }, inv(), on);
  assert.strictEqual(over.title, 'Fee overdue');
  assert.strictEqual(over.body,
    'Dear Parent, the fee payment for Asha Rao (invoice INV-7) is overdue by 7 days. Outstanding amount: ₹1,500.00. Please contact the school office if payment has already been made.');
  assert.match(fr.buildMessage({ kind: 'AFTER', days: 1 }, inv(), off).body, /overdue by 1 day\./);
  assert.ok(!/₹|INV-7/.test(fr.buildMessage({ kind: 'AFTER', days: 7 }, inv(), off).body));
  assert.match(fr.formatMoney(5000, 'KWD'), /5/); // currencies with other decimals do not throw
  assert.strictEqual(fr.formatMoney(12345, 'JPY').includes('12,345'), true); // zero-decimal currency
});

// ---- D. delivery ----------------------------------------------------------

test('overdue steps: 1, 7 and 15 days after the due date notify as FEE_OVERDUE_REMINDER', async () => {
  const db = fakeDb(base({
    [`${B}/invoices/a`]: inv({ dueDateKey: '2026-08-02' }), // 1 day overdue
    [`${B}/invoices/b`]: inv({ dueDateKey: '2026-07-27' }), // 7
    [`${B}/invoices/c`]: inv({ dueDateKey: '2026-07-19' }), // 15
    [`${B}/invoices/d`]: inv({ dueDateKey: '2026-07-30' }), // 4: not a step
  }));
  const r = await run(db);
  assert.deepStrictEqual(r, { created: 3, scanned: 3 });
  assert.deepStrictEqual(notes(db), ['FEE_OVERDUE__a__1__pu1', 'FEE_OVERDUE__b__7__pu1', 'FEE_OVERDUE__c__15__pu1']);
  const n = db.store.get(`${B}/notifications/FEE_OVERDUE__b__7__pu1`);
  assert.deepStrictEqual({ t: n.type, off: n.reminderOffset, st: n.studentId, due: n.dueDateKey }, { t: 'FEE_OVERDUE_REMINDER', off: -7, st: 'st1', due: '2026-07-27' });
  assert.match(n.body, /overdue by 7 days/);
});

test('the settings drive everything: custom days, delivery time, amount and number in the text', async () => {
  const db = fakeDb(base({
    [SET]: custom({
      deliveryTime: '10:00',
      includeAmount: true,
      includeInvoiceNumber: true,
      beforeDue: { enabled: true, offsets: [{ days: 5, enabled: true }, { days: 3, enabled: false }] },
      afterDue: { enabled: false, offsets: [{ days: 1, enabled: true }] },
    }),
    [`${B}/invoices/five`]: inv({ dueDateKey: '2026-08-08' }),
    [`${B}/invoices/three`]: inv({ dueDateKey: '2026-08-06' }), // step switched off
    [`${B}/invoices/late`]: inv({ dueDateKey: '2026-08-02' }), // whole overdue group off
  }));
  // 09:30 IST is before this school's 10:00
  assert.deepStrictEqual(await run(db, NOON), { created: 0, scanned: 0 });
  // 10:30 IST
  assert.deepStrictEqual(await run(db, '2026-08-03T05:00:00Z'), { created: 1, scanned: 1 });
  assert.deepStrictEqual(notes(db), ['FEE_DUE__five__5__pu1']);
  assert.match(db.store.get(`${B}/notifications/FEE_DUE__five__5__pu1`).body, /\(invoice INV-7\).*Amount: ₹1,500\.00/);
});

test('a school with reminders disabled sends nothing, and says why', async () => {
  const logs = [];
  const db = fakeDb(base({ [SET]: custom({ enabled: false }), [`${B}/invoices/i1`]: inv() }));
  assert.deepStrictEqual(await run(db, NOON, (e, f) => logs.push([e, f])), { created: 0, scanned: 0 });
  assert.deepStrictEqual(logs, [['fee reminders: school skipped', { schoolId: 's1', reason: 'disabled' }]]);
});

test('a paid, cancelled or voided invoice, a zero balance and a missing due date get nothing', async () => {
  const db = fakeDb(base({
    [`${B}/invoices/paid`]: inv({ status: 'PAID', balanceMinor: 0 }),
    [`${B}/invoices/cancelled`]: inv({ status: 'CANCELLED' }),
    [`${B}/invoices/void`]: inv({ status: 'VOID' }),
    [`${B}/invoices/zero`]: inv({ balanceMinor: 0 }),
    [`${B}/invoices/nodue`]: inv({ dueDateKey: undefined }),
  }));
  assert.deepStrictEqual(await run(db), { created: 0, scanned: 0 });
});

test('a payment that lands between the query and the send stops the reminder, and the amount is the current balance', async () => {
  const db = fakeDb(base({ [SET]: custom({ includeAmount: true }), [`${B}/invoices/i1`]: inv(), [`${B}/invoices/i2`]: inv() }));
  // i1 is settled and i2 part-paid after the query has read them: wrap the re-read
  const real = db.collectionGroup;
  db.collectionGroup = (name) => {
    const q = real(name);
    const get = q.get;
    q.get = async () => {
      const r = await get();
      db.store.set(`${B}/invoices/i1`, inv({ status: 'PAID', balanceMinor: 0 }));
      db.store.set(`${B}/invoices/i2`, inv({ status: 'PARTIALLY_PAID', balanceMinor: 40000 }));
      return r;
    };
    return q;
  };
  const r = await run(db);
  assert.strictEqual(r.created, 1);
  assert.deepStrictEqual(notes(db), ['FEE_DUE__i2__3__pu1']);
  assert.match(db.store.get(`${B}/notifications/FEE_DUE__i2__3__pu1`).body, /₹400\.00/);
});

test('every authorized parent is notified; two children of one parent get one each; strangers none', async () => {
  const db = fakeDb(base({
    [`${B}/students/st1/parentLinks/p9`]: { parentId: 'p9', status: 'ACTIVE', canAccessPortal: true },
    'users/pu9': { schoolId: 's1', status: 'ACTIVE', role: 'PARENT', linkedParentId: 'p9' },
    [`${B}/students/st2/parentLinks/p1`]: { parentId: 'p1', status: 'ACTIVE', canAccessPortal: true },
    [`${B}/invoices/c1`]: inv({ studentName: 'Asha' }),
    [`${B}/invoices/c2`]: inv({ studentId: 'st2', studentName: 'Ravi' }),
    [`${B}/invoices/x`]: inv({ studentId: 'stranger' }),
  }));
  await run(db);
  assert.deepStrictEqual(notes(db), ['FEE_DUE__c1__3__pu1', 'FEE_DUE__c1__3__pu9', 'FEE_DUE__c2__3__pu1']);
  assert.match(db.store.get(`${B}/notifications/FEE_DUE__c2__3__pu1`).body, /Ravi/);
});

test('running twice, or two runs at once, creates each reminder once', async () => {
  const db = fakeDb(base({ [`${B}/invoices/i1`]: inv() }));
  const logs = [];
  const both = await Promise.all([run(db), run(db, NOON, (e) => logs.push(e))]);
  assert.strictEqual(both[0].created + both[1].created, 1);
  assert.strictEqual(notes(db).length, 1);
  assert.deepStrictEqual(await run(db), { created: 0, scanned: 1 });
});

test('rollout: a before-due reminder already sent under the old fixed policy is not sent again', async () => {
  const db = fakeDb(base({
    [`${B}/invoices/i1`]: inv(),
    [`${B}/notifications/FEE_DUE__i1__3__pu1`]: { type: 'FEE_DUE_REMINDER' }, // written by the previous version
  }));
  assert.deepStrictEqual(await run(db), { created: 0, scanned: 1 });
});

test('a failure on one invoice does not stop the others, and the next run retries it', async () => {
  const db = fakeDb(base({
    [`${B}/students/stboom/parentLinks/pb`]: { parentId: 'pboom', status: 'ACTIVE', canAccessPortal: true },
    'users/pub': { schoolId: 's1', status: 'ACTIVE', role: 'PARENT', linkedParentId: 'pboom' },
    [`${B}/invoices/bad`]: inv({ studentId: 'stboom' }),
    [`${B}/invoices/good`]: inv(),
  }));
  const real = db.collection;
  let broke = true;
  db.collection = (p) => {
    const c = real(p);
    if (p !== 'users') return c;
    // the parent lookup for one family fails while the outage lasts
    return { where: (f, op, v) => {
      const w = (conds) => ({
        where: (f2, o2, v2) => w([...conds, [f2, v2]]),
        get: async () => {
          if (broke && conds.some(([, v3]) => v3 === 'pboom')) throw Object.assign(new Error('unavailable'), { code: 14 });
          return conds.reduce((q, [f3, v3]) => q.where(f3, '==', v3), c).get();
        },
      });
      return w([[f, v]]);
    } };
  };
  const logs = [];
  assert.deepStrictEqual(await run(db, NOON, (e) => logs.push(e)), { created: 1, scanned: 2, failed: 1 });
  assert.ok(logs.includes('fee reminders: invoice failed'));
  broke = false;
  assert.deepStrictEqual(await run(db), { created: 1, scanned: 2 });
  assert.deepStrictEqual(notes(db), ['FEE_DUE__bad__3__pub', 'FEE_DUE__good__3__pu1']);
});

test('one school\'s broken settings read does not stop another school', async () => {
  const db = fakeDb({
    'schools/s1': { timezone: 'Asia/Kolkata' }, ...family(), [`${B}/invoices/i1`]: inv(),
    'schools/s2': { timezone: 'Asia/Kolkata' }, ...family('s2', 'st1', 'q1', 'qu1'), 'schools/s2/branches/b1/invoices/i1': inv(),
  });
  const real = db.collection;
  db.collection = (p) => {
    const c = real(p);
    if (p !== 'schools') return c;
    return { ...c, doc: (id) => (id === 's1'
      ? { collection: () => ({ doc: () => ({ get: async () => { throw new Error('unavailable'); } }) }) }
      : c.doc(id)) };
  };
  const logs = [];
  const r = await run(db, NOON, (e) => logs.push(e));
  assert.strictEqual(r.created, 1);
  assert.deepStrictEqual(notes(db), ['FEE_DUE__i1__3__qu1']);
  assert.ok(logs.includes('fee reminders: school failed'));
});

test('schools never see each other\'s invoices: settings and parents are per school', async () => {
  const db = fakeDb({
    'schools/s1': { timezone: 'Asia/Kolkata' }, ...family(), [`${B}/invoices/i1`]: inv(),
    'schools/s2': { timezone: 'Asia/Kolkata' }, ...family('s2', 'st1', 'q1', 'qu1'), 'schools/s2/branches/b1/invoices/i1': inv(),
    'schools/s2/feeReminderSettings/config': custom({ enabled: false }),
  });
  await run(db);
  assert.deepStrictEqual(notes(db), ['FEE_DUE__i1__3__pu1']); // s2 is switched off; s1 keeps going
});

test('logs carry ids and counts, never names or amounts', async () => {
  const logs = [];
  const db = fakeDb(base({ [SET]: custom({ includeAmount: true }), [`${B}/invoices/i1`]: inv() }));
  await run(db, NOON, (e, f) => logs.push(JSON.stringify([e, f])));
  await run(db, NOON, (e, f) => logs.push(JSON.stringify([e, f])));
  assert.ok(logs.length > 0);
  assert.ok(logs.every((l) => !/Asha|1500|150000|INV-7|pu1/.test(l)), logs.join('\n'));
});

// ---- E. who may change the settings ---------------------------------------

const world = () => fakeDb({
  'users/admin': { schoolId: 's1', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
  'users/other-admin': { schoolId: 's2', role: 'SCHOOL_ADMIN', status: 'ACTIVE' },
  'users/branch': { schoolId: 's1', role: 'BRANCH_ADMIN', branchId: 'b1', status: 'ACTIVE' },
  'users/teacher': { schoolId: 's1', role: 'TEACHER', status: 'ACTIVE' },
  'users/parent': { schoolId: 's1', role: 'PARENT', status: 'ACTIVE' },
});
const save = (db, uid, data) => fr.updateFeeReminderSettings({ db, now: 'TS' }, uid, {}, data);

test('only the school admin of that school can save; others and cross-school calls are refused', async () => {
  const db = world();
  const good = { schoolId: 's1', settings: fr.defaults() };
  assert.deepStrictEqual((await save(db, 'teacher', good)).error, 'PERMISSION_DENIED');
  assert.deepStrictEqual((await save(db, 'parent', good)).error, 'PERMISSION_DENIED');
  assert.deepStrictEqual((await save(db, 'branch', good)).error, 'PERMISSION_DENIED');
  assert.deepStrictEqual((await save(db, 'other-admin', good)).error, 'PERMISSION_DENIED'); // another school's admin
  assert.deepStrictEqual((await save(db, 'nobody', good)).error, 'PERMISSION_DENIED');
  assert.strictEqual(db.store.has(SET), false);
  const ok = await save(db, 'admin', good);
  assert.ok(ok.result);
  const saved = db.store.get(SET);
  assert.deepStrictEqual({ s: saved.schoolId, by: saved.updatedBy, at: saved.updatedAt }, { s: 's1', by: 'admin', at: 'TS' });
  assert.strictEqual(db.store.has('schools/s2/feeReminderSettings/config'), false);
});

test('invalid settings are refused by the backend and nothing is written', async () => {
  const db = world();
  const r = await save(db, 'admin', { schoolId: 's1', settings: custom({ deliveryTime: 'late' }) });
  assert.strictEqual(r.error, 'INVALID_ARGUMENT');
  assert.match(r.reason, /deliveryTime/);
  assert.strictEqual((await save(db, 'admin', { schoolId: '', settings: fr.defaults() })).error, 'INVALID_ARGUMENT');
  assert.strictEqual(db.store.has(SET), false);
});

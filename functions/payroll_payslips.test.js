'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const r = require('./payroll_runs');
const ps = require('./payroll_payslips');

const T = {};
const ts = (key) => new Date(`${key}T00:00:00Z`);
const B = 'schools/sA/branches/b1';
const NOV = ['02', '03', '04', '05', '06', '09', '10', '11', '12', '13', '16', '17', '18', '19', '20', '23', '24', '25', '26', '27', '30'].map((d) => `2026-11-${d}`);
const structure = (staff, basic) => [`${B}/salaryStructures/${staff}_00001`, {
  staffId: staff, seq: 1, effectiveFrom: '2026-04-01', latest: true, currency: 'INR',
  lines: [{ componentId: 'pc_basic', nameSnapshot: 'Basic salary', kind: 'EARNING', calc: 'FIXED', amountMinor: basic }],
  grossMinor: basic, deductionsMinor: 0, netMinor: basic,
}];
const presentAll = (staff) => NOV.map((d) => [`${B}/staffAttendance/${d}_${staff}`, { staffId: staff, dateKey: d, status: 'PRESENT' }]);

const seed = (extra = {}) => ({
  'schools/sA': { name: 'Rosewood High', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
  'schools/sB': { name: 'B', status: 'ACTIVE' },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN', displayName: 'Olive Owner' },
  'users/owner2': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  'users/t1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/t2': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/t3': { schoolId: 'sA', branchId: 'b1', status: 'INACTIVE', role: 'TEACHER' },
  'users/t4': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/parent': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  'users/otherTeacher': { schoolId: 'sB', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/ba2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  [B]: { name: 'Main campus' },
  [`${B}/staff/st1`]: { firstName: 'Asha', lastName: 'Rao', employeeCode: 'E1', status: 'ACTIVE', joiningDate: ts('2020-06-01'), userId: 't1' },
  [`${B}/staff/st2`]: { firstName: 'Bala', employeeCode: 'E2', status: 'ACTIVE', joiningDate: ts('2020-06-01'), userId: 't2' },
  [`${B}/staff/st3`]: { firstName: 'Chitra', employeeCode: 'E3', status: 'ACTIVE', joiningDate: ts('2020-06-01'), userId: 't3' },
  [`${B}/staff/st4`]: { firstName: 'Dev', employeeCode: 'E4', status: 'ACTIVE', joiningDate: ts('2020-06-01') },
  ...Object.fromEntries([structure('st1', 2100000), structure('st2', 4200000), structure('st3', 1000000), structure('st4', 1000000), ...presentAll('st1'), ...presentAll('st2'), ...presentAll('st3'), ...presentAll('st4')]),
  ...extra,
});
const env = (extra) => {
  const db = fakeDb(seed(extra));
  return { db, ctx: { db, now: 'TS', wall: () => new Date('2026-11-30T12:00:00Z') } };
};
const base = (extra = {}) => ({ schoolId: 'sA', branchId: 'b1', period: '2026-11', ...extra });
const notices = (db) => [...db.store.entries()].filter(([k]) => k.includes('/notifications/')).map(([k, v]) => ({ id: k.split('/').pop(), ...v }));
async function paidRun(ctx) {
  await r.createPayrollRun(ctx, 'fin', T, base());
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: { kind: 'EARNING', label: 'Diwali bonus', amountMinor: 500000, reason: 'Internal: trust approved this' } }));
  await r.approvePayrollRun(ctx, 'owner', T, base());
  return r.payPayrollRun(ctx, 'fin', T, base({ payment: { paymentMode: 'BANK_TRANSFER', paymentReference: 'NEFT-1', paidDate: '2026-11-30' } }));
}

test('paying publishes: one notice per staff member with an active login, naming the month and never an amount', async () => {
  const { ctx, db } = env();
  const out = await paidRun(ctx);
  assert.equal(out.result.status, 'PAID');
  assert.equal(out.result.noticesCreated, 2, 't1 and t2 only: t3 is inactive and st4 has no login');
  const n = notices(db).sort((a, b) => a.id.localeCompare(b.id));
  assert.deepEqual(n.map((x) => x.id), ['PAYSLIP_PUBLISHED__2026-11__t1', 'PAYSLIP_PUBLISHED__2026-11__t2']);
  assert.deepEqual([n[0].type, n[0].audience, n[0].recipientUserId, n[0].refType, n[0].refId, n[0].branchId, n[0].readAt], ['PAYSLIP_PUBLISHED', 'USER', 't1', 'PAYSLIP', '2026-11', 'b1', null]);
  assert.equal(n[0].body, 'Your payslip for November 2026 is available.');
  assert.equal(/\d{4,}|₹|INR/.test(`${n[0].title} ${n[0].body}`.replace('2026', '')), false, 'no amount on a lock screen');
  assert.equal((await db.collection('schools').doc('sA').collection('branches').doc('b1').collection('payrollRuns').doc('2026-11').get()).data().publishedAt, 'TS');
});

test('a repeated payment completes missing notices and never duplicates them', async () => {
  const { ctx, db } = env();
  await paidRun(ctx);
  db.store.delete(`${B}/notifications/PAYSLIP_PUBLISHED__2026-11__t2`);
  const again = await r.payPayrollRun(ctx, 'owner', T, base({ payment: { paymentMode: 'CASH' } }));
  assert.equal(again.result.duplicate, true);
  assert.equal(again.result.noticesCreated, 1, 'only the missing one');
  assert.equal(notices(db).length, 2);
  assert.equal((await r.payPayrollRun(ctx, 'owner', T, base({ payment: { paymentMode: 'CASH' } }))).result.noticesCreated, 0);
});

test('nothing is readable before the run is paid, in any earlier state', async () => {
  const { ctx } = env();
  await r.createPayrollRun(ctx, 'fin', T, base());
  const get = () => ps.getMyPayslip(ctx, 't1', T, base());
  assert.equal((await get()).error, 'NOT_FOUND', 'calculated');
  assert.deepEqual((await ps.listMyPayslips(ctx, 't1', T, { schoolId: 'sA' })).result.payslips, []);
  await r.approvePayrollRun(ctx, 'owner', T, base());
  assert.equal((await get()).error, 'NOT_FOUND', 'approved');
  await r.payPayrollRun(ctx, 'fin', T, base({ payment: { paymentMode: 'CASH' } }));
  assert.ok((await get()).result, 'paid');
});

test('a cancelled run is never readable', async () => {
  const { ctx } = env();
  await r.createPayrollRun(ctx, 'fin', T, base());
  await r.cancelPayrollRun(ctx, 'fin', T, base({ reason: 'Wrong data used for the month' }));
  assert.equal((await ps.getMyPayslip(ctx, 't1', T, base())).error, 'NOT_FOUND');
  assert.deepEqual((await ps.listMyPayslips(ctx, 't1', T, { schoolId: 'sA' })).result.payslips, []);
});

test('a staff member reads their own payslip: figures, the school, the one-off item; no warnings, no internal reasons', async () => {
  const { ctx } = env();
  await paidRun(ctx);
  const list = (await ps.listMyPayslips(ctx, 't1', T, { schoolId: 'sA' })).result.payslips;
  assert.deepEqual(list, [{ branchId: 'b1', period: '2026-11', paidDate: '2026-11-30', netMinor: 2600000, currency: 'INR' }]);
  const p = (await ps.getMyPayslip(ctx, 't1', T, base())).result.payslip;
  assert.deepEqual([p.schoolName, p.branchName, p.staffName, p.employeeCode, p.paidDate, p.paymentMode, p.netMinor, p.grossMinor], ['Rosewood High', 'Main campus', 'Asha Rao', 'E1', '2026-11-30', 'BANK_TRANSFER', 2600000, 2600000]);
  assert.deepEqual(p.adjustments, [{ label: 'Diwali bonus', kind: 'EARNING', amountMinor: 500000 }]);
  assert.equal(p.lines[0].name, 'Basic salary');
  assert.deepEqual([p.workingDays, p.paidDays, p.unpaidDays], [21, 21, 0]);
  const text = JSON.stringify(p);
  for (const hidden of ['Internal: trust approved this', 'warnings', 'NEFT-1', 'createdBy', 'baseGross']) assert.equal(text.includes(hidden), false, hidden);
});

test('a staff member can read ONLY their own: no id is accepted from the client', async () => {
  const { ctx } = env();
  await paidRun(ctx);
  const mine = (await ps.getMyPayslip(ctx, 't2', T, base({ staffId: 'st1', userId: 't1', uid: 't1' }))).result.payslip;
  assert.equal(mine.staffName, 'Bala', 'a staffId in the request is ignored');
  assert.equal(mine.netMinor, 4200000);
  assert.equal((await ps.listMyPayslips(ctx, 't2', T, { schoolId: 'sA', staffId: 'st1' })).result.payslips[0].netMinor, 4200000);
});

test('who is refused: parent, no staff record, another school, deactivated, branch admin elsewhere, ghost', async () => {
  const { ctx } = env();
  await paidRun(ctx);
  for (const u of ['parent', 'otherTeacher', 't3', 'ghost']) {
    assert.equal((await ps.getMyPayslip(ctx, u, T, base())).error, 'PERMISSION_DENIED', u);
    assert.equal((await ps.listMyPayslips(ctx, u, T, { schoolId: 'sA' })).error, 'PERMISSION_DENIED', `list ${u}`);
  }
  // signed in to the school and a staff role, but not a staff member of this branch / any branch
  assert.equal((await ps.getMyPayslip(ctx, 't4', T, base())).error, 'NOT_FOUND');
  assert.deepEqual((await ps.listMyPayslips(ctx, 't4', T, { schoolId: 'sA' })).result.payslips, []);
  assert.equal((await ps.getMyPayslip(ctx, 'ba2', T, base())).error, 'NOT_FOUND', 'a branch admin of another branch');
  assert.equal((await ps.getMyPayslip(ctx, 'owner', T, base())).error, 'NOT_FOUND', 'a school admin with no staff record');
  for (const bad of [{ branchId: '../b' }, { period: '2026-13' }, { period: undefined }, { schoolId: '../x' }]) {
    assert.equal((await ps.getMyPayslip(ctx, 't1', T, base(bad))).error, 'PERMISSION_DENIED', JSON.stringify(bad));
  }
  assert.equal((await ps.getMyPayslip(ctx, 't1', T, base({ branchId: 'b2' }))).error, 'NOT_FOUND');
});

test('a school admin or finance user who is also a staff member reads their own', async () => {
  const { ctx } = env({ [`${B}/staff/st5`]: { firstName: 'Olive', employeeCode: 'E5', status: 'ACTIVE', joiningDate: ts('2020-06-01'), userId: 'owner' }, ...Object.fromEntries([structure('st5', 900000), ...presentAll('st5')]), [`${B}/staff/st6`]: { firstName: 'Fay', employeeCode: 'E6', status: 'ACTIVE', joiningDate: ts('2020-06-01'), userId: 'fin' }, ...Object.fromEntries([structure('st6', 800000), ...presentAll('st6')]) });
  await paidRun(ctx);
  assert.equal((await ps.getMyPayslip(ctx, 'owner', T, base())).result.payslip.netMinor, 900000);
  assert.equal((await ps.getMyPayslip(ctx, 'fin', T, base())).result.payslip.netMinor, 800000);
});

test('module off or suspended school: nothing is readable', async () => {
  const off = env({ 'schools/sA': { name: 'A', status: 'ACTIVE', features: { payroll: false } } });
  assert.equal((await ps.getMyPayslip(off.ctx, 't1', T, base())).error, 'PERMISSION_DENIED');
  const susp = env({ 'schools/sA': { name: 'A', status: 'SUSPENDED' } });
  assert.equal((await ps.listMyPayslips(susp.ctx, 't1', T, { schoolId: 'sA' })).error, 'PERMISSION_DENIED');
});

test('reads write nothing', async () => {
  const { ctx, db } = env();
  await paidRun(ctx);
  const before = JSON.stringify([...db.store.entries()]);
  await ps.getMyPayslip(ctx, 't1', T, base());
  await ps.listMyPayslips(ctx, 't1', T, { schoolId: 'sA' });
  assert.equal(JSON.stringify([...db.store.entries()]), before);
});

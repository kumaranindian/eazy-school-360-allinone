'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const r = require('./payroll_runs');
const reg = require('./payroll_register');

const T = {};
const ts = (key) => new Date(`${key}T00:00:00Z`);
const B = 'schools/sA/branches/b1';
const B2 = 'schools/sA/branches/b2';
const NOV = ['02', '03', '04', '05', '06', '09', '10', '11', '12', '13', '16', '17', '18', '19', '20', '23', '24', '25', '26', '27', '30'].map((d) => `2026-11-${d}`);
const structure = (staff, lines) => [`${B}/salaryStructures/${staff}_00001`, {
  staffId: staff, seq: 1, effectiveFrom: '2026-04-01', latest: true, currency: 'INR', lines,
  grossMinor: 0, deductionsMinor: 0, netMinor: 0,
}];
const basic = (n) => ({ componentId: 'pc_basic', nameSnapshot: 'Basic salary', kind: 'EARNING', calc: 'FIXED', amountMinor: n });
const hra = { componentId: 'pc_hra', nameSnapshot: 'HRA', kind: 'EARNING', calc: 'PERCENT', percentBp: 4000, basisId: 'pc_basic', amountMinor: 840000 };
const pf = { componentId: 'pc_pf', nameSnapshot: 'Provident fund', kind: 'DEDUCTION', calc: 'PERCENT', percentBp: 1200, basisId: 'pc_basic', amountMinor: 252000 };
const presentAll = (staff) => NOV.map((d) => [`${B}/staffAttendance/${d}_${staff}`, { staffId: staff, dateKey: d, status: 'PRESENT' }]);
const paidRunDoc = (period, net, extra = {}) => ({ period, status: 'PAID', currency: 'INR', payslipCount: 3, grossMinor: net + 100, deductionsMinor: 100, netMinor: net, unrecoveredDeductionMinor: 0, paidDate: `${period}-28`, paymentMode: 'CASH', expenseNumber: `EXP-${period.slice(0, 4)}-${String(Number(period.slice(5))).padStart(5, '0')}`, ...extra });

const seed = (extra = {}) => ({
  'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/owner2': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  'users/finB2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'FINANCE' },
  'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/otherOwner': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  [B]: { name: 'Main campus' },
  [B2]: { name: 'North campus' },
  [`${B}/staff/st1`]: { firstName: 'Asha', lastName: 'Rao', employeeCode: 'E1', status: 'ACTIVE', joiningDate: ts('2020-06-01') },
  [`${B}/staff/st2`]: { firstName: '=HYPERLINK("http://evil")', employeeCode: 'E2', status: 'ACTIVE', joiningDate: ts('2020-06-01') },
  ...Object.fromEntries([structure('st1', [basic(2100000), hra, pf]), structure('st2', [basic(4200000)]), ...presentAll('st1'), ...presentAll('st2')]),
  [`${B}/payrollRuns/2026-09`]: paidRunDoc('2026-09', 5000000),
  [`${B}/payrollRuns/2026-10`]: paidRunDoc('2026-10', 5100000),
  [`${B}/payrollRuns/2026-08`]: { ...paidRunDoc('2026-08', 4900000), status: 'CANCELLED' },
  [`${B2}/payrollRuns/2026-10`]: paidRunDoc('2026-10', 1000000),
  [`${B}/payrollRuns/2026-07`]: { ...paidRunDoc('2026-07', 4800000), status: 'CALCULATED' },
  ...extra,
});
const env = (extra) => {
  const db = fakeDb(seed(extra));
  return { db, ctx: { db, now: 'TS', wall: () => new Date('2026-11-30T12:00:00Z') } };
};
const base = (extra = {}) => ({ schoolId: 'sA', branchId: 'b1', period: '2026-11', ...extra });
const range = (extra = {}) => ({ schoolId: 'sA', fromPeriod: '2026-07', toPeriod: '2026-11', ...extra });
async function paidNovember(ctx) {
  await r.createPayrollRun(ctx, 'fin', T, base());
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: { kind: 'EARNING', label: 'Diwali bonus', amountMinor: 500000, reason: 'Festival bonus agreed by the trust' } }));
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st2', adjustment: { kind: 'DEDUCTION', label: 'Loan', amountMinor: 100000, reason: 'Salary advance recovery agreed' } }));
  await r.approvePayrollRun(ctx, 'owner', T, base());
  return r.payPayrollRun(ctx, 'fin', T, base({ payment: { paymentMode: 'BANK_TRANSFER', paidDate: '2026-11-30' } }));
}

test('range validation', () => {
  const ok = reg.validateRange({ fromPeriod: '2026-01', toPeriod: '2026-11' }, '2026-11');
  assert.ok(ok.value);
  for (const bad of [{}, { fromPeriod: '2026-01' }, { fromPeriod: '2026-11', toPeriod: '2026-01' }, { fromPeriod: '2026-01', toPeriod: '2026-12' }, { fromPeriod: '2024-01', toPeriod: '2026-11' }, { fromPeriod: '2026-13', toPeriod: '2026-11' }, { fromPeriod: 5, toPeriod: '2026-11' }, null]) {
    assert.ok(reg.validateRange(bad, '2026-11').errors, JSON.stringify(bad));
  }
  assert.ok(reg.validateRange({ fromPeriod: '2024-12', toPeriod: '2026-11' }, '2026-11').value, 'exactly 24 months');
});

test('the register lists PAID runs only, newest first, with totals', async () => {
  const { ctx } = env();
  const out = (await reg.getPayrollRegister(ctx, 'fin', T, range({ branchId: 'b1' }))).result;
  assert.deepEqual(out.rows.map((x) => [x.period, x.netMinor]), [['2026-10', 5100000], ['2026-09', 5000000]], 'a cancelled and a calculated run are not a record of payment');
  assert.deepEqual([out.totals.runs, out.totals.netMinor, out.totals.payslipCount], [2, 10100000, 6]);
  assert.deepEqual([out.currency, out.whole, out.rows[0].expenseNumber, out.rows[0].paymentMode], ['INR', false, 'EXP-2026-00010', 'CASH']);
});

test('the range narrows the register', async () => {
  const { ctx } = env();
  const out = (await reg.getPayrollRegister(ctx, 'fin', T, range({ branchId: 'b1', fromPeriod: '2026-10', toPeriod: '2026-10' }))).result;
  assert.deepEqual(out.rows.map((x) => x.period), ['2026-10']);
});

test('the whole school: a school admin sees every branch; finance and others do not', async () => {
  const { ctx } = env();
  const out = (await reg.getPayrollRegister(ctx, 'owner', T, range())).result;
  assert.equal(out.whole, true);
  assert.deepEqual(out.rows.map((x) => [x.period, x.branchName, x.netMinor]), [['2026-10', 'Main campus', 5100000], ['2026-10', 'North campus', 1000000], ['2026-09', 'Main campus', 5000000]]);
  assert.equal(out.totals.netMinor, 11100000);
  for (const u of ['fin', 'finB2', 'ba1', 'teacher', 'otherOwner', 'ghost']) {
    assert.equal((await reg.getPayrollRegister(ctx, u, T, range())).error, 'PERMISSION_DENIED', `whole ${u}`);
  }
});

test('a branch: its finance and any school admin; not another branch, branch admin or teacher', async () => {
  const { ctx } = env();
  for (const u of ['owner', 'fin']) assert.ok((await reg.getPayrollRegister(ctx, u, T, range({ branchId: 'b1' }))).result, u);
  for (const u of ['finB2', 'ba1', 'teacher', 'otherOwner', 'ghost']) assert.equal((await reg.getPayrollRegister(ctx, u, T, range({ branchId: 'b1' }))).error, 'PERMISSION_DENIED', u);
  assert.equal((await reg.getPayrollRegister(ctx, 'owner', T, range({ branchId: '../b' }))).error, 'PERMISSION_DENIED');
  assert.equal((await reg.getPayrollRegister(ctx, 'owner', T, range({ toPeriod: '2026-12', branchId: 'b1' }))).error, 'INVALID_ARGUMENT');
});

test('module off: nothing is returned', async () => {
  const { ctx } = env({ 'schools/sA': { name: 'A', status: 'ACTIVE', features: { payroll: false } } });
  assert.equal((await reg.getPayrollRegister(ctx, 'owner', T, range({ branchId: 'b1' }))).error, 'PERMISSION_DENIED');
});

test('the CSV: one row per person, one column per component, one-off items, totals, money in plain decimals', async () => {
  const { ctx } = env();
  await paidNovember(ctx);
  const out = (await reg.exportPayrollRegister(ctx, 'fin', T, base())).result;
  assert.deepEqual([out.rows, out.currency, out.period], [2, 'INR', '2026-11']);
  const lines = out.csv.split('\r\n');
  assert.equal(lines[0], 'employee_code,name,working_days,paid_days,unpaid_days,Basic salary,HRA,one_off_earnings,Provident fund,one_off_deductions,total_earnings,total_deductions,net_pay,currency,payment_mode,paid_date');
  const asha = lines.find((l) => l.startsWith('E1,'));
  assert.equal(asha, 'E1,Asha Rao,21,21,0,21000.00,8400.00,5000.00,2520.00,0.00,34400.00,2520.00,31880.00,INR,BANK_TRANSFER,2026-11-30');
  const bala = lines.find((l) => l.includes('HYPERLINK'));
  assert.ok(bala.endsWith(',42000.00,0.00,0.00,0.00,1000.00,42000.00,1000.00,41000.00,INR,BANK_TRANSFER,2026-11-30'), bala);
  assert.equal(lines[lines.length - 1], 'TOTAL,2 staff,,,,63000.00,8400.00,5000.00,2520.00,1000.00,76400.00,3520.00,72880.00,INR,,');
  assert.equal(lines.length, 4, 'header, two people, totals');
});

test('the CSV is spreadsheet-safe: a name that looks like a formula is neutralised', async () => {
  const { ctx } = env();
  await paidNovember(ctx);
  const csv = (await reg.exportPayrollRegister(ctx, 'owner', T, base())).result.csv;
  assert.equal(/(^|,)=HYPERLINK/.test(csv), false, 'no cell starts with =');
  assert.ok(csv.includes("'=HYPERLINK") || csv.includes('"\'=HYPERLINK'), 'it is quoted as text');
});

test('the CSV exists only for a paid run, for school admin and finance of the branch', async () => {
  const { ctx, db } = env();
  await r.createPayrollRun(ctx, 'fin', T, base());
  assert.equal((await reg.exportPayrollRegister(ctx, 'owner', T, base())).error, 'FAILED_PRECONDITION', 'calculated');
  assert.equal((await reg.exportPayrollRegister(ctx, 'owner', T, base({ period: '2026-05' }))).error, 'NOT_FOUND');
  await r.approvePayrollRun(ctx, 'owner', T, base());
  await r.payPayrollRun(ctx, 'fin', T, base({ payment: { paymentMode: 'CASH' } }));
  for (const u of ['finB2', 'ba1', 'teacher', 'otherOwner', 'ghost']) assert.equal((await reg.exportPayrollRegister(ctx, u, T, base())).error, 'PERMISSION_DENIED', u);
  for (const bad of [{ branchId: '../b' }, { period: '2026-13' }, { period: undefined }]) assert.equal((await reg.exportPayrollRegister(ctx, 'owner', T, base(bad))).error, 'PERMISSION_DENIED', JSON.stringify(bad));
  const before = JSON.stringify([...db.store.entries()]);
  await reg.exportPayrollRegister(ctx, 'owner', T, base());
  await reg.getPayrollRegister(ctx, 'owner', T, range());
  assert.equal(JSON.stringify([...db.store.entries()]), before, 'reads write nothing');
});

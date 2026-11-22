'use strict';
// Role-by-callable proof for ALL payroll callables: every actor calls every callable; the ones that may not are
// refused with PERMISSION_DENIED and the database is byte-for-byte unchanged; the ones that may are not refused for
// permission reasons. The table below IS the permission model of payroll, written once, independently of the code.
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const pay = require('./payroll');
const prev = require('./payroll_preview');
const runs = require('./payroll_runs');
const slips = require('./payroll_payslips');
const reg = require('./payroll_register');

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
const seed = () => ({
  'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
  'schools/sB': { name: 'B', status: 'ACTIVE' },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/owner2': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  'users/finB2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'FINANCE' },
  'users/finOff': { schoolId: 'sA', branchId: 'b1', status: 'INACTIVE', role: 'FINANCE' },
  'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/parent': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  'users/platform': { status: 'ACTIVE', role: 'PLATFORM_ADMIN', platformRole: 'OWNER' },
  'users/otherOwner': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  [B]: { name: 'Main' },
  'schools/sA/branches/b2': { name: 'North' },
  [`${B}/staff/st1`]: { firstName: 'Asha', lastName: 'Rao', employeeCode: 'E1', status: 'ACTIVE', joiningDate: ts('2020-06-01'), userId: 'teacher' },
  [`${B}/staff/st2`]: { firstName: 'Bala', employeeCode: 'E2', status: 'ACTIVE', joiningDate: ts('2020-06-01') },
  ...Object.fromEntries([structure('st1', 2100000), structure('st2', 4200000), ...presentAll('st1'), ...presentAll('st2')]),
});
const ACTORS = ['owner', 'fin', 'finB2', 'finOff', 'ba1', 'teacher', 'parent', 'platform', 'otherOwner', 'ghost'];
const base = (x = {}) => ({ schoolId: 'sA', branchId: 'b1', period: '2026-11', ...x });
const adj = { kind: 'EARNING', label: 'Bonus', amountMinor: 1000, reason: 'Festival bonus agreed by the trust' };
const PAY = { payment: { paymentMode: 'CASH' } };

// callable -> { state: how far the run must be, call(ctx, uid), allowed: who may call it }
const SA = ['owner'];
const SA_FIN = ['owner', 'fin'];
// School-level configuration (the list of components, the policy): no one's pay, so finance of ANY branch may read it,
// exactly like the expense categories. Pay figures (structures, runs, payslips, registers) are branch-scoped below.
const SCHOOL_CONFIG_READ = ['owner', 'fin', 'finB2'];
const STAFF_ROLES = ['owner', 'fin', 'finB2', 'ba1', 'teacher']; // own payslips: any active staff role of the school
const TABLE = {
  listPayComponents: { call: (c, u) => pay.listPayComponents(c, u, T, { schoolId: 'sA' }), allowed: SCHOOL_CONFIG_READ },
  savePayComponent: { call: (c, u) => pay.savePayComponent(c, u, T, { schoolId: 'sA', name: 'Allowance', kind: 'EARNING', calc: 'FIXED' }), allowed: SA },
  getSalaryStructure: { call: (c, u) => pay.getSalaryStructure(c, u, T, base({ staffId: 'st1' })), allowed: SA_FIN },
  saveSalaryStructure: { call: (c, u) => pay.saveSalaryStructure(c, u, T, base({ staffId: 'st1', effectiveFrom: '2026-12-01', reason: 'Annual increment agreed', lines: [{ componentId: 'pc_basic', amountMinor: 2200000 }] })), allowed: SA },
  listSalaryStructures: { call: (c, u) => pay.listSalaryStructures(c, u, T, base()), allowed: SA_FIN },
  getPayrollSettings: { call: (c, u) => prev.getPayrollSettings(c, u, T, { schoolId: 'sA' }), allowed: SCHOOL_CONFIG_READ },
  savePayrollSettings: { call: (c, u) => prev.savePayrollSettings(c, u, T, { schoolId: 'sA', settings: { unmarkedDays: 'PAID' } }), allowed: SA },
  previewPayroll: { call: (c, u) => prev.previewPayroll(c, u, T, base()), allowed: SA_FIN },
  createPayrollRun: { state: 'none', call: (c, u) => runs.createPayrollRun(c, u, T, base()), allowed: SA_FIN },
  calculatePayrollRun: { state: 'calculated', call: (c, u) => runs.calculatePayrollRun(c, u, T, base()), allowed: SA_FIN },
  adjustPayslip: { state: 'calculated', call: (c, u) => runs.adjustPayslip(c, u, T, base({ staffId: 'st1', adjustment: adj })), allowed: SA_FIN },
  removePayslipAdjustment: { state: 'calculated', call: (c, u) => runs.removePayslipAdjustment(c, u, T, base({ staffId: 'st1', adjustmentId: 'x' })), allowed: SA_FIN },
  approvePayrollRun: { state: 'calculated', call: (c, u) => runs.approvePayrollRun(c, u, T, base()), allowed: SA },
  payPayrollRun: { state: 'approved', call: (c, u) => runs.payPayrollRun(c, u, T, base(PAY)), allowed: SA_FIN },
  cancelPayrollRun: { state: 'calculated', call: (c, u) => runs.cancelPayrollRun(c, u, T, base({ reason: 'Wrong month chosen by mistake' })), allowed: SA_FIN },
  listPayrollRuns: { state: 'calculated', call: (c, u) => runs.listPayrollRuns(c, u, T, base()), allowed: SA_FIN },
  getPayrollRun: { state: 'calculated', call: (c, u) => runs.getPayrollRun(c, u, T, base()), allowed: SA_FIN },
  getPayslip: { state: 'calculated', call: (c, u) => runs.getPayslip(c, u, T, base({ staffId: 'st1' })), allowed: SA_FIN },
  getPayrollRunHistory: { state: 'calculated', call: (c, u) => runs.getPayrollRunHistory(c, u, T, base()), allowed: SA_FIN },
  getPayrollRegisterBranch: { state: 'paid', call: (c, u) => reg.getPayrollRegister(c, u, T, { schoolId: 'sA', branchId: 'b1', fromPeriod: '2026-10', toPeriod: '2026-11' }), allowed: SA_FIN },
  getPayrollRegisterWholeSchool: { state: 'paid', call: (c, u) => reg.getPayrollRegister(c, u, T, { schoolId: 'sA', fromPeriod: '2026-10', toPeriod: '2026-11' }), allowed: SA },
  exportPayrollRegister: { state: 'paid', call: (c, u) => reg.exportPayrollRegister(c, u, T, base()), allowed: SA_FIN },
  listMyPayslips: { state: 'paid', call: (c, u) => slips.listMyPayslips(c, u, T, { schoolId: 'sA' }), allowed: STAFF_ROLES },
  getMyPayslip: { state: 'paid', call: (c, u) => slips.getMyPayslip(c, u, T, base()), allowed: STAFF_ROLES },
};

async function world(state) {
  const db = fakeDb(seed());
  const ctx = { db, now: 'TS', wall: () => new Date('2026-11-30T12:00:00Z') };
  if (state && state !== 'none') {
    await runs.createPayrollRun(ctx, 'fin', T, base());
    if (state === 'approved' || state === 'paid') await runs.approvePayrollRun(ctx, 'owner', T, base());
    if (state === 'paid') await runs.payPayrollRun(ctx, 'fin', T, base(PAY));
  }
  return { db, ctx };
}
const snapshot = (db) => JSON.stringify([...db.store.entries()]);

test('the permission table covers every payroll callable exactly once', () => {
  const exported = new Set(
    ['listPayComponents', 'savePayComponent', 'getSalaryStructure', 'saveSalaryStructure', 'listSalaryStructures', 'getPayrollSettings', 'savePayrollSettings', 'previewPayroll',
      'createPayrollRun', 'calculatePayrollRun', 'adjustPayslip', 'removePayslipAdjustment', 'approvePayrollRun', 'payPayrollRun', 'cancelPayrollRun',
      'listPayrollRuns', 'getPayrollRun', 'getPayslip', 'getPayrollRunHistory', 'getPayrollRegister', 'exportPayrollRegister', 'listMyPayslips', 'getMyPayslip'],
  );
  const covered = new Set(Object.keys(TABLE).map((k) => k.replace(/(Branch|WholeSchool)$/, '')));
  assert.deepEqual([...covered].sort(), [...exported].sort());
  // and index.js really exports each of them (a callable nobody tested cannot be added silently)
  const idx = require('./index.js');
  const payrollExports = Object.keys(idx).filter((k) => exported.has(k));
  assert.equal(payrollExports.length, exported.size);
});

for (const [name, spec] of Object.entries(TABLE)) {
  test(`${name}: allowed for ${spec.allowed.join(', ')}; everyone else is refused and nothing is written`, async () => {
    for (const actor of ACTORS) {
      const { db, ctx } = await world(spec.state);
      const before = snapshot(db);
      const out = await spec.call(ctx, actor);
      if (spec.allowed.includes(actor)) {
        assert.notEqual(out && out.error, 'PERMISSION_DENIED', `${name} by ${actor} should be allowed: ${JSON.stringify(out)}`);
      } else {
        assert.equal(out && out.error, 'PERMISSION_DENIED', `${name} by ${actor} should be refused: ${JSON.stringify(out)}`);
        assert.equal(snapshot(db), before, `${name} by ${actor} wrote something`);
      }
    }
  });
}

test('a finance user of another branch and a platform admin never see this branch, whatever the call', async () => {
  const { ctx } = await world('paid');
  for (const actor of ['finB2', 'platform']) {
    for (const k of ['getPayrollRun', 'getPayslip', 'getPayrollRunHistory', 'listPayrollRuns', 'exportPayrollRegister', 'getSalaryStructure', 'listSalaryStructures', 'previewPayroll']) {
      assert.equal((await TABLE[k].call(ctx, actor)).error, 'PERMISSION_DENIED', `${k} ${actor}`);
    }
  }
});

test('a staff member reads their own payslip but no other call about pay', async () => {
  const { ctx } = await world('paid');
  assert.ok((await TABLE.getMyPayslip.call(ctx, 'teacher')).result);
  for (const [k, spec] of Object.entries(TABLE)) {
    if (k === 'listMyPayslips' || k === 'getMyPayslip') continue;
    assert.equal((await spec.call(ctx, 'teacher')).error, 'PERMISSION_DENIED', `${k} by the staff member`);
  }
});

test('module switched off, or the school suspended or closed: every payroll callable refuses everyone', async () => {
  for (const school of [
    { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata', features: { payroll: false } },
    { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata', features: { staff: false } },
    { name: 'A', status: 'SUSPENDED', currency: 'INR' },
    { name: 'A', status: 'CLOSED', currency: 'INR' },
  ]) {
    const { db, ctx } = await world('paid');
    db.store.set('schools/sA', school);
    for (const [k, spec] of Object.entries(TABLE)) {
      for (const actor of ['owner', 'fin', 'teacher']) {
        const out = await spec.call(ctx, actor);
        assert.equal(out && out.error, 'PERMISSION_DENIED', `${k} by ${actor} when ${JSON.stringify(school.features || school.status)}`);
      }
    }
  }
});

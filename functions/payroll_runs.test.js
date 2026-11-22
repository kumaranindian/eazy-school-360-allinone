'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const r = require('./payroll_runs');
const pp = require('./payroll_preview');

const T = {};
const ts = (key) => new Date(`${key}T00:00:00Z`);
const B = 'schools/sA/branches/b1';
const NOV = ['02', '03', '04', '05', '06', '09', '10', '11', '12', '13', '16', '17', '18', '19', '20', '23', '24', '25', '26', '27', '30'].map((d) => `2026-11-${d}`);
const structure = (staff, seq, basic) => [`${B}/salaryStructures/${staff}_0000${seq}`, {
  staffId: staff, seq, effectiveFrom: '2026-04-01', latest: true, currency: 'INR',
  lines: [{ componentId: 'pc_basic', nameSnapshot: 'Basic salary', kind: 'EARNING', calc: 'FIXED', amountMinor: basic }],
  grossMinor: basic, deductionsMinor: 0, netMinor: basic,
}];
const presentAll = (staff) => NOV.map((d) => [`${B}/staffAttendance/${d}_${staff}`, { staffId: staff, dateKey: d, status: 'PRESENT' }]);

const seed = (extra = {}) => ({
  'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN', displayName: 'Olive Owner' },
  'users/owner2': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN', displayName: 'Omar Owner' },
  'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE', displayName: 'Fay Finance' },
  'users/finB2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'FINANCE' },
  'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/otherOwner': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  [B]: { name: 'One' },
  [`${B}/staff/st1`]: { firstName: 'Asha', lastName: 'Rao', employeeCode: 'E1', status: 'ACTIVE', joiningDate: ts('2020-06-01') },
  [`${B}/staff/st2`]: { firstName: 'Bala', employeeCode: 'E2', status: 'ACTIVE', joiningDate: ts('2020-06-01') },
  ...Object.fromEntries([structure('st1', 1, 2100000), structure('st2', 1, 4200000), ...presentAll('st1'), ...presentAll('st2')]),
  ...extra,
});
const env = (extra) => {
  const db = fakeDb(seed(extra));
  return { db, ctx: { db, now: 'TS', wall: () => new Date('2026-11-30T12:00:00Z') } };
};
const base = (extra = {}) => ({ schoolId: 'sA', branchId: 'b1', period: '2026-11', ...extra });
const create = (ctx, uid = 'fin', b = {}) => r.createPayrollRun(ctx, uid, T, base(b));
const run = async (db) => (await db.collection('schools').doc('sA').collection('branches').doc('b1').collection('payrollRuns').doc('2026-11').get()).data();
const slip = async (db, id) => (await db.collection('schools').doc('sA').collection('branches').doc('b1').collection('payrollRuns').doc('2026-11').collection('payslips').doc(id).get()).data();
const history = (db) => [...db.store.entries()].filter(([k]) => k.includes('/payrollRuns/2026-11/history/')).map(([, v]) => v).sort((a, b) => a.seq - b.seq);
const adj = (o = {}) => ({ kind: 'EARNING', label: 'Diwali bonus', amountMinor: 500000, reason: 'Festival bonus agreed by the trust', ...o });

test('pure: payslip totals with adjustments, and adjustment validation', () => {
  const s = { baseGrossMinor: 1000, baseDeductionsMinor: 100, adjustments: [{ kind: 'EARNING', amountMinor: 50 }, { kind: 'DEDUCTION', amountMinor: 30 }] };
  assert.deepEqual(r.slipTotals(s), { grossMinor: 1050, deductionsMinor: 130, netMinor: 920 });
  assert.ok(r.slipTotals({ ...s, adjustments: [{ kind: 'DEDUCTION', amountMinor: 901 }] }).errors);
  assert.equal(r.slipTotals({ ...s, adjustments: [{ kind: 'DEDUCTION', amountMinor: 900 }] }).netMinor, 0);
  assert.ok(r.validateAdjustment(adj()).value);
  for (const bad of [null, {}, adj({ kind: 'BONUS' }), adj({ label: 'x' }), adj({ amountMinor: 0 }), adj({ amountMinor: 1.5 }), adj({ amountMinor: '5' }), adj({ amountMinor: 1e12 + 1 }), adj({ reason: 'short' }), adj({ reason: 'x'.repeat(301) })]) {
    assert.ok(r.validateAdjustment(bad).errors, JSON.stringify(bad));
  }
  assert.deepEqual(Object.keys(r.TRANSITIONS).sort(), ['approve', 'calculate', 'cancel', 'pay']);
});

test('create: one run per branch and month, calculated at once, with history', async () => {
  const { ctx, db } = env();
  const out = await create(ctx);
  assert.deepEqual([out.result.status, out.result.payslipCount, out.result.skippedCount], ['CALCULATED', 2, 0]);
  const rn = await run(db);
  assert.deepEqual([rn.status, rn.grossMinor, rn.netMinor, rn.payslipCount, rn.currency, rn.workingDays, rn.createdBy], ['CALCULATED', 6300000, 6300000, 2, 'INR', 21, 'fin']);
  const p = await slip(db, 'st1');
  assert.deepEqual([p.staffName, p.netMinor, p.paidDays, p.structureSeq, p.baseGrossMinor], ['Asha Rao', 2100000, 21, 1, 2100000]);
  assert.deepEqual(history(db).map((h) => [h.seq, h.action, h.from, h.to, h.actorId]), [[1, 'create', null, 'DRAFT', 'fin'], [2, 'create', 'DRAFT', 'CALCULATED', 'fin']]);
  assert.equal((await create(ctx)).error, 'ALREADY_EXISTS');
  assert.equal((await create(ctx, 'owner')).error, 'ALREADY_EXISTS', 'even for another preparer');
  assert.equal((await db.collection('schools').doc('sA').get()).data().currencyLocked, undefined, 'currency is locked by structures, not by a run');
});

test('create: skipped staff (no structure) are counted; people who left are not listed', async () => {
  const { ctx, db } = env({
    [`${B}/staff/st4`]: { firstName: 'Dev', status: 'ACTIVE', joiningDate: ts('2018-01-01') },
    [`${B}/staff/st3`]: { firstName: 'Chitra', status: 'RESIGNED', joiningDate: ts('2019-01-01'), statusChangeDate: ts('2026-10-15') },
  });
  const out = await create(ctx);
  assert.deepEqual([out.result.payslipCount, out.result.skippedCount], [2, 1]);
  assert.deepEqual((await run(db)).skippedStaffIds, ['st4']);
});

test('create: bad or out-of-range months are refused and nothing is written', async () => {
  const { ctx, db } = env();
  const before = db.store.size;
  for (const period of [undefined, 5, '2026-13', '2026-12', '2027-01', '2024-01', '26-11', '']) {
    assert.equal((await create(ctx, 'fin', { period })).error, 'INVALID_ARGUMENT', String(period));
  }
  assert.equal(db.store.size, before);
});

test('who may do what, callable by callable (a refused call writes nothing)', async () => {
  const roles = ['owner', 'fin', 'finB2', 'ba1', 'teacher', 'otherOwner', 'ghost'];
  const allowed = {
    create: ['owner', 'fin'], calculate: ['owner', 'fin'], adjust: ['owner', 'fin'], remove: ['owner', 'fin'],
    approve: ['owner'], pay: ['owner', 'fin'], cancel: ['owner', 'fin'],
    list: ['owner', 'fin'], get: ['owner', 'fin'], slip: ['owner', 'fin'], hist: ['owner', 'fin'],
  };
  const call = (ctx, kind, uid) => {
    const b = base({ staffId: 'st1' });
    switch (kind) {
      case 'create': return r.createPayrollRun(ctx, uid, T, b);
      case 'calculate': return r.calculatePayrollRun(ctx, uid, T, b);
      case 'adjust': return r.adjustPayslip(ctx, uid, T, { ...b, adjustment: adj() });
      case 'remove': return r.removePayslipAdjustment(ctx, uid, T, { ...b, adjustmentId: 'abc' });
      case 'approve': return r.approvePayrollRun(ctx, uid, T, { ...b, acknowledgeWarnings: true });
      case 'pay': return r.payPayrollRun(ctx, uid, T, { ...b, payment: { paymentMode: 'BANK_TRANSFER' } });
      case 'cancel': return r.cancelPayrollRun(ctx, uid, T, { ...b, reason: 'Wrong month chosen by mistake' });
      case 'list': return r.listPayrollRuns(ctx, uid, T, b);
      case 'get': return r.getPayrollRun(ctx, uid, T, b);
      case 'slip': return r.getPayslip(ctx, uid, T, b);
      default: return r.getPayrollRunHistory(ctx, uid, T, b);
    }
  };
  for (const kind of Object.keys(allowed)) {
    for (const uid of roles) {
      const { ctx, db } = env();
      if (kind !== 'create') await create(ctx, 'fin');
      const before = JSON.stringify([...db.store.entries()]);
      const out = await call(ctx, kind, uid);
      if (allowed[kind].includes(uid)) {
        assert.notEqual(out.error, 'PERMISSION_DENIED', `${kind} by ${uid} should be allowed: ${JSON.stringify(out)}`);
      } else {
        assert.equal(out.error, 'PERMISSION_DENIED', `${kind} by ${uid}`);
        assert.equal(JSON.stringify([...db.store.entries()]), before, `${kind} by ${uid} wrote something`);
      }
    }
  }
});

test('module off, suspended school: every payroll run call is refused', async () => {
  const off = env({ 'schools/sA': { name: 'A', status: 'ACTIVE', features: { payroll: false } } });
  assert.equal((await create(off.ctx, 'owner')).error, 'PERMISSION_DENIED');
  const susp = env({ 'schools/sA': { name: 'A', status: 'SUSPENDED' } });
  assert.equal((await create(susp.ctx, 'owner')).error, 'PERMISSION_DENIED');
});

test('adjust: add, totals follow, history names the item and never the amount, remove', async () => {
  const { ctx, db } = env();
  await create(ctx);
  const a = await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: adj() }));
  assert.equal(a.result.adjustmentCount, 1);
  let p = await slip(db, 'st1');
  assert.deepEqual([p.grossMinor, p.netMinor, p.baseGrossMinor], [2600000, 2600000, 2100000]);
  assert.deepEqual((await run(db)).netMinor, 6800000);
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: adj({ kind: 'DEDUCTION', label: 'Loan instalment', amountMinor: 100000, reason: 'Salary advance recovery agreed' }) }));
  p = await slip(db, 'st1');
  assert.deepEqual([p.grossMinor, p.deductionsMinor, p.netMinor], [2600000, 100000, 2500000]);
  const rn = await run(db);
  assert.deepEqual([rn.grossMinor, rn.deductionsMinor, rn.netMinor, rn.adjustmentCount], [6800000, 100000, 6700000, 2]);
  assert.equal(JSON.stringify(history(db)).includes('500000'), false, 'no amount in the history');
  assert.ok(history(db).some((h) => h.action === 'adjust' && h.staffId === 'st1'));
  const first = p.adjustments[0].id;
  await r.removePayslipAdjustment(ctx, 'fin', T, base({ staffId: 'st1', adjustmentId: first }));
  p = await slip(db, 'st1');
  assert.deepEqual([p.grossMinor, p.netMinor, p.adjustments.length], [2100000, 2000000, 1]);
  assert.equal((await run(db)).netMinor, 6300000 - 100000);
  assert.equal((await r.removePayslipAdjustment(ctx, 'fin', T, base({ staffId: 'st1', adjustmentId: first }))).error, 'NOT_FOUND');
});

test('adjust: refusals', async () => {
  const { ctx, db } = env();
  await create(ctx);
  const t = (b) => r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', ...b }));
  assert.equal((await t({ adjustment: adj({ kind: 'DEDUCTION', amountMinor: 2100001 }) })).error, 'FAILED_PRECONDITION', 'the net would be negative');
  assert.equal((await t({ adjustment: adj({ amountMinor: 0 }) })).error, 'INVALID_ARGUMENT');
  assert.equal((await t({ adjustment: null })).error, 'INVALID_ARGUMENT');
  assert.equal((await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'nobody', adjustment: adj() }))).error, 'NOT_FOUND');
  assert.equal((await t({ adjustment: adj(), baseVersion: 1 })).error, 'ABORTED');
  for (let i = 0; i < 10; i++) assert.ok((await t({ adjustment: adj({ amountMinor: 1 + i }) })).result);
  assert.equal((await t({ adjustment: adj() })).error, 'FAILED_PRECONDITION', 'at most 10');
  assert.equal((await slip(db, 'st1')).adjustments.length, 10);
  assert.equal((await r.adjustPayslip(ctx, 'fin', T, base({ staffId: '../x', adjustment: adj() }))).error, 'PERMISSION_DENIED');
  assert.equal((await r.removePayslipAdjustment(ctx, 'fin', T, base({ staffId: 'st1', adjustmentId: '../x' }))).error, 'INVALID_ARGUMENT');
});

test('recalculate keeps the adjustments, picks up new facts and drops people who no longer qualify', async () => {
  const { ctx, db } = env();
  await create(ctx);
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: adj() }));
  // a staff member is marked absent after the run was made, and st2 loses their structure
  db.store.set(`${B}/staffAttendance/2026-11-02_st1`, { staffId: 'st1', dateKey: '2026-11-02', status: 'ABSENT' });
  db.store.delete(`${B}/salaryStructures/st2_00001`);
  const out = await r.calculatePayrollRun(ctx, 'owner', T, base());
  assert.deepEqual([out.result.payslipCount, out.result.skippedCount, out.result.removedPayslips, out.result.droppedAdjustments], [1, 1, 1, 0]);
  const p = await slip(db, 'st1');
  assert.equal(p.baseGrossMinor, 2000000, '2,100,000 x 20/21');
  assert.equal(p.adjustments.length, 1, 'the bonus was kept');
  assert.equal(p.netMinor, 2500000);
  assert.equal(await slip(db, 'st2'), undefined);
  const rn = await run(db);
  assert.deepEqual([rn.netMinor, rn.payslipCount, rn.version], [2500000, 1, 6], 'create 1, lock 2, calculated 3, adjust 4, lock 5, calculated 6');
  assert.equal((await r.calculatePayrollRun(ctx, 'owner', T, base({ baseVersion: 1 }))).error, 'ABORTED');
});

test('recalculate drops one-off items that the new base cannot carry, and says so', async () => {
  const { ctx, db } = env();
  await create(ctx);
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: adj({ kind: 'DEDUCTION', label: 'Big recovery', amountMinor: 2000000, reason: 'Recover the overpaid advance' }) }));
  for (const d of NOV.slice(0, 20)) db.store.set(`${B}/staffAttendance/${d}_st1`, { staffId: 'st1', dateKey: d, status: 'ABSENT' });
  const out = await r.calculatePayrollRun(ctx, 'fin', T, base());
  assert.equal(out.result.droppedAdjustments, 1);
  assert.deepEqual((await slip(db, 'st1')).adjustments, []);
});

test('approve: separation of duties, things to check, tampered totals, frozen afterwards', async () => {
  const { ctx, db } = env({ [`${B}/staff/st4`]: { firstName: 'Dev', status: 'ACTIVE', joiningDate: ts('2018-01-01') } });
  await create(ctx, 'owner');
  const ap = (uid, b = {}) => r.approvePayrollRun(ctx, uid, T, base(b));
  assert.equal((await ap('owner', { acknowledgeWarnings: true })).error, 'PERMISSION_DENIED', 'the person who prepared it cannot approve it');
  assert.equal((await ap('owner2')).error, 'FAILED_PRECONDITION', 'a staff member without a structure needs an explicit acknowledgement');
  assert.equal((await ap('owner2', { acknowledgeWarnings: true, baseVersion: 1 })).error, 'ABORTED');
  // totals that no longer match the payslips are caught
  db.store.set(`${B}/payrollRuns/2026-11/payslips/st1`, { ...(await slip(db, 'st1')), netMinor: 1 });
  assert.equal((await ap('owner2', { acknowledgeWarnings: true })).error, 'FAILED_PRECONDITION');
  await r.calculatePayrollRun(ctx, 'fin', T, base());
  const ok = await ap('owner2', { acknowledgeWarnings: true });
  assert.deepEqual([ok.result.status, ok.result.version], ['APPROVED', 6]);
  const rn = await run(db);
  assert.deepEqual([rn.approvedBy, rn.approvedByName], ['owner2', 'Omar Owner']);
  assert.equal((await ap('owner2', { acknowledgeWarnings: true })).result.duplicate, true, 'approving twice is harmless');
  // frozen
  assert.equal((await r.calculatePayrollRun(ctx, 'fin', T, base())).error, 'FAILED_PRECONDITION');
  assert.equal((await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: adj() }))).error, 'FAILED_PRECONDITION');
  assert.equal((await r.removePayslipAdjustment(ctx, 'fin', T, base({ staffId: 'st1', adjustmentId: 'abc' }))).error, 'FAILED_PRECONDITION');
  assert.ok(history(db).some((h) => h.action === 'approve' && h.actorId === 'owner2'));
});

test('approve: the school can allow one administrator to prepare and approve', async () => {
  const { ctx } = env();
  await create(ctx, 'owner');
  assert.equal((await r.approvePayrollRun(ctx, 'owner', T, base())).error, 'PERMISSION_DENIED');
  await pp.savePayrollSettings(ctx, 'owner', T, { schoolId: 'sA', settings: { unmarkedDays: 'PAID', allowSelfApproval: true } });
  assert.equal((await r.approvePayrollRun(ctx, 'owner', T, base())).result.status, 'APPROVED');
});

test('approve: someone who only adjusted also counts as having prepared it', async () => {
  const { ctx } = env();
  await create(ctx, 'fin');
  await r.adjustPayslip(ctx, 'owner', T, base({ staffId: 'st1', adjustment: adj() }));
  assert.equal((await r.approvePayrollRun(ctx, 'owner', T, base())).error, 'PERMISSION_DENIED');
  assert.equal((await r.approvePayrollRun(ctx, 'owner2', T, base())).result.status, 'APPROVED');
});

test('approve: warnings (days nobody marked) need acknowledging', async () => {
  const { ctx, db } = env();
  db.store.delete(`${B}/staffAttendance/2026-11-02_st1`);
  await create(ctx, 'fin');
  assert.ok((await run(db)).warningCount > 0);
  assert.equal((await r.approvePayrollRun(ctx, 'owner', T, base())).error, 'FAILED_PRECONDITION');
  assert.equal((await r.approvePayrollRun(ctx, 'owner', T, base({ acknowledgeWarnings: 'yes' }))).error, 'FAILED_PRECONDITION', 'only the boolean true counts');
  assert.equal((await r.approvePayrollRun(ctx, 'owner', T, base({ acknowledgeWarnings: true }))).result.status, 'APPROVED');
});

test('an empty run cannot be approved', async () => {
  const { ctx } = env({ [`${B}/staff/st1`]: { firstName: 'Asha', status: 'RESIGNED', joiningDate: ts('2020-06-01'), statusChangeDate: ts('2020-07-01') }, [`${B}/staff/st2`]: { firstName: 'Bala', status: 'RESIGNED', joiningDate: ts('2020-06-01'), statusChangeDate: ts('2020-07-01') } });
  await create(ctx, 'fin');
  assert.equal((await r.approvePayrollRun(ctx, 'owner', T, base({ acknowledgeWarnings: true }))).error, 'FAILED_PRECONDITION');
});

test('pay: only an approved run; mode, reference and date are checked; paying twice is harmless; frozen after', async () => {
  const { ctx, db } = env();
  await create(ctx, 'fin');
  const pay = (uid, payment) => r.payPayrollRun(ctx, uid, T, base({ payment }));
  assert.equal((await pay('fin', { paymentMode: 'BANK_TRANSFER' })).error, 'FAILED_PRECONDITION', 'not approved yet');
  await r.approvePayrollRun(ctx, 'owner', T, base());
  for (const bad of [undefined, {}, { paymentMode: 'BARTER' }, { paymentMode: 'CASH', paymentReference: 'x'.repeat(61) }, { paymentMode: 'CASH', paidDate: '2026-12-01' }, { paymentMode: 'CASH', paidDate: '2026-10-31' }, { paymentMode: 'CASH', paidDate: '2026-02-30' }, { paymentMode: 'CASH', paidDate: 'x' }]) {
    assert.equal((await pay('fin', bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
  assert.equal((await pay('ba1', { paymentMode: 'CASH' })).error, 'PERMISSION_DENIED');
  const ok = await pay('fin', { paymentMode: 'BANK_TRANSFER', paymentReference: ' NEFT-991 ', paidDate: '2026-11-30' });
  assert.deepEqual([ok.result.status, ok.result.version], ['PAID', 5]);
  const rn = await run(db);
  assert.deepEqual([rn.paidBy, rn.paidDate, rn.paymentMode, rn.paymentReference], ['fin', '2026-11-30', 'BANK_TRANSFER', 'NEFT-991']);
  assert.equal((await pay('owner', { paymentMode: 'CASH' })).result.duplicate, true);
  assert.equal((await run(db)).paymentMode, 'BANK_TRANSFER', 'the first payment stands');
  assert.equal((await r.cancelPayrollRun(ctx, 'owner', T, base({ reason: 'Trying to undo a paid run' }))).error, 'FAILED_PRECONDITION', 'a paid run is final');
  assert.equal((await r.calculatePayrollRun(ctx, 'owner', T, base())).error, 'FAILED_PRECONDITION');
});

test('cancel: a reason; finance before approval, only a school admin after; the month can then be started again', async () => {
  const { ctx, db } = env();
  await create(ctx, 'fin');
  assert.equal((await r.cancelPayrollRun(ctx, 'fin', T, base({ reason: 'short' }))).error, 'INVALID_ARGUMENT');
  assert.equal((await r.cancelPayrollRun(ctx, 'ba1', T, base({ reason: 'A branch admin has no say' }))).error, 'PERMISSION_DENIED');
  await r.approvePayrollRun(ctx, 'owner', T, base());
  assert.equal((await r.cancelPayrollRun(ctx, 'fin', T, base({ reason: 'Finance cannot undo an approval' }))).error, 'PERMISSION_DENIED');
  assert.equal((await r.cancelPayrollRun(ctx, 'owner', T, base({ reason: 'Wrong attendance data used' }))).result.status, 'CANCELLED');
  assert.equal((await run(db)).cancelReason, 'Wrong attendance data used');
  assert.equal((await r.cancelPayrollRun(ctx, 'owner', T, base({ reason: 'Wrong attendance data used' }))).result.duplicate, true);
  const again = await create(ctx, 'fin');
  assert.equal(again.result.status, 'CALCULATED');
  assert.equal((await run(db)).cancelReason, undefined, 'the new run starts clean');
  assert.ok(history(db).filter((h) => h.action === 'create').length >= 3, 'the old history is kept');
  assert.deepEqual(history(db).map((h) => h.seq), history(db).map((_, i) => i + 1), 'sequence continues');
});

test('reads: list, run, payslip, history', async () => {
  const { ctx } = env();
  await create(ctx, 'fin');
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: adj() }));
  const list = (await r.listPayrollRuns(ctx, 'owner', T, base())).result;
  assert.equal(list.runs.length, 1);
  assert.deepEqual([list.runs[0].period, list.runs[0].status, list.runs[0].netMinor, list.canApprove, list.canPay], ['2026-11', 'CALCULATED', 6800000, true, true]);
  assert.equal((await r.listPayrollRuns(ctx, 'fin', T, base())).result.canApprove, false);
  const got = (await r.getPayrollRun(ctx, 'fin', T, base())).result;
  assert.deepEqual(got.payslips.map((p) => [p.staffId, p.name, p.netMinor, p.adjustmentCount]), [['st1', 'Asha Rao', 2600000, 1], ['st2', 'Bala', 4200000, 0]]);
  assert.equal(JSON.stringify(got.payslips).includes('lines'), false, 'the table has totals, not lines');
  const one = (await r.getPayslip(ctx, 'owner', T, base({ staffId: 'st1' }))).result.payslip;
  assert.deepEqual([one.lines[0].amountMinor, one.adjustments[0].label, one.baseGrossMinor], [2100000, 'Diwali bonus', 2100000]);
  assert.equal((await r.getPayslip(ctx, 'owner', T, base({ staffId: 'nobody' }))).error, 'NOT_FOUND');
  assert.equal((await r.getPayrollRun(ctx, 'owner', T, base({ period: '2026-10' }))).error, 'NOT_FOUND');
  const h = (await r.getPayrollRunHistory(ctx, 'owner', T, base())).result.history;
  assert.deepEqual(h.map((x) => x.action), ['create', 'create', 'adjust']);
  assert.equal(h[0].actorName, 'Fay Finance');
});

test('a client cannot plant a status, totals or a payslip through any request field', async () => {
  const { ctx, db } = env();
  const out = await r.createPayrollRun(ctx, 'fin', T, { ...base(), status: 'PAID', netMinor: 1, payslipCount: 99, createdBy: 'x', version: 50 });
  assert.equal(out.result.status, 'CALCULATED');
  const rn = await run(db);
  assert.deepEqual([rn.status, rn.netMinor, rn.payslipCount, rn.createdBy, rn.version], ['CALCULATED', 6300000, 2, 'fin', 3]);
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: { ...adj(), id: 'planted', atMs: 1, grossMinor: 9 }, grossMinor: 9 }));
  const p = await slip(db, 'st1');
  assert.notEqual(p.adjustments[0].id, 'planted');
  assert.equal(p.grossMinor, 2600000);
});

// ---- phase P5: the paid run is posted as ONE Salaries expense --------------------------------------------------

const exp = require('./expenses');
const expWf = require('./expense_workflow');
const expReports = require('./expense_reports');
const expense = async (db) => (await db.collection('schools').doc('sA').collection('branches').doc('b1').collection('expenses').doc('payroll_2026-11').get()).data();
const payIt = async (ctx, extra = {}) => {
  await create(ctx, 'fin');
  await r.approvePayrollRun(ctx, 'owner', T, base());
  return r.payPayrollRun(ctx, 'fin', T, base({ payment: { paymentMode: 'BANK_TRANSFER', paymentReference: 'NEFT-9', paidDate: '2026-11-30', ...extra } }));
};

test('P5: paying posts one PAID Salaries expense for the net pay, linked both ways', async () => {
  const { ctx, db } = env();
  await create(ctx, 'fin');
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: adj() }));
  await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st2', adjustment: adj({ kind: 'DEDUCTION', label: 'Loan', amountMinor: 100000, reason: 'Salary advance recovery agreed' }) }));
  await r.approvePayrollRun(ctx, 'owner2', T, base());
  const out = await r.payPayrollRun(ctx, 'fin', T, base({ payment: { paymentMode: 'BANK_TRANSFER', paymentReference: 'NEFT-9', paidDate: '2026-11-30' } }));
  assert.equal(out.result.expenseNumber, 'EXP-2026-00001');
  const e = await expense(db);
  assert.deepEqual(
    [e.number, e.categoryId, e.categoryName, e.amountMinor, e.currency, e.expenseDate, e.status, e.source, e.payrollPeriod, e.paymentMode, e.paymentReference, e.paidDate, e.paidBy, e.decidedBy, e.version],
    ['EXP-2026-00001', 'cat_salaries', 'Salaries', 6700000, 'INR', '2026-11-30', 'PAID', 'PAYROLL', '2026-11', 'BANK_TRANSFER', 'NEFT-9', '2026-11-30', 'fin', 'owner2', 1],
    'the amount is the NET pay (6,800,000 earned less 100,000 recovered), adjustments included',
  );
  assert.equal(e.payee, 'Payroll November 2026');
  assert.equal(e.description, 'Salaries for November 2026 (2 staff)');
  const rn = await run(db);
  assert.deepEqual([rn.expenseId, rn.expenseNumber], ['payroll_2026-11', 'EXP-2026-00001']);
  assert.equal((await r.getPayrollRun(ctx, 'owner', T, base())).result.run.expenseNumber, 'EXP-2026-00001');
  const h = [...db.store.entries()].filter(([k]) => k.includes('/expenses/payroll_2026-11/history/')).map(([, v]) => v);
  assert.deepEqual(h.map((x) => [x.seq, x.action, x.to, x.actorId]), [[1, 'post', 'PAID', 'fin']]);
  assert.equal((await db.collection('schools').doc('sA').collection('branches').doc('b1').collection('expenseSequences').doc('EXP-2026').get()).data().next, 1);
  assert.ok((await db.collection('schools').doc('sA').collection('expenseCategories').doc('cat_salaries').get()).exists, 'the Salaries category is there');
});

test('P5: the number continues the branch sequence; a repeated payment never posts twice', async () => {
  const { ctx, db } = env({ [`${B}/expenseSequences/EXP-2026`]: { next: 41 } });
  const out = await payIt(ctx);
  assert.equal(out.result.expenseNumber, 'EXP-2026-00042');
  const again = await r.payPayrollRun(ctx, 'owner', T, base({ payment: { paymentMode: 'CASH' } }));
  assert.equal(again.result.duplicate, true);
  assert.equal((await db.collection('schools').doc('sA').collection('branches').doc('b1').collection('expenseSequences').doc('EXP-2026').get()).data().next, 42);
  assert.equal([...db.store.keys()].filter((k) => /\/expenses\/[^/]+$/.test(k)).length, 1);
});

test('P5: a refused or failed payment posts nothing', async () => {
  const { ctx, db } = env();
  await create(ctx, 'fin');
  assert.equal((await r.payPayrollRun(ctx, 'fin', T, base({ payment: { paymentMode: 'CASH' } }))).error, 'FAILED_PRECONDITION', 'not approved');
  await r.approvePayrollRun(ctx, 'owner', T, base().period ? base() : base());
  assert.equal((await r.payPayrollRun(ctx, 'ba1', T, base({ payment: { paymentMode: 'CASH' } }))).error, 'PERMISSION_DENIED');
  assert.equal((await r.payPayrollRun(ctx, 'fin', T, base({ payment: { paymentMode: 'BARTER' } }))).error, 'INVALID_ARGUMENT');
  assert.equal(await expense(db), undefined);
  assert.equal((await run(db)).expenseNumber, undefined);
});

test('P5: a month whose net pay is zero posts no expense', async () => {
  const absent = Object.fromEntries(NOV.flatMap((d) => ['st1', 'st2'].map((s) => [`${B}/staffAttendance/${d}_${s}`, { staffId: s, dateKey: d, status: 'ABSENT' }])));
  const { ctx, db } = env(absent);
  const out = await payIt(ctx);
  assert.equal(out.result.status, 'PAID');
  assert.equal(out.result.expenseNumber, null);
  assert.equal(await expense(db), undefined);
});

test('P5: the expense shows in the expense module, cannot be edited or cancelled there, and counts in its reports', async () => {
  const { ctx, db } = env();
  await payIt(ctx);
  const got = await exp.getExpense(ctx, 'fin', T, { schoolId: 'sA', branchId: 'b1', expenseId: 'payroll_2026-11' });
  assert.deepEqual([got.result.expense.status, got.result.expense.source, got.result.expense.payrollPeriod, got.result.expense.amountMinor], ['PAID', 'PAYROLL', '2026-11', 6300000]);
  const list = await exp.listExpenses(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1' });
  assert.ok(list.result.expenses.some((x) => x.id === 'payroll_2026-11' && x.source === 'PAYROLL'));
  const edit = await exp.updateExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', expenseId: 'payroll_2026-11', expense: { categoryId: 'cat_other', amountMinor: 1, expenseDate: '2026-11-01' } });
  assert.equal(edit.error, 'FAILED_PRECONDITION', 'only a draft can be edited');
  const cancel = await expWf.cancelExpense(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', expenseId: 'payroll_2026-11', reason: 'Trying to undo the salaries' });
  assert.equal(cancel.error, 'FAILED_PRECONDITION', 'a paid expense cannot be cancelled');
  const rep = await expReports.getExpenseReport(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', fromDate: '2026-11-01', toDate: '2026-11-30' });
  assert.equal(rep.result.totals.spentMinor, 6300000);
  assert.ok(rep.result.byCategory.some((c) => c.categoryId === 'cat_salaries' && c.totalMinor === 6300000), 'under Salaries');
  assert.equal((await expense(db)).status, 'PAID');
});

test('P5: with the expense module switched off the run is still paid and the record is kept', async () => {
  const { ctx, db } = env({ 'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata', features: { expenses: false } } });
  const out = await payIt(ctx);
  assert.equal(out.result.status, 'PAID');
  assert.equal((await expense(db)).source, 'PAYROLL');
});

test('P5: an expense already at that id is never overwritten', async () => {
  const { ctx, db } = env({ [`${B}/expenses/payroll_2026-11`]: { number: 'EXP-2026-00007', amountMinor: 1, status: 'PAID', source: 'PAYROLL', note: 'kept' } });
  const out = await payIt(ctx);
  assert.equal(out.result.status, 'PAID');
  const e = await expense(db);
  assert.deepEqual([e.number, e.amountMinor, e.note], ['EXP-2026-00007', 1, 'kept']);
});

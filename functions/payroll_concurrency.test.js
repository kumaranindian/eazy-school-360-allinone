'use strict';
// Hardening: a recalculation must never rewrite payslips under an approval being signed, a payroll must refuse
// rather than silently leave someone out, and a salary structure has a bounded history.
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const r = require('./payroll_runs');
const pay = require('./payroll');
const prev = require('./payroll_preview');

const T = {};
const ts = (key) => new Date(`${key}T00:00:00Z`);
const B = 'schools/sA/branches/b1';
const NOW = new Date('2026-11-30T12:00:00Z');
const NOV = ['02', '03', '04', '05', '06', '09', '10', '11', '12', '13', '16', '17', '18', '19', '20', '23', '24', '25', '26', '27', '30'].map((d) => `2026-11-${d}`);
const structure = (staff, seq, basic, extra = {}) => [`${B}/salaryStructures/${staff}_${String(seq).padStart(5, '0')}`, {
  staffId: staff, seq, effectiveFrom: '2026-04-01', latest: seq === 1, currency: 'INR',
  lines: [{ componentId: 'pc_basic', nameSnapshot: 'Basic salary', kind: 'EARNING', calc: 'FIXED', amountMinor: basic }],
  grossMinor: basic, deductionsMinor: 0, netMinor: basic, ...extra,
}];
const seed = (extra = {}) => ({
  'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/owner2': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  [B]: { name: 'Main' },
  [`${B}/staff/st1`]: { firstName: 'Asha', employeeCode: 'E1', status: 'ACTIVE', joiningDate: ts('2020-06-01') },
  ...Object.fromEntries([structure('st1', 1, 2100000), ...NOV.map((d) => [`${B}/staffAttendance/${d}_st1`, { staffId: 'st1', dateKey: d, status: 'PRESENT' }])]),
  ...extra,
});
const env = (extra) => {
  const db = fakeDb(seed(extra));
  return { db, ctx: { db, now: 'TS', wall: () => NOW } };
};
const base = (x = {}) => ({ schoolId: 'sA', branchId: 'b1', period: '2026-11', ...x });
const runDoc = async (db) => (await db.collection('schools').doc('sA').collection('branches').doc('b1').collection('payrollRuns').doc('2026-11').get()).data();
const adj = { kind: 'EARNING', label: 'Bonus', amountMinor: 1000, reason: 'Festival bonus agreed by the trust' };

test('a finished calculation leaves no lock behind', async () => {
  const { ctx, db } = env();
  await r.createPayrollRun(ctx, 'fin', T, base());
  const run = await runDoc(db);
  assert.deepEqual([run.status, run.calculating, run.calculatingAtMs], ['CALCULATED', false, null]);
});

test('while a calculation holds the run, nobody can approve, adjust or start another', async () => {
  const { ctx, db } = env();
  await r.createPayrollRun(ctx, 'fin', T, base());
  const ref = db.collection('schools').doc('sA').collection('branches').doc('b1').collection('payrollRuns').doc('2026-11');
  await ref.update({ calculating: true, calculatingAtMs: NOW.getTime() - 1000 });
  const before = JSON.stringify([...db.store.entries()]);
  for (const out of [
    await r.approvePayrollRun(ctx, 'owner', T, base()),
    await r.adjustPayslip(ctx, 'fin', T, base({ staffId: 'st1', adjustment: adj })),
    await r.calculatePayrollRun(ctx, 'fin', T, base()),
  ]) assert.equal(out.error, 'ABORTED', JSON.stringify(out));
  assert.equal(JSON.stringify([...db.store.entries()]), before, 'the refused calls wrote nothing');
});

test('a lock that was never released (a crashed calculation) expires', async () => {
  const { ctx, db } = env();
  await r.createPayrollRun(ctx, 'fin', T, base());
  const ref = db.collection('schools').doc('sA').collection('branches').doc('b1').collection('payrollRuns').doc('2026-11');
  await ref.update({ calculating: true, calculatingAtMs: NOW.getTime() - 6 * 60 * 1000 });
  assert.equal((await r.calculatePayrollRun(ctx, 'fin', T, base())).result.status, 'CALCULATED', 'a stale lock does not block');
  assert.equal((await runDoc(db)).calculating, false);
});

test('an approval that began before a recalculation took the run fails its version check and approves nothing', async () => {
  const { ctx, db } = env();
  await r.createPayrollRun(ctx, 'fin', T, base());
  // simulate a recalculation taking the run between the approver's reads and their commit
  const realTx = db.runTransaction.bind(db);
  let fired = false;
  db.runTransaction = async (fn, opts) => {
    if (!fired) {
      fired = true;
      const ref = db.collection('schools').doc('sA').collection('branches').doc('b1').collection('payrollRuns').doc('2026-11');
      const cur = (await ref.get()).data();
      await ref.update({ calculating: true, calculatingAtMs: NOW.getTime(), version: cur.version + 1 });
    }
    return realTx(fn, opts);
  };
  const out = await r.approvePayrollRun(ctx, 'owner', T, base());
  assert.equal(out.error, 'ABORTED');
  assert.equal((await runDoc(db)).status, 'CALCULATED', 'not approved');
});

test('a calculation that fails releases the run', async () => {
  // more than 1000 staff: refused, not silently truncated
  const many = Object.fromEntries(Array.from({ length: 1001 }, (_, i) => [`${B}/staff/m${i}`, { firstName: 'S', status: 'ACTIVE', joiningDate: ts('2020-06-01') }]));
  const { ctx, db } = env(many);
  const out = await r.createPayrollRun(ctx, 'fin', T, base());
  assert.equal(out.error, 'FAILED_PRECONDITION');
  assert.match(out.reason, /more than 1000 staff/);
  const run = await runDoc(db);
  assert.deepEqual([run.status, run.calculating], ['DRAFT', false], 'the run is a draft and not locked');
  // fix the cause (remove the extra staff); the same run can now be calculated
  for (const k of Object.keys(many)) db.store.delete(k);
  assert.equal((await r.calculatePayrollRun(ctx, 'fin', T, base())).result.status, 'CALCULATED');
});

test('too many salary versions in the branch is refused, not silently truncated', async () => {
  const versions = Object.fromEntries(Array.from({ length: 5001 }, (_, i) => structure(`x${i}`, 1, 100)));
  const { ctx } = env(versions);
  const out = await r.createPayrollRun(ctx, 'fin', T, base());
  assert.equal(out.error, 'FAILED_PRECONDITION');
  assert.equal((await prev.previewPayroll(ctx, 'owner', T, base())).error, 'FAILED_PRECONDITION');
});

test('a salary structure keeps at most 200 versions', async () => {
  const versions = Object.fromEntries(Array.from({ length: 200 }, (_, i) => structure('st1', i + 1, 2100000 + i, { effectiveFrom: '2026-04-01', latest: i === 199 })));
  const { ctx, db } = env(versions);
  await pay.listPayComponents(ctx, 'owner', T, { schoolId: 'sA' }); // seeds the built-in Basic
  const out = await pay.saveSalaryStructure(ctx, 'owner', T, base({ staffId: 'st1', effectiveFrom: '2026-12-01', reason: 'One more increment', lines: [{ componentId: 'pc_basic', amountMinor: 3000000 }] }));
  assert.equal(out.error, 'FAILED_PRECONDITION');
  assert.match(out.reason, /at most 200 versions/);
  assert.equal([...db.store.keys()].filter((k) => k.includes('salaryStructures/st1_')).length, 200);
});

test('the audit trail keeps who changed whose pay, never the amount, the item name or the reason', () => {
  const { REQUEST_REDACTED, RESPONSE_OMITTED } = require('./call_audit');
  const a = REQUEST_REDACTED.adjustPayslip({ schoolId: 's', staffId: 'st1', period: '2026-11', adjustment: adj });
  assert.deepEqual(a.adjustment, { kind: 'EARNING', amountMinor: '[not recorded]', label: '[not recorded]', reason: '[not recorded]' });
  assert.equal(a.staffId, 'st1');
  const s = REQUEST_REDACTED.saveSalaryStructure({ staffId: 'st1', reason: 'Demotion after review', lines: [{ amountMinor: 5 }] });
  assert.equal(s.reason, '[not recorded]');
  assert.equal(s.lines, '[1 lines; amounts not recorded]');
  for (const name of ['getPayrollRunHistory', 'getPayslip', 'getMyPayslip', 'previewPayroll', 'exportPayrollRegister', 'getPayrollRegister', 'listPayrollRuns', 'getPayrollRun', 'getSalaryStructure', 'listSalaryStructures', 'listMyPayslips']) {
    assert.ok(RESPONSE_OMITTED.has(name), `${name} response must not be copied into the audit trail`);
  }
});

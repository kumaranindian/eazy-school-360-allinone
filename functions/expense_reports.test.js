'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const r = require('./expense_reports');

const NOW = new Date('2026-11-15T10:00:00Z');
const T = {};
let n = 0;
const exp = (o = {}) => ({
  schoolId: 'sA', branchId: 'b1', number: `EXP-2026-${String(++n).padStart(5, '0')}`, categoryId: 'cat_other', categoryName: 'Other',
  amountMinor: 10000, currency: 'INR', expenseDate: '2026-11-10', payee: 'Vendor', description: '', status: 'PAID', version: 2,
  createdBy: 'fin', createdByName: 'Fin One', ...o,
});
const env = (rows = [], extra = {}) => {
  const seed = {
    'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
    'schools/sB': { name: 'B', status: 'ACTIVE', currency: 'INR' },
    'schools/sA/branches/b1': { name: 'Main' },
    'schools/sA/branches/b2': { name: 'North' },
    'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
    'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
    'users/ba2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
    'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
    'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
    'users/otherOwner': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
    ...extra,
  };
  rows.forEach((row, i) => { seed[`schools/sA/branches/${row.branchId || 'b1'}/expenses/x${i}`] = row; });
  const db = fakeDb(seed);
  return { db, ctx: { db, now: 'TS', wall: () => NOW, nowDate: () => NOW } };
};
const q = (o = {}) => ({ schoolId: 'sA', fromDate: '2026-11-01', toDate: '2026-11-15', ...o });

test('validateRange: real dates, ordered, not in the future, at most 366 days', () => {
  const ok = (o) => r.validateRange({ fromDate: '2026-11-01', toDate: '2026-11-15', ...o }, '2026-11-15');
  assert.ok(ok({}).value);
  assert.ok(ok({ fromDate: '2026-11-15' }).value, 'one day is a range');
  for (const bad of [{ fromDate: 'x' }, { toDate: '2026-02-30' }, { toDate: '2026-11-16' }, { fromDate: '2026-11-16', toDate: '2026-11-15' }, { fromDate: '2025-11-14' }, { fromDate: undefined }]) {
    assert.ok(ok(bad).errors, JSON.stringify(bad));
  }
  assert.ok(ok({ fromDate: '2025-11-15' }).value, 'exactly a year back is allowed');
  assert.ok(r.validateRange(null, '2026-11-15').errors);
});

test('aggregate: spend is approved + paid only; the rest is shown apart', () => {
  const rows = [
    exp({ status: 'PAID', amountMinor: 1000, categoryId: 'a', categoryName: 'A', expenseDate: '2026-10-05' }),
    exp({ status: 'APPROVED', amountMinor: 500, categoryId: 'a', categoryName: 'A', expenseDate: '2026-11-05' }),
    exp({ status: 'PAID', amountMinor: 3000, categoryId: 'b', categoryName: 'B', expenseDate: '2026-11-06' }),
    exp({ status: 'SUBMITTED', amountMinor: 700, categoryId: 'b', categoryName: 'B' }),
    exp({ status: 'DRAFT', amountMinor: 111 }),
    exp({ status: 'REJECTED', amountMinor: 222 }),
    exp({ status: 'CANCELLED', amountMinor: 333 }),
    exp({ status: 'FUTURE_STATE', amountMinor: 999 }),
  ];
  const a = r.aggregate(rows);
  assert.deepEqual(a.totals, { spentMinor: 4500, paidMinor: 4000, unpaidApprovedMinor: 500, awaitingApprovalMinor: 700 });
  assert.deepEqual(a.byStatus.PAID, { count: 2, totalMinor: 4000 });
  assert.deepEqual(a.byStatus.DRAFT, { count: 1, totalMinor: 111 });
  assert.deepEqual(a.byCategory.map((c) => [c.name, c.totalMinor, c.paidMinor, c.count]), [['B', 3000, 3000, 1], ['A', 1500, 1000, 2]], 'largest first');
  assert.deepEqual(a.byMonth.map((m) => [m.month, m.totalMinor]), [['2026-10', 1000], ['2026-11', 3500]], 'oldest month first');
  assert.deepEqual(a.byBranch, []);
  assert.equal(Object.values(a.byStatus).reduce((s, x) => s + x.count, 0), 7, 'an unknown status is not counted');
});

test('aggregate: nothing at all is a calm zero report', () => {
  const a = r.aggregate([]);
  assert.deepEqual(a.totals, { spentMinor: 0, paidMinor: 0, unpaidApprovedMinor: 0, awaitingApprovalMinor: 0 });
  assert.deepEqual([a.byCategory, a.byMonth], [[], []]);
});

test('aggregate: by branch for the whole school, named', () => {
  const a = r.aggregate([exp({ branchId: 'b1', amountMinor: 100 }), exp({ branchId: 'b2', amountMinor: 900 })], { branchNames: { b1: 'Main', b2: 'North' }, includeBranches: true });
  assert.deepEqual(a.byBranch.map((b) => [b.name, b.totalMinor]), [['North', 900], ['Main', 100]]);
});

test('plainAmount is exact and follows the currency decimals', () => {
  assert.equal(r.plainAmount(125050, 'INR'), '1250.50');
  assert.equal(r.plainAmount(5, 'INR'), '0.05');
  assert.equal(r.plainAmount(0, 'INR'), '0.00');
  assert.equal(r.plainAmount(1500, 'JPY'), '1500');
  assert.equal(r.plainAmount(1234, 'KWD'), '1.234');
  assert.equal(r.plainAmount(999999999999, 'INR'), '9999999999.99', 'no floating point drift at the cap');
});

test('toCsv: one header, one row per expense, spreadsheet formulas neutralised, commas and quotes quoted', () => {
  const csv = r.toCsv([exp({ payee: '=HYPERLINK("http://x")', description: 'a, "b"', amountMinor: 125050, branchId: 'b1' })], { currency: 'INR', branchNames: { b1: 'Main' } });
  const [head, row] = csv.split('\n');
  assert.equal(head, r.CSV_HEADER.join(','));
  assert.ok(row.includes("'=HYPERLINK"), 'formula neutralised');
  assert.ok(row.includes('"a, ""b"""'));
  assert.ok(row.includes(',1250.50,INR,'));
  assert.ok(row.startsWith('EXP-'));
  assert.ok(row.includes(',Main,'));
});

test('report: a branch admin or finance sees their branch; only a school admin sees the whole school', async () => {
  const e = env([exp({ amountMinor: 1000 }), exp({ amountMinor: 5000, branchId: 'b2' })]);
  const own = await r.getExpenseReport(e.ctx, 'ba1', T, q({ branchId: 'b1' }));
  assert.equal(own.result.scope, 'BRANCH');
  assert.equal(own.result.totals.spentMinor, 1000);
  assert.equal((await r.getExpenseReport(e.ctx, 'fin', T, q({ branchId: 'b1' }))).result.totals.spentMinor, 1000);
  assert.equal((await r.getExpenseReport(e.ctx, 'ba1', T, q({ branchId: 'b2' }))).error, 'PERMISSION_DENIED', "another branch's numbers");
  assert.equal((await r.getExpenseReport(e.ctx, 'ba1', T, q())).error, 'PERMISSION_DENIED', 'the whole school is not for a branch admin');
  assert.equal((await r.getExpenseReport(e.ctx, 'fin', T, q())).error, 'PERMISSION_DENIED');
  assert.equal((await r.getExpenseReport(e.ctx, 'teacher', T, q({ branchId: 'b1' }))).error, 'PERMISSION_DENIED');
  assert.equal((await r.getExpenseReport(e.ctx, 'otherOwner', T, q())).error, 'PERMISSION_DENIED');
  const whole = await r.getExpenseReport(e.ctx, 'owner', T, q());
  assert.equal(whole.result.scope, 'SCHOOL');
  assert.equal(whole.result.totals.spentMinor, 6000);
  assert.deepEqual(whole.result.byBranch.map((b) => [b.name, b.totalMinor]), [['North', 5000], ['Main', 1000]]);
  assert.equal((await r.getExpenseReport(e.ctx, 'owner', T, q({ branchId: 'b2' }))).result.totals.spentMinor, 5000, 'a school admin may pick one branch');
  assert.equal((await r.getExpenseReport(e.ctx, 'owner', T, q({ branchId: '../x' }))).error, 'PERMISSION_DENIED');
});

test('report: only the date range counts; the range is validated; a school with no expenses reports zero', async () => {
  const e = env([exp({ expenseDate: '2026-10-31' }), exp({ expenseDate: '2026-11-01' }), exp({ expenseDate: '2026-11-15' }), exp({ expenseDate: '2026-11-16' })]);
  const out = await r.getExpenseReport(e.ctx, 'owner', T, q());
  assert.equal(out.result.rows, 2, 'both ends are inclusive, outside is not');
  assert.equal(out.result.currency, 'INR');
  assert.equal((await r.getExpenseReport(e.ctx, 'owner', T, q({ toDate: '2026-11-16' }))).error, 'INVALID_ARGUMENT');
  assert.equal((await r.getExpenseReport(e.ctx, 'owner', T, q({ fromDate: '2024-01-01' }))).error, 'INVALID_ARGUMENT');
  assert.equal((await r.getExpenseReport(env().ctx, 'owner', T, q())).result.totals.spentMinor, 0);
});

test('report: the range ends today in the SCHOOL zone, not the server clock', async () => {
  const e = env([]);
  e.ctx.wall = () => new Date('2026-11-15T20:00:00Z'); // the 16th in Kolkata
  assert.ok((await r.getExpenseReport(e.ctx, 'owner', T, q({ toDate: '2026-11-16' }))).result, 'the 16th is today for this school');
});

test('report: a module switched off or a suspended school gives nothing', async () => {
  const off = env([exp()], { 'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', features: { expenses: false } } });
  assert.equal((await r.getExpenseReport(off.ctx, 'owner', T, q())).error, 'PERMISSION_DENIED');
});

test('export: a CSV of the range, optionally one status, with money exact and names resolved', async () => {
  const e = env([
    exp({ expenseDate: '2026-11-03', amountMinor: 125050, status: 'PAID', paymentMode: 'UPI', paymentReference: 'UTR1', paidDate: '2026-11-04' }),
    exp({ expenseDate: '2026-11-02', amountMinor: 100, status: 'DRAFT' }),
    exp({ expenseDate: '2026-11-05', amountMinor: 700, status: 'SUBMITTED', branchId: 'b2' }),
  ]);
  const all = await r.exportExpenses(e.ctx, 'owner', T, q());
  const lines = all.result.csv.split('\n');
  assert.equal(lines.length, 4);
  assert.equal(all.result.rows, 3);
  assert.deepEqual(lines.slice(1).map((l) => l.split(',')[2]), ['2026-11-02', '2026-11-03', '2026-11-05'], 'oldest first');
  assert.ok(lines[2].includes(',1250.50,INR,PAID,UPI,UTR1,2026-11-04,'));
  assert.ok(lines[3].includes(',North,'), 'the branch name, not its id');
  const paid = await r.exportExpenses(e.ctx, 'owner', T, q({ status: 'PAID' }));
  assert.equal(paid.result.rows, 1);
  assert.equal((await r.exportExpenses(e.ctx, 'owner', T, q({ status: 'NOPE' }))).error, 'INVALID_ARGUMENT');
  const branch = await r.exportExpenses(e.ctx, 'ba1', T, q({ branchId: 'b1' }));
  assert.equal(branch.result.rows, 2);
  assert.ok(branch.result.csv.includes(',Main,'));
  assert.equal((await r.exportExpenses(e.ctx, 'ba1', T, q({ branchId: 'b2' }))).error, 'PERMISSION_DENIED');
  assert.equal((await r.exportExpenses(e.ctx, 'ba1', T, q())).error, 'PERMISSION_DENIED');
  assert.equal((await r.exportExpenses(e.ctx, 'teacher', T, q({ branchId: 'b1' }))).error, 'PERMISSION_DENIED');
});

test('the export is not copied into the audit trail, only the request is', () => {
  assert.ok(require('./call_audit').RESPONSE_OMITTED.has('exportExpenses'));
});

test('the report callables are wired', () => {
  const m = require('./index.js');
  for (const name of ['getExpenseReport', 'exportExpenses']) assert.ok(m[name], name);
});

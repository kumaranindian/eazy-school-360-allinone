'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const pp = require('./payroll_preview');
const p = require('./payroll');

const T = {};
const ts = (key) => new Date(`${key}T00:00:00Z`);
const B = 'schools/sA/branches/b1';
const NOV = ['02', '03', '04', '05', '06', '09', '10', '11', '12', '13', '16', '17', '18', '19', '20', '23', '24', '25', '26', '27', '30'].map((d) => `2026-11-${d}`);
const att = (staff, day, status) => [`${B}/staffAttendance/${day}_${staff}`, { staffId: staff, dateKey: day, status }];

const seed = (extra = {}) => ({
  'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  'users/finB2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'FINANCE' },
  'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  [B]: { name: 'One' },
  [`${B}/staff/st1`]: { firstName: 'Asha', lastName: 'Rao', employeeCode: 'E1', status: 'ACTIVE', joiningDate: ts('2020-06-01') },
  [`${B}/staff/st2`]: { firstName: 'Bala', employeeCode: 'E2', status: 'ACTIVE', joiningDate: ts('2026-11-16') },
  [`${B}/staff/st3`]: { firstName: 'Chitra', employeeCode: 'E3', status: 'RESIGNED', joiningDate: ts('2019-01-01'), statusChangeDate: ts('2026-10-15') },
  [`${B}/staff/st4`]: { firstName: 'Dev', employeeCode: 'E4', status: 'ACTIVE', joiningDate: ts('2018-01-01') },
  [`${B}/salaryStructures/st1_00001`]: {
    staffId: 'st1', seq: 1, effectiveFrom: '2026-04-01', latest: true, currency: 'INR',
    lines: [{ componentId: 'pc_basic', nameSnapshot: 'Basic salary', kind: 'EARNING', calc: 'FIXED', amountMinor: 2100000 }],
    grossMinor: 2100000, deductionsMinor: 0, netMinor: 2100000,
  },
  [`${B}/salaryStructures/st2_00001`]: {
    staffId: 'st2', seq: 1, effectiveFrom: '2026-04-01', latest: true, currency: 'INR',
    lines: [{ componentId: 'pc_basic', nameSnapshot: 'Basic salary', kind: 'EARNING', calc: 'FIXED', amountMinor: 4200000 }],
    grossMinor: 4200000, deductionsMinor: 0, netMinor: 4200000,
  },
  ...Object.fromEntries(NOV.map((d) => att('st1', d, 'PRESENT'))),
  ...extra,
});
const env = (extra) => {
  const db = fakeDb(seed(extra));
  return { db, ctx: { db, now: 'TS', wall: () => new Date('2026-11-30T12:00:00Z') } };
};
const one = (ctx, body = {}, uid = 'owner') => pp.previewPayroll(ctx, uid, T, { schoolId: 'sA', branchId: 'b1', period: '2026-11', staffId: 'st1', ...body });

test('a full month present pays the structure; the explanation is complete', async () => {
  const { ctx } = env();
  const r = (await one(ctx)).result;
  assert.equal(r.calculation.workingDays, 21);
  assert.equal(r.calculation.paidDays, 21);
  assert.equal(r.calculation.netMinor, 2100000);
  assert.equal(r.calculation.dayRows.length, 21);
  assert.equal(r.staff.name, 'Asha Rao');
  assert.equal(r.structure.seq, 1);
  assert.equal(r.currency, 'INR');
});

test('absence, approved leave of both kinds, a holiday and a special working day are all honoured', async () => {
  const extra = {
    [`${B}/settings/workingDays`]: { isWorkingDay: { SATURDAY: false, SUNDAY: false }, saturdayOffWeeks: [], effectiveFrom: null, history: [] },
    [`${B}/academicYears/y1/holidays/h1`]: { date: ts('2026-11-10'), type: 'FESTIVAL', status: 'ACTIVE', name: 'Diwali' },
    [`${B}/academicYears/y1/holidays/h2`]: { date: ts('2026-11-14'), type: 'SPECIAL_WORKING_DAY', status: 'ACTIVE', name: 'Makeup Saturday' },
    ...Object.fromEntries([att('st1', '2026-11-02', 'ABSENT'), att('st1', '2026-11-03', 'ABSENT'), att('st1', '2026-11-14', 'PRESENT')]),
    [`${B}/leaveApplications/l1`]: { subjectKind: 'STAFF', subjectId: 'st1', status: 'APPROVED', payType: 'PAID', halfDay: 'NONE', countedDateKeys: ['2026-11-02'] },
    [`${B}/leaveApplications/l2`]: { subjectKind: 'STAFF', subjectId: 'st1', status: 'APPROVED', payType: 'UNPAID', halfDay: 'NONE', countedDateKeys: ['2026-11-04', '2026-11-05'] },
    [`${B}/leaveApplications/l3`]: { subjectKind: 'STAFF', subjectId: 'st1', status: 'PENDING', payType: 'UNPAID', halfDay: 'NONE', countedDateKeys: ['2026-11-06'] },
    [`${B}/leaveApplications/l4`]: { subjectKind: 'STUDENT', subjectId: 'st1', status: 'APPROVED', payType: 'UNPAID', halfDay: 'NONE', countedDateKeys: ['2026-11-09'] },
    [`${B}/leaveApplications/l5`]: { subjectKind: 'STAFF', subjectId: 'st9', status: 'APPROVED', payType: 'UNPAID', halfDay: 'NONE', countedDateKeys: ['2026-11-11'] },
    [`${B}/leaveApplications/l6`]: { subjectKind: 'STAFF', subjectId: 'st1', status: 'APPROVED', payType: 'UNPAID', halfDay: 'NONE', countedDateKeys: ['2026-10-30'] },
  };
  // the 10th is a holiday (drop its PRESENT mark); the 14th is a special working day (+1); so 21 - 1 + 1 = 21
  delete extra[`${B}/staffAttendance/2026-11-10_st1`];
  const { ctx, db } = env(extra);
  db.store.delete(`${B}/staffAttendance/2026-11-10_st1`);
  const r = (await one(ctx)).result.calculation;
  assert.equal(r.workingDays, 21, 'the 10th is closed, the 14th is open');
  assert.equal(r.days.paidLeave, 1, 'the 2nd: paid leave beats the ABSENT mark');
  assert.equal(r.days.absent, 1, 'the 3rd');
  assert.equal(r.days.unpaidLeave, 2, 'the 4th and 5th; a pending, a student and another staff member and an October leave are not counted');
  assert.equal(r.unpaidDays, 3);
  assert.equal(r.lines[0].amountMinor, 1800000, '2,100,000 x 18/21');
});

test('a joiner mid-month, a leaver before the month, and a staff member with no structure', async () => {
  const { ctx } = env();
  const all = (await pp.previewPayroll(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', period: '2026-11' })).result;
  assert.deepEqual(all.staff.map((s) => s.staffId), ['st1', 'st2', 'st4'], 'st3 left in October');
  const st2 = all.staff.find((s) => s.staffId === 'st2');
  assert.equal(st2.calculation.paidDays, 11, 'joined on the 16th: 11 school days');
  assert.equal(st2.calculation.netMinor, 2200000, '4,200,000 x 22/42');
  assert.equal(all.staff.find((s) => s.staffId === 'st4').hasStructure, false);
  assert.equal(all.staff.find((s) => s.staffId === 'st4').calculation, null);
  assert.equal(all.workingDays, 21);
  const oct = (await pp.previewPayroll(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', period: '2026-10' })).result;
  assert.ok(oct.staff.some((s) => s.staffId === 'st3'), 'st3 was employed until the 15th');
  assert.equal(oct.staff.some((s) => s.staffId === 'st2'), false, 'st2 had not joined');
});

test('the school policy for unmarked days is read and can be saved by a school admin only', async () => {
  const { ctx } = env();
  const none = Object.fromEntries(['st1'].map(() => [0, 0]));
  assert.ok(none);
  assert.equal((await pp.getPayrollSettings(ctx, 'fin', T, { schoolId: 'sA' })).result.settings.unmarkedDays, 'PAID');
  assert.equal((await pp.savePayrollSettings(ctx, 'fin', T, { schoolId: 'sA', settings: { unmarkedDays: 'UNPAID' } })).error, 'PERMISSION_DENIED');
  assert.equal((await pp.savePayrollSettings(ctx, 'owner', T, { schoolId: 'sA', settings: { unmarkedDays: 'MAYBE' } })).error, 'INVALID_ARGUMENT');
  assert.equal((await pp.savePayrollSettings(ctx, 'owner', T, { schoolId: 'sA', settings: { unmarkedDays: 'UNPAID' }, baseVersion: 0 })).result.version, 1);
  assert.equal((await pp.savePayrollSettings(ctx, 'owner', T, { schoolId: 'sA', settings: { unmarkedDays: 'PAID' }, baseVersion: 0 })).error, 'ABORTED');
  // with UNPAID, the days nobody marked are not paid
  const { ctx: c2, db } = env();
  await pp.savePayrollSettings(c2, 'owner', T, { schoolId: 'sA', settings: { unmarkedDays: 'UNPAID' } });
  db.store.delete(`${B}/staffAttendance/2026-11-02_st1`);
  const r = (await one(c2)).result.calculation;
  assert.equal(r.days.unmarked, 1);
  assert.equal(r.unpaidDays, 1);
  assert.equal(r.warnings[0].code, 'NOT_MARKED');
});

test('who may preview: school admin and finance of the branch only', async () => {
  const { ctx } = env();
  assert.ok((await one(ctx, {}, 'fin')).result);
  for (const u of ['ba1', 'teacher', 'finB2', 'ghost']) {
    assert.equal((await one(ctx, {}, u)).error, 'PERMISSION_DENIED', u);
    assert.equal((await pp.previewPayroll(ctx, u, T, { schoolId: 'sA', branchId: 'b1', period: '2026-11' })).error, 'PERMISSION_DENIED', `branch ${u}`);
  }
  assert.equal((await pp.previewPayroll(ctx, 'owner', T, { schoolId: 'sA', branchId: '../b', period: '2026-11' })).error, 'PERMISSION_DENIED');
});

test('bad periods and staff ids are refused; nothing is written', async () => {
  const { ctx, db } = env();
  const before = db.store.size;
  for (const period of [undefined, null, 5, '2026-13', '2026-1', '26-11', '2026-12', '2027-01', '2024-01', '']) {
    assert.equal((await one(ctx, { period })).error, 'INVALID_ARGUMENT', String(period));
  }
  assert.equal((await one(ctx, { staffId: '../x' })).error, 'INVALID_ARGUMENT');
  assert.equal((await one(ctx, { staffId: 'nobody' })).error, 'NOT_FOUND');
  assert.equal(db.store.size, before, 'a preview writes nothing');
});

test('the structure in force on the first of the month is used, not a later revision', async () => {
  const { ctx } = env({
    [`${B}/salaryStructures/st1_00002`]: {
      staffId: 'st1', seq: 2, effectiveFrom: '2026-12-01', latest: true, currency: 'INR',
      lines: [{ componentId: 'pc_basic', nameSnapshot: 'Basic salary', kind: 'EARNING', calc: 'FIXED', amountMinor: 9900000 }],
      grossMinor: 9900000, deductionsMinor: 0, netMinor: 9900000,
    },
  });
  const r = (await one(ctx)).result;
  assert.equal(r.structure.seq, 1);
  assert.equal(r.calculation.netMinor, 2100000);
});

test('the preview is the same whether asked for one person or the whole branch', async () => {
  const { ctx } = env();
  const single = (await one(ctx)).result.calculation;
  const all = (await pp.previewPayroll(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', period: '2026-11' })).result.staff.find((s) => s.staffId === 'st1').calculation;
  assert.equal(all.netMinor, single.netMinor);
  assert.equal(all.paidDays, single.paidDays);
  assert.equal(all.warningCount, single.warnings.length);
});

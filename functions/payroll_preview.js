'use strict';

// Payroll phase P2: the month's pay worked out from the structure, the branch calendar, staff attendance and
// approved leave, WITHOUT saving anything (runs and payslips are phase P3/P4). It exists so the school can see
// exactly what a run would pay, and why, before there is a run.
//
//   schools/{s}/payrollSettings/config      { unmarkedDays: PAID | UNPAID, version }
//
// Reads (all through the Admin SDK, bounded): branches/{b}/settings/workingDays, academicYears/*/holidays,
// staffAttendance (one date-range query), leaveApplications (subjectKind == STAFF), staff, salaryStructures.
// Salary figures are in the response, so the call is school admin / finance only and its response is kept
// out of the audit trail.

const { validId } = require('./ids');
const { authorize, CAPS, inForce, structureView } = require('./payroll');
const { civilToday, wall } = require('./expenses');
const calendar = require('./payroll_calendar');
const { calculateMonth, UNMARKED } = require('./payroll_calculator');

const DEFAULT_SETTINGS = Object.freeze({ unmarkedDays: 'PAID', allowSelfApproval: false });
const ATTENDANCE_CAP = 20000;
const LEAVE_CAP = 5000;
const STAFF_CAP = 1000;
const TERMINAL = ['RESIGNED', 'TERMINATED', 'RETIRED'];

const settingsRef = (db, schoolId) => db.collection('schools').doc(schoolId).collection('payrollSettings').doc('config');
const branchRef = (db, schoolId, branchId) => db.collection('schools').doc(schoolId).collection('branches').doc(branchId);
const staffName = (s) => [s.firstName, s.middleName, s.lastName].filter(Boolean).join(' ');
const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');

function validateSettings(input) {
  const i = input && typeof input === 'object' ? input : {};
  if (i.unmarkedDays !== undefined && !UNMARKED.includes(i.unmarkedDays)) return { errors: { unmarkedDays: `one of ${UNMARKED.join(', ')}` } };
  if (i.allowSelfApproval !== undefined && typeof i.allowSelfApproval !== 'boolean') return { errors: { allowSelfApproval: 'must be true or false' } };
  return {
    value: {
      unmarkedDays: i.unmarkedDays === undefined ? DEFAULT_SETTINGS.unmarkedDays : i.unmarkedDays,
      allowSelfApproval: i.allowSelfApproval === undefined ? DEFAULT_SETTINGS.allowSelfApproval : i.allowSelfApproval,
    },
  };
}
const settingsView = (s) => ({
  unmarkedDays: UNMARKED.includes(s && s.unmarkedDays) ? s.unmarkedDays : DEFAULT_SETTINGS.unmarkedDays,
  allowSelfApproval: s && s.allowSelfApproval === true,
  version: s && Number.isInteger(s.version) ? s.version : 0,
});

/** The school's payroll policy (defaults when never saved). School admin and finance. */
async function getPayrollSettings(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const caller = await authorize(db, uid, token, schoolId, null, 'view');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const stored = (await settingsRef(db, schoolId).get()).data();
  return { result: { settings: settingsView(stored), canManage: CAPS.manage.includes(caller.role) } };
}

/** School admin only; optimistic version. */
async function savePayrollSettings(ctx, uid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const caller = await authorize(db, uid, token, schoolId, null, 'manage');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const parsed = validateSettings(data.settings);
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
  const ref = settingsRef(db, schoolId);
  return db.runTransaction(async (tx) => {
    const prev = (await tx.get(ref)).data();
    const current = prev && Number.isInteger(prev.version) ? prev.version : 0;
    if (data.baseVersion !== undefined && data.baseVersion !== current) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    tx.set(ref, { schoolId, version: current + 1, ...parsed.value, updatedAt: now, updatedBy: uid });
    return { result: { version: current + 1 } };
  });
}

// ---- reading the month's facts ------------------------------------------------------------------

async function loadFacts(db, schoolId, branchId, period) {
  const b = branchRef(db, schoolId, branchId);
  const from = `${period}-01`;
  const dates = calendar.datesOf(period);
  const to = dates[dates.length - 1];
  const workingDays = (await b.collection('settings').doc('workingDays').get()).data() || null;
  const holidays = [];
  for (const y of (await b.collection('academicYears').get()).docs) {
    for (const h of (await y.ref.collection('holidays').get()).docs) holidays.push(h.data());
  }
  const att = await b.collection('staffAttendance').where('dateKey', '>=', from).where('dateKey', '<=', to).limit(ATTENDANCE_CAP + 1).get();
  if (att.docs.length > ATTENDANCE_CAP) return { error: 'FAILED_PRECONDITION', reason: 'too many attendance records for one preview' };
  const attendance = new Map();
  for (const d of att.docs) {
    const r = d.data();
    if (!r.staffId || !r.dateKey) continue;
    if (!attendance.has(r.staffId)) attendance.set(r.staffId, {});
    attendance.get(r.staffId)[r.dateKey] = r.status;
  }
  const lv = await b.collection('leaveApplications').where('subjectKind', '==', 'STAFF').limit(LEAVE_CAP + 1).get();
  if (lv.docs.length > LEAVE_CAP) return { error: 'FAILED_PRECONDITION', reason: 'too many leave records for one preview' };
  const leave = new Map();
  for (const d of lv.docs) {
    const a = d.data();
    if (a.status !== 'APPROVED' || !a.subjectId) continue;
    const keys = (Array.isArray(a.countedDateKeys) ? a.countedDateKeys : []).filter((k) => k >= from && k <= to);
    if (!keys.length) continue;
    if (!leave.has(a.subjectId)) leave.set(a.subjectId, []);
    leave.get(a.subjectId).push({ dateKeys: keys, halfDay: a.halfDay || 'NONE', payType: a.payType });
  }
  return { facts: { workingDays, holidays, attendance, leave, workingDates: calendar.workingDatesOf(period, workingDays, holidays), from, to } };
}

function employmentOf(staff) {
  const from = calendar.keyOf(staff.joiningDate);
  const to = TERMINAL.includes(staff.status) ? calendar.keyOf(staff.statusChangeDate) : null;
  return { from, to };
}

/** The month's pay for one staff member from [facts] and their structure versions; pure given its inputs. */
function payFor(staff, structureDoc, facts, settings) {
  if (!structureDoc) return null;
  return calculateMonth({
    workingDates: facts.workingDates,
    lines: (structureDoc.lines || []).map((l) => ({ ...l, name: l.nameSnapshot })),
    attendance: facts.attendance.get(staff.id) || {},
    leave: facts.leave.get(staff.id) || [],
    employment: employmentOf(staff.data),
    settings,
  });
}

const summary = (r) => ({
  workingDays: r.workingDays, paidDays: r.paidDays, unpaidDays: r.unpaidDays,
  grossMinor: r.grossMinor, deductionsMinor: r.deductionsMinor, netMinor: r.netMinor,
  unrecoveredDeductionMinor: r.unrecoveredDeductionMinor, warningCount: r.warnings.length,
});

/**
 * Every current staff member of the branch employed at any time in [period], each with the structure in force
 * on the 1st and the month's calculation (null when there is no structure). Shared by the preview and by
 * payroll runs, so a run pays exactly what the preview showed.
 */
async function branchCalculations(db, schoolId, branchId, period, settings, facts) {
  const b = branchRef(db, schoolId, branchId);
  const periodStart = `${period}-01`;
  const all = (await b.collection('staff').limit(STAFF_CAP).get()).docs.map((d) => ({ id: d.id, data: d.data() }));
  const byStaff = new Map();
  for (const d of (await b.collection('salaryStructures').limit(STAFF_CAP * 5).get()).docs) {
    const v = d.data();
    if (!byStaff.has(v.staffId)) byStaff.set(v.staffId, []);
    byStaff.get(v.staffId).push({ id: d.id, data: v });
  }
  const rows = [];
  for (const s of all) {
    const emp = employmentOf(s.data);
    if (emp.to && emp.to < facts.from) continue; // left before this month
    if (emp.from && emp.from > facts.to) continue; // joins after it
    const inf = inForce(byStaff.get(s.id) || [], periodStart);
    rows.push({ staff: s, inf, calc: payFor(s, inf && inf.data, facts, settings) });
  }
  return { rows };
}

/**
 * What a month's pay would be. With a staffId: the full explanation for that person (every line, each day,
 * every warning). Without: one summary row per current staff member of the branch. Nothing is saved.
 * School admin and finance only (a branch admin sees no pay).
 */
async function previewPayroll(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId)) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, 'view');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const period = data.period;
  if (typeof period !== 'string' || !calendar.PERIOD.test(period)) return { error: 'INVALID_ARGUMENT', reason: 'period: yyyy-mm' };
  const school = (await db.collection('schools').doc(schoolId).get()).data() || {};
  const today = civilToday(wall(ctx), school.timezone || 'UTC');
  if (period > today.slice(0, 7)) return { error: 'INVALID_ARGUMENT', reason: 'period: a month that has not started cannot be calculated' };
  const earliest = `${String(Number(today.slice(0, 4)) - 2).padStart(4, '0')}-${today.slice(5, 7)}`;
  if (period < earliest) return { error: 'INVALID_ARGUMENT', reason: 'period: more than 2 years back' };
  const single = data.staffId !== undefined && data.staffId !== null;
  if (single && !validId(data.staffId)) return { error: 'INVALID_ARGUMENT', reason: 'staffId' };

  const settings = settingsView((await settingsRef(db, schoolId).get()).data());
  const loaded = await loadFacts(db, schoolId, branchId, period);
  if (loaded.error) return loaded;
  const { facts } = loaded;
  const staffCol = branchRef(db, schoolId, branchId).collection('staff');
  const sCol = branchRef(db, schoolId, branchId).collection('salaryStructures');

  const versionsFor = async (staffId) => (await sCol.where('staffId', '==', staffId).limit(200).get()).docs.map((d) => ({ id: d.id, data: d.data() }));
  const periodStart = `${period}-01`;

  if (single) {
    const snap = await staffCol.doc(data.staffId).get();
    if (!snap.exists) return { error: 'NOT_FOUND', reason: 'that staff member does not exist' };
    const staff = { id: snap.id, data: snap.data() };
    const inf = inForce(await versionsFor(staff.id), periodStart);
    const r = payFor(staff, inf && inf.data, facts, settings);
    return {
      result: {
        period, currency: school.currency || 'INR', settings: { unmarkedDays: settings.unmarkedDays },
        staff: { id: staff.id, name: staffName(staff.data), employeeCode: staff.data.employeeCode || '', status: staff.data.status || '' },
        structure: inf ? structureView(inf.id, inf.data) : null,
        calculation: r,
      },
    };
  }

  const calcs = await branchCalculations(db, schoolId, branchId, period, settings, facts);
  const rows = calcs.rows.map((r) => ({
    staffId: r.staff.id, name: staffName(r.staff.data), employeeCode: r.staff.data.employeeCode || '', status: r.staff.data.status || '',
    hasStructure: !!r.inf, calculation: r.calc ? summary(r.calc) : null,
  }));
  rows.sort((a, b) => a.name.localeCompare(b.name));
  return { result: { period, currency: school.currency || 'INR', settings: { unmarkedDays: settings.unmarkedDays }, workingDays: facts.workingDates.length, staff: rows } };
}

module.exports = { branchCalculations, staffName, DEFAULT_SETTINGS, validateSettings, settingsView, getPayrollSettings, savePayrollSettings, previewPayroll, payFor, employmentOf, loadFacts, settingsRef };

'use strict';

// Payroll phase P4: a staff member reads THEIR OWN payslips. Published means the run is PAID (payroll_runs.js);
// nothing is readable earlier. The caller never names a staff member: the staff record is found from the signed-in
// user (staff.userId), so nobody can ask for someone else's pay by sending a different id. A parent, a user with
// no staff record, a user of another school, a deactivated user and a platform admin get nothing. Responses carry
// pay figures, so they are kept out of the audit trail (call_audit.js); the one-off items are shown with their
// name and amount, but not the internal reason an administrator wrote.

const { loginAllowed, schoolGate } = require('./access');
const { validId } = require('./ids');
const calendar = require('./payroll_calendar');

const FEATURE = 'payroll';
const STAFF_ROLES = ['SCHOOL_ADMIN', 'BRANCH_ADMIN', 'TEACHER', 'FINANCE'];
const toMs = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : t instanceof Date ? t.getTime() : typeof t === 'number' ? t : null);

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);

/** The caller, or null: signed in to THIS school, a staff role, login allowed, school usable, payroll module on. */
async function authorizeSelf(db, uid, token, schoolId) {
  if (!validId(schoolId)) return null;
  const profile = (await db.collection('users').doc(uid).get()).data();
  if (!profile || profile.schoolId !== schoolId || !loginAllowed(profile, token)) return null;
  if (!STAFF_ROLES.includes(profile.role)) return null;
  if (!(await schoolGate(db, schoolId, FEATURE)).allowed) return null;
  return { uid, profile };
}

/** The caller's own staff record(s): { branchId, staffId, data }. A school admin may sit in any branch. */
async function ownStaff(db, schoolId, uid, profile, onlyBranch) {
  let branches = [...new Set([profile.branchId, ...Object.keys(profile.branchRoles || {})].filter((b) => validId(b)))];
  if (profile.role === 'SCHOOL_ADMIN' || !branches.length) {
    branches = (await db.collection('schools').doc(schoolId).collection('branches').limit(100).get()).docs.map((d) => d.id);
  }
  if (onlyBranch) branches = branches.filter((b) => b === onlyBranch);
  const out = [];
  for (const b of branches) {
    const snap = await branchRef(db, schoolId, b).collection('staff').where('userId', '==', uid).limit(2).get();
    for (const d of snap.docs) out.push({ branchId: b, staffId: d.id, data: d.data() });
  }
  return out;
}

const staffName = (s) => [s.firstName, s.middleName, s.lastName].filter(Boolean).join(' ');

/** The months the caller has been paid, newest first. */
async function listMyPayslips(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const caller = await authorizeSelf(db, uid, token, schoolId);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const mine = await ownStaff(db, schoolId, uid, caller.profile);
  const rows = [];
  for (const m of mine) {
    const runs = await branchRef(db, schoolId, m.branchId).collection('payrollRuns').where('status', '==', 'PAID').limit(36).get();
    for (const r of runs.docs) {
      const slip = (await r.ref.collection('payslips').doc(m.staffId).get()).data();
      if (!slip) continue;
      const run = r.data();
      rows.push({ branchId: m.branchId, period: r.id, paidDate: run.paidDate || null, netMinor: slip.netMinor, currency: slip.currency || run.currency || '' });
    }
  }
  rows.sort((a, b) => (a.period < b.period ? 1 : a.period > b.period ? -1 : 0));
  return { result: { payslips: rows } };
}

/** One of the caller's own payslips, once its run is paid. Anything else is NOT_FOUND (an unpublished run is not hinted at). */
async function getMyPayslip(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !calendar.PERIOD.test(String(data.period))) return { error: 'PERMISSION_DENIED' };
  const caller = await authorizeSelf(db, uid, token, schoolId);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const mine = (await ownStaff(db, schoolId, uid, caller.profile, branchId))[0];
  if (!mine) return { error: 'NOT_FOUND', reason: 'no payslip found' };
  const runRef = branchRef(db, schoolId, branchId).collection('payrollRuns').doc(data.period);
  const run = (await runRef.get()).data();
  if (!run || run.status !== 'PAID') return { error: 'NOT_FOUND', reason: 'no payslip found' };
  const p = (await runRef.collection('payslips').doc(mine.staffId).get()).data();
  if (!p) return { error: 'NOT_FOUND', reason: 'no payslip found' };
  const school = (await db.collection('schools').doc(schoolId).get()).data() || {};
  const branch = (await branchRef(db, schoolId, branchId).get()).data() || {};
  return {
    result: {
      payslip: {
        period: data.period,
        schoolName: school.name || '',
        branchName: branch.name || '',
        staffName: staffName(mine.data),
        employeeCode: mine.data.employeeCode || '',
        currency: p.currency || run.currency || '',
        paidDate: run.paidDate || null,
        paymentMode: run.paymentMode || null,
        workingDays: p.workingDays, paidDays: p.paidDays, unpaidDays: p.unpaidDays,
        days: p.days || {},
        lines: (p.lines || []).map((l) => ({ name: l.name || '', kind: l.kind, plannedMinor: l.plannedMinor, amountMinor: l.amountMinor })),
        adjustments: (p.adjustments || []).map((a) => ({ label: a.label, kind: a.kind, amountMinor: a.amountMinor })),
        grossMinor: p.grossMinor, deductionsMinor: p.deductionsMinor, netMinor: p.netMinor,
        unrecoveredDeductionMinor: p.unrecoveredDeductionMinor || 0,
        publishedAtMs: toMs(run.publishedAt),
      },
    },
  };
}

module.exports = { STAFF_ROLES, authorizeSelf, ownStaff, listMyPayslips, getMyPayslip };

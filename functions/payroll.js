'use strict';

// Staff payroll (docs/expense-management/IMPLEMENTATION_PLAN.md, section 6), phase P1: the foundation.
//
//   schools/{s}/payComponents/{id}                              { name, kind, calc, basisComponentId, percentBp, active, system, key }
//   schools/{s}/branches/{b}/salaryStructures/{staffId_00001}   { staffId, seq, effectiveFrom, lines[], gross/deductions/net, latest, ... }
//
// Salary data is the most sensitive data in the system. Like expenses, EVERY read and write is a callable and
// the collections have NO client rules (default deny): a staff member, a parent, a teacher or a branch admin
// cannot read a single figure around the checks below. Who may do what is ONE table (CAPS). The school
// configures its own components; no statutory rule (PF, ESI, tax) is built in, because the product is
// multi-country. A structure is append-only and effective-dated: a raise is a NEW version, the old ones stay,
// and each line keeps a snapshot of its component's name, so a past payslip can never change.

const { loginAllowed, schoolGate } = require('./access');
const { validId } = require('./ids');
const { roleIn, validDate, civilToday, wall } = require('./expenses');
const { lockCurrency } = require('./currency_lock');
const math = require('./payroll_math');

const FEATURE = 'payroll';
const SCHOOL_ADMIN = 'SCHOOL_ADMIN';
const FINANCE = 'FINANCE';

// capability -> roles that hold it. A branch admin is deliberately absent: they get totals later, never an
// individual's pay. Finance may read structures (they prepare the runs); only a school admin edits them or
// the components, so a pay change always has a school admin's name on it.
const CAPS = Object.freeze({
  view: [SCHOOL_ADMIN, FINANCE],
  editStructure: [SCHOOL_ADMIN],
  manage: [SCHOOL_ADMIN],
  // payroll runs (phase P3): finance prepares and pays, only a school admin approves
  prepare: [SCHOOL_ADMIN, FINANCE],
  approve: [SCHOOL_ADMIN],
  pay: [SCHOOL_ADMIN, FINANCE],
});

const trim = (v) => (typeof v === 'string' ? v.trim() : '');
const normalise = (s) => trim(s).toLowerCase().replace(/\s+/g, ' ');
const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');
const toMs = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : t instanceof Date ? t.getTime() : typeof t === 'number' ? t : null);

const components = (db, schoolId) => db.collection('schools').doc(schoolId).collection('payComponents');
const structures = (db, schoolId, branchId) => db.collection('schools').doc(schoolId).collection('branches').doc(branchId).collection('salaryStructures');
const staffRef = (db, schoolId, branchId, staffId) => db.collection('schools').doc(schoolId).collection('branches').doc(branchId).collection('staff').doc(staffId);
const seqId = (n) => String(n).padStart(5, '0');
const structureId = (staffId, seq) => `${staffId}_${seqId(seq)}`;

/** The caller for capability [cap] in [branchId] (null for school-level calls), or null when not allowed. */
async function authorize(db, uid, token, schoolId, branchId, cap) {
  if (!validId(schoolId)) return null;
  if (branchId !== null && !validId(branchId)) return null;
  const roles = Object.prototype.hasOwnProperty.call(CAPS, cap) ? CAPS[cap] : null;
  if (!roles) return null;
  const profile = (await db.collection('users').doc(uid).get()).data();
  if (!profile || profile.schoolId !== schoolId || !loginAllowed(profile, token)) return null;
  const role = branchId === null ? profile.role : roleIn(profile, branchId);
  if (!role || !roles.includes(role)) return null;
  if (!(await schoolGate(db, schoolId, FEATURE)).allowed) return null;
  return { uid, role, profile };
}

// ---- pay components ----------------------------------------------------------------------------

// Seeded once per school (deterministic id). The system component can be neither renamed nor switched off:
// every structure needs a base to take percentages of.
const DEFAULT_COMPONENTS = Object.freeze([{ key: 'BASIC', name: 'Basic salary', kind: 'EARNING', calc: 'FIXED', system: true }]);
const MAX_COMPONENTS = 50;
const componentId = (key) => `pc_${key.toLowerCase()}`;
const componentView = (id, c) => ({
  id,
  name: c.name,
  kind: c.kind,
  calc: c.calc,
  basisComponentId: c.basisComponentId || null,
  percentBp: Number.isInteger(c.percentBp) ? c.percentBp : null,
  active: c.active !== false,
  system: c.system === true,
});

async function ensureDefaultComponents(ctx, schoolId) {
  const { db, now } = ctx;
  const existing = await components(db, schoolId).limit(1).get();
  if (existing.docs.length) return false;
  for (const c of DEFAULT_COMPONENTS) {
    try {
      await components(db, schoolId).doc(componentId(c.key)).create({ schoolId, key: c.key, name: c.name, kind: c.kind, calc: c.calc, active: true, system: true, createdAt: now });
    } catch (e) {
      if (!(e && (e.code === 6 || e.code === 'already-exists' || /already exists/i.test(String(e.message))))) throw e;
    }
  }
  return true;
}

/** The school's pay components (the built-in basic is seeded on first use); active ones unless a school admin asks for all. */
async function listPayComponents(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const caller = await authorize(db, uid, token, schoolId, null, 'view');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  await ensureDefaultComponents(ctx, schoolId);
  const all = (await components(db, schoolId).get()).docs.map((d) => componentView(d.id, d.data()));
  const includeInactive = data.includeInactive === true && CAPS.manage.includes(caller.role);
  const rows = (includeInactive ? all : all.filter((c) => c.active)).sort((a, b) => (a.system === b.system ? a.name.localeCompare(b.name) : a.system ? -1 : 1));
  return { components: rows, canManage: CAPS.manage.includes(caller.role) };
}

/**
 * School admin only: add a component, or rename / switch one on or off / change a percentage's default.
 * What a component IS (earning or deduction, fixed or percentage, and its basis) never changes after it is
 * created, so an old structure cannot quietly mean something else; add a new component instead.
 */
async function savePayComponent(ctx, uid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const caller = await authorize(db, uid, token, schoolId, null, 'manage');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const name = trim(data.name);
  if (name.length < 2 || name.length > 60) return { error: 'INVALID_ARGUMENT', reason: 'name: 2-60 characters' };
  if (data.active !== undefined && typeof data.active !== 'boolean') return { error: 'INVALID_ARGUMENT', reason: 'active: must be true or false' };
  await ensureDefaultComponents(ctx, schoolId);
  const all = (await components(db, schoolId).get()).docs;
  const same = all.find((d) => normalise(d.data().name) === normalise(name));
  const isNew = data.componentId === undefined || data.componentId === null;
  const bp = data.percentBp === undefined || data.percentBp === null ? null : data.percentBp;
  if (bp !== null && (!Number.isSafeInteger(bp) || bp < 1 || bp > math.MAX_BP)) return { error: 'INVALID_ARGUMENT', reason: 'percentBp: between 0.01% and 100% (in hundredths of a percent)' };

  if (isNew) {
    if (!math.KINDS.includes(data.kind)) return { error: 'INVALID_ARGUMENT', reason: `kind: one of ${math.KINDS.join(', ')}` };
    if (!math.CALCS.includes(data.calc)) return { error: 'INVALID_ARGUMENT', reason: `calc: one of ${math.CALCS.join(', ')}` };
    let basisComponentId = null;
    if (data.calc === 'PERCENT') {
      if (!validId(data.basisComponentId)) return { error: 'INVALID_ARGUMENT', reason: 'basisComponentId: choose what the percentage is of' };
      const basis = all.find((d) => d.id === data.basisComponentId);
      const b = basis && basis.data();
      if (!b || b.active === false || b.kind !== 'EARNING' || b.calc !== 'FIXED') return { error: 'INVALID_ARGUMENT', reason: 'basisComponentId: must be an active, fixed earning' };
      basisComponentId = data.basisComponentId;
      if (bp === null) return { error: 'INVALID_ARGUMENT', reason: 'percentBp: required for a percentage component' };
    }
    if (same) return { error: 'ALREADY_EXISTS', reason: 'a component with that name already exists' };
    if (all.length >= MAX_COMPONENTS) return { error: 'FAILED_PRECONDITION', reason: `at most ${MAX_COMPONENTS} components` };
    const ref = components(db, schoolId).doc();
    await ref.set({ schoolId, name, kind: data.kind, calc: data.calc, basisComponentId, percentBp: data.calc === 'PERCENT' ? bp : null, active: data.active !== false, system: false, createdAt: now, createdBy: uid });
    return { result: { id: ref.id } };
  }

  if (!validId(data.componentId)) return { error: 'INVALID_ARGUMENT', reason: 'componentId' };
  const ref = components(db, schoolId).doc(data.componentId);
  const cur = (await ref.get()).data();
  if (!cur) return { error: 'NOT_FOUND', reason: 'that component does not exist' };
  if (cur.system && (normalise(name) !== normalise(cur.name) || data.active === false)) return { error: 'FAILED_PRECONDITION', reason: 'a built-in component cannot be renamed or switched off' };
  if (same && same.id !== data.componentId) return { error: 'ALREADY_EXISTS', reason: 'a component with that name already exists' };
  if (bp !== null && cur.calc !== 'PERCENT') return { error: 'INVALID_ARGUMENT', reason: 'percentBp: only a percentage component has one' };
  await ref.update({ name: cur.system ? cur.name : name, active: data.active === undefined ? cur.active !== false : data.active, percentBp: cur.calc === 'PERCENT' && bp !== null ? bp : cur.percentBp === undefined ? null : cur.percentBp, updatedAt: now, updatedBy: uid });
  return { result: { id: data.componentId } };
}

// ---- salary structures -------------------------------------------------------------------------

const REASON_MIN = 10;
const REASON_MAX = 300;
const TERMINAL = ['RESIGNED', 'TERMINATED', 'RETIRED'];
const MAX_VERSIONS = 200;

const lineView = (l) => ({
  componentId: l.componentId,
  name: l.nameSnapshot || '',
  kind: l.kind,
  calc: l.calc,
  amountMinor: l.amountMinor,
  percentBp: Number.isInteger(l.percentBp) ? l.percentBp : null,
  basisId: l.basisId || null,
});
const structureView = (id, d) => ({
  id,
  staffId: d.staffId,
  seq: d.seq,
  effectiveFrom: d.effectiveFrom,
  currency: d.currency || '',
  lines: (d.lines || []).map(lineView),
  grossMinor: d.grossMinor,
  deductionsMinor: d.deductionsMinor,
  netMinor: d.netMinor,
  latest: d.latest === true,
  reason: d.reason || null,
  createdAtMs: toMs(d.createdAt),
  createdBy: d.createdBy || null,
});
const firstOfMonth = (v) => validDate(v) && v.endsWith('-01');
const staffName = (s) => [s.firstName, s.middleName, s.lastName].filter(Boolean).join(' ');

/** All versions of one staff member's structure, newest first. */
async function versionsOf(db, schoolId, branchId, staffId) {
  const snap = await structures(db, schoolId, branchId).where('staffId', '==', staffId).limit(MAX_VERSIONS).get();
  return snap.docs.map((d) => ({ id: d.id, data: d.data() })).sort((a, b) => b.data.seq - a.data.seq);
}

/** The version in force on [date]: the latest effective date not after it (a later revision of the same date wins). */
function inForce(versions, date) {
  return versions.filter((v) => v.data.effectiveFrom <= date).sort((a, b) => (a.data.effectiveFrom === b.data.effectiveFrom ? b.data.seq - a.data.seq : a.data.effectiveFrom < b.data.effectiveFrom ? 1 : -1))[0] || null;
}

async function schoolFacts(ctx, schoolId) {
  const s = (await ctx.db.collection('schools').doc(schoolId).get()).data() || {};
  const timeZone = s.timezone || 'UTC';
  return { currency: s.currency || 'INR', today: civilToday(wall(ctx), timeZone) };
}

/** One staff member's structure: the version in force today and the whole history. School admin and finance only. */
async function getSalaryStructure(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !validId(data.staffId)) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, 'view');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const staff = (await staffRef(db, schoolId, branchId, data.staffId).get()).data();
  if (!staff) return { error: 'NOT_FOUND', reason: 'that staff member does not exist' };
  const facts = await schoolFacts(ctx, schoolId);
  const versions = await versionsOf(db, schoolId, branchId, data.staffId);
  const current = inForce(versions, facts.today);
  return {
    result: {
      staff: { id: data.staffId, name: staffName(staff), employeeCode: staff.employeeCode || '', status: staff.status || '' },
      current: current ? structureView(current.id, current.data) : null,
      history: versions.map((v) => structureView(v.id, v.data)),
      currency: facts.currency,
      canEdit: CAPS.editStructure.includes(caller.role),
    },
  };
}

/**
 * School admin only: a NEW version of a staff member's structure, effective from the 1st of a month. It never
 * edits an old version. The first version needs no reason; every later one needs a reason (10-300 characters)
 * so a pay change is always explained. Every component must exist and be active, and the lines are checked and
 * worked out by payroll_math.js (percentages, rounding, no negative net).
 */
async function saveSalaryStructure(ctx, uid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !validId(data.staffId)) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, 'editStructure');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const staff = (await staffRef(db, schoolId, branchId, data.staffId).get()).data();
  if (!staff) return { error: 'NOT_FOUND', reason: 'that staff member does not exist' };
  if (TERMINAL.includes(staff.status)) return { error: 'FAILED_PRECONDITION', reason: 'this staff member has left; their pay cannot be changed' };
  const facts = await schoolFacts(ctx, schoolId);
  if (!firstOfMonth(data.effectiveFrom)) return { error: 'INVALID_ARGUMENT', reason: 'effectiveFrom: the 1st of a month (yyyy-mm-01)' };
  const earliest = `${String(Number(facts.today.slice(0, 4)) - 2).padStart(4, '0')}-01-01`;
  if (data.effectiveFrom < earliest) return { error: 'INVALID_ARGUMENT', reason: 'effectiveFrom: cannot be more than 2 years back' };
  const reason = typeof data.reason === 'string' ? data.reason.trim() : '';
  if (reason.length > REASON_MAX) return { error: 'INVALID_ARGUMENT', reason: `reason: up to ${REASON_MAX} characters` };

  // Lines: the CLIENT sends only { componentId, amountMinor | percentBp }; what each component is comes from the school's list.
  if (!Array.isArray(data.lines) || data.lines.length > math.MAX_LINES) return { error: 'INVALID_ARGUMENT', reason: `lines: 1-${math.MAX_LINES} lines` };
  const comps = new Map((await components(db, schoolId).get()).docs.map((d) => [d.id, d.data()]));
  const lines = [];
  for (const [i, l] of data.lines.entries()) {
    const c = l && typeof l === 'object' && validId(l.componentId) ? comps.get(l.componentId) : null;
    if (!c || c.active === false) return { error: 'INVALID_ARGUMENT', reason: `lines[${i}].componentId: that component is not available` };
    lines.push({
      componentId: l.componentId,
      kind: c.kind,
      calc: c.calc,
      amountMinor: c.calc === 'FIXED' ? l.amountMinor : undefined,
      percentBp: c.calc === 'PERCENT' ? (l.percentBp === undefined || l.percentBp === null ? c.percentBp : l.percentBp) : undefined,
      basisId: c.calc === 'PERCENT' ? c.basisComponentId : undefined,
    });
  }
  const ev = math.evaluate(lines);
  if (ev.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(ev.errors) };
  const snapshot = ev.lines.map((l) => ({ ...l, nameSnapshot: comps.get(l.componentId).name }));

  const versions = await versionsOf(db, schoolId, branchId, data.staffId);
  const latest = versions[0] || null;
  if (latest && data.effectiveFrom < latest.data.effectiveFrom) return { error: 'FAILED_PRECONDITION', reason: `effectiveFrom: cannot be before the current latest version (${latest.data.effectiveFrom}); history is not rewritten` };
  if (latest && reason.length < REASON_MIN) return { error: 'INVALID_ARGUMENT', reason: `reason: ${REASON_MIN}-${REASON_MAX} characters, explain the change` };
  if (data.baseSeq !== undefined && data.baseSeq !== (latest ? latest.data.seq : 0)) return { error: 'ABORTED', reason: 'changed by someone else; reload' };

  const seq = (latest ? latest.data.seq : 0) + 1;
  const ref = structures(db, schoolId, branchId).doc(structureId(data.staffId, seq));
  const prevRef = latest ? structures(db, schoolId, branchId).doc(latest.id) : null;
  const out = await db.runTransaction(async (tx) => {
    if ((await tx.get(ref)).exists) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    if (prevRef) tx.update(prevRef, { latest: false });
    tx.set(ref, {
      schoolId, branchId, staffId: data.staffId, seq, effectiveFrom: data.effectiveFrom, currency: facts.currency,
      lines: snapshot, grossMinor: ev.grossMinor, deductionsMinor: ev.deductionsMinor, netMinor: ev.netMinor,
      latest: true, reason: reason || null, createdAt: now, createdBy: uid, updatedAt: now, updatedBy: uid,
    });
    return { result: { id: ref.id, seq } };
  });
  if (out.result) await lockCurrency(db, schoolId, () => wall(ctx));
  return out;
}

/**
 * The branch's staff with their latest structure's totals (so who has no structure yet is visible). School
 * admin and finance only; individual lines are not included, only gross, deductions and net.
 */
async function listSalaryStructures(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId)) return { error: 'PERMISSION_DENIED' };
  if (!(await authorize(db, uid, token, schoolId, branchId, 'view'))) return { error: 'PERMISSION_DENIED' };
  const staff = await db.collection('schools').doc(schoolId).collection('branches').doc(branchId).collection('staff').limit(1000).get();
  const latest = await structures(db, schoolId, branchId).where('latest', '==', true).limit(1000).get();
  const byStaff = new Map(latest.docs.map((d) => [d.data().staffId, d.data()]));
  const rows = staff.docs
    .filter((s) => !TERMINAL.includes(s.data().status))
    .map((s) => {
      const st = byStaff.get(s.id);
      const d = s.data();
      return {
        staffId: s.id, name: staffName(d), employeeCode: d.employeeCode || '', status: d.status || '',
        hasStructure: !!st, effectiveFrom: st ? st.effectiveFrom : null,
        grossMinor: st ? st.grossMinor : null, deductionsMinor: st ? st.deductionsMinor : null, netMinor: st ? st.netMinor : null,
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
  const facts = await schoolFacts(ctx, schoolId);
  return { result: { staff: rows, currency: facts.currency } };
}

module.exports = {
  FEATURE, CAPS, DEFAULT_COMPONENTS, authorize, componentId, ensureDefaultComponents,
  listPayComponents, savePayComponent, getSalaryStructure, saveSalaryStructure, listSalaryStructures,
  inForce, structureView, componentView,
};

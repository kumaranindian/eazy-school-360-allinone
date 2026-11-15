'use strict';

// Expense management (docs/expense-management/IMPLEMENTATION_PLAN.md), phase E1: the foundation.
//
//   schools/{s}/expenseSettings/config        { approvalRequired, allowSelfApproval, approverRoles, receiptRequiredOverMinor, version }
//   schools/{s}/expenseCategories/{id}        { name, active, system, key }
//
// Like admissions, every write is a callable (Admin SDK) and clients have NO rules for these
// collections (default deny), so approval, numbering and the money rules cannot be bypassed from a
// client. Who may do what is ONE table (CAPS) used by every callable here and by the later phases.

const { loginAllowed, schoolGate } = require('./access');
const { validId } = require('./ids');

const FEATURE = 'expenses';
const SCHOOL_ADMIN = 'SCHOOL_ADMIN';
const BRANCH_ADMIN = 'BRANCH_ADMIN';
const FINANCE = 'FINANCE';

// capability -> roles that hold it. A school admin acts in any branch; the others only in their own
// branch (home branch or users.branchRoles). `approve` for a branch admin additionally needs the
// school setting `approverRoles` to include BRANCH_ADMIN.
const CAPS = Object.freeze({
  view: [SCHOOL_ADMIN, BRANCH_ADMIN, FINANCE],
  create: [SCHOOL_ADMIN, BRANCH_ADMIN, FINANCE],
  approve: [SCHOOL_ADMIN, BRANCH_ADMIN],
  pay: [SCHOOL_ADMIN, FINANCE],
  report: [SCHOOL_ADMIN, BRANCH_ADMIN, FINANCE],
  manage: [SCHOOL_ADMIN],
});

const DEFAULT_SETTINGS = Object.freeze({
  approvalRequired: true,
  allowSelfApproval: false,
  approverRoles: [SCHOOL_ADMIN],
  receiptRequiredOverMinor: null,
});
const APPROVER_ROLES = [SCHOOL_ADMIN, BRANCH_ADMIN];

// Seeded once per school (deterministic ids, so a repeat is harmless). `system` categories are used by
// other modules (payroll posts to SALARIES) and can be neither renamed nor switched off.
const DEFAULT_CATEGORIES = Object.freeze([
  { key: 'SALARIES', name: 'Salaries', system: true },
  { key: 'MAINTENANCE', name: 'Maintenance and repairs' },
  { key: 'UTILITIES', name: 'Utilities (electricity, water, internet)' },
  { key: 'SUPPLIES', name: 'Supplies and stationery' },
  { key: 'TRANSPORT', name: 'Transport and fuel' },
  { key: 'EVENTS', name: 'Events and activities' },
  { key: 'TECHNOLOGY', name: 'Technology and software' },
  { key: 'SECURITY', name: 'Security and housekeeping' },
  { key: 'OTHER', name: 'Other' },
]);

const isStr = (v) => typeof v === 'string';
const trim = (v) => (isStr(v) ? v.trim() : '');
const normalise = (s) => trim(s).toLowerCase().replace(/\s+/g, ' ');

const settingsRef = (db, schoolId) => db.collection('schools').doc(schoolId).collection('expenseSettings').doc('config');
const categories = (db, schoolId) => db.collection('schools').doc(schoolId).collection('expenseCategories');
const categoryId = (key) => `cat_${key.toLowerCase()}`;

/** The role the caller holds in [branchId] (home role, or a per-branch role), or null when none. */
function roleIn(profile, branchId) {
  if (profile.role === SCHOOL_ADMIN) return SCHOOL_ADMIN;
  if (!branchId) return null;
  if (profile.branchId === branchId) return profile.role;
  const r = (profile.branchRoles || {})[branchId];
  return typeof r === 'string' ? r : null;
}

/**
 * The caller for capability [cap] in [branchId] (null for school-level calls), or null when not allowed.
 * Checks: signed-in profile of THIS school, login allowed (second factor etc.), the role holds the
 * capability, the branch scope, and that the school is usable and has the module switched on.
 * Returns { uid, role, profile, settings? } so callers never re-derive the role.
 */
async function authorize(db, uid, token, schoolId, branchId, cap) {
  if (!validId(schoolId)) return null;
  if (branchId !== null && !validId(branchId)) return null;
  const roles = Object.prototype.hasOwnProperty.call(CAPS, cap) ? CAPS[cap] : null;
  if (!roles) return null;
  const profile = (await db.collection('users').doc(uid).get()).data();
  if (!profile || profile.schoolId !== schoolId || !loginAllowed(profile, token)) return null;
  // School-level calls (settings, categories) have no branch: any role in the capability's list that the user holds at home.
  const role = branchId === null ? profile.role : roleIn(profile, branchId);
  if (!role || !roles.includes(role)) return null;
  if (!(await schoolGate(db, schoolId, FEATURE)).allowed) return null;
  return { uid, role, profile };
}

// ---- settings (pure validation) ----------------------------------------------------------------

/** Validates a settings payload; returns { errors } or { value }. Unknown keys are ignored, not stored. */
function validateSettings(input) {
  const errors = {};
  const i = input && typeof input === 'object' ? input : {};
  const d = DEFAULT_SETTINGS;
  const flag = (k) => {
    if (i[k] === undefined) return d[k];
    if (typeof i[k] !== 'boolean') errors[k] = 'must be true or false';
    return i[k] === true;
  };
  const approvalRequired = flag('approvalRequired');
  const allowSelfApproval = flag('allowSelfApproval');
  let approverRoles = d.approverRoles;
  if (i.approverRoles !== undefined) {
    if (!Array.isArray(i.approverRoles) || !i.approverRoles.length || i.approverRoles.some((r) => !APPROVER_ROLES.includes(r))) {
      errors.approverRoles = `one or more of ${APPROVER_ROLES.join(', ')}`;
    } else {
      approverRoles = [...new Set(i.approverRoles)].sort();
    }
  }
  let receiptRequiredOverMinor = d.receiptRequiredOverMinor;
  if (i.receiptRequiredOverMinor !== undefined && i.receiptRequiredOverMinor !== null) {
    if (!Number.isSafeInteger(i.receiptRequiredOverMinor) || i.receiptRequiredOverMinor < 0) errors.receiptRequiredOverMinor = 'a whole amount in minor units, 0 or more';
    else receiptRequiredOverMinor = i.receiptRequiredOverMinor;
  }
  if (Object.keys(errors).length) return { errors };
  return { value: { approvalRequired, allowSelfApproval, approverRoles, receiptRequiredOverMinor } };
}

const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');
const settingsView = (s) => ({
  approvalRequired: s.approvalRequired,
  allowSelfApproval: s.allowSelfApproval,
  approverRoles: s.approverRoles,
  receiptRequiredOverMinor: s.receiptRequiredOverMinor === undefined ? null : s.receiptRequiredOverMinor,
  version: Number.isInteger(s.version) ? s.version : 0,
});

/** Any role that can see expenses: the school's settings (defaults when never saved) and what the caller may manage. */
async function getExpenseSettings(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const caller = await authorize(db, uid, token, schoolId, null, 'view');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const stored = (await settingsRef(db, schoolId).get()).data();
  return { settings: settingsView({ ...DEFAULT_SETTINGS, ...(stored || {}) }), canManage: CAPS.manage.includes(caller.role) };
}

/** School admin only. Optimistic version check so two admins do not overwrite each other. */
async function saveExpenseSettings(ctx, uid, token, data) {
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
    if (data.baseVersion !== undefined && data.baseVersion !== current) return { error: 'ABORTED', reason: 'settings changed by someone else; reload' };
    tx.set(ref, { schoolId, version: current + 1, ...parsed.value, updatedAt: now, updatedBy: uid });
    return { result: { version: current + 1 } };
  });
}

// ---- categories --------------------------------------------------------------------------------

const catView = (id, c) => ({ id, name: c.name, active: c.active !== false, system: c.system === true, key: c.key || null });

/** Writes the default categories when the school has none (deterministic ids; never overwrites an edit). */
async function ensureDefaultCategories(ctx, schoolId) {
  const { db, now } = ctx;
  const existing = await categories(db, schoolId).limit(1).get();
  if (existing.docs.length) return false;
  for (const c of DEFAULT_CATEGORIES) {
    const ref = categories(db, schoolId).doc(categoryId(c.key));
    try {
      await ref.create({ schoolId, key: c.key, name: c.name, active: true, system: c.system === true, createdAt: now });
    } catch (e) {
      if (!(e && (e.code === 6 || e.code === 'already-exists' || /already exists/i.test(String(e.message))))) throw e;
    }
  }
  return true;
}

/** Any role that can see expenses: the categories (defaults seeded on first use), active ones unless asked otherwise. */
async function listExpenseCategories(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const caller = await authorize(db, uid, token, schoolId, null, 'view');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  await ensureDefaultCategories(ctx, schoolId);
  const snap = await categories(db, schoolId).get();
  const all = snap.docs.map((d) => catView(d.id, d.data()));
  const includeInactive = data.includeInactive === true && CAPS.manage.includes(caller.role);
  const rows = (includeInactive ? all : all.filter((c) => c.active)).sort((a, b) => (a.system === b.system ? a.name.localeCompare(b.name) : a.system ? -1 : 1));
  return { categories: rows };
}

/**
 * School admin only: add a category, or rename / switch one on or off. Categories are never deleted
 * (expenses refer to them); a system category can be neither renamed nor switched off.
 */
async function saveExpenseCategory(ctx, uid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const caller = await authorize(db, uid, token, schoolId, null, 'manage');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const name = trim(data.name);
  if (name.length < 2 || name.length > 60) return { error: 'INVALID_ARGUMENT', reason: 'name: 2-60 characters' };
  if (data.active !== undefined && typeof data.active !== 'boolean') return { error: 'INVALID_ARGUMENT', reason: 'active: must be true or false' };
  await ensureDefaultCategories(ctx, schoolId);
  const all = (await categories(db, schoolId).get()).docs;
  const same = all.find((d) => normalise(d.data().name) === normalise(name));
  if (data.categoryId === undefined || data.categoryId === null) {
    if (same) return { error: 'ALREADY_EXISTS', reason: 'a category with that name already exists' };
    if (all.length >= 100) return { error: 'FAILED_PRECONDITION', reason: 'at most 100 categories' };
    const ref = categories(db, schoolId).doc();
    await ref.set({ schoolId, name, active: data.active !== false, system: false, createdAt: now, createdBy: uid });
    return { result: { id: ref.id } };
  }
  if (!validId(data.categoryId)) return { error: 'INVALID_ARGUMENT', reason: 'categoryId' };
  const ref = categories(db, schoolId).doc(data.categoryId);
  const cur = (await ref.get()).data();
  if (!cur) return { error: 'NOT_FOUND', reason: 'that category does not exist' };
  if (cur.system && (normalise(name) !== normalise(cur.name) || data.active === false)) return { error: 'FAILED_PRECONDITION', reason: 'a built-in category cannot be renamed or switched off' };
  if (same && same.id !== data.categoryId) return { error: 'ALREADY_EXISTS', reason: 'a category with that name already exists' };
  await ref.update({ name: cur.system ? cur.name : name, active: data.active === undefined ? cur.active !== false : data.active, updatedAt: now, updatedBy: uid });
  return { result: { id: data.categoryId } };
}

module.exports = {
  FEATURE, CAPS, DEFAULT_SETTINGS, DEFAULT_CATEGORIES, APPROVER_ROLES,
  authorize, roleIn, validateSettings, ensureDefaultCategories, categoryId,
  getExpenseSettings, saveExpenseSettings, listExpenseCategories, saveExpenseCategory,
};

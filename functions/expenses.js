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
const crypto = require('node:crypto');
const { validId } = require('./ids');
const { lockCurrency } = require('./currency_lock');

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


// ---- expenses (phase E2: create, edit a draft, list, read) ---------------------------------------
//
//   schools/{s}/branches/{b}/expenses/{id}
//   schools/{s}/branches/{b}/expenseSequences/{EXP-yyyy}     { next }
//
// A new expense is a DRAFT. Submitting, approving and paying arrive in phase E4; nothing here can move
// an expense past DRAFT, so no amount can be approved or paid by this phase.

const STATUSES = Object.freeze(['DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED', 'PAID', 'CANCELLED']);
const PAYMENT_MODES = Object.freeze(['CASH', 'BANK_TRANSFER', 'UPI', 'CHEQUE', 'CARD', 'OTHER']);
const MAX_MINOR = 1e12;
const PAGE_DEFAULT = 25;
const PAGE_MAX = 50;
const SCAN_CAP = 400;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const REQUEST_KEY = /^[A-Za-z0-9_-]{8,64}$/;

function validDate(v) {
  if (!isStr(v) || !DATE.test(v)) return false;
  const d = new Date(`${v}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === v;
}

function civilToday(now, timeZone) {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
  } catch (_) {
    return now.toISOString().slice(0, 10);
  }
}
const yearsBefore = (today, n) => `${String(Number(today.slice(0, 4)) - n).padStart(4, '0')}${today.slice(4)}`;

const branchRef = (db, schoolId, branchId) => db.collection('schools').doc(schoolId).collection('branches').doc(branchId);
const expenseCol = (db, schoolId, branchId) => branchRef(db, schoolId, branchId).collection('expenses');
const sequenceDoc = (db, schoolId, branchId, key) => branchRef(db, schoolId, branchId).collection('expenseSequences').doc(key);
const wall = (ctx) => (ctx.wall ? ctx.wall() : ctx.nowDate ? ctx.nowDate() : new Date());
const toMs = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : t instanceof Date ? t.getTime() : typeof t === 'number' ? t : null);

/**
 * Validates the editable part of an expense; the school's "today" (its own zone) bounds the date.
 * Returns { errors } or { value }. The category is checked against the school's list by the caller.
 */
function validateExpense(input, { today }) {
  const errors = {};
  const i = input && typeof input === 'object' ? input : {};
  if (!validId(i.categoryId)) errors.categoryId = 'choose a category';
  if (!Number.isSafeInteger(i.amountMinor) || i.amountMinor < 1 || i.amountMinor > MAX_MINOR) errors.amountMinor = 'a whole amount in minor units, above 0';
  if (!validDate(i.expenseDate)) errors.expenseDate = 'a date (yyyy-mm-dd)';
  else if (i.expenseDate > today) errors.expenseDate = 'cannot be in the future';
  else if (i.expenseDate < yearsBefore(today, 5)) errors.expenseDate = 'cannot be more than 5 years ago';
  const payee = i.payee === undefined || i.payee === null ? '' : trim(i.payee);
  if (payee.length > 120) errors.payee = 'up to 120 characters';
  const description = i.description === undefined || i.description === null ? '' : trim(i.description);
  if (description.length > 500) errors.description = 'up to 500 characters';
  let paymentMode = null;
  if (i.paymentMode !== undefined && i.paymentMode !== null && i.paymentMode !== '') {
    if (!PAYMENT_MODES.includes(i.paymentMode)) errors.paymentMode = `one of ${PAYMENT_MODES.join(', ')}`;
    else paymentMode = i.paymentMode;
  }
  const paymentReference = i.paymentReference === undefined || i.paymentReference === null ? '' : trim(i.paymentReference);
  if (paymentReference.length > 60) errors.paymentReference = 'up to 60 characters';
  if (Object.keys(errors).length) return { errors };
  return { value: { categoryId: i.categoryId, amountMinor: i.amountMinor, expenseDate: i.expenseDate, payee, description, paymentMode, paymentReference } };
}

const expenseView = (id, d) => ({
  id,
  number: d.number || '',
  branchId: d.branchId || '',
  categoryId: d.categoryId || '',
  categoryName: d.categoryName || '',
  amountMinor: d.amountMinor,
  currency: d.currency || '',
  expenseDate: d.expenseDate || '',
  payee: d.payee || '',
  description: d.description || '',
  paymentMode: d.paymentMode || null,
  paymentReference: d.paymentReference || '',
  status: d.status,
  source: d.source || 'MANUAL',
  payrollPeriod: d.payrollPeriod || null,
  version: Number.isInteger(d.version) ? d.version : 1,
  receiptCount: Number.isInteger(d.receiptCount) ? d.receiptCount : 0,
  submittedBy: d.submittedBy || null,
  submittedAtMs: toMs(d.submittedAt),
  decidedBy: d.decidedBy || null,
  decidedByName: d.decidedByName || null,
  decidedAtMs: toMs(d.decidedAt),
  decisionReason: d.decisionReason || null,
  paidDate: d.paidDate || null,
  paidBy: d.paidBy || null,
  paidAtMs: toMs(d.paidAt),
  cancelReason: d.cancelReason || null,
  createdBy: d.createdBy || null,
  createdByName: d.createdByName || null,
  createdAtMs: toMs(d.createdAt),
  updatedAtMs: toMs(d.updatedAt),
});

async function schoolFacts(db, schoolId, now) {
  const s = (await db.collection('schools').doc(schoolId).get()).data() || {};
  const timeZone = s.timezone || 'UTC';
  return { currency: s.currency || 'INR', timeZone, today: civilToday(now, timeZone) };
}

/** Records a new DRAFT expense (numbered, in the school's currency). A repeat of the same clientRequestId returns the first. */
async function createExpense(ctx, uid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  const caller = await authorize(db, uid, token, schoolId, validId(branchId) ? branchId : '', 'create');
  if (!caller || !validId(branchId)) return { error: 'PERMISSION_DENIED' };
  if (data.clientRequestId !== undefined && !REQUEST_KEY.test(data.clientRequestId || '')) return { error: 'INVALID_ARGUMENT', reason: 'clientRequestId' };
  const facts = await schoolFacts(db, schoolId, wall(ctx));
  const parsed = validateExpense(data.expense, { today: facts.today });
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
  if (!(await branchRef(db, schoolId, branchId).get()).exists) return { error: 'NOT_FOUND', reason: 'that branch does not exist' };
  const col = expenseCol(db, schoolId, branchId);
  const id = data.clientRequestId ? `x_${crypto.createHash('sha256').update(`${uid}|${schoolId}|${branchId}|${data.clientRequestId}`).digest('hex').slice(0, 28)}` : null;
  const ref = id ? col.doc(id) : col.doc();
  const year = facts.today.slice(0, 4);
  const out = await db.runTransaction(async (tx) => {
    if (id && (await tx.get(ref)).exists) return { result: { id: ref.id, duplicate: true } };
    const cat = (await tx.get(categories(db, schoolId).doc(parsed.value.categoryId))).data();
    if (!cat || cat.active === false) return { error: 'INVALID_ARGUMENT', reason: 'categoryId: that category is not available' };
    const seqRef = sequenceDoc(db, schoolId, branchId, `EXP-${year}`);
    const cur = (await tx.get(seqRef)).data();
    const n = (cur && Number.isInteger(cur.next) ? cur.next : 0) + 1;
    tx.set(seqRef, { schoolId, branchId, year, next: n, updatedAt: now });
    tx.set(ref, {
      schoolId, branchId, number: `EXP-${year}-${String(n).padStart(5, '0')}`,
      ...parsed.value, categoryName: cat.name, currency: facts.currency,
      status: 'DRAFT', version: 1, source: 'MANUAL',
      createdAt: now, createdBy: uid, createdByName: trim(caller.profile.displayName || caller.profile.name) || null,
      updatedAt: now, updatedBy: uid,
    });
    return { result: { id: ref.id } };
  });
  if (out.result && !out.result.duplicate) await lockCurrency(db, schoolId, () => wall(ctx));
  return out;
}

/** Edits a DRAFT: its creator, or a school/branch admin. Optimistic version; nothing past DRAFT is editable. */
async function updateExpense(ctx, uid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !validId(data.expenseId)) return { error: 'PERMISSION_DENIED' };
  const caller = await authorize(db, uid, token, schoolId, branchId, 'create');
  if (!caller) return { error: 'PERMISSION_DENIED' };
  const facts = await schoolFacts(db, schoolId, wall(ctx));
  const parsed = validateExpense(data.expense, { today: facts.today });
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
  const ref = expenseCol(db, schoolId, branchId).doc(data.expenseId);
  return db.runTransaction(async (tx) => {
    const cur = (await tx.get(ref)).data();
    if (!cur) return { error: 'NOT_FOUND', reason: 'that expense does not exist' };
    if (cur.status !== 'DRAFT') return { error: 'FAILED_PRECONDITION', reason: 'only a draft can be edited' };
    if (cur.createdBy !== uid && ![SCHOOL_ADMIN, BRANCH_ADMIN].includes(caller.role)) return { error: 'PERMISSION_DENIED' };
    if (data.baseVersion !== undefined && data.baseVersion !== cur.version) return { error: 'ABORTED', reason: 'changed by someone else; reload' };
    let categoryName = cur.categoryName;
    if (parsed.value.categoryId !== cur.categoryId) {
      const cat = (await tx.get(categories(db, schoolId).doc(parsed.value.categoryId))).data();
      if (!cat || cat.active === false) return { error: 'INVALID_ARGUMENT', reason: 'categoryId: that category is not available' };
      categoryName = cat.name;
    }
    tx.update(ref, { ...parsed.value, categoryName, version: cur.version + 1, updatedAt: now, updatedBy: uid });
    return { result: { id: ref.id, version: cur.version + 1 } };
  });
}

/** One expense of the branch. */
async function getExpense(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId) || !validId(data.expenseId)) return { error: 'PERMISSION_DENIED' };
  if (!(await authorize(db, uid, token, schoolId, branchId, 'view'))) return { error: 'PERMISSION_DENIED' };
  const snap = await expenseCol(db, schoolId, branchId).doc(data.expenseId).get();
  if (!snap.exists) return { error: 'NOT_FOUND', reason: 'that expense does not exist' };
  return { result: { expense: expenseView(snap.id, snap.data()) } };
}

/**
 * A page of the branch's expenses, newest date first. Filters: status, category, date range. One equality
 * filter uses an index (status wins); the other is applied to fetched rows, bounded by SCAN_CAP.
 */
async function listExpenses(ctx, uid, token, data) {
  const { db } = ctx;
  const schoolId = data && data.schoolId;
  const branchId = data && data.branchId;
  if (!validId(branchId)) return { error: 'PERMISSION_DENIED' };
  if (!(await authorize(db, uid, token, schoolId, branchId, 'view'))) return { error: 'PERMISSION_DENIED' };
  const d = data || {};
  if (d.status !== undefined && d.status !== null && !STATUSES.includes(d.status)) return { error: 'INVALID_ARGUMENT', reason: 'status' };
  if (d.categoryId !== undefined && d.categoryId !== null && !validId(d.categoryId)) return { error: 'INVALID_ARGUMENT', reason: 'categoryId' };
  for (const k of ['fromDate', 'toDate']) if (d[k] !== undefined && d[k] !== null && !validDate(d[k])) return { error: 'INVALID_ARGUMENT', reason: k };
  const limit = Math.min(Math.max(Number.isInteger(d.limit) ? d.limit : PAGE_DEFAULT, 1), PAGE_MAX);
  const col = expenseCol(db, schoolId, branchId);
  let last = null;
  if (d.cursor && typeof d.cursor === 'object') {
    if (!validId(d.cursor.id)) return { error: 'INVALID_ARGUMENT', reason: 'cursor' };
    const c = await col.doc(d.cursor.id).get();
    if (!c.exists) return { error: 'INVALID_ARGUMENT', reason: 'cursor' };
    last = c;
  }
  const out = [];
  let scanned = 0;
  let more = false;
  for (;;) {
    let q = col;
    if (d.status) q = q.where('status', '==', d.status);
    else if (d.categoryId) q = q.where('categoryId', '==', d.categoryId);
    if (d.fromDate) q = q.where('expenseDate', '>=', d.fromDate);
    if (d.toDate) q = q.where('expenseDate', '<=', d.toDate);
    q = q.orderBy('expenseDate', 'desc');
    if (last) q = q.startAfter(last);
    const snap = await q.limit(100).get();
    for (const s of snap.docs) {
      scanned++;
      last = s;
      const e = s.data();
      if (d.status && d.categoryId && e.categoryId !== d.categoryId) continue;
      if (out.length === limit) {
        more = true;
        break;
      }
      out.push(expenseView(s.id, e));
    }
    if (more || snap.docs.length < 100 || scanned >= SCAN_CAP) {
      if (!more && snap.docs.length >= 100 && scanned >= SCAN_CAP) more = true;
      break;
    }
  }
  const nextCursor = more && out.length ? { id: out[out.length - 1].id } : null;
  return { result: { expenses: out, nextCursor } };
}

module.exports = {
  FEATURE, CAPS, DEFAULT_SETTINGS, DEFAULT_CATEGORIES, APPROVER_ROLES,
  authorize, roleIn, validateSettings, ensureDefaultCategories, categoryId,
  getExpenseSettings, saveExpenseSettings, listExpenseCategories, saveExpenseCategory,
  STATUSES, PAYMENT_MODES, validateExpense, civilToday,
  createExpense, updateExpense, getExpense, listExpenses, expenseCollection: expenseCol,
  settingsRef, settingsView, expenseView, validDate, wall,
};

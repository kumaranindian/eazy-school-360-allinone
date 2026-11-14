'use strict';

// The central school access engine (docs/platform-governance/, Phase 2).
//
// ONE place decides whether a user may use a school's feature right now. Every
// protected callable reaches it through a gateway (`access.assertAdmin`, the
// admission/provisioning/branch gates, the scheduled jobs). It never trusts
// anything the client says: it reads the school and the caller's profile from
// Firestore on every call (authoritative state). The Firestore rules cannot
// afford this logic, so they read the mirrored `users.schoolAccess` flag that the
// lifecycle service keeps in step (consistency: seconds for admin changes).
//
// Order of evaluation: membership (never leak another school's state) ->
// lifecycle -> subscription -> feature -> user account -> role -> branch.

const { methodAllowed } = require('./access');
const subscriptions = require('./subscriptions');

const CODES = Object.freeze({
  ACCESS_GRANTED: 'ACCESS_GRANTED',
  SCHOOL_INACTIVE: 'SCHOOL_INACTIVE',
  SCHOOL_SUSPENDED: 'SCHOOL_SUSPENDED',
  SCHOOL_EXPIRED: 'SCHOOL_EXPIRED',
  SCHOOL_CLOSED: 'SCHOOL_CLOSED',
  SUBSCRIPTION_NOT_STARTED: 'SUBSCRIPTION_NOT_STARTED',
  SUBSCRIPTION_EXPIRED: 'SUBSCRIPTION_EXPIRED',
  FEATURE_DISABLED: 'FEATURE_DISABLED',
  USER_DISABLED: 'USER_DISABLED',
  INSUFFICIENT_PERMISSION: 'INSUFFICIENT_PERMISSION',
  BRANCH_ACCESS_DENIED: 'BRANCH_ACCESS_DENIED',
});

const LIFECYCLE_CODE = {
  INACTIVE: CODES.SCHOOL_INACTIVE,
  SUSPENDED: CODES.SCHOOL_SUSPENDED,
  EXPIRED: CODES.SCHOOL_EXPIRED,
  CLOSED: CODES.SCHOOL_CLOSED,
};
const LIFECYCLE = ['INACTIVE', 'ACTIVE', 'SUSPENDED', 'EXPIRED', 'CLOSED'];
// A school from before lifecycle states has no status: it is ACTIVE.
const lifecycleOf = (school) => (LIFECYCLE.includes(school && school.status) ? school.status : 'ACTIVE');

const grant = () => ({ allowed: true, code: CODES.ACCESS_GRANTED });
const deny = (code) => ({ allowed: false, code });

/**
 * Subscription decision. `subscription` is the already-evaluated state
 * (`{status}`: NOT_STARTED, TRIAL, ACTIVE, GRACE_PERIOD, EXPIRED, CANCELLED).
 * No subscription = a school from before subscriptions: allowed (policy D2).
 * (Phase 5/6 compute `status` from the dates; this function only applies it.)
 */
function subscriptionCode(subscription) {
  if (!subscription || !subscription.status) return null;
  switch (subscription.status) {
    case 'NOT_STARTED':
      return CODES.SUBSCRIPTION_NOT_STARTED;
    case 'EXPIRED':
    case 'CANCELLED':
      return CODES.SUBSCRIPTION_EXPIRED;
    default:
      return null; // TRIAL, ACTIVE, GRACE_PERIOD
  }
}

/** Per-branch role of a user (home role in the home branch, else `branchRoles`). */
const roleIn = (user, branchId) => (user.branchId === branchId ? user.role : (user.branchRoles || {})[branchId] || null);

/**
 * Pure decision. Inputs are plain data so every rule is unit-testable.
 *   school      the school document ({status, features}) or null
 *   subscription the evaluated subscription ({status}) or null/undefined
 *   user        the caller's /users profile or null
 *   token       the caller's auth token (sign-in method, second factor)
 *   schoolId    the school the operation targets
 *   feature     optional feature key (checked against school.features)
 *   branchId    optional branch the operation targets
 *   roles       optional list of roles allowed to perform it (in that branch)
 */
function decide({ school, subscription, user, token, schoolId, feature, branchId, roles }) {
  // Membership first: never reveal another school's lifecycle to an outsider.
  if (!user || !school || user.schoolId !== schoolId) return deny(CODES.INSUFFICIENT_PERMISSION);

  const state = lifecycleOf(school);
  if (state !== 'ACTIVE') return deny(LIFECYCLE_CODE[state]);

  const sub = subscriptionCode(subscription);
  if (sub) return deny(sub);

  if (feature && featureOff(school, feature)) return deny(CODES.FEATURE_DISABLED);

  // The mirrored pause flag is part of the user's own state (it should already be covered
  // by the lifecycle above; it also catches a mirror that is ahead of a lagging read).
  if (user.status !== 'ACTIVE' || !methodAllowed(user, token)) return deny(CODES.USER_DISABLED);

  if (Array.isArray(roles) && roles.length) {
    const effective = branchId ? roleIn(user, branchId) : user.role;
    // A school admin acts in every branch of their school.
    const ok = user.role === 'SCHOOL_ADMIN' ? roles.includes('SCHOOL_ADMIN') || roles.includes('BRANCH_ADMIN') || roles.includes(effective) : roles.includes(effective);
    if (!ok) return deny(branchId && effective === null && user.role !== 'SCHOOL_ADMIN' ? CODES.BRANCH_ACCESS_DENIED : CODES.INSUFFICIENT_PERMISSION);
  } else if (branchId && user.role !== 'SCHOOL_ADMIN' && roleIn(user, branchId) === null) {
    return deny(CODES.BRANCH_ACCESS_DENIED);
  }
  return grant();
}

/** The subscription's status computed NOW from its dates (never the stored status), or null (legacy school). */
async function liveSubscription(db, schoolId, school, now) {
  const doc = (await db.collection('schoolSubscriptions').doc(schoolId).get()).data();
  if (!doc) return null;
  const status = subscriptions.statusAt(doc, now || new Date(), subscriptions.zoneOf(school));
  return status ? { status } : null;
}

/**
 * Reads authoritative state and decides. `opts.enforceSubscription` turns the
 * subscription check on (Phase 6 flips it; until then no subscription document is
 * consulted, so no extra read happens).
 */
async function evaluateSchoolAccess(db, { uid, token, schoolId, feature, branchId, roles }, opts = {}) {
  if (!uid || typeof schoolId !== 'string' || !schoolId) return deny(CODES.INSUFFICIENT_PERMISSION);
  const user = (await db.collection('users').doc(uid).get()).data();
  const school = (await db.collection('schools').doc(schoolId).get()).data();
  let subscription;
  if (opts.enforceSubscription) subscription = await liveSubscription(db, schoolId, school, opts.now);
  return decide({ school, subscription, user, token, schoolId, feature, branchId, roles });
}

/**
 * The school-level half only (lifecycle, subscription, feature) for gateways that
 * have already authenticated the caller with their own role rules.
 */
async function schoolUsable(db, schoolId, feature, opts = {}) {
  if (typeof schoolId !== 'string' || !schoolId) return deny(CODES.INSUFFICIENT_PERMISSION);
  const school = (await db.collection('schools').doc(schoolId).get()).data();
  if (!school) return deny(CODES.INSUFFICIENT_PERMISSION);
  const state = lifecycleOf(school);
  if (state !== 'ACTIVE') return deny(LIFECYCLE_CODE[state]);
  if (opts.enforceSubscription) {
    const sub = subscriptionCode(await liveSubscription(db, schoolId, school, opts.now));
    if (sub) return deny(sub);
  }
  if (feature && featureOff(school, feature)) return deny(CODES.FEATURE_DISABLED);
  return grant();
}

/** True only when the school explicitly switched [feature] off. */
const featureOff = (school, feature) => !!school && !require('./features').usable(school.features, feature);

/**
 * Subscription enforcement is ON unless GOV_SUBSCRIPTION_ENFORCEMENT=false (a kill switch). Schools without a
 * subscription document are legacy and always allowed, so turning it on blocks nobody by itself.
 */
const subscriptionsEnforced = (env = process.env) => String(env.GOV_SUBSCRIPTION_ENFORCEMENT || '').toLowerCase() !== 'false';

module.exports = { CODES, decide, evaluateSchoolAccess, schoolUsable, subscriptionCode, lifecycleOf, featureOff, subscriptionsEnforced };

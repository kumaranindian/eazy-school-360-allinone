'use strict';

// The public enquiry page (docs/admission-management/, phase 9): `admission/{slug}`.
//
// Anyone can open the page and send an enquiry, so nothing here trusts the caller:
//   - the school and branch come ONLY from the slug the school registered
//     (admissionPortalSlugs/{slug}); the client never names a school or branch;
//   - the same field validation as a staff enquiry, with the source fixed to
//     "Website", no remarks, no assignee, one guardian, and only the years and
//     classes the school offers;
//   - explicit consent, recorded with the version of the text that was accepted;
//   - a honeypot field, optional Cloudflare Turnstile verification, and App Check
//     (ENFORCE_APP_CHECK, reCAPTCHA v3 on web) at the callable;
//   - rate limits per client address, per mobile number and per school, kept as
//     hashed counters (no raw addresses are stored);
//   - the reply never says whether a duplicate exists or what is inside the school;
//   - `pub_{requestId}` is the enquiry id (create-only), so a retry returns the same reference.
// Staff see the enquiry like any other (source Website, channel PUBLIC_PORTAL) and
// the usual duplicate flag. Nothing is converted or approved here.

const crypto = require('crypto');
const a = require('./admission');

const REQUEST_ID = /^[A-Za-z0-9_-]{8,64}$/;
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const LIMITS = {
  ip: { max: 5, windowMs: HOUR },
  phone: { max: 3, windowMs: DAY },
  school: { max: 300, windowMs: HOUR },
};

const sha = (salt, value) => crypto.createHash('sha256').update(`${salt}|${value}`).digest('hex').slice(0, 32);

/**
 * Counts one use of [key] in a fixed window; returns false when the limit is
 * already reached. A transaction, so concurrent requests cannot slip past.
 */
async function consume(db, schoolId, key, { max, windowMs }, nowMs, now) {
  const ref = db.collection('schools').doc(schoolId).collection('publicLimits').doc(key);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = snap.exists ? snap.data() : null;
    if (!d || nowMs - d.windowStart >= windowMs) {
      tx.set(ref, { schoolId, count: 1, windowStart: nowMs, expireAt: new Date(nowMs + windowMs * 2), updatedAt: now });
      return true;
    }
    if (d.count >= max) return false;
    tx.update(ref, { count: d.count + 1, updatedAt: now });
    return true;
  }, { maxAttempts: 10 });
}

/** Cloudflare Turnstile server check. Returns true when the token is valid. */
async function verifyTurnstile(token, ip, { secret, fetchFn }) {
  if (!token || typeof token !== 'string' || token.length > 2048) return false;
  try {
    const body = new URLSearchParams({ secret, response: token });
    if (ip) body.set('remoteip', ip);
    const res = await fetchFn('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body });
    const json = await res.json();
    return json && json.success === true;
  } catch (_) {
    return false;
  }
}

async function portalFor(db, slug) {
  const s = a.isStr(slug) ? slug.trim().toLowerCase() : '';
  if (!/^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/.test(s)) return null;
  const snap = await db.collection('admissionPortalSlugs').doc(s).get();
  if (!snap.exists || snap.data().enabled !== true) return null;
  const { schoolId, branchId } = snap.data();
  const settings = await a.loadSettings(db, schoolId);
  const p = settings.publicPortal || {};
  if (!settings.enabled || p.enabled !== true || p.slug !== s || p.branchId !== branchId) return null;
  const school = await db.collection('schools').doc(schoolId).get();
  // A suspended school, or one with the module switched off by the platform, has no public page.
  const sd = school.data() || {};
  if ((sd.status && sd.status !== 'ACTIVE') || (sd.features && (sd.features.admission === false || sd.features.publicAdmission === false))) return null;
  const branch = await a.branchRef(db, schoolId, branchId).get();
  if (!school.exists || !branch.exists) return null;
  return { schoolId, branchId, settings, portal: p, school: school.data(), branch: branch.data() };
}

const toDate = (v) => (v && typeof v.toDate === 'function' ? v.toDate() : v ? new Date(v) : null);

/** What the public form needs: the school's name, the offered years and classes, the consent text. */
async function getPublicPortal(ctx, _uid, _token, data) {
  const { db } = ctx;
  const p = await portalFor(db, data && data.slug);
  if (!p) return { error: 'NOT_FOUND' };
  if (ctx.clientIp) {
    const salt = process.env.PUBLIC_PORTAL_SALT || p.schoolId;
    const ok = await consume(db, p.schoolId, `view_${sha(salt, ctx.clientIp)}`, { max: 60, windowMs: HOUR }, a.wall(ctx).getTime(), ctx.now);
    if (!ok) return { error: 'RESOURCE_EXHAUSTED' };
  }
  return { result: await describe(ctx, p) };
}

/** The offered years and classes plus the texts of the public form. */
async function describe(ctx, p) {
  const { db } = ctx;
  const b = a.branchRef(db, p.schoolId, p.branchId);
  const years = await b.collection('academicYears').get();
  const offeredYears = new Set(p.settings.academicYearIds || []);
  const offeredClasses = new Set(p.settings.classIds || []);
  const out = [];
  for (const y of years.docs) {
    const yd = y.data();
    if (yd.status && yd.status !== 'ACTIVE' && yd.status !== 'UPCOMING') continue;
    if (offeredYears.size && !offeredYears.has(y.id)) continue;
    const end = toDate(yd.endDate);
    if (end && end.getTime() < a.wall(ctx).getTime()) continue;
    const classes = await b.collection('academicYears').doc(y.id).collection('classes').get();
    const list = classes.docs
      .filter((c) => (!offeredClasses.size || offeredClasses.has(c.id)) && (!c.data().status || c.data().status === 'ACTIVE'))
      .map((c) => ({ id: c.id, name: c.data().name }));
    if (list.length) out.push({ id: y.id, name: yd.name, classes: list });
  }
  return {
    schoolName: p.school.name || '',
    branchName: p.branch.name || '',
    introText: p.portal.introText || '',
    consentText: p.portal.consentText,
    consentVersion: p.portal.consentVersion,
    academicYears: out,
    captchaRequired: Boolean(ctx.turnstileSecret),
  };
}

/** The public form's submission. The reply is only the reference number. */
async function submitPublicEnquiry(ctx, _uid, _token, data) {
  const { db, now } = ctx;
  const d = data || {};
  // A bot that fills the hidden field is told "thanks" and nothing is stored.
  if (a.isStr(d.website) && d.website.trim() !== '') return { result: { reference: null } };
  const p = await portalFor(db, d.slug);
  if (!p) return { error: 'NOT_FOUND' };
  if (!a.isStr(d.requestId) || !REQUEST_ID.test(d.requestId)) return { error: 'INVALID_ARGUMENT', reason: 'requestId is required' };
  const consent = d.consent || {};
  if (consent.accepted !== true) return { error: 'INVALID_ARGUMENT', reason: 'consent is required to send an enquiry' };
  if (consent.version !== p.portal.consentVersion) return { error: 'FAILED_PRECONDITION', reason: 'the consent text has changed; reload the page' };

  if (ctx.turnstileSecret) {
    const ok = await (ctx.verifyCaptcha || verifyTurnstile)(d.captchaToken, ctx.clientIp, { secret: ctx.turnstileSecret, fetchFn: ctx.fetchFn || fetch });
    if (!ok) return { error: 'PERMISSION_DENIED', reason: 'the verification check failed' };
  }

  const zone = (p.school && p.school.timezone) || 'UTC';
  const today = a.civilToday(a.wall(ctx), zone);
  const e = d.enquiry || {};
  const guardian = (Array.isArray(e.guardians) ? e.guardians : [])[0] || {};
  const years = (await describe(ctx, p)).academicYears;
  const year = years.find((y) => y.id === e.academicYearId);
  if (!year || !year.classes.some((c) => c.id === e.interestedClassId)) return { error: 'INVALID_ARGUMENT', reason: 'choose an academic year and class that the school offers' };
  const settings = { ...p.settings, sources: ['Website'], academicYearIds: [], classIds: [] };
  const parsed = a.validateEnquiry({
    student: e.student,
    academicYearId: e.academicYearId,
    interestedClassId: e.interestedClassId,
    source: 'Website',
    guardians: [{ name: guardian.name, phone: guardian.phone, email: guardian.email, relationship: guardian.relationship }],
    address: e.address,
    remarks: null,
  }, settings, { today });
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(parsed.errors) };
  const value = parsed.value;

  // Rate limits (after validation so a typo does not burn the allowance).
  const nowMs = a.wall(ctx).getTime();
  const salt = process.env.PUBLIC_PORTAL_SALT || p.schoolId;
  const checks = [['school', 'all'], ['phone', `phone_${sha(salt, value.primaryPhone)}`]];
  if (ctx.clientIp) checks.unshift(['ip', `ip_${sha(salt, ctx.clientIp)}`]);
  const ref = a.branchRef(db, p.schoolId, p.branchId).collection('admissionEnquiries').doc(`pub_${d.requestId}`);
  const existing = await ref.get();
  if (existing.exists) return { result: { reference: existing.data().enquiryNumber } };
  for (const [kind, key] of checks) {
    if (!(await consume(db, p.schoolId, key === 'all' ? 'school' : key, LIMITS[kind], nowMs, now))) return { error: 'RESOURCE_EXHAUSTED' };
  }

  const near = await a.branchRef(db, p.schoolId, p.branchId).collection('admissionEnquiries')
    .where('primaryPhone', '==', value.primaryPhone).where('academicYearId', '==', value.academicYearId).limit(25).get();
  const duplicateOf = a.duplicateMatches(value, near.docs.map((x) => ({ id: x.id, data: x.data() })));
  const histRef = a.branchRef(db, p.schoolId, p.branchId).collection('admissionStatusHistory').doc(`${ref.id}__1`);
  return db.runTransaction(async (tx) => {
    const again = await tx.get(ref);
    if (again.exists) return { result: { reference: again.data().enquiryNumber } };
    const enquiryNumber = await a.nextNumber(tx, ctx, p.schoolId, p.branchId, p.settings.enquiryPrefix, today.slice(0, 4));
    tx.set(ref, {
      schoolId: p.schoolId,
      branchId: p.branchId,
      enquiryNumber,
      ...value,
      enquiryDate: today,
      assignedTo: null,
      status: 'NEW',
      heldFrom: null,
      statusReason: null,
      duplicateOf,
      activityCount: 0,
      openActivityCount: 0,
      channel: 'PUBLIC_PORTAL',
      consent: { accepted: true, version: p.portal.consentVersion, acceptedAt: now, ipHash: ctx.clientIp ? sha(salt, ctx.clientIp) : null },
      revision: 1,
      createdAt: now,
      createdBy: 'public-portal',
      updatedAt: now,
      updatedBy: 'public-portal',
    });
    tx.set(histRef, { schoolId: p.schoolId, branchId: p.branchId, enquiryId: ref.id, revision: 1, from: null, to: 'NEW', reason: 'Public enquiry form', actorId: 'public-portal', at: now });
    return { result: { reference: enquiryNumber } };
  }, { maxAttempts: 10 });
}

module.exports = { consume, verifyTurnstile, portalFor, getPublicPortal, submitPublicEnquiry, LIMITS, sha };

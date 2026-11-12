'use strict';

// Convert an approved application into a student (docs/admission-management/, phase 8).
//
// ONE transaction writes everything, so a conversion is all-or-nothing and a
// retry can never leave a half-converted family:
//   students/{s_<enquiryId>}                 the student (same fields the admission form writes)
//   students/{id}/academicRecords/{id}       the placement (year, class, section, roll)
//   admissionNumbers/{key}                   the reservation of the ADM-#### number (same key the rules use)
//   parents/{...} + students/{id}/parentLinks/{parentId} + parentAccess/{parentId}
//   admissionConversions/{enquiryId}         the conversion record (idempotency key, fee carry-over, who/when)
//   the enquiry moves APPROVED -> ADMISSION_CONFIRMED with a history entry
//
// Ids are derived from the enquiry (`s_<enquiryId>`, `p_<mobile>`), so repeating the
// call returns the first result instead of creating a second student.

const a = require('./admission');
const apps = require('./admission_applications');
const fees = require('./admission_fees');

const RELATIONSHIPS = { FATHER: 'FATHER', MOTHER: 'MOTHER', GUARDIAN: 'GUARDIAN', FATHER_: 'FATHER' };
const CONVERSION_STATUS = 'COMPLETED';
const SCAN_LIMIT = 200;

const branchRef = a.branchRef;
const studentIdOf = (enquiryId) => `s_${enquiryId}`;
const keyOf = (n) => String(n).trim().toLowerCase().replace(/\//g, '~');
const formatAdm = (n) => `ADM-${String(n).padStart(4, '0')}`;

/** `ADM-<digits>` sequence of a number, or null. */
function sequenceOf(n) {
  const m = /^ADM-(\d+)$/.exec(String(n || '').trim());
  return m ? Number(m[1]) : null;
}

function relationshipOf(text) {
  const t = a.trim(text).toUpperCase();
  if (t.includes('FATHER') || t === 'DAD') return 'FATHER';
  if (t.includes('MOTHER') || t === 'MOM') return 'MOTHER';
  if (t.includes('GUARDIAN')) return 'GUARDIAN';
  return t ? 'OTHER' : 'GUARDIAN';
}

function splitName(name) {
  const parts = a.trim(name).split(/\s+/).filter(Boolean);
  if (parts.length <= 1) return { firstName: parts[0] || '', middleName: null, lastName: '' };
  return { firstName: parts[0], middleName: parts.length > 2 ? parts.slice(1, -1).join(' ') : null, lastName: parts[parts.length - 1] };
}

/** Validates what the admin chooses at conversion. Returns { errors } or { value }. */
function validateConversion(input, { today }) {
  const errors = {};
  const i = input || {};
  for (const k of ['academicYearId', 'classId', 'sectionId']) {
    if (!a.isStr(i[k]) || !a.ID.test(i[k])) errors[k] = 'is required';
  }
  const roll = a.trim(i.rollNumber);
  if (roll.length > 20) errors.rollNumber = 'up to 20 characters';
  const admissionDate = i.admissionDate ? i.admissionDate : today;
  if (typeof admissionDate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(admissionDate) || Number.isNaN(Date.parse(admissionDate))) errors.admissionDate = 'must be a date (yyyy-mm-dd)';
  const dob = i.dateOfBirth ? i.dateOfBirth : null;
  if (dob !== null && (typeof dob !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(dob) || Number.isNaN(Date.parse(dob)) || dob > today)) errors.dateOfBirth = 'must be a past date (yyyy-mm-dd)';
  if (i.gender !== undefined && i.gender !== null && !['MALE', 'FEMALE', 'OTHER'].includes(i.gender)) errors.gender = 'is not a valid gender';
  if (Object.keys(errors).length) return { errors };
  return { value: { academicYearId: i.academicYearId, classId: i.classId, sectionId: i.sectionId, rollNumber: roll || null, admissionDate, dateOfBirth: dob, gender: i.gender || null, acceptOutstandingFees: i.acceptOutstandingFees === true } };
}

/** Highest ADM-<digits> sequence among the branch's students (a ranged query; the fake db ignores ranges). */
async function highestSequence(db, schoolId, branchId) {
  const snap = await branchRef(db, schoolId, branchId)
    .collection('students')
    .where('admissionNumber', '>=', 'ADM-')
    .where('admissionNumber', '<', 'ADM.')
    .orderBy('admissionNumber', 'desc')
    .limit(50)
    .get();
  return snap.docs.reduce((best, d) => Math.max(best, sequenceOf(d.data().admissionNumber) || 0), 0);
}

async function convertToStudent(ctx, uid, token, data) {
  const { db, now } = ctx;
  const { schoolId, branchId, enquiryId } = data || {};
  const caller = await a.authorize(db, uid, token, schoolId, branchId || null);
  if (!caller || !branchId) return { error: 'PERMISSION_DENIED' };
  const settings = await a.loadSettings(db, schoolId);
  if (!settings.enabled) return { error: 'FAILED_PRECONDITION', reason: 'admissions are not enabled for this school' };
  if (!apps.mayDecide(caller, settings)) return { error: 'PERMISSION_DENIED' };
  if (!a.isStr(enquiryId) || !a.ID.test(enquiryId)) return { error: 'INVALID_ARGUMENT', reason: 'enquiryId is required' };
  const today = a.civilToday(a.wall(ctx), await a.schoolZone(db, schoolId));
  const parsed = validateConversion(data.conversion, { today });
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: a.reasonOf(parsed.errors) };
  const v = parsed.value;
  const b = branchRef(db, schoolId, branchId);
  const studentId = studentIdOf(enquiryId);
  const convRef = b.collection('admissionConversions').doc(enquiryId);

  // Reads that need no transaction: the starting admission number, and which
  // existing parent (any id) already has each guardian's mobile.
  const startSeq = (ctx.highestSequence ? await ctx.highestSequence(db, schoolId, branchId) : await highestSequence(db, schoolId, branchId)) + 1;
  const guardianSnap = (await b.collection('admissionApplications').doc(enquiryId).get());
  const enquirySnap = await b.collection('admissionEnquiries').doc(enquiryId).get();
  if (!enquirySnap.exists) return { error: 'NOT_FOUND' };
  const guardians = ((guardianSnap.exists ? guardianSnap.data().guardians : null) || enquirySnap.data().guardians || []).slice(0, 4);
  const existingParent = [];
  for (const g of guardians) {
    const found = await b.collection('parents').where('phone', '==', g.phone).limit(1).get();
    existingParent.push(found.docs.length ? found.docs[0].id : null);
  }

  return db.runTransaction(async (tx) => {
    const done = await tx.get(convRef);
    const enquiry = await a.loadEnquiry(tx, ctx, schoolId, branchId, enquiryId);
    if (done.exists) return { result: { studentId: done.data().studentId, admissionNumber: done.data().admissionNumber, duplicate: true } };
    if (!enquiry) return { error: 'NOT_FOUND' };
    const e = enquiry.data;
    if (e.status !== 'APPROVED') return { error: 'FAILED_PRECONDITION', reason: `only an APPROVED enquiry can be converted (this one is ${e.status})` };
    const appSnap = await tx.get(b.collection('admissionApplications').doc(enquiryId));
    if (!appSnap.exists || appSnap.data().status !== 'APPROVED') return { error: 'FAILED_PRECONDITION', reason: 'the application is not approved' };
    const app = appSnap.data();

    // The chosen placement must exist: section inside class inside year.
    const section = await tx.get(b.collection('academicYears').doc(v.academicYearId).collection('classes').doc(v.classId).collection('sections').doc(v.sectionId));
    if (!section.exists) return { error: 'FAILED_PRECONDITION', reason: 'the section does not belong to the selected class and academic year' };

    const dateOfBirth = v.dateOfBirth || (app.student && app.student.dateOfBirth) || null;
    const gender = v.gender || (app.student && app.student.gender) || null;
    if (!dateOfBirth) return { error: 'FAILED_PRECONDITION', reason: 'the date of birth is required to create the student' };
    if (!gender) return { error: 'FAILED_PRECONDITION', reason: 'the gender is required to create the student' };

    // Fees: read the four fee records; unpaid balances need an explicit acceptance.
    const feeDocs = [];
    for (const category of fees.CATEGORIES) {
      const snap = await tx.get(b.collection('admissionFees').doc(fees.feeId(enquiryId, category)));
      if (snap.exists) feeDocs.push({ ref: snap.ref || b.collection('admissionFees').doc(fees.feeId(enquiryId, category)), data: snap.data() });
    }
    const live = feeDocs.filter((f) => f.data.status !== 'CANCELLED');
    const balance = live.reduce((t, f) => t + fees.balanceOf(f.data), 0);
    if (balance > 0 && !v.acceptOutstandingFees) return { error: 'FAILED_PRECONDITION', reason: 'admission fees are still due; collect them or confirm that conversion may go ahead with a balance' };

    // Parents: reuse by mobile, else create with an id derived from the mobile.
    const parentPlan = [];
    for (let idx = 0; idx < guardians.length; idx++) {
      const g = guardians[idx];
      const parentId = existingParent[idx] || `p_${g.phone}`;
      const ref = b.collection('parents').doc(parentId);
      const snap = await tx.get(ref);
      const access = await tx.get(b.collection('parentAccess').doc(parentId));
      parentPlan.push({ g, idx, ref, exists: snap.exists, parentId, access: access.exists ? access.data() : null });
    }

    // Admission number: the first free reservation from the starting sequence.
    let seq = startSeq;
    let admissionNumber = null;
    let resRef = null;
    for (let n = 0; n < SCAN_LIMIT; n++, seq++) {
      const candidate = formatAdm(seq);
      resRef = b.collection('admissionNumbers').doc(keyOf(candidate));
      if (!(await tx.get(resRef)).exists) { admissionNumber = candidate; break; }
    }
    if (!admissionNumber) return { error: 'ABORTED', reason: 'could not reserve an admission number; try again' };

    // ---- all reads are done; writes ----
    const names = splitName(e.studentName || [(app.student || {}).firstName, (app.student || {}).lastName].filter(Boolean).join(' '));
    const st = app.student || e.student || {};
    const firstName = st.firstName || names.firstName;
    const lastName = st.lastName || '';
    const displayName = [firstName, lastName].filter(Boolean).join(' ');
    const addr = app.address || e.address || {};
    const admissionDate = new Date(`${v.admissionDate}T00:00:00Z`);
    tx.set(b.collection('students').doc(studentId), {
      schoolId, branchId, admissionNumber, studentCode: `STU-${studentId.slice(0, 8).toUpperCase()}`,
      firstName, middleName: null, lastName, displayName, displayNameLower: displayName.toLowerCase(),
      dateOfBirth: new Date(`${dateOfBirth}T00:00:00Z`), gender, bloodGroup: null, photoUrl: null, email: null, phone: null,
      addressLine1: addr.line1 || null, addressLine2: null, city: addr.city || null, state: addr.state || null, country: addr.country || null, postalCode: null,
      admissionDate, status: 'ACTIVE',
      currentAcademicYearId: v.academicYearId, currentClassId: v.classId, currentSectionId: v.sectionId, currentRollNumber: v.rollNumber,
      admissionEnquiryId: enquiryId,
      createdAt: now, updatedAt: now, createdBy: uid, updatedBy: uid,
    });
    tx.set(b.collection('students').doc(studentId).collection('academicRecords').doc(`r_${enquiryId}`), {
      studentId, schoolId, branchId, academicYearId: v.academicYearId, classId: v.classId, sectionId: v.sectionId, rollNumber: v.rollNumber,
      startDate: admissionDate, endDate: null, status: 'ACTIVE', createdAt: now, updatedAt: now, createdBy: uid, updatedBy: uid,
    });
    tx.set(resRef, { schoolId, branchId, studentId, admissionNumber, createdAt: now, createdBy: uid });

    const sectionKey = `${v.classId}__${v.sectionId}`;
    const parentIds = [];
    for (const p of parentPlan) {
      const { g } = p;
      if (!p.exists) {
        const n = splitName(g.name);
        tx.set(p.ref, {
          schoolId, branchId, firstName: n.firstName, middleName: n.middleName, lastName: n.lastName,
          displayName: g.name, displayNameLower: g.name.toLowerCase(), phone: g.phone, alternatePhone: g.alternatePhone || null, email: g.email || null,
          occupation: null, photoUrl: null, addressLine1: addr.line1 || null, addressLine2: null, city: addr.city || null, state: addr.state || null, country: addr.country || null, postalCode: null,
          status: 'ACTIVE', linkedUserId: null, createdAt: now, updatedAt: now, createdBy: uid, updatedBy: uid,
        });
      }
      tx.set(b.collection('students').doc(studentId).collection('parentLinks').doc(p.parentId), {
        schoolId, branchId, studentId, parentId: p.parentId, relationshipType: relationshipOf(g.relationship),
        isPrimary: p.idx === 0, isEmergencyContact: p.idx === 0, canAccessPortal: true, status: 'ACTIVE',
        createdAt: now, updatedAt: now, createdBy: uid, updatedBy: uid,
      });
      const classKeys = [...new Set([...((p.access && p.access.classKeys) || []), v.classId])].sort();
      const sectionKeys = [...new Set([...((p.access && p.access.sectionKeys) || []), sectionKey])].sort();
      tx.set(b.collection('parentAccess').doc(p.parentId), { schoolId, branchId, parentId: p.parentId, classKeys, sectionKeys, updatedAt: now, updatedBy: uid });
      parentIds.push(p.parentId);
    }

    for (const f of feeDocs) tx.update(f.ref, { studentId, convertedAt: now });
    const feeSummary = fees.summarize(feeDocs.map((f) => f.data));
    tx.set(convRef, {
      schoolId, branchId, enquiryId, applicationId: enquiryId, studentId, admissionNumber, status: CONVERSION_STATUS,
      academicYearId: v.academicYearId, classId: v.classId, sectionId: v.sectionId, parentIds,
      fees: feeDocs.map((f) => ({ category: f.data.category, amountMinor: f.data.amountMinor, netPaidMinor: fees.netPaid(f.data), balanceMinor: fees.balanceOf(f.data), status: f.data.status, receiptNumber: f.data.lastReceiptNumber || null })),
      feeNetPaidMinor: feeSummary.netPaidMinor, feeBalanceMinor: feeSummary.balanceMinor, acceptedOutstandingFees: balance > 0,
      convertedBy: uid, convertedAt: now,
    });
    tx.update(enquiry.ref, { studentId, admissionNumber });
    a.applyStatus(tx, ctx, enquiry, { to: 'ADMISSION_CONFIRMED', reason: `Converted to student ${admissionNumber}`, uid });
    return { result: { studentId, admissionNumber, parentIds, duplicate: false } };
  }, { maxAttempts: 10 });
}

module.exports = { convertToStudent, validateConversion, sequenceOf, relationshipOf, splitName, studentIdOf, formatAdm };

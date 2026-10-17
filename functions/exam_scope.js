'use strict';

// examinations/{id}.sectionScope: the section id, or 'ALL' for a class-wide
// examination. A concrete string that families filter on: firestore.rules
// cannot prove "no section" from a null filter on the live service, but they
// can prove it from an equality on a string (as for announcements'
// `audienceKind`). The app writes it on create; this stamps any examination
// that does not carry the right value (written before the field existed, or by
// an older app build), so it never depends on someone remembering to.

const branchRef = (db, s, b) => db.collection('schools').doc(s).collection('branches').doc(b);

/** The value `sectionScope` must hold for an examination document. */
const scopeOf = (exam) => (typeof exam.sectionId === 'string' && exam.sectionId ? exam.sectionId : 'ALL');

/** Stamps one examination if its sectionScope is missing or wrong. Returns whether it wrote. */
async function stampExam(ref, data) {
  if (!data || data.sectionScope === scopeOf(data)) return false;
  await ref.update({ sectionScope: scopeOf(data) });
  return true;
}

/** Stamps every examination of the given classes in a branch. Returns how many were written. */
async function stampClasses(db, schoolId, branchId, classIds) {
  let n = 0;
  for (const classId of new Set(classIds)) {
    if (typeof classId !== 'string' || !classId) continue;
    const snap = await branchRef(db, schoolId, branchId).collection('examinations').where('classId', '==', classId).get();
    for (const d of snap.docs) if (await stampExam(d.ref, d.data())) n++;
  }
  return n;
}

module.exports = { scopeOf, stampExam, stampClasses };

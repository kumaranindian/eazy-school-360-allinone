'use strict';
// Pure planner for backfilling admission-number reservations (ACAD-2).
// Students admitted before reservations existed hold a number but no
// `admissionNumbers/{key}` document. The key must equal the one the app and
// firestore.rules compute (lib/features/students/domain/admission_key.dart).

const MAX_LENGTH = 60;

function admissionKey(number) {
  return String(number).trim().toLowerCase().replaceAll('/', '~');
}

function validNumber(number) {
  const n = String(number || '').trim();
  return n.length > 0 && n.length <= MAX_LENGTH && /^[A-Za-z0-9#]/.test(n) && !n.includes('\n');
}

/**
 * @param students  [{ id, admissionNumber }]
 * @param reservedKeys  Set of keys that already have a reservation
 * @returns { create: [{ key, studentId, number }], duplicates: [{ key, studentIds }], invalid: [{ studentId, number }] }
 */
function planBackfill(students, reservedKeys = new Set()) {
  const byKey = new Map();
  const invalid = [];
  for (const s of students) {
    if (!s.admissionNumber || !String(s.admissionNumber).trim()) continue; // nothing to reserve
    if (!validNumber(s.admissionNumber)) {
      invalid.push({ studentId: s.id, number: s.admissionNumber });
      continue;
    }
    const key = admissionKey(s.admissionNumber);
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push(s);
  }
  const create = [];
  const duplicates = [];
  for (const [key, list] of byKey) {
    if (list.length > 1) {
      duplicates.push({ key, studentIds: list.map((s) => s.id).sort() });
      continue; // a human decides which student keeps the number
    }
    if (reservedKeys.has(key)) continue;
    create.push({ key, studentId: list[0].id, number: String(list[0].admissionNumber).trim() });
  }
  return { create, duplicates, invalid };
}

module.exports = { admissionKey, validNumber, planBackfill };

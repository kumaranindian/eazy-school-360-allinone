// One commit of `generateChunkSize` (6) invoices — what generateInvoices writes
// per transaction — must be accepted by the real firestore.rules. Production
// enforces a 20-document-lookup budget per batched write that the emulator may
// not; the app keeps the chunk small enough to stay well under it.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp, writeBatch } from 'firebase/firestore';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

const S = 'fee-chunk';
const B = 'north';
const Y = 'y1';
const P = 'M-2026-06';
const path = (...p) => ['schools', S, 'branches', B, ...p];
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const invNo = (n) => `INV-2026-${String(n).padStart(6, '0')}`;

async function seed(students) {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    await setDoc(doc(db, 'schools', S), { name: 'S', status: 'ACTIVE', ...audit('seed') });
    await setDoc(doc(db, ...path()), { schoolId: S, name: B, status: 'ACTIVE', ...audit('seed') });
    await setDoc(doc(db, 'users', 'chunk-admin'), {
      schoolId: S, branchId: null, name: 'A', email: 'a@x.com', role: 'SCHOOL_ADMIN', status: 'ACTIVE', linkedParentId: null, ...audit('seed'),
    });
    for (let i = 1; i <= students; i++) {
      await setDoc(doc(db, ...path('students', `stu-${i}`)), { schoolId: S, branchId: B, status: 'ACTIVE', displayName: `S${i}`, ...audit('seed') });
    }
  });
}

function chunk(db, size, startSeq = 1, counterExists = false) {
  const b = writeBatch(db);
  const uid = 'chunk-admin';
  const last = startSeq + size - 1;
  const counter = doc(db, ...path('feeCounters', `invoice_${Y}`));
  if (counterExists) b.update(counter, { last, updatedAt: serverTimestamp(), updatedBy: uid });
  else b.set(counter, { schoolId: S, branchId: B, last, updatedAt: serverTimestamp(), updatedBy: uid });
  for (let i = 0; i < size; i++) {
    const seq = startSeq + i;
    const student = `stu-${seq}`;
    const id = `${student}__${Y}__${P}`;
    const chargeId = `${student}__${Y}__tuition__${P}`;
    b.set(doc(db, ...path('invoiceNumbers', invNo(seq))), { schoolId: S, branchId: B, academicYearId: Y, numberSeq: seq });
    b.set(doc(db, ...path('invoices', id)), {
      schoolId: S, branchId: B, invoiceNumber: invNo(seq), numberSeq: seq, studentId: student, studentName: 'S', admissionNumber: 'A',
      academicYearId: Y, academicYearName: '2026-27', classId: 'c5', className: 'C5', sectionId: 'sa', sectionName: 'A',
      periodKind: 'MONTHLY', periodKey: P, periodLabel: 'June 2026', issueDateKey: '2026-06-01', dueDateKey: '2026-06-16',
      lines: [{ assignmentId: `${student}__${Y}__tuition`, structureId: `${Y}__tuition`, name: 'Tuition', category: 'TUITION', description: null,
        amountMinor: 100000, discountMinor: 0, concessionNote: null, chargeId }],
      subtotalMinor: 100000, discountMinor: 0, payableMinor: 100000, waivedMinor: 0, paidMinor: 0, balanceMinor: 100000, status: 'ISSUED',
      currency: 'INR', schoolName: 'S', branchName: 'N', ...audit(uid),
    });
    b.set(doc(db, ...path('feeCharges', chargeId)), { schoolId: S, branchId: B, invoiceId: id, assignmentId: `${student}__${Y}__tuition` });
  }
  return b;
}

for (const size of [1, 3, 6]) {
  test(`one commit of ${size} invoice(s)`, async () => {
    await seed(size);
    const db = testEnv.authenticatedContext('chunk-admin').firestore();
    await assertSucceeds(chunk(db, size).commit());
  });
}

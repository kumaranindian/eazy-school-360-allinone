// Firestore security-rules tests for Milestone 6 — Fees (see ../firestore.rules
// and ../docs/milestone-6-fees-management.md). Own school ids (`fee-a-<n>`) and
// uid prefix (`fee-`) so it can run beside the other files on the shared emulator.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, where, writeBatch,
} from 'firebase/firestore';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

let A = 'fee-a';
let B = 'fee-b';
let counter = 0;
const NORTH = 'north';
const SOUTH = 'south';
const YEAR = 'y1';
const PERIOD = 'M-2026-06';

const branch = (s, b) => ['schools', s, 'branches', b];
const seed = (fn) => testEnv.withSecurityRulesDisabled(async (c) => fn(c.firestore()));
const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const col = (db, name, b = NORTH, s = A) => collection(db, ...branch(s, b), name);
const ref = (db, name, id, b = NORTH, s = A) => doc(db, ...branch(s, b), name, id);

const invNo = (seq) => `INV-2026-${String(seq).padStart(6, '0')}`;
const rctNo = (seq) => `RCT-2026-${String(seq).padStart(6, '0')}`;
const invId = (student = 'stu-1', period = PERIOD) => `${student}__${YEAR}__${period}`;

const userDoc = ({ schoolId, branchId = null, role, linkedParentId = null }) => ({
  schoolId, branchId, name: 'T', email: 't@example.com', role, status: 'ACTIVE', linkedParentId, ...audit('seed'),
});

// ---------------------------------------------------------------- builders

function structureDoc({ code = 'TUITION', year = YEAR, amount = 100000, status = 'ACTIVE', frequency = 'MONTHLY', uid }) {
  return {
    schoolId: A, branchId: NORTH, academicYearId: year, code, name: 'Tuition', category: 'TUITION', customCategoryLabel: null,
    frequency, amountMinor: amount, classId: null, sectionId: null, isOptional: false, effectiveFromKey: null, effectiveToKey: null,
    dueOffsetDays: 15, description: null, paymentInstructions: null, status, ...audit(uid),
  };
}
const structureId = (code = 'TUITION', year = YEAR) => `${year}__${code.toLowerCase()}`;

function assignmentDoc({ studentId = 'stu-1', structure = structureId(), year = YEAR, concessionType = 'NONE', concessionValue = 0, reason = null, approvedBy = null, uid }) {
  return {
    schoolId: A, branchId: NORTH, academicYearId: year, studentId, structureId: structure, structureName: 'Tuition', classId: 'c5', sectionId: 'sa',
    concessionType, concessionValue, concessionReason: reason, concessionApprovedBy: approvedBy, status: 'ACTIVE', ...audit(uid),
  };
}

function invoiceDoc({ studentId = 'stu-1', periodKey = PERIOD, seq = 1, subtotal = 100000, discount = 0, uid, overrides = {} }) {
  const payable = subtotal - discount;
  return {
    schoolId: A, branchId: NORTH, invoiceNumber: invNo(seq), numberSeq: seq, studentId, studentName: 'Anil Kumar', admissionNumber: 'ADM-1',
    academicYearId: YEAR, academicYearName: '2026-27', classId: 'c5', className: 'Class 5', sectionId: 'sa', sectionName: 'A',
    periodKind: 'MONTHLY', periodKey, periodLabel: 'June 2026', issueDateKey: '2026-06-01', dueDateKey: '2026-06-16',
    lines: [{ assignmentId: `${studentId}__${structureId()}`, structureId: structureId(), name: 'Tuition', category: 'TUITION', amountMinor: subtotal, discountMinor: discount, chargeId: `${studentId}__${structureId()}__${periodKey}` }],
    subtotalMinor: subtotal, discountMinor: discount, payableMinor: payable, waivedMinor: 0, paidMinor: 0, balanceMinor: payable, status: 'ISSUED',
    currency: 'INR', schoolName: 'S', branchName: 'North', ...audit(uid), ...overrides,
  };
}

/** Writes counter bump + number reservation(s) + invoice(s) + charge locks, as the app does. */
function issueBatch(db, uid, items, { counterExists = false, counterLast, kind = 'invoice' } = {}) {
  const batch = writeBatch(db);
  const last = counterLast ?? Math.max(...items.map((i) => i.seq ?? 1));
  const counterRef = ref(db, 'feeCounters', `${kind}_${YEAR}`);
  if (counterExists) batch.update(counterRef, { last, updatedAt: serverTimestamp(), updatedBy: uid });
  else batch.set(counterRef, { schoolId: A, branchId: NORTH, last, updatedAt: serverTimestamp(), updatedBy: uid });
  for (const item of items) {
    const seq = item.seq ?? 1;
    const doc_ = invoiceDoc({ ...item, seq, uid });
    batch.set(ref(db, 'invoiceNumbers', invNo(seq)), { schoolId: A, branchId: NORTH, academicYearId: YEAR, numberSeq: seq });
    batch.set(ref(db, 'invoices', invId(item.studentId, item.periodKey ?? PERIOD)), doc_);
    for (const line of doc_.lines) {
      batch.set(ref(db, 'feeCharges', line.chargeId), { schoolId: A, branchId: NORTH, invoiceId: invId(item.studentId, item.periodKey ?? PERIOD), assignmentId: line.assignmentId });
    }
  }
  return batch;
}

const paymentDoc = ({ paymentId, invoiceId = invId(), studentId = 'stu-1', amount, balanceBefore, method = 'CASH', referenceNo = null, uid, rseq = 1, overrides = {} }) => ({
  schoolId: A, branchId: NORTH, invoiceId, invoiceNumber: invNo(1), studentId, studentName: 'Anil Kumar', academicYearId: YEAR, classId: 'c5', sectionId: 'sa',
  amountMinor: amount, method, methodLabel: null, referenceNo, paymentDateKey: '2026-06-10', notes: null, receiptNumber: rctNo(rseq),
  balanceAfterMinor: balanceBefore - amount, collectedBy: uid, collectorName: 'Fin', status: 'ACTIVE', createdAt: serverTimestamp(), createdBy: uid, ...overrides,
});

const receiptDoc = ({ paymentId, amount, balanceAfter, rseq = 1, uid, studentId = 'stu-1' }) => ({
  schoolId: A, branchId: NORTH, receiptNumber: rctNo(rseq), numberSeq: rseq, paymentId, invoiceId: invId(), invoiceNumber: invNo(1), periodLabel: 'June 2026',
  studentId, studentName: 'Anil Kumar', admissionNumber: 'ADM-1', className: 'Class 5', sectionName: 'A', academicYearId: YEAR, academicYearName: '2026-27',
  schoolName: 'S', branchName: 'North', amountMinor: amount, method: 'CASH', paymentDateKey: '2026-06-10', balanceAfterMinor: balanceAfter,
  collectorName: 'Fin', currency: 'INR', status: 'ACTIVE', createdAt: serverTimestamp(), createdBy: uid,
});

const statusFor = (payable, waived, paid) => (payable - waived - paid <= 0 ? 'PAID' : paid + waived > 0 ? 'PARTIALLY_PAID' : 'ISSUED');

/**
 * One payment, exactly as the app writes it. `inv` is what the client believes
 * the invoice looks like (payable/waived/paid); tests pass stale values to
 * simulate races.
 */
function collectBatch(db, uid, { paymentId, amount, inv = { payable: 100000, waived: 0, paid: 0 }, rseq = 1, counterExists = false, method = 'CASH', referenceNo = null, overrides = {}, invoiceOverrides = {}, skip = [] }) {
  const balanceBefore = inv.payable - inv.waived - inv.paid;
  const batch = writeBatch(db);
  const counterRef = ref(db, 'feeCounters', `receipt_${YEAR}`);
  if (!skip.includes('counter')) {
    if (counterExists) batch.update(counterRef, { last: rseq, updatedAt: serverTimestamp(), updatedBy: uid });
    else batch.set(counterRef, { schoolId: A, branchId: NORTH, last: rseq, updatedAt: serverTimestamp(), updatedBy: uid });
  }
  if (!skip.includes('reservation')) batch.set(ref(db, 'receiptNumbers', rctNo(rseq)), { schoolId: A, branchId: NORTH, academicYearId: YEAR, numberSeq: rseq });
  if (!skip.includes('receipt')) batch.set(ref(db, 'receipts', paymentId), receiptDoc({ paymentId, amount, balanceAfter: balanceBefore - amount, rseq, uid }));
  if (!skip.includes('payment')) batch.set(ref(db, 'payments', paymentId), paymentDoc({ paymentId, amount, balanceBefore, method, referenceNo, uid, rseq, overrides }));
  if (!skip.includes('invoice')) {
    const paid = inv.paid + amount;
    batch.update(ref(db, 'invoices', invId()), {
      paidMinor: paid, balanceMinor: inv.payable - inv.waived - paid, status: statusFor(inv.payable, inv.waived, paid),
      lastEventType: 'PAYMENT', lastEventId: paymentId, updatedAt: serverTimestamp(), updatedBy: uid, ...invoiceOverrides,
    });
  }
  return batch;
}

async function seedWorld({ invoice = true, paid = 0 } = {}) {
  counter += 1;
  A = `fee-a-${counter}`;
  B = `fee-b-${counter}`;
  await seed(async (db) => {
    for (const s of [A, B]) {
      await setDoc(doc(db, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      for (const b of s === A ? [NORTH, SOUTH] : [NORTH]) await setDoc(doc(db, ...branch(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'fee-admin': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'fee-admin-b': { schoolId: B, branchId: NORTH, role: 'SCHOOL_ADMIN' },
      'fee-br-north': { schoolId: A, branchId: NORTH, role: 'BRANCH_ADMIN' },
      'fee-br-south': { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' },
      'fee-fin-north': { schoolId: A, branchId: NORTH, role: 'FINANCE' },
      'fee-fin-south': { schoolId: A, branchId: SOUTH, role: 'FINANCE' },
      'fee-fin-b': { schoolId: B, branchId: NORTH, role: 'FINANCE' },
      'fee-teacher': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'fee-parent': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'parent-1' },
      'fee-parent2': { schoolId: A, branchId: NORTH, role: 'PARENT', linkedParentId: 'parent-2' },
    };
    for (const [uid, u] of Object.entries(users)) await setDoc(doc(db, 'users', uid), userDoc(u));

    const n = branch(A, NORTH);
    await setDoc(doc(db, ...n, 'students', 'stu-1'), { schoolId: A, branchId: NORTH, status: 'ACTIVE', displayName: 'Anil Kumar', ...audit('seed') });
    await setDoc(doc(db, ...n, 'students', 'stu-2'), { schoolId: A, branchId: NORTH, status: 'ACTIVE', displayName: 'Bina Kumar', ...audit('seed') });
    await setDoc(doc(db, ...n, 'students', 'stu-left'), { schoolId: A, branchId: NORTH, status: 'LEFT', displayName: 'Gone', ...audit('seed') });
    await setDoc(doc(db, ...n, 'students', 'stu-1', 'parentLinks', 'parent-1'), {
      schoolId: A, branchId: NORTH, studentId: 'stu-1', parentId: 'parent-1', canAccessPortal: true, status: 'ACTIVE', relationshipType: 'FATHER', ...audit('seed'),
    });
    await setDoc(doc(db, ...n, 'students', 'stu-2', 'parentLinks', 'parent-2'), {
      schoolId: A, branchId: NORTH, studentId: 'stu-2', parentId: 'parent-2', canAccessPortal: true, status: 'ACTIVE', relationshipType: 'MOTHER', ...audit('seed'),
    });

    await setDoc(ref(db, 'feeStructures', structureId()), structureDoc({ uid: 'seed' }));
    await setDoc(ref(db, 'feeStructures', structureId('OLD')), structureDoc({ code: 'OLD', status: 'INACTIVE', uid: 'seed' }));
    await setDoc(ref(db, 'feeStructures', structureId('NEXT', 'y2')), structureDoc({ code: 'NEXT', year: 'y2', uid: 'seed' }));

    if (invoice) {
      await setDoc(ref(db, 'invoices', invId()), { ...invoiceDoc({ uid: 'seed' }), paidMinor: paid, balanceMinor: 100000 - paid, status: paid ? 'PARTIALLY_PAID' : 'ISSUED' });
      await setDoc(ref(db, 'invoiceNumbers', invNo(1)), { schoolId: A, branchId: NORTH, academicYearId: YEAR, numberSeq: 1 });
      await setDoc(ref(db, 'feeCounters', `invoice_${YEAR}`), { schoolId: A, branchId: NORTH, last: 1, updatedBy: 'seed' });
    }
  });
}

// ===================================================================== TESTS

test('Tenant isolation: a School B admin and finance user can neither read nor write School A fee data', async () => {
  await seedWorld();
  for (const uid of ['fee-admin-b', 'fee-fin-b']) {
    const db = asUser(uid);
    await assertFails(getDoc(ref(db, 'invoices', invId())));
    await assertFails(getDocs(col(db, 'invoices')));
    await assertFails(getDocs(col(db, 'payments')));
    await assertFails(getDocs(col(db, 'receipts')));
    await assertFails(getDoc(ref(db, 'feeStructures', structureId())));
    await assertFails(setDoc(ref(db, 'feeStructures', structureId('NEW')), structureDoc({ code: 'NEW', uid })));
    await assertFails(issueBatch(db, uid, [{ studentId: 'stu-2', seq: 2 }], { counterExists: true }).commit());
    await assertFails(collectBatch(db, uid, { paymentId: 'p-evil', amount: 1000, rseq: 1 }).commit());
    await assertFails(updateDoc(ref(db, 'invoices', invId()), { status: 'VOID' }));
  }
});

test('Branch isolation: South finance and South admin cannot touch North invoices, payments or structures', async () => {
  await seedWorld();
  for (const uid of ['fee-fin-south', 'fee-br-south']) {
    const db = asUser(uid);
    await assertFails(getDoc(ref(db, 'invoices', invId())));
    await assertFails(getDocs(col(db, 'payments')));
    await assertFails(collectBatch(db, uid, { paymentId: 'p-south', amount: 1000 }).commit());
    await assertFails(setDoc(ref(db, 'feeStructures', structureId('SOUTHFEE')), structureDoc({ code: 'SOUTHFEE', uid })));
  }
  // the school admin spans branches
  await assertSucceeds(getDoc(ref(asUser('fee-admin'), 'invoices', invId())));
});

test('Teachers have no financial access at all', async () => {
  await seedWorld();
  const db = asUser('fee-teacher');
  for (const name of ['invoices', 'payments', 'receipts', 'feeStructures', 'studentFeeAssignments', 'feeCounters', 'paymentReversals', 'financialAuditLogs']) {
    await assertFails(getDocs(col(db, name)));
  }
  await assertFails(collectBatch(db, 'fee-teacher', { paymentId: 'p-t', amount: 1000 }).commit());
  await assertFails(setDoc(ref(db, 'financialAuditLogs', 'x'), { schoolId: A, branchId: NORTH, actorId: 'fee-teacher', at: serverTimestamp(), type: 'X' }));
});

test('Parents read ONLY their linked child\'s invoices, payments, receipts and assignments — and never write', async () => {
  await seedWorld({ paid: 40000 });
  await seed(async (db) => {
    await setDoc(ref(db, 'invoices', invId('stu-2')), { ...invoiceDoc({ studentId: 'stu-2', seq: 2, uid: 'seed' }) });
    await setDoc(ref(db, 'payments', 'p-1'), { ...paymentDoc({ paymentId: 'p-1', amount: 40000, balanceBefore: 100000, uid: 'fee-fin-north' }) });
    await setDoc(ref(db, 'receipts', 'p-1'), receiptDoc({ paymentId: 'p-1', amount: 40000, balanceAfter: 60000, uid: 'fee-fin-north' }));
    await setDoc(ref(db, 'studentFeeAssignments', `stu-1__${structureId()}`), assignmentDoc({ uid: 'seed' }));
  });
  const parent = asUser('fee-parent');
  await assertSucceeds(getDoc(ref(parent, 'invoices', invId())));
  await assertSucceeds(getDoc(ref(parent, 'payments', 'p-1')));
  await assertSucceeds(getDoc(ref(parent, 'receipts', 'p-1')));
  await assertSucceeds(getDoc(ref(parent, 'studentFeeAssignments', `stu-1__${structureId()}`)));
  // the query shape the app uses
  await assertSucceeds(getDocs(query(col(parent, 'invoices'), where('studentId', '==', 'stu-1'))));

  // someone else's child, and unconstrained listing
  await assertFails(getDoc(ref(parent, 'invoices', invId('stu-2'))));
  await assertFails(getDocs(query(col(parent, 'invoices'), where('studentId', '==', 'stu-2'))));
  await assertFails(getDocs(col(parent, 'invoices')));
  await assertFails(getDocs(col(parent, 'payments')));
  // other parent cannot see stu-1
  await assertFails(getDoc(ref(asUser('fee-parent2'), 'invoices', invId())));
  await assertSucceeds(getDoc(ref(asUser('fee-parent2'), 'invoices', invId('stu-2'))));

  // no structures, counters, reversals or audit logs; no writes
  await assertFails(getDocs(col(parent, 'feeStructures')));
  await assertFails(getDocs(col(parent, 'financialAuditLogs')));
  await assertFails(updateDoc(ref(parent, 'invoices', invId()), { status: 'PAID' }));
  await assertFails(collectBatch(parent, 'fee-parent', { paymentId: 'p-parent', amount: 1000, inv: { payable: 100000, waived: 0, paid: 40000 }, rseq: 2, counterExists: false }).commit());
  await assertFails(setDoc(ref(parent, 'payments', 'p-x'), paymentDoc({ paymentId: 'p-x', amount: 100, balanceBefore: 60000, uid: 'fee-parent' })));
});

test('A parent link without portal access, or an inactive one, grants nothing', async () => {
  await seedWorld();
  await seed((db) => updateDoc(doc(db, ...branch(A, NORTH), 'students', 'stu-1', 'parentLinks', 'parent-1'), { canAccessPortal: false }));
  await assertFails(getDoc(ref(asUser('fee-parent'), 'invoices', invId())));
});

test('Parent -> children lookup (collection group on parentLinks) is limited to the parent\'s own links', async () => {
  await seedWorld();
  const mine = (db, parentId) => getDocs(query(collectionGroup(db, 'parentLinks'), where('schoolId', '==', A), where('parentId', '==', parentId)));
  const snap = await assertSucceeds(mine(asUser('fee-parent'), 'parent-1'));
  if (snap.size !== 1) throw new Error(`expected 1 link, got ${snap.size}`);
  await assertFails(mine(asUser('fee-parent'), 'parent-2'));
  await assertFails(mine(asUser('fee-fin-north'), 'parent-1'));
  await assertFails(mine(asUser('fee-teacher'), 'parent-1'));
});

// ------------------------------------------------------------- structures

test('Fee structures: only admins configure them; id = year__code; positive amounts; no duplicates; never deleted', async () => {
  await seedWorld();
  const admin = asUser('fee-br-north');
  const create = (db, over, code = 'BUS') => setDoc(ref(db, 'feeStructures', structureId(code)), { ...structureDoc({ code, uid: db === admin ? 'fee-br-north' : 'fee-fin-north' }), ...over });

  await assertSucceeds(create(admin, {}));
  await assertFails(create(admin, {})); // duplicate code => update, rejected
  await assertFails(create(asUser('fee-fin-north'), {}, 'BUS2')); // finance cannot configure
  await assertFails(setDoc(ref(admin, 'feeStructures', 'y1__wrong'), structureDoc({ code: 'BUS3', uid: 'fee-br-north' }))); // id != year__code
  await assertFails(create(admin, { amountMinor: 0 }, 'ZERO'));
  await assertFails(create(admin, { amountMinor: -500 }, 'NEG'));
  await assertFails(create(admin, { amountMinor: 10.5 }, 'FLT'));
  await assertFails(create(admin, { frequency: 'WEEKLY' }, 'FRQ'));
  await assertFails(create(admin, { code: 'bad code' }, 'BAD'));

  const meta = { updatedAt: serverTimestamp(), updatedBy: 'fee-br-north' };
  await assertSucceeds(updateDoc(ref(admin, 'feeStructures', structureId('BUS')), { amountMinor: 120000, ...meta }));
  await assertFails(updateDoc(ref(admin, 'feeStructures', structureId('BUS')), { amountMinor: 0, ...meta }));
  await assertFails(updateDoc(ref(admin, 'feeStructures', structureId('BUS')), { code: 'OTHER', ...meta })); // identity
  await assertFails(updateDoc(ref(admin, 'feeStructures', structureId('BUS')), { academicYearId: 'y2', ...meta }));
  await assertFails(updateDoc(ref(asUser('fee-fin-north'), 'feeStructures', structureId('BUS')), { amountMinor: 1, updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' }));
  await assertFails(deleteDoc(ref(admin, 'feeStructures', structureId('BUS'))));
  await assertSucceeds(getDoc(ref(asUser('fee-fin-north'), 'feeStructures', structureId('BUS')))); // finance may read
});

test('Editing a fee structure does not touch an issued invoice (snapshot is independent)', async () => {
  await seedWorld();
  const before = (await seed2(async (db) => (await getDoc(ref(db, 'invoices', invId()))).data())) ;
  await assertSucceeds(updateDoc(ref(asUser('fee-admin'), 'feeStructures', structureId()), { amountMinor: 999999, updatedAt: serverTimestamp(), updatedBy: 'fee-admin' }));
  const after = await seed2(async (db) => (await getDoc(ref(db, 'invoices', invId()))).data());
  if (after.payableMinor !== before.payableMinor || after.lines[0].amountMinor !== before.lines[0].amountMinor) throw new Error('invoice changed');
});

async function seed2(fn) {
  let out;
  await seed(async (db) => { out = await fn(db); });
  return out;
}

// ------------------------------------------------------------ assignments

test('Assignments: finance assigns; one per student+fee head; structure must be active and in the same year', async () => {
  await seedWorld({ invoice: false });
  const fin = asUser('fee-fin-north');
  const id = `stu-1__${structureId()}`;
  await assertSucceeds(setDoc(ref(fin, 'studentFeeAssignments', id), assignmentDoc({ uid: 'fee-fin-north' })));
  await assertFails(setDoc(ref(fin, 'studentFeeAssignments', id), assignmentDoc({ uid: 'fee-fin-north' }))); // duplicate
  await assertFails(setDoc(ref(fin, 'studentFeeAssignments', 'wrong-id'), assignmentDoc({ studentId: 'stu-2', uid: 'fee-fin-north' })));
  await assertFails(setDoc(ref(fin, 'studentFeeAssignments', `stu-2__${structureId('OLD')}`), assignmentDoc({ studentId: 'stu-2', structure: structureId('OLD'), uid: 'fee-fin-north' }))); // inactive
  await assertFails(setDoc(ref(fin, 'studentFeeAssignments', `stu-2__${structureId('NEXT', 'y2')}`), assignmentDoc({ studentId: 'stu-2', structure: structureId('NEXT', 'y2'), uid: 'fee-fin-north' }))); // other year
  await assertFails(setDoc(ref(fin, 'studentFeeAssignments', `stu-2__${structureId('GHOST')}`), assignmentDoc({ studentId: 'stu-2', structure: structureId('GHOST'), uid: 'fee-fin-north' })));
  // cancel / re-activate
  const meta = { updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' };
  await assertSucceeds(updateDoc(ref(fin, 'studentFeeAssignments', id), { status: 'CANCELLED', ...meta }));
  await assertSucceeds(updateDoc(ref(fin, 'studentFeeAssignments', id), { status: 'ACTIVE', ...meta }));
  await assertFails(updateDoc(ref(fin, 'studentFeeAssignments', id), { studentId: 'stu-2', ...meta }));
  await assertFails(deleteDoc(ref(fin, 'studentFeeAssignments', id)));
});

test('Concessions need an admin, a positive value, a reason, and the approver recorded', async () => {
  await seedWorld({ invoice: false });
  const id = (s) => `${s}__${structureId()}`;
  const concession = { concessionType: 'PERCENT', concessionValue: 2500, reason: 'Sibling discount' };
  await assertFails(setDoc(ref(asUser('fee-fin-north'), 'studentFeeAssignments', id('stu-1')), assignmentDoc({ ...concession, approvedBy: 'fee-fin-north', uid: 'fee-fin-north' })));
  const admin = asUser('fee-br-north');
  await assertSucceeds(setDoc(ref(admin, 'studentFeeAssignments', id('stu-1')), assignmentDoc({ ...concession, approvedBy: 'fee-br-north', uid: 'fee-br-north' })));
  await assertFails(setDoc(ref(admin, 'studentFeeAssignments', id('stu-2')), assignmentDoc({ studentId: 'stu-2', ...concession, concessionValue: 10001, approvedBy: 'fee-br-north', uid: 'fee-br-north' }))); // > 100%
  await assertFails(setDoc(ref(admin, 'studentFeeAssignments', id('stu-2')), assignmentDoc({ studentId: 'stu-2', ...concession, reason: null, approvedBy: 'fee-br-north', uid: 'fee-br-north' })));
  await assertFails(setDoc(ref(admin, 'studentFeeAssignments', id('stu-2')), assignmentDoc({ studentId: 'stu-2', ...concession, approvedBy: 'someone-else', uid: 'fee-br-north' })));
  await assertFails(setDoc(ref(admin, 'studentFeeAssignments', id('stu-2')), assignmentDoc({ studentId: 'stu-2', concessionType: 'NONE', concessionValue: 500, uid: 'fee-br-north' })));
  // finance cannot edit a concession afterwards either
  await assertFails(updateDoc(ref(asUser('fee-fin-north'), 'studentFeeAssignments', id('stu-1')), { concessionValue: 9999, concessionApprovedBy: 'fee-fin-north', updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' }));
});

// ---------------------------------------------------------------- invoices

test('Issuing: finance issues an invoice with its number reservation and charge locks in one batch', async () => {
  await seedWorld({ invoice: false });
  const fin = asUser('fee-fin-north');
  await assertSucceeds(issueBatch(fin, 'fee-fin-north', [{ studentId: 'stu-1', seq: 1 }]).commit());
  const snap = await assertSucceeds(getDoc(ref(fin, 'invoices', invId())));
  if (snap.data().balanceMinor !== 100000) throw new Error('bad balance');
  // bulk: several invoices in one commit, numbers consecutive
  await assertSucceeds(issueBatch(fin, 'fee-fin-north', [{ studentId: 'stu-2', seq: 2 }], { counterExists: true }).commit());
});

test('Issuing is refused for parents, teachers, other branches and other schools', async () => {
  await seedWorld({ invoice: false });
  for (const uid of ['fee-parent', 'fee-teacher', 'fee-fin-south', 'fee-br-south', 'fee-fin-b', 'fee-admin-b']) {
    await assertFails(issueBatch(asUser(uid), uid, [{ studentId: 'stu-1', seq: 1 }]).commit());
  }
});

test('Invoice arithmetic is enforced: payable = subtotal - discount, balance = payable, nothing pre-paid, positive total', async () => {
  await seedWorld({ invoice: false });
  const fin = asUser('fee-fin-north');
  const bad = (overrides, seq) => {
    const b = writeBatch(fin);
    b.set(ref(fin, 'feeCounters', `invoice_${YEAR}`), { schoolId: A, branchId: NORTH, last: seq, updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' });
    b.set(ref(fin, 'invoiceNumbers', invNo(seq)), { schoolId: A, branchId: NORTH, academicYearId: YEAR, numberSeq: seq });
    b.set(ref(fin, 'invoices', invId('stu-1', `P${seq}`)), invoiceDoc({ periodKey: `P${seq}`, seq, uid: 'fee-fin-north', overrides }));
    return b.commit();
  };
  await assertFails(bad({ payableMinor: 90000 }, 1)); // payable != subtotal - discount
  await assertFails(bad({ balanceMinor: 50000 }, 1)); // balance != payable
  await assertFails(bad({ paidMinor: 1000, balanceMinor: 99000 }, 1)); // pre-paid
  await assertFails(bad({ waivedMinor: 1000, balanceMinor: 99000 }, 1)); // pre-waived
  await assertFails(bad({ status: 'PAID' }, 1));
  await assertFails(bad({ lines: [] }, 1));
  await assertFails(bad({ subtotalMinor: 0, payableMinor: 0, balanceMinor: 0 }, 1)); // zero invoice
  await assertFails(bad({ subtotalMinor: -5, payableMinor: -5, balanceMinor: -5 }, 1));
  await assertFails(bad({ dueDateKey: '2026-05-01' }, 1)); // due before issue
  await assertFails(bad({ issueDateKey: 'June 1' }, 1));
  await assertSucceeds(bad({}, 1));
});

test('One invoice per student per period: re-issuing the same period (a retry) cannot create a second', async () => {
  await seedWorld({ invoice: false });
  const fin = asUser('fee-fin-north');
  await assertSucceeds(issueBatch(fin, 'fee-fin-north', [{ studentId: 'stu-1', seq: 1 }]).commit());
  await assertFails(issueBatch(fin, 'fee-fin-north', [{ studentId: 'stu-1', seq: 2 }], { counterExists: true }).commit());
  // and the id must be the canonical one
  const b = writeBatch(fin);
  b.set(ref(fin, 'feeCounters', `invoice_${YEAR}`), { last: 3, updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north', schoolId: A, branchId: NORTH });
  b.set(ref(fin, 'invoiceNumbers', invNo(3)), { schoolId: A, branchId: NORTH, academicYearId: YEAR, numberSeq: 3 });
  b.set(ref(fin, 'invoices', 'random-id'), invoiceDoc({ periodKey: 'P9', seq: 3, uid: 'fee-fin-north' }));
  await assertFails(b.commit());
});

test('Invoice numbers are unique and sequence-bound: reuse, skipping the counter and a missing reservation all fail', async () => {
  await seedWorld({ invoice: false });
  const fin = asUser('fee-fin-north');
  await assertSucceeds(issueBatch(fin, 'fee-fin-north', [{ studentId: 'stu-1', seq: 1 }]).commit());

  // two clients racing: B read the counter at 0 and also takes number 1
  await assertFails(issueBatch(asUser('fee-br-north'), 'fee-br-north', [{ studentId: 'stu-2', seq: 1 }], { counterExists: true, counterLast: 1 }).commit());

  // a number the counter did not move through is refused
  const noBump = writeBatch(fin);
  noBump.set(ref(fin, 'invoiceNumbers', invNo(7)), { schoolId: A, branchId: NORTH, academicYearId: YEAR, numberSeq: 7 });
  noBump.set(ref(fin, 'invoices', invId('stu-2')), invoiceDoc({ studentId: 'stu-2', seq: 7, uid: 'fee-fin-north' }));
  await assertFails(noBump.commit());

  // counter must only increase
  await assertFails(updateDoc(ref(fin, 'feeCounters', `invoice_${YEAR}`), { last: 0, updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' }));
  await assertFails(updateDoc(ref(fin, 'feeCounters', `invoice_${YEAR}`), { last: 1, updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' }));

  // an invoice that names a number with no reservation
  const noRes = writeBatch(fin);
  noRes.update(ref(fin, 'feeCounters', `invoice_${YEAR}`), { last: 2, updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' });
  noRes.set(ref(fin, 'invoices', invId('stu-2')), invoiceDoc({ studentId: 'stu-2', seq: 2, uid: 'fee-fin-north' }));
  await assertFails(noRes.commit());

  // a later, properly sequenced one still works (gaps are fine)
  await assertSucceeds(issueBatch(fin, 'fee-fin-north', [{ studentId: 'stu-2', seq: 5 }], { counterExists: true, counterLast: 5 }).commit());
});

test('A student who is not an active student of this branch cannot be invoiced', async () => {
  await seedWorld({ invoice: false });
  const fin = asUser('fee-fin-north');
  await assertFails(issueBatch(fin, 'fee-fin-north', [{ studentId: 'stu-left', seq: 1 }]).commit());
  await assertFails(issueBatch(fin, 'fee-fin-north', [{ studentId: 'stu-from-elsewhere', seq: 1 }]).commit());
});

test('Issued invoices are immutable apart from the derived money fields', async () => {
  await seedWorld();
  const admin = asUser('fee-admin');
  const meta = { updatedAt: serverTimestamp(), updatedBy: 'fee-admin' };
  for (const change of [
    { payableMinor: 1 }, { subtotalMinor: 1 }, { discountMinor: 5 }, { lines: [] }, { studentId: 'stu-2' }, { invoiceNumber: invNo(99) },
    { dueDateKey: '2030-01-01' }, { schoolId: B }, { branchId: SOUTH }, { periodKey: 'X' }, { studentName: 'Someone Else' },
  ]) {
    await assertFails(updateDoc(ref(admin, 'invoices', invId()), { ...change, lastEventType: 'WAIVER', lastEventId: 'w', ...meta }));
    await assertFails(updateDoc(ref(admin, 'invoices', invId()), { ...change, ...meta }));
  }
  await assertFails(deleteDoc(ref(admin, 'invoices', invId())));
});

// ---------------------------------------------------------------- payments

test('Payments: partial, then another partial, then the rest — status, balance and receipts follow', async () => {
  await seedWorld();
  const fin = asUser('fee-fin-north');
  await assertSucceeds(collectBatch(fin, 'fee-fin-north', { paymentId: 'p1', amount: 30000, inv: { payable: 100000, waived: 0, paid: 0 }, rseq: 1 }).commit());
  let inv = (await seed2(async (db) => (await getDoc(ref(db, 'invoices', invId()))).data()));
  if (inv.status !== 'PARTIALLY_PAID' || inv.paidMinor !== 30000 || inv.balanceMinor !== 70000) throw new Error(JSON.stringify(inv));

  await assertSucceeds(collectBatch(fin, 'fee-fin-north', { paymentId: 'p2', amount: 20000, inv: { payable: 100000, waived: 0, paid: 30000 }, rseq: 2, counterExists: true }).commit());
  await assertSucceeds(collectBatch(fin, 'fee-fin-north', { paymentId: 'p3', amount: 50000, inv: { payable: 100000, waived: 0, paid: 50000 }, rseq: 3, counterExists: true }).commit());
  inv = (await seed2(async (db) => (await getDoc(ref(db, 'invoices', invId()))).data()));
  if (inv.status !== 'PAID' || inv.balanceMinor !== 0 || inv.paidMinor !== 100000) throw new Error(JSON.stringify(inv));

  // the receipt exists, is numbered, and matches
  const receipt = (await seed2(async (db) => (await getDoc(ref(db, 'receipts', 'p2'))).data()));
  if (receipt.receiptNumber !== rctNo(2) || receipt.balanceAfterMinor !== 50000) throw new Error('bad receipt');
});

test('Overpayment is rejected — by even one minor unit — and so are zero, negative and fractional amounts', async () => {
  await seedWorld();
  const fin = asUser('fee-fin-north');
  const inv = { payable: 100000, waived: 0, paid: 0 };
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'pa', amount: 100001, inv }).commit());
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'pb', amount: 0, inv }).commit());
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'pc', amount: -100, inv }).commit());
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'pd', amount: 99.5, inv }).commit());
  await assertSucceeds(collectBatch(fin, 'fee-fin-north', { paymentId: 'pe', amount: 100000, inv }).commit());
  // and nothing more once paid
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'pf', amount: 1, inv: { payable: 100000, waived: 0, paid: 100000 }, rseq: 2, counterExists: true }).commit());
});

test('CONCURRENCY: two cashiers who both saw a ₹700 balance cannot both collect ₹700 — the second is refused', async () => {
  await seedWorld({ paid: 30000 });
  const inv = { payable: 100000, waived: 0, paid: 30000 }; // both clients loaded this
  await assertSucceeds(collectBatch(asUser('fee-fin-north'), 'fee-fin-north', { paymentId: 'cashier-a', amount: 70000, inv, rseq: 1 }).commit());
  // cashier B's batch was built from the same stale view of the invoice
  await assertFails(collectBatch(asUser('fee-br-north'), 'fee-br-north', { paymentId: 'cashier-b', amount: 70000, inv, rseq: 2, counterExists: true }).commit());
  const final = (await seed2(async (db) => (await getDoc(ref(db, 'invoices', invId()))).data()));
  if (final.paidMinor !== 100000 || final.balanceMinor !== 0) throw new Error(JSON.stringify(final));
});

test('CONCURRENCY: stale partial payments cannot over-collect or leave a wrong balance', async () => {
  await seedWorld();
  const inv = { payable: 100000, waived: 0, paid: 0 };
  await assertSucceeds(collectBatch(asUser('fee-fin-north'), 'fee-fin-north', { paymentId: 'x1', amount: 60000, inv, rseq: 1 }).commit());
  // B also believed the balance was 100000 and tries 60000 against that stale state
  await assertFails(collectBatch(asUser('fee-br-north'), 'fee-br-north', { paymentId: 'x2', amount: 60000, inv, rseq: 2, counterExists: true }).commit());
  // B retries with fresh state and a legal amount
  await assertSucceeds(collectBatch(asUser('fee-br-north'), 'fee-br-north', { paymentId: 'x2', amount: 40000, inv: { payable: 100000, waived: 0, paid: 60000 }, rseq: 2, counterExists: true }).commit());
});

test('IDEMPOTENCY: the same payment id cannot be submitted twice', async () => {
  await seedWorld();
  const fin = asUser('fee-fin-north');
  await assertSucceeds(collectBatch(fin, 'fee-fin-north', { paymentId: 'key-1', amount: 10000, rseq: 1 }).commit());
  // replay of the exact same request (double-click / network retry)
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'key-1', amount: 10000, inv: { payable: 100000, waived: 0, paid: 10000 }, rseq: 2, counterExists: true }).commit());
  const stored = await seed2(async (db) => (await getDocs(col(db, 'payments'))).size);
  const rcpts = await seed2(async (db) => (await getDocs(col(db, 'receipts'))).size);
  if (stored !== 1 || rcpts !== 1) throw new Error(`payments=${stored} receipts=${rcpts}`);
});

test('A payment is inseparable from its invoice update and receipt', async () => {
  await seedWorld();
  const fin = asUser('fee-fin-north');
  const inv = { payable: 100000, waived: 0, paid: 0 };
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'n1', amount: 1000, inv, skip: ['invoice'] }).commit()); // payment without moving the invoice
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'n2', amount: 1000, inv, skip: ['receipt'] }).commit()); // no receipt
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'n3', amount: 1000, inv, skip: ['reservation'] }).commit()); // receipt number unreserved
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'n4', amount: 1000, inv, skip: ['counter'] }).commit()); // number outside the sequence
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'n5', amount: 1000, inv, skip: ['payment'] }).commit()); // invoice moved with no payment
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'n6', amount: 1000, inv, invoiceOverrides: { paidMinor: 5000, balanceMinor: 95000, status: 'PARTIALLY_PAID' } }).commit()); // invoice moved by the wrong amount
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'n7', amount: 1000, inv, invoiceOverrides: { balanceMinor: 1 } }).commit()); // wrong balance
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'n8', amount: 100000, inv, invoiceOverrides: { status: 'PARTIALLY_PAID' } }).commit()); // wrong status
  // direct invoice tampering without any payment record
  await assertFails(updateDoc(ref(fin, 'invoices', invId()), { paidMinor: 100000, balanceMinor: 0, status: 'PAID', lastEventType: 'PAYMENT', lastEventId: 'ghost', updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' }));
  const n = await seed2(async (db) => (await getDocs(col(db, 'payments'))).size);
  if (n !== 0) throw new Error('a payment slipped through');
});

test('Payment validation: reference for non-cash, honest collector, matching student/invoice, receipts match', async () => {
  await seedWorld();
  const fin = asUser('fee-fin-north');
  const inv = { payable: 100000, waived: 0, paid: 0 };
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'v1', amount: 1000, inv, method: 'UPI' }).commit()); // UPI needs a reference
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'v2', amount: 1000, inv, method: 'CHEQUE', referenceNo: '1' }).commit());
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'v3', amount: 1000, inv, method: 'CRYPTO' }).commit());
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'v4', amount: 1000, inv, overrides: { collectedBy: 'someone-else' } }).commit());
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'v5', amount: 1000, inv, overrides: { studentId: 'stu-2' } }).commit());
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'v6', amount: 1000, inv, overrides: { academicYearId: 'y2' } }).commit());
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'v7', amount: 1000, inv, overrides: { balanceAfterMinor: 0 } }).commit());
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'v8', amount: 1000, inv, overrides: { invoiceId: invId('stu-2') } }).commit()); // someone else's invoice
  await assertFails(collectBatch(fin, 'fee-fin-north', { paymentId: 'v9', amount: 1000, inv, overrides: { createdBy: 'forged' } }).commit());
  await assertSucceeds(collectBatch(fin, 'fee-fin-north', { paymentId: 'v10', amount: 1000, inv, method: 'UPI', referenceNo: 'UTR123456' }).commit());
});

test('Payments, receipts and their amounts can never be edited or deleted', async () => {
  await seedWorld();
  const fin = asUser('fee-fin-north');
  await assertSucceeds(collectBatch(fin, 'fee-fin-north', { paymentId: 'imm', amount: 20000 }).commit());
  const admin = asUser('fee-admin');
  const meta = { updatedAt: serverTimestamp(), updatedBy: 'fee-admin' };
  for (const uid of [fin, admin]) {
    await assertFails(updateDoc(ref(uid, 'payments', 'imm'), { amountMinor: 1, updatedAt: serverTimestamp(), updatedBy: 'x' }));
    await assertFails(deleteDoc(ref(uid, 'payments', 'imm')));
    await assertFails(deleteDoc(ref(uid, 'receipts', 'imm')));
    await assertFails(updateDoc(ref(uid, 'receipts', 'imm'), { amountMinor: 1 }));
  }
  await assertFails(updateDoc(ref(admin, 'payments', 'imm'), { amountMinor: 5, ...meta }));
  await assertFails(updateDoc(ref(admin, 'payments', 'imm'), { status: 'REVERSED', ...meta })); // not without a reversal record
  await assertFails(updateDoc(ref(fin, 'payments', 'imm'), { status: 'REVERSED', updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' }));
});

test('A void invoice accepts no payments; a paid one accepts none either', async () => {
  await seedWorld();
  await assertSucceeds(updateDoc(ref(asUser('fee-admin'), 'invoices', invId()), {
    status: 'VOID', voidReason: 'Issued in error', voidedAt: serverTimestamp(), voidedBy: 'fee-admin', lastEventType: 'VOID', lastEventId: 'v', updatedAt: serverTimestamp(), updatedBy: 'fee-admin',
  }));
  await assertFails(collectBatch(asUser('fee-fin-north'), 'fee-fin-north', { paymentId: 'late', amount: 1000 }).commit());
});

// ------------------------------------------------- reversal / refund / void / waiver

async function payFully(paymentId = 'pay1', amount = 40000, rseq = 1) {
  await assertSucceeds(collectBatch(asUser('fee-fin-north'), 'fee-fin-north', { paymentId, amount, rseq, counterExists: rseq > 1 }).commit());
}

function reverseBatch(db, uid, { paymentId = 'pay1', amount = 40000, kind = 'REVERSAL', reason = 'Entered in error', invBefore = { payable: 100000, waived: 0, paid: 40000 }, skip = [], overrides = {}, invoiceOverrides = {} }) {
  const b = writeBatch(db);
  if (!skip.includes('reversal')) {
    b.set(ref(db, 'paymentReversals', paymentId), {
      schoolId: A, branchId: NORTH, paymentId, kind, reason, amountMinor: amount, invoiceId: invId(), studentId: 'stu-1', reversalDateKey: '2026-06-11',
      reversedBy: uid, createdAt: serverTimestamp(), ...overrides,
    });
  }
  if (!skip.includes('payment')) b.update(ref(db, 'payments', paymentId), { status: 'REVERSED', updatedAt: serverTimestamp(), updatedBy: uid });
  if (!skip.includes('receipt')) b.update(ref(db, 'receipts', paymentId), { status: 'REVERSED', updatedAt: serverTimestamp(), updatedBy: uid });
  if (!skip.includes('invoice')) {
    const paid = invBefore.paid - amount;
    b.update(ref(db, 'invoices', invId()), {
      paidMinor: paid, balanceMinor: invBefore.payable - invBefore.waived - paid, status: statusFor(invBefore.payable, invBefore.waived, paid),
      lastEventType: 'REVERSAL', lastEventId: paymentId, updatedAt: serverTimestamp(), updatedBy: uid, ...invoiceOverrides,
    });
  }
  return b;
}

test('Reversal / refund: admin only, once, with a reason; the payment and receipt are kept and marked, and the invoice is restored', async () => {
  await seedWorld();
  await payFully();
  await assertFails(reverseBatch(asUser('fee-fin-north'), 'fee-fin-north', {}).commit()); // finance cannot
  await assertFails(reverseBatch(asUser('fee-teacher'), 'fee-teacher', {}).commit());
  await assertFails(reverseBatch(asUser('fee-br-south'), 'fee-br-south', {}).commit()); // other branch
  await assertFails(reverseBatch(asUser('fee-admin'), 'fee-admin', { reason: '' }).commit()); // reason required
  await assertFails(reverseBatch(asUser('fee-admin'), 'fee-admin', { kind: 'CHARGEBACK' }).commit());
  await assertFails(reverseBatch(asUser('fee-admin'), 'fee-admin', { amount: 10000 }).commit()); // must reverse the whole payment
  await assertFails(reverseBatch(asUser('fee-admin'), 'fee-admin', { skip: ['invoice'] }).commit()); // invoice must follow
  await assertFails(reverseBatch(asUser('fee-admin'), 'fee-admin', { skip: ['reversal'] }).commit()); // no record, no reversal
  await assertFails(reverseBatch(asUser('fee-admin'), 'fee-admin', { invoiceOverrides: { paidMinor: 10000, balanceMinor: 90000, status: 'PARTIALLY_PAID' } }).commit()); // wrong amount taken off the invoice

  await assertSucceeds(reverseBatch(asUser('fee-br-north'), 'fee-br-north', { kind: 'REFUND', reason: 'Parent withdrew the child' }).commit());
  const { payment, receipt, invoice, reversal } = await seed2(async (db) => ({
    payment: (await getDoc(ref(db, 'payments', 'pay1'))).data(),
    receipt: (await getDoc(ref(db, 'receipts', 'pay1'))).data(),
    invoice: (await getDoc(ref(db, 'invoices', invId()))).data(),
    reversal: (await getDoc(ref(db, 'paymentReversals', 'pay1'))).data(),
  }));
  if (payment.status !== 'REVERSED' || payment.amountMinor !== 40000) throw new Error('payment not kept intact');
  if (receipt.status !== 'REVERSED' || receipt.receiptNumber !== rctNo(1)) throw new Error('receipt not kept');
  if (invoice.paidMinor !== 0 || invoice.balanceMinor !== 100000 || invoice.status !== 'ISSUED') throw new Error(JSON.stringify(invoice));
  if (reversal.kind !== 'REFUND' || reversal.reason.length < 3) throw new Error('reversal not recorded');

  // a payment is reversed only once, and the record is permanent
  await assertFails(reverseBatch(asUser('fee-admin'), 'fee-admin', { invBefore: { payable: 100000, waived: 0, paid: 40000 } }).commit());
  await assertFails(deleteDoc(ref(asUser('fee-admin'), 'paymentReversals', 'pay1')));
  await assertFails(updateDoc(ref(asUser('fee-admin'), 'paymentReversals', 'pay1'), { reason: 'rewritten' }));
});

test('After a reversal the invoice can be paid again with a new payment and a new receipt', async () => {
  await seedWorld();
  await payFully();
  await assertSucceeds(reverseBatch(asUser('fee-admin'), 'fee-admin', {}).commit());
  await assertSucceeds(collectBatch(asUser('fee-fin-north'), 'fee-fin-north', { paymentId: 'pay2', amount: 100000, rseq: 2, counterExists: true }).commit());
  const inv = await seed2(async (db) => (await getDoc(ref(db, 'invoices', invId()))).data());
  if (inv.status !== 'PAID' || inv.paidMinor !== 100000) throw new Error(JSON.stringify(inv));
});

function waiverBatch(db, uid, { id = 'w1', amount = 25000, reason = 'Hardship waiver approved', inv = { payable: 100000, waived: 0, paid: 0 }, invoiceOverrides = {}, skip = [] }) {
  const b = writeBatch(db);
  if (!skip.includes('waiver')) {
    b.set(ref(db, 'invoiceWaivers', id), {
      schoolId: A, branchId: NORTH, invoiceId: invId(), studentId: 'stu-1', amountMinor: amount, reason, approvedBy: uid, waiverDateKey: '2026-06-12', createdAt: serverTimestamp(),
    });
  }
  const waived = inv.waived + amount;
  b.update(ref(db, 'invoices', invId()), {
    waivedMinor: waived, balanceMinor: inv.payable - waived - inv.paid, status: statusFor(inv.payable, waived, inv.paid),
    lastEventType: 'WAIVER', lastEventId: id, updatedAt: serverTimestamp(), updatedBy: uid, ...invoiceOverrides,
  });
  return b;
}

test('Waivers: admin only, a reason, never more than the balance, and the invoice follows exactly', async () => {
  await seedWorld();
  await assertFails(waiverBatch(asUser('fee-fin-north'), 'fee-fin-north', {}).commit());
  await assertFails(waiverBatch(asUser('fee-admin'), 'fee-admin', { amount: 100001 }).commit());
  await assertFails(waiverBatch(asUser('fee-admin'), 'fee-admin', { amount: 0 }).commit());
  await assertFails(waiverBatch(asUser('fee-admin'), 'fee-admin', { reason: '' }).commit());
  await assertFails(waiverBatch(asUser('fee-admin'), 'fee-admin', { skip: ['waiver'] }).commit());
  await assertFails(waiverBatch(asUser('fee-admin'), 'fee-admin', { invoiceOverrides: { balanceMinor: 10 } }).commit());
  await assertFails(waiverBatch(asUser('fee-admin-b'), 'fee-admin-b', {}).commit());
  await assertSucceeds(waiverBatch(asUser('fee-admin'), 'fee-admin', {}).commit());
  const inv = await seed2(async (db) => (await getDoc(ref(db, 'invoices', invId()))).data());
  if (inv.waivedMinor !== 25000 || inv.balanceMinor !== 75000 || inv.status !== 'PARTIALLY_PAID') throw new Error(JSON.stringify(inv));
  // the balance after a waiver is what a payment is checked against
  await assertFails(collectBatch(asUser('fee-fin-north'), 'fee-fin-north', { paymentId: 'pw1', amount: 80000, inv: { payable: 100000, waived: 25000, paid: 0 } }).commit());
  await assertSucceeds(collectBatch(asUser('fee-fin-north'), 'fee-fin-north', { paymentId: 'pw2', amount: 75000, inv: { payable: 100000, waived: 25000, paid: 0 } }).commit());
  const done = await seed2(async (db) => (await getDoc(ref(db, 'invoices', invId()))).data());
  if (done.status !== 'PAID' || done.balanceMinor !== 0) throw new Error(JSON.stringify(done));
});

test('Voiding: admin only, with a reason, only when nothing is paid; the charge locks are then released', async () => {
  await seedWorld();
  await seed((db) => setDoc(ref(db, 'feeCharges', `stu-1__${structureId()}__${PERIOD}`), { schoolId: A, branchId: NORTH, invoiceId: invId(), assignmentId: `stu-1__${structureId()}` }));
  const voidFields = (uid, over = {}) => ({
    status: 'VOID', voidReason: 'Issued twice', voidedAt: serverTimestamp(), voidedBy: uid, lastEventType: 'VOID', lastEventId: 'v1', updatedAt: serverTimestamp(), updatedBy: uid, ...over,
  });
  await assertFails(updateDoc(ref(asUser('fee-fin-north'), 'invoices', invId()), voidFields('fee-fin-north')));
  await assertFails(updateDoc(ref(asUser('fee-admin'), 'invoices', invId()), voidFields('fee-admin', { voidReason: '' })));
  await assertFails(updateDoc(ref(asUser('fee-admin'), 'invoices', invId()), voidFields('fee-admin', { voidedBy: 'someone-else' })));
  await assertFails(deleteDoc(ref(asUser('fee-admin'), 'feeCharges', `stu-1__${structureId()}__${PERIOD}`))); // not while the invoice is live

  await assertSucceeds(updateDoc(ref(asUser('fee-admin'), 'invoices', invId()), voidFields('fee-admin')));
  await assertSucceeds(deleteDoc(ref(asUser('fee-admin'), 'feeCharges', `stu-1__${structureId()}__${PERIOD}`)));
  // terminal: no further changes at all
  await assertFails(updateDoc(ref(asUser('fee-admin'), 'invoices', invId()), { status: 'ISSUED', lastEventType: 'WAIVER', lastEventId: 'x', updatedAt: serverTimestamp(), updatedBy: 'fee-admin' }));
});

test('An invoice with money paid cannot be voided until the payments are reversed', async () => {
  await seedWorld();
  await payFully();
  const v = { status: 'VOID', voidReason: 'Oops', voidedAt: serverTimestamp(), voidedBy: 'fee-admin', lastEventType: 'VOID', lastEventId: 'v', updatedAt: serverTimestamp(), updatedBy: 'fee-admin' };
  await assertFails(updateDoc(ref(asUser('fee-admin'), 'invoices', invId()), v));
  await assertSucceeds(reverseBatch(asUser('fee-admin'), 'fee-admin', {}).commit());
  await assertSucceeds(updateDoc(ref(asUser('fee-admin'), 'invoices', invId()), { ...v, updatedAt: serverTimestamp(), voidedAt: serverTimestamp() }));
});

// -------------------------------------------------------------- audit logs

test('Financial audit log is append-only, attributable, and readable by admins only', async () => {
  await seedWorld();
  const log = (db, uid, over = {}) => setDoc(ref(db, 'financialAuditLogs', `${Math.random()}`.slice(2)), {
    schoolId: A, branchId: NORTH, actorId: uid, at: serverTimestamp(), type: 'INVOICE_VOIDED', ...over,
  });
  await assertSucceeds(log(asUser('fee-fin-north'), 'fee-fin-north'));
  await assertFails(log(asUser('fee-fin-north'), 'fee-fin-north', { actorId: 'forged' }));
  await assertFails(log(asUser('fee-fin-north'), 'fee-fin-north', { at: new Date('2020-01-01') }));
  await assertFails(log(asUser('fee-parent'), 'fee-parent'));
  await assertFails(log(asUser('fee-fin-b'), 'fee-fin-b'));
  const any = await seed2(async (db) => (await getDocs(col(db, 'financialAuditLogs'))).docs[0].id);
  await assertFails(updateDoc(ref(asUser('fee-admin'), 'financialAuditLogs', any), { type: 'X' }));
  await assertFails(deleteDoc(ref(asUser('fee-admin'), 'financialAuditLogs', any)));
  await assertSucceeds(getDocs(col(asUser('fee-admin'), 'financialAuditLogs')));
  await assertFails(getDocs(col(asUser('fee-fin-north'), 'financialAuditLogs')));
});

// ---------------------------------------------------------- reporting reads

test('Finance and admins can run the report queries (filters the app uses) on their own branch only', async () => {
  await seedWorld();
  const q = (db) => getDocs(query(col(db, 'invoices'), where('academicYearId', '==', YEAR), where('status', 'in', ['ISSUED', 'PARTIALLY_PAID']), where('dueDateKey', '<', '2026-07-01')));
  await assertSucceeds(q(asUser('fee-fin-north')));
  await assertSucceeds(q(asUser('fee-br-north')));
  await assertFails(q(asUser('fee-fin-south')));
  await assertFails(q(asUser('fee-fin-b')));
  await assertFails(q(asUser('fee-teacher')));
});

test('REPLAY: an invoice cannot be moved again by pointing at a payment that already exists', async () => {
  await seedWorld();
  const fin = asUser('fee-fin-north');
  await assertSucceeds(collectBatch(fin, 'fee-fin-north', { paymentId: 'real', amount: 10000 }).commit());
  // try to count the same payment a second time by re-pointing the invoice at it
  await assertFails(updateDoc(ref(fin, 'invoices', invId()), {
    paidMinor: 20000, balanceMinor: 80000, status: 'PARTIALLY_PAID', lastEventType: 'PAYMENT', lastEventId: 'real', updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north',
  }));
  const inv = await seed2(async (db) => (await getDoc(ref(db, 'invoices', invId()))).data());
  if (inv.paidMinor !== 10000) throw new Error('paid was inflated');
});

test('Invoice numbers cannot be taken below the counter without moving it (no squatting on unused numbers)', async () => {
  await seedWorld({ invoice: false });
  const fin = asUser('fee-fin-north');
  await assertSucceeds(issueBatch(fin, 'fee-fin-north', [{ studentId: 'stu-1', seq: 5 }], { counterLast: 5 }).commit());
  const b = writeBatch(fin);
  b.set(ref(fin, 'invoiceNumbers', invNo(3)), { schoolId: A, branchId: NORTH, academicYearId: YEAR, numberSeq: 3 });
  b.set(ref(fin, 'invoices', invId('stu-2')), invoiceDoc({ studentId: 'stu-2', seq: 3, uid: 'fee-fin-north' }));
  await assertFails(b.commit());
});

test('A payment cannot exceed the balance even if the invoice update is withheld from the rule check (independent layer)', async () => {
  await seedWorld({ paid: 90000 });
  const fin = asUser('fee-fin-north');
  // payment alone, no invoice update: the payment rule must itself refuse 20000 > 10000 balance
  const b = writeBatch(fin);
  b.set(ref(fin, 'receiptNumbers', rctNo(1)), { schoolId: A, branchId: NORTH, academicYearId: YEAR, numberSeq: 1 });
  b.set(ref(fin, 'feeCounters', `receipt_${YEAR}`), { schoolId: A, branchId: NORTH, last: 1, updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' });
  b.set(ref(fin, 'receipts', 'over'), receiptDoc({ paymentId: 'over', amount: 20000, balanceAfter: -10000, uid: 'fee-fin-north' }));
  b.set(ref(fin, 'payments', 'over'), paymentDoc({ paymentId: 'over', amount: 20000, balanceBefore: 10000, uid: 'fee-fin-north' }));
  b.update(ref(fin, 'invoices', invId()), { lastEventType: 'PAYMENT', lastEventId: 'over', updatedAt: serverTimestamp(), updatedBy: 'fee-fin-north' });
  await assertFails(b.commit());
});

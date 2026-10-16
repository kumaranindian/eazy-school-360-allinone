// Moving a student to another branch. The documents the Dart code writes
// (fixtures/branch-transfer-write-plans.json, exported by
// test/students/branch_transfer_write_contract_test.dart) must be accepted by
// the real rules, and every way of forging or half-doing the move refused.
// Prefix: bt-.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, setDoc, serverTimestamp, Timestamp, writeBatch } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const SCHOOL = 'bt-a';
const OTHER = 'bt-z';
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const P = (b, ...rest) => ['schools', SCHOOL, 'branches', b, ...rest];

function decode(value) {
  if (Array.isArray(value)) return value.map(decode);
  if (value && typeof value === 'object') {
    if (value.$serverTimestamp) return serverTimestamp();
    if (value.$time) return Timestamp.fromDate(new Date(value.$time));
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, decode(v)]));
  }
  return value;
}
const plans = JSON.parse(readFileSync('fixtures/branch-transfer-write-plans.json', 'utf8').replaceAll('__SCHOOL__', SCHOOL));
const ops = () => plans.scenarios[0].batches[0].ops;

// Fresh world for every test (the move is one-way).
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [SCHOOL, OTHER]) {
      await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      for (const b of ['north', 'south']) await setDoc(doc(d, 'schools', s, 'branches', b), { schoolId: s, name: b, status: 'ACTIVE', ...audit('seed') });
    }
    const users = {
      'bt-admin': { schoolId: SCHOOL, branchId: null, role: 'SCHOOL_ADMIN' },
      'bt-ba-n': { schoolId: SCHOOL, branchId: 'north', role: 'BRANCH_ADMIN' },
      'bt-ba-s': { schoolId: SCHOOL, branchId: 'south', role: 'BRANCH_ADMIN' },
      'bt-both': { schoolId: SCHOOL, branchId: 'north', role: 'BRANCH_ADMIN', branchRoles: { south: 'BRANCH_ADMIN' } },
      'bt-teacher': { schoolId: SCHOOL, branchId: 'north', role: 'TEACHER' },
      'bt-admin-z': { schoolId: OTHER, branchId: null, role: 'SCHOOL_ADMIN' },
      'bt-parent': { schoolId: SCHOOL, branchId: 'north', role: 'PARENT', linkedParentId: 'par-new' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...audit('seed') });
    }
    // the student as the admission flow left it
    await setDoc(doc(d, ...P('north', 'students', 'stu-1')), {
      schoolId: SCHOOL, branchId: 'north', admissionNumber: 'N-001', studentCode: 'STU-STU-1', firstName: 'Anil', lastName: 'Kumar',
      dateOfBirth: Timestamp.fromDate(new Date('2014-05-04')), gender: 'MALE', admissionDate: Timestamp.fromDate(new Date('2020-06-01')),
      status: 'ACTIVE', currentAcademicYearId: 'y1', currentClassId: 'c5', currentSectionId: 'sa', currentRollNumber: '7', ...audit('seed'),
    });
    await setDoc(doc(d, ...P('north', 'students', 'stu-1', 'academicRecords', 'rec-old')), {
      schoolId: SCHOOL, branchId: 'north', studentId: 'stu-1', academicYearId: 'y1', classId: 'c5', sectionId: 'sa',
      startDate: Timestamp.fromDate(new Date('2020-06-01')), status: 'ACTIVE', ...audit('seed'),
    });
    for (const p of ['par-existing', 'par-new']) {
      await setDoc(doc(d, ...P('north', 'students', 'stu-1', 'parentLinks', p)), {
        schoolId: SCHOOL, branchId: 'north', studentId: 'stu-1', parentId: p, relationshipType: 'FATHER', status: 'ACTIVE', canAccessPortal: true, ...audit('seed'),
      });
    }
    await setDoc(doc(d, ...P('north', 'parents', 'par-new')), { schoolId: SCHOOL, branchId: 'north', firstName: 'Ravi', status: 'ACTIVE', linkedUserId: 'user-par', ...audit('seed') });
    await setDoc(doc(d, ...P('south', 'parents', 'par-existing')), { schoolId: SCHOOL, branchId: 'south', firstName: 'Exi', status: 'ACTIVE', ...audit('seed') });
  });
});

function batchOf(db, list) {
  const b = writeBatch(db);
  for (const op of list) {
    const ref = doc(db, ...op.path.split('/'));
    if (op.op === 'set') b.set(ref, decode(op.data));
    else b.update(ref, decode(op.data));
  }
  return b;
}
const run = (uid, list = ops()) => batchOf(as(uid), list).commit();
const without = (suffix) => ops().filter((o) => !o.path.endsWith(suffix));
const patch = (suffix, fn) => ops().map((o) => (o.path.endsWith(suffix) ? { ...o, data: fn(structuredClone(o.data)) } : o));

test('the Dart-written move is accepted for a school admin, as one batch', async () => {
  await assertSucceeds(run('bt-admin'));
  const d = as('bt-admin');
  const moved = (await getDoc(doc(d, ...P('north', 'students', 'stu-1')))).data();
  assert_(moved.status === 'TRANSFERRED' && moved.transferredTo.branchId === 'south', 'old record points forward');
  const fresh = (await getDoc(doc(d, ...P('south', 'students', 'stu-1')))).data();
  assert_(fresh.status === 'ACTIVE' && fresh.transferredFrom.branchId === 'north', 'new record points back');
  assert_((await getDocs(collection(d, 'schools', SCHOOL, 'studentTransfers'))).size === 1, 'one audit entry');
});

function assert_(cond, msg) {
  if (!cond) throw new Error(msg);
}

test('only a school admin may move a student — not branch admins, teachers, parents or another school', async () => {
  for (const uid of ['bt-ba-n', 'bt-ba-s', 'bt-both', 'bt-teacher', 'bt-parent', 'bt-admin-z']) {
    await assertFails(run(uid));
  }
});

test('after the move the family reads the child in the new branch and the old record stays readable', async () => {
  await assertSucceeds(run('bt-admin'));
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), 'users', 'bt-parent'), { name: 'P', email: 'p@example.com', status: 'ACTIVE', schoolId: SCHOOL, branchId: 'north', role: 'PARENT', linkedParentId: 'par-new', ...audit('seed') });
  });
  const d = as('bt-parent');
  await assertSucceeds(getDoc(doc(d, ...P('south', 'students', 'stu-1'))));
  await assertSucceeds(getDoc(doc(d, ...P('south', 'students', 'stu-1', 'parentLinks', 'par-new'))));
  await assertSucceeds(getDoc(doc(d, ...P('south', 'parents', 'par-new'))));
  await assertSucceeds(getDoc(doc(d, ...P('north', 'students', 'stu-1')))); // history stays
});

test('a new-branch record cannot claim a transfer the old record does not confirm', async () => {
  // destination + links only: the source is never marked TRANSFERRED
  const noSource = ops().filter((o) => !(o.path.endsWith('north/students/stu-1') || o.path.includes('academicRecords/rec-old') || o.path.includes('studentTransfers')));
  await assertFails(run('bt-admin', noSource));
  // forged provenance pointing at a student that is not being moved
  await assertFails(run('bt-admin', patch('south/students/stu-1', (d) => ({ ...d, transferredFrom: { ...d.transferredFrom, studentId: 'someone-else' } }))));
  // provenance with extra keys
  await assertFails(run('bt-admin', patch('south/students/stu-1', (d) => ({ ...d, transferredFrom: { ...d.transferredFrom, extra: 1 } }))));
  // a brand-new student claiming to come from the same branch
  await assertFails(run('bt-admin', patch('south/students/stu-1', (d) => ({ ...d, transferredFrom: { ...d.transferredFrom, branchId: 'south' } }))));
});

test('the old record cannot be marked transferred without the matching new record', async () => {
  const noDest = ops().filter((o) => !o.path.includes('south/students/stu-1') && !o.path.includes('south/parents') && !o.path.includes('studentTransfers'));
  await assertFails(run('bt-admin', noDest));
  // pointing at a different student id than the one created
  await assertFails(run('bt-admin', patch('north/students/stu-1', (d) => ({ ...d, transferredTo: { ...d.transferredTo, studentId: 'other' } }))));
  // pointing at the same branch
  await assertFails(run('bt-admin', patch('north/students/stu-1', (d) => ({ ...d, transferredTo: { ...d.transferredTo, branchId: 'north' } }))));
  // status other than TRANSFERRED
  await assertFails(run('bt-admin', patch('north/students/stu-1', (d) => ({ ...d, status: 'LEFT' }))));
});

test('transferredTo is writable once, only by the move; transferredFrom never changes', async () => {
  await assertSucceeds(run('bt-admin'));
  const d = as('bt-admin');
  const upd = (path, data) => writeBatch(d).update(doc(d, ...path), { ...data, updatedAt: serverTimestamp(), updatedBy: 'bt-admin' }).commit();
  await assertFails(upd(P('north', 'students', 'stu-1'), { transferredTo: { branchId: 'south', studentId: 'x', admissionNumber: 'y' } }));
  // a moved student cannot be set ACTIVE again in the old branch (they would be enrolled twice)
  await assertFails(upd(P('north', 'students', 'stu-1'), { status: 'ACTIVE' }));
  await assertFails(upd(P('north', 'students', 'stu-1'), { status: 'LEFT' }));
  // other edits (a correction to the notes) are fine
  await assertSucceeds(upd(P('north', 'students', 'stu-1'), { statusChangeNotes: 'checked' }));
  await assertFails(upd(P('south', 'students', 'stu-1'), { transferredFrom: { branchId: 'north', studentId: 'x', admissionNumber: 'y' } }));
});

test('a student that is not active cannot be moved, and cannot be moved twice', async () => {
  await assertSucceeds(run('bt-admin'));
  await env.withSecurityRulesDisabled(async (c) => {
    // reset the destination so only the source check is exercised
    await (await import('firebase/firestore')).deleteDoc(doc(c.firestore(), ...P('south', 'students', 'stu-1')));
  });
  await assertFails(run('bt-admin'));
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), ...P('north', 'students', 'stu-1')), { status: 'LEFT' }, { merge: true });
  });
  await assertFails(run('bt-admin'));
});

test('an existing record in the new branch is never overwritten by a move', async () => {
  await env.withSecurityRulesDisabled(async (c) => {
    await setDoc(doc(c.firestore(), ...P('south', 'students', 'stu-1')), { schoolId: SCHOOL, branchId: 'south', status: 'ACTIVE', ...audit('seed') });
  });
  await assertFails(run('bt-admin'));
});

test('the audit entry must match the move and cannot be forged, edited or deleted', async () => {
  // audit alone, without a move
  const auditOnly = ops().filter((o) => o.path.includes('studentTransfers'));
  await assertFails(run('bt-admin', auditOnly));
  // audit naming other branches than the move
  await assertFails(run('bt-admin', patch('studentTransfers/tr-1', (d) => ({ ...d, toBranchId: 'north', fromBranchId: 'south' }))));
  // extra / missing fields
  await assertFails(run('bt-admin', patch('studentTransfers/tr-1', (d) => ({ ...d, extra: true }))));
  // a move with no audit entry at all is still allowed by the student rules, but a client
  // cannot write an audit entry on its own for a real, completed move
  await assertSucceeds(run('bt-admin'));
  const d = as('bt-admin');
  await assertFails(setDoc(doc(d, 'schools', SCHOOL, 'studentTransfers', 'late'), {
    schoolId: SCHOOL, studentId: 'stu-1', studentName: 'x', fromBranchId: 'north', toBranchId: 'south', createdAt: serverTimestamp(), createdBy: 'bt-admin',
  }));
  await assertFails(setDoc(doc(d, 'schools', SCHOOL, 'studentTransfers', 'tr-1'), { schoolId: SCHOOL }, { merge: true }));
  await assertFails((await import('firebase/firestore')).deleteDoc(doc(d, 'schools', SCHOOL, 'studentTransfers', 'tr-1')));
  // readable by school admins only
  await assertSucceeds(getDocs(collection(d, 'schools', SCHOOL, 'studentTransfers')));
  await assertFails(getDocs(collection(as('bt-ba-n'), 'schools', SCHOOL, 'studentTransfers')));
});

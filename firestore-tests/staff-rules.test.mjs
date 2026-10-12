// Firestore security-rules tests for Milestone 4 — Staff + Teacher
// management (see ../firestore.rules and
// ../docs/milestone-4-staff-teacher-management.md).
//
// Uses its own school ids (`st-a`, `st-b`) and uids so it can run beside
// rules.test.mjs against the same emulator project without interfering.
//
// Run with: firebase emulators:exec --only firestore,storage "cd firestore-tests && npm test"
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
});

after(async () => {
  await testEnv.cleanup();
});

// Re-assigned per test by seedWorld() so each test gets a fresh tenant and
// never sees another test's assignment slots (the emulator is shared).
let A = 'st-a';
let B = 'st-b';
let worldCounter = 0;
const NORTH = 'north';
const SOUTH = 'south';
const YEAR = 'year-1';
const CLASS5 = 'class-5';
const SEC_A = 'sec-a';
const SEC_B = 'sec-b';
const SEC_OFF = 'sec-off';
const MATH = 'subj-math';
const SCIENCE = 'subj-science'; // exists, but NOT linked to class 5

const branch = (school, b) => ['schools', school, 'branches', b];

async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (context) => fn(context.firestore()));
}
const asUser = (uid) => testEnv.authenticatedContext(uid).firestore();

function userDoc({ schoolId, branchId = null, role, status = 'ACTIVE' }) {
  return {
    schoolId, branchId, name: 'Test User', email: 'user@example.com', role, status,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed',
  };
}

const audit = (uid) => ({
  createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid,
});

function configDoc(schoolId, branchId, { code, name, status = 'ACTIVE', createdBy = 'seed' }) {
  return { schoolId, branchId, name, code, description: null, status, ...audit(createdBy) };
}

function staffDoc({
  schoolId = A, branchId = NORTH, code = 'EMP-0001', departmentId = 'adm', designationId = 'teacher',
  isTeacher = true, userId = null, status = 'ACTIVE', createdBy = 'seed',
}) {
  return {
    schoolId, branchId,
    employeeCode: code, employeeCodeLower: code.toLowerCase(),
    firstName: 'Priya', middleName: null, lastName: 'S',
    displayName: 'Priya S', displayNameLower: 'priya s',
    photoUrl: null, dateOfBirth: new Date('1990-01-01'), gender: 'FEMALE', bloodGroup: null,
    phone: '9999999999', alternatePhone: null, email: null, emailLower: null,
    address: null, city: null, state: null, country: null, postalCode: null,
    joiningDate: new Date('2020-06-01'), employmentType: 'FULL_TIME',
    departmentId, designationId, isTeacher, userId, status,
    statusChangeReason: null, statusChangeDate: null, statusChangeNotes: null,
    ...audit(createdBy),
  };
}

function codeDoc({ schoolId = A, branchId = NORTH, staffId, code, createdBy }) {
  return { schoolId, branchId, staffId, employeeCode: code, createdAt: serverTimestamp(), createdBy };
}

function assignmentDoc({
  schoolId = A, branchId = NORTH, teacherStaffId = 'staff-priya', classId = CLASS5, sectionId = SEC_A,
  subjectId = MATH, isClassTeacher = false, createdBy,
}) {
  return {
    schoolId, branchId, academicYearId: YEAR, teacherStaffId, classId, sectionId,
    subjectId: isClassTeacher ? null : subjectId, isClassTeacher,
    startDate: new Date('2026-06-01'), endDate: null, status: 'ACTIVE', ...audit(createdBy),
  };
}

const slotKey = ({ classId = CLASS5, sectionId = SEC_A, subjectId = MATH, isClassTeacher = false }) =>
  [YEAR, classId, sectionId, isClassTeacher ? 'CLASS_TEACHER' : subjectId].join('__');

function slotDoc({ schoolId = A, branchId = NORTH, assignmentId, teacherStaffId = 'staff-priya', createdBy }) {
  return { schoolId, branchId, assignmentId, teacherStaffId, createdAt: serverTimestamp(), createdBy };
}

/** Creates staff + its code reservation in one batch, as the app does. */
async function createStaff(db, { staffId, code, uid, ...rest }) {
  const schoolId = rest.schoolId ?? A;
  const branchId = rest.branchId ?? NORTH;
  const batch = writeBatch(db);
  batch.set(doc(db, ...branch(schoolId, branchId), 'staff', staffId), staffDoc({ code, createdBy: uid, ...rest }));
  batch.set(doc(db, ...branch(schoolId, branchId), 'staffCodes', code.toLowerCase()), codeDoc({ schoolId, branchId, staffId, code, createdBy: uid }));
  return batch.commit();
}

/** Creates an assignment + its slot in one batch, as the app does. */
async function assign(db, { assignmentId, uid, schoolId = A, branchId = NORTH, ...rest }) {
  const batch = writeBatch(db);
  batch.set(doc(db, ...branch(schoolId, branchId), 'teacherAssignments', assignmentId), assignmentDoc({ schoolId, branchId, createdBy: uid, ...rest }));
  batch.set(
    doc(db, ...branch(schoolId, branchId), 'assignmentSlots', slotKey(rest)),
    slotDoc({ schoolId, branchId, assignmentId, teacherStaffId: rest.teacherStaffId ?? 'staff-priya', createdBy: uid }),
  );
  return batch.commit();
}

/** Seeds both schools, users, config, academic structure and a few staff. */
async function seedWorld() {
  worldCounter += 1;
  A = `st-a-${worldCounter}`;
  B = `st-b-${worldCounter}`;
  await seed(async (db) => {
    for (const s of [A, B]) {
      await setDoc(doc(db, 'schools', s), { name: s, status: 'ACTIVE', ...audit('seed') });
      for (const b of s === A ? [NORTH, SOUTH] : [NORTH]) {
        await setDoc(doc(db, ...branch(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...audit('seed') });
      }
    }
    const users = {
      'stf-admin-a': { schoolId: A, role: 'SCHOOL_ADMIN' },
      'stf-admin-b': { schoolId: B, branchId: NORTH, role: 'SCHOOL_ADMIN' },
      'stf-bradmin-north': { schoolId: A, branchId: NORTH, role: 'BRANCH_ADMIN' },
      'stf-bradmin-south': { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' },
      'stf-teacher-priya': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'stf-teacher-other': { schoolId: A, branchId: NORTH, role: 'TEACHER' },
      'stf-finance-north': { schoolId: A, branchId: NORTH, role: 'FINANCE' },
      'stf-parent-1': { schoolId: A, branchId: NORTH, role: 'PARENT' },
      'stf-user-b': { schoolId: B, branchId: NORTH, role: 'TEACHER' },
    };
    for (const [uid, u] of Object.entries(users)) await setDoc(doc(db, 'users', uid), userDoc(u));

    const n = branch(A, NORTH);
    await setDoc(doc(db, ...n, 'departments', 'adm'), configDoc(A, NORTH, { code: 'ADM', name: 'Administration' }));
    await setDoc(doc(db, ...n, 'departments', 'old'), configDoc(A, NORTH, { code: 'OLD', name: 'Old', status: 'INACTIVE' }));
    await setDoc(doc(db, ...n, 'designations', 'teacher'), configDoc(A, NORTH, { code: 'TEACHER', name: 'Teacher' }));

    const sb = branch(A, SOUTH);
    await setDoc(doc(db, ...sb, 'departments', 'adm'), configDoc(A, SOUTH, { code: 'ADM', name: 'Administration' }));
    await setDoc(doc(db, ...sb, 'designations', 'teacher'), configDoc(A, SOUTH, { code: 'TEACHER', name: 'Teacher' }));

    const cls = [...n, 'academicYears', YEAR, 'classes', CLASS5];
    await setDoc(doc(db, ...n, 'academicYears', YEAR), { schoolId: A, branchId: NORTH, name: '2026-27', status: 'ACTIVE', ...audit('seed') });
    await setDoc(doc(db, ...cls), { schoolId: A, branchId: NORTH, academicYearId: YEAR, name: 'Class 5', status: 'ACTIVE', ...audit('seed') });
    for (const [id, status] of [[SEC_A, 'ACTIVE'], [SEC_B, 'ACTIVE'], [SEC_OFF, 'INACTIVE']]) {
      await setDoc(doc(db, ...cls, 'sections', id), { schoolId: A, branchId: NORTH, academicYearId: YEAR, classId: CLASS5, name: id, status, ...audit('seed') });
    }
    await setDoc(doc(db, ...cls, 'classSubjects', MATH), { schoolId: A, branchId: NORTH, academicYearId: YEAR, classId: CLASS5, subjectName: 'Maths', createdAt: serverTimestamp(), createdBy: 'seed' });

    const mk = async (staffId, code, extra) => {
      await setDoc(doc(db, ...n, 'staff', staffId), staffDoc({ code, ...extra }));
      await setDoc(doc(db, ...n, 'staffCodes', code.toLowerCase()), codeDoc({ staffId, code, createdBy: 'seed' }));
    };
    await mk('staff-priya', 'EMP-0001', { userId: 'stf-teacher-priya' });
    await mk('staff-arun', 'EMP-0002', { userId: null });
    await mk('staff-accountant', 'EMP-0003', { isTeacher: false, designationId: 'teacher' });
    await mk('staff-notice', 'EMP-0004', { status: 'ON_NOTICE' });
    await mk('staff-resigned', 'EMP-0005', { status: 'RESIGNED' });
    await setDoc(doc(db, ...branch(A, SOUTH), 'staff', 'staff-south'), staffDoc({ branchId: SOUTH, code: 'EMP-S1' }));
    await setDoc(doc(db, ...branch(A, SOUTH), 'staffCodes', 'emp-s1'), codeDoc({ branchId: SOUTH, staffId: 'staff-south', code: 'EMP-S1', createdBy: 'seed' }));
  });
}

const staffRef = (db, id, s = A, b = NORTH) => doc(db, ...branch(s, b), 'staff', id);

// ---------------------------------------------------------------------
// Tenant + branch isolation
// ---------------------------------------------------------------------

test('School isolation: School A admin creates/reads School A staff; School B admin is denied both', async () => {
  await seedWorld();
  await assertSucceeds(createStaff(asUser('stf-admin-a'), { staffId: 'new-1', code: 'EMP-0100', uid: 'stf-admin-a' }));
  await assertSucceeds(getDoc(staffRef(asUser('stf-admin-a'), 'new-1')));

  const adminB = asUser('stf-admin-b');
  await assertFails(getDoc(staffRef(adminB, 'staff-priya')));
  await assertFails(getDocs(collection(adminB, ...branch(A, NORTH), 'staff')));
  await assertFails(createStaff(adminB, { staffId: 'evil-1', code: 'EMP-0666', uid: 'stf-admin-b' }));
  await assertFails(updateDoc(staffRef(adminB, 'staff-priya'), { phone: '1', updatedAt: serverTimestamp(), updatedBy: 'stf-admin-b' }));
});

test('School isolation: School B cannot read School A departments, designations or assignments', async () => {
  await seedWorld();
  const userB = asUser('stf-user-b');
  const adminB = asUser('stf-admin-b');
  for (const [col, id] of [['departments', 'adm'], ['designations', 'teacher']]) {
    await assertFails(getDoc(doc(adminB, ...branch(A, NORTH), col, id)));
    await assertFails(getDoc(doc(userB, ...branch(A, NORTH), col, id)));
  }
  await assertFails(getDocs(collection(adminB, ...branch(A, NORTH), 'teacherAssignments')));
});

test('Branch isolation: North branch admin manages North staff; South staff is denied; school admin sees both', async () => {
  await seedWorld();
  const north = asUser('stf-bradmin-north');
  await assertSucceeds(getDoc(staffRef(north, 'staff-priya')));
  await assertSucceeds(createStaff(north, { staffId: 'n-new', code: 'EMP-0200', uid: 'stf-bradmin-north' }));
  await assertFails(getDoc(staffRef(north, 'staff-south', A, SOUTH)));
  await assertFails(createStaff(north, { staffId: 's-new', code: 'EMP-0201', uid: 'stf-bradmin-north', branchId: SOUTH }));
  await assertFails(updateDoc(staffRef(north, 'staff-south', A, SOUTH), { phone: '1', updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north' }));

  const schoolAdmin = asUser('stf-admin-a');
  await assertSucceeds(getDoc(staffRef(schoolAdmin, 'staff-priya')));
  await assertSucceeds(getDoc(staffRef(schoolAdmin, 'staff-south', A, SOUTH)));
});

// ---------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------

test('Parent has no access to staff management of any kind', async () => {
  await seedWorld();
  const parent = asUser('stf-parent-1');
  await assertFails(getDoc(staffRef(parent, 'staff-priya')));
  await assertFails(getDocs(collection(parent, ...branch(A, NORTH), 'staff')));
  await assertFails(getDoc(doc(parent, ...branch(A, NORTH), 'departments', 'adm')));
  await assertFails(getDocs(collection(parent, ...branch(A, NORTH), 'teacherAssignments')));
  await assertFails(createStaff(parent, { staffId: 'p-new', code: 'EMP-0300', uid: 'stf-parent-1' }));
});

test('Teacher: reads ONLY their own staff record, never colleagues\'; cannot write staff at all', async () => {
  await seedWorld();
  const teacher = asUser('stf-teacher-priya');
  await assertSucceeds(getDoc(staffRef(teacher, 'staff-priya')));
  await assertFails(getDoc(staffRef(teacher, 'staff-arun')));
  await assertFails(getDocs(collection(teacher, ...branch(A, NORTH), 'staff')));
  // How the app finds "my staff record":
  const own = await assertSucceeds(getDocs(query(collection(teacher, ...branch(A, NORTH), 'staff'), where('userId', '==', 'stf-teacher-priya'))));
  assert(own.size === 1);

  await assertFails(updateDoc(staffRef(teacher, 'staff-priya'), { phone: '1', updatedAt: serverTimestamp(), updatedBy: 'stf-teacher-priya' }));
  await assertFails(createStaff(teacher, { staffId: 't-new', code: 'EMP-0400', uid: 'stf-teacher-priya' }));
  await assertFails(getDoc(doc(teacher, ...branch(A, NORTH), 'staffCodes', 'emp-0001')));
});

test('Teacher can read departments/designations (to render their profile) but not write them', async () => {
  await seedWorld();
  const teacher = asUser('stf-teacher-priya');
  await assertSucceeds(getDoc(doc(teacher, ...branch(A, NORTH), 'departments', 'adm')));
  await assertSucceeds(getDoc(doc(teacher, ...branch(A, NORTH), 'designations', 'teacher')));
  await assertFails(updateDoc(doc(teacher, ...branch(A, NORTH), 'departments', 'adm'), { name: 'X', updatedAt: serverTimestamp(), updatedBy: 'stf-teacher-priya' }));
  await assertFails(setDoc(doc(teacher, ...branch(A, NORTH), 'departments', 'new'), configDoc(A, NORTH, { code: 'NEW', name: 'N', createdBy: 'stf-teacher-priya' })));
});

test('Finance can read staff in their own branch, but cannot write or open documents', async () => {
  await seedWorld();
  const finance = asUser('stf-finance-north');
  await assertSucceeds(getDoc(staffRef(finance, 'staff-priya')));
  await assertSucceeds(getDocs(collection(finance, ...branch(A, NORTH), 'staff')));
  await assertFails(getDoc(staffRef(finance, 'staff-south', A, SOUTH)));
  await assertFails(updateDoc(staffRef(finance, 'staff-priya'), { phone: '1', updatedAt: serverTimestamp(), updatedBy: 'stf-finance-north' }));
  await assertFails(createStaff(finance, { staffId: 'f-new', code: 'EMP-0500', uid: 'stf-finance-north' }));
  await seed((db) => setDoc(doc(db, ...branch(A, NORTH), 'staff', 'staff-priya', 'documents', 'd1'), { schoolId: A, branchId: NORTH, staffId: 'staff-priya', status: 'ACTIVE' }));
  await assertFails(getDoc(doc(finance, ...branch(A, NORTH), 'staff', 'staff-priya', 'documents', 'd1')));
});

test('Designation is not an authorization input: a staff record titled "Principal" gives no access', async () => {
  await seedWorld();
  await seed(async (db) => {
    await setDoc(doc(db, ...branch(A, NORTH), 'designations', 'principal'), configDoc(A, NORTH, { code: 'PRINCIPAL', name: 'Principal' }));
    await updateDoc(staffRef(db, 'staff-priya'), { designationId: 'principal' });
  });
  const teacher = asUser('stf-teacher-priya'); // role TEACHER, designation Principal
  await assertFails(getDocs(collection(teacher, ...branch(A, NORTH), 'staff')));
  await assertFails(createStaff(teacher, { staffId: 'x', code: 'EMP-0600', uid: 'stf-teacher-priya', designationId: 'principal' }));
});

// ---------------------------------------------------------------------
// Employee code uniqueness
// ---------------------------------------------------------------------

test('Employee codes are unique per branch and case-insensitive; a record needs its reservation', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');

  await assertFails(createStaff(admin, { staffId: 'dup-1', code: 'EMP-0001', uid: 'stf-bradmin-north' })); // exists
  await assertFails(createStaff(admin, { staffId: 'dup-2', code: 'emp-0001', uid: 'stf-bradmin-north' })); // same code, other case

  // Staff without any reservation is refused.
  await assertFails(setDoc(staffRef(admin, 'no-code'), staffDoc({ code: 'EMP-0700', createdBy: 'stf-bradmin-north' })));

  // Reservation pointing at a different staff id is refused.
  const batch = writeBatch(admin);
  batch.set(staffRef(admin, 'mismatch'), staffDoc({ code: 'EMP-0701', createdBy: 'stf-bradmin-north' }));
  batch.set(doc(admin, ...branch(A, NORTH), 'staffCodes', 'emp-0701'), codeDoc({ staffId: 'someone-else', code: 'EMP-0701', createdBy: 'stf-bradmin-north' }));
  await assertFails(batch.commit());

  // Malformed code is refused.
  await assertFails(createStaff(admin, { staffId: 'bad-code', code: 'bad code!', uid: 'stf-bradmin-north' }));

  // The same code in a DIFFERENT branch is allowed (uniqueness is per branch).
  await assertSucceeds(createStaff(asUser('stf-admin-a'), { staffId: 'south-dup', code: 'EMP-0001', uid: 'stf-admin-a', branchId: SOUTH }));
});

test('Changing an employee code moves the reservation atomically; stealing another\'s code is refused', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  const ok = writeBatch(admin);
  ok.update(staffRef(admin, 'staff-arun'), {
    employeeCode: 'EMP-0222', employeeCodeLower: 'emp-0222', updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north',
  });
  ok.delete(doc(admin, ...branch(A, NORTH), 'staffCodes', 'emp-0002'));
  ok.set(doc(admin, ...branch(A, NORTH), 'staffCodes', 'emp-0222'), codeDoc({ staffId: 'staff-arun', code: 'EMP-0222', createdBy: 'stf-bradmin-north' }));
  await assertSucceeds(ok.commit());

  // Changing the code without a reservation is refused.
  await assertFails(updateDoc(staffRef(admin, 'staff-accountant'), {
    employeeCode: 'EMP-0333', employeeCodeLower: 'emp-0333', updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north',
  }));

  // Taking a code another record holds is refused.
  const steal = writeBatch(admin);
  steal.update(staffRef(admin, 'staff-accountant'), {
    employeeCode: 'EMP-0001', employeeCodeLower: 'emp-0001', updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north',
  });
  steal.set(doc(admin, ...branch(A, NORTH), 'staffCodes', 'emp-0001'), codeDoc({ staffId: 'staff-accountant', code: 'EMP-0001', createdBy: 'stf-bradmin-north' }));
  await assertFails(steal.commit());

  // A reservation cannot be released while its staff record still uses the code.
  await assertFails(deleteDoc(doc(admin, ...branch(A, NORTH), 'staffCodes', 'emp-0001')));
});

// ---------------------------------------------------------------------
// Immutable fields, lifecycle, deletes
// ---------------------------------------------------------------------

test('schoolId, branchId, createdAt/createdBy are immutable on staff', async () => {
  await seedWorld();
  const admin = asUser('stf-admin-a');
  const meta = { updatedAt: serverTimestamp(), updatedBy: 'stf-admin-a' };
  await assertFails(updateDoc(staffRef(admin, 'staff-priya'), { schoolId: B, ...meta }));
  await assertFails(updateDoc(staffRef(admin, 'staff-priya'), { branchId: SOUTH, ...meta }));
  await assertFails(updateDoc(staffRef(admin, 'staff-priya'), { createdBy: 'someone', ...meta }));
  await assertFails(updateDoc(staffRef(admin, 'staff-priya'), { createdAt: serverTimestamp(), ...meta }));
  await assertFails(updateDoc(staffRef(admin, 'staff-priya'), { phone: '1', updatedBy: 'forged', updatedAt: serverTimestamp() })); // actor must be the caller
  await assertFails(updateDoc(staffRef(admin, 'staff-priya'), { somethingNew: 1, ...meta })); // unknown field
  await assertSucceeds(updateDoc(staffRef(admin, 'staff-priya'), { phone: '8888888888', ...meta }));
});

test('Staff are never hard-deleted', async () => {
  await seedWorld();
  await assertFails(deleteDoc(staffRef(asUser('stf-admin-a'), 'staff-priya')));
  await assertFails(deleteDoc(doc(asUser('stf-admin-a'), ...branch(A, NORTH), 'departments', 'adm')));
  await assertFails(deleteDoc(doc(asUser('stf-admin-a'), ...branch(A, NORTH), 'designations', 'teacher')));
});

test('Lifecycle: ACTIVE -> ON_NOTICE -> RESIGNED is allowed; a resigned member can never be reactivated', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  const meta = { updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north' };
  await assertSucceeds(updateDoc(staffRef(admin, 'staff-arun'), { status: 'ON_NOTICE', ...meta }));
  await assertSucceeds(updateDoc(staffRef(admin, 'staff-arun'), { status: 'RESIGNED', statusChangeReason: 'moved', ...meta }));
  await assertFails(updateDoc(staffRef(admin, 'staff-arun'), { status: 'ACTIVE', ...meta }));
  await assertFails(updateDoc(staffRef(admin, 'staff-resigned'), { status: 'ACTIVE', ...meta }));
  // Other edits to a resigned record (e.g. correcting a phone number) remain possible.
  await assertSucceeds(updateDoc(staffRef(admin, 'staff-resigned'), { phone: '7777777777', ...meta }));
});

// ---------------------------------------------------------------------
// Departments / designations
// ---------------------------------------------------------------------

test('Departments: id must equal the lower-cased code, codes are unique, and the code is immutable', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  const dept = (id, code) => setDoc(doc(admin, ...branch(A, NORTH), 'departments', id), configDoc(A, NORTH, { code, name: 'Finance', createdBy: 'stf-bradmin-north' }));

  await assertSucceeds(dept('fin', 'FIN'));
  await assertFails(dept('fin', 'FIN')); // duplicate code -> same id
  await assertFails(dept('wrong-id', 'OPS')); // id does not match code
  await assertFails(dept('bad', 'a')); // too short
  await assertFails(dept('has space', 'has space'));

  const meta = { updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north' };
  await assertSucceeds(updateDoc(doc(admin, ...branch(A, NORTH), 'departments', 'fin'), { name: 'Finance & Accounts', status: 'INACTIVE', ...meta }));
  await assertFails(updateDoc(doc(admin, ...branch(A, NORTH), 'departments', 'fin'), { code: 'ACCT', ...meta }));

  // Same code in another branch is a different document.
  await assertSucceeds(setDoc(doc(asUser('stf-bradmin-south'), ...branch(A, SOUTH), 'departments', 'fin'), configDoc(A, SOUTH, { code: 'FIN', name: 'Finance', createdBy: 'stf-bradmin-south' })));
  await assertFails(setDoc(doc(asUser('stf-bradmin-south'), ...branch(A, NORTH), 'departments', 'ops'), configDoc(A, NORTH, { code: 'OPS', name: 'Ops', createdBy: 'stf-bradmin-south' })));
});

test('Designations: codes are unique per branch', async () => {
  await seedWorld();
  const admin = asUser('stf-admin-a');
  const des = (id, code) => setDoc(doc(admin, ...branch(A, NORTH), 'designations', id), configDoc(A, NORTH, { code, name: 'Accountant', createdBy: 'stf-admin-a' }));
  await assertSucceeds(des('accountant', 'ACCOUNTANT'));
  await assertFails(des('accountant', 'ACCOUNTANT'));
  await assertFails(des('Accountant2', 'accountant2')); // id must be the lower-case form
});

test('A staff member can only reference an ACTIVE department and designation of their own branch', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  await assertFails(createStaff(admin, { staffId: 'r1', code: 'EMP-0801', uid: 'stf-bradmin-north', departmentId: 'old' })); // inactive
  await assertFails(createStaff(admin, { staffId: 'r2', code: 'EMP-0802', uid: 'stf-bradmin-north', departmentId: 'ghost' })); // missing
  await assertFails(createStaff(admin, { staffId: 'r3', code: 'EMP-0803', uid: 'stf-bradmin-north', designationId: 'ghost' }));
  await assertSucceeds(createStaff(admin, { staffId: 'r4', code: 'EMP-0804', uid: 'stf-bradmin-north' }));
  const meta = { updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north' };
  await assertFails(updateDoc(staffRef(admin, 'staff-priya'), { departmentId: 'old', ...meta }));
  await assertSucceeds(updateDoc(staffRef(admin, 'staff-priya'), { departmentId: 'adm', ...meta }));
});

test('New staff must start ACTIVE and unlinked', async () => {
  await seedWorld();
  const admin = asUser('stf-admin-a');
  await assertFails(createStaff(admin, { staffId: 's1', code: 'EMP-0901', uid: 'stf-admin-a', status: 'RETIRED' }));
  await assertFails(createStaff(admin, { staffId: 's2', code: 'EMP-0902', uid: 'stf-admin-a', userId: 'stf-teacher-priya' }));
  await assertFails(createStaff(admin, { staffId: 's3', code: 'EMP-0903', uid: 'stf-admin-a', createdBy: 'forged' }));
});

// ---------------------------------------------------------------------
// User-account link
// ---------------------------------------------------------------------

test('Linking an application account: same-school user ok, other-school user refused, unlink ok', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  const meta = { updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north' };
  await assertFails(updateDoc(staffRef(admin, 'staff-arun'), { userId: 'stf-user-b', ...meta }));
  await assertFails(updateDoc(staffRef(admin, 'staff-arun'), { userId: 'does-not-exist', ...meta }));
  await assertSucceeds(updateDoc(staffRef(admin, 'staff-arun'), { userId: 'stf-teacher-other', ...meta }));
  await assertSucceeds(updateDoc(staffRef(admin, 'staff-arun'), { userId: null, ...meta }));
});

// ---------------------------------------------------------------------
// Teacher assignments
// ---------------------------------------------------------------------

test('Assignment: valid subject assignment and class-teacher assignment are created with their slots', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  await assertSucceeds(assign(admin, { assignmentId: 'a1', uid: 'stf-bradmin-north' }));
  await assertSucceeds(assign(admin, { assignmentId: 'a2', uid: 'stf-bradmin-north', isClassTeacher: true }));
  // Same teacher can be class teacher of several sections.
  await assertSucceeds(assign(admin, { assignmentId: 'a3', uid: 'stf-bradmin-north', isClassTeacher: true, sectionId: SEC_B }));
});

test('Assignment is refused for a non-teacher, a non-active member, a missing member or another branch\'s member', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  await assertFails(assign(admin, { assignmentId: 'x1', uid: 'stf-bradmin-north', teacherStaffId: 'staff-accountant' })); // not a teacher
  await assertFails(assign(admin, { assignmentId: 'x2', uid: 'stf-bradmin-north', teacherStaffId: 'staff-notice' })); // ON_NOTICE
  await assertFails(assign(admin, { assignmentId: 'x3', uid: 'stf-bradmin-north', teacherStaffId: 'staff-resigned' }));
  await assertFails(assign(admin, { assignmentId: 'x4', uid: 'stf-bradmin-north', teacherStaffId: 'ghost' }));
  await assertFails(assign(admin, { assignmentId: 'x5', uid: 'stf-bradmin-north', teacherStaffId: 'staff-south' })); // other branch's staff id
});

test('Assignment is refused for a subject not configured for the class, and for a missing or inactive section', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  await assertFails(assign(admin, { assignmentId: 'y1', uid: 'stf-bradmin-north', subjectId: SCIENCE })); // not linked to class 5
  await assertFails(assign(admin, { assignmentId: 'y2', uid: 'stf-bradmin-north', sectionId: SEC_OFF })); // inactive section
  await assertFails(assign(admin, { assignmentId: 'y3', uid: 'stf-bradmin-north', sectionId: 'ghost' }));
  await assertFails(assign(admin, { assignmentId: 'y4', uid: 'stf-bradmin-north', classId: 'ghost-class' }));
});

test('Assignment needs its uniqueness slot, claimed under the right key', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  // No slot at all.
  await assertFails(setDoc(doc(admin, ...branch(A, NORTH), 'teacherAssignments', 'z1'), assignmentDoc({ createdBy: 'stf-bradmin-north' })));
  // Slot under the wrong key.
  const wrong = writeBatch(admin);
  wrong.set(doc(admin, ...branch(A, NORTH), 'teacherAssignments', 'z2'), assignmentDoc({ createdBy: 'stf-bradmin-north' }));
  wrong.set(doc(admin, ...branch(A, NORTH), 'assignmentSlots', 'some__other__key'), slotDoc({ assignmentId: 'z2', createdBy: 'stf-bradmin-north' }));
  await assertFails(wrong.commit());
  // isClassTeacher with a subject, and a subject assignment without one, are malformed.
  const bad = writeBatch(admin);
  bad.set(doc(admin, ...branch(A, NORTH), 'teacherAssignments', 'z3'), { ...assignmentDoc({ createdBy: 'stf-bradmin-north', isClassTeacher: true }), subjectId: MATH });
  bad.set(doc(admin, ...branch(A, NORTH), 'assignmentSlots', slotKey({ isClassTeacher: true })), slotDoc({ assignmentId: 'z3', createdBy: 'stf-bradmin-north' }));
  await assertFails(bad.commit());
  const noSubject = writeBatch(admin);
  noSubject.set(doc(admin, ...branch(A, NORTH), 'teacherAssignments', 'z4'), { ...assignmentDoc({ createdBy: 'stf-bradmin-north' }), subjectId: null });
  noSubject.set(doc(admin, ...branch(A, NORTH), 'assignmentSlots', slotKey({ subjectId: 'null' })), slotDoc({ assignmentId: 'z4', createdBy: 'stf-bradmin-north' }));
  await assertFails(noSubject.commit());
});

test('Duplicate prevention: one class teacher per section, one teacher per section+subject', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  await assertSucceeds(assign(admin, { assignmentId: 'd1', uid: 'stf-bradmin-north', isClassTeacher: true, sectionId: SEC_B }));
  // Another teacher as class teacher of the same section.
  await assertFails(assign(admin, { assignmentId: 'd2', uid: 'stf-bradmin-north', isClassTeacher: true, sectionId: SEC_B, teacherStaffId: 'staff-arun' }));
  // The same teacher twice.
  await assertFails(assign(admin, { assignmentId: 'd3', uid: 'stf-bradmin-north', isClassTeacher: true, sectionId: SEC_B }));

  await assertSucceeds(assign(admin, { assignmentId: 'd4', uid: 'stf-bradmin-north' }));
  await assertFails(assign(admin, { assignmentId: 'd5', uid: 'stf-bradmin-north', teacherStaffId: 'staff-arun' })); // other teacher, same section+subject
  await assertFails(assign(admin, { assignmentId: 'd6', uid: 'stf-bradmin-north' })); // same teacher, same section+subject
  // A class teacher may also be a subject teacher in the same section (different slots).
  await assertSucceeds(assign(admin, { assignmentId: 'd7', uid: 'stf-bradmin-north', isClassTeacher: true }));
});

test('Assignment authority: teachers, finance and parents cannot create; other branches and schools cannot', async () => {
  await seedWorld();
  await assertFails(assign(asUser('stf-teacher-priya'), { assignmentId: 'u1', uid: 'stf-teacher-priya' }));
  await assertFails(assign(asUser('stf-finance-north'), { assignmentId: 'u2', uid: 'stf-finance-north' }));
  await assertFails(assign(asUser('stf-parent-1'), { assignmentId: 'u3', uid: 'stf-parent-1' }));
  await assertFails(assign(asUser('stf-bradmin-south'), { assignmentId: 'u4', uid: 'stf-bradmin-south' }));
  await assertFails(assign(asUser('stf-admin-b'), { assignmentId: 'u5', uid: 'stf-admin-b' }));
  await assertSucceeds(assign(asUser('stf-admin-a'), { assignmentId: 'u6', uid: 'stf-admin-a' }));
});

test('Ending an assignment keeps the row, frees the slot, and a successor can then take it (history)', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  await assertSucceeds(assign(admin, { assignmentId: 'h1', uid: 'stf-bradmin-north' }));

  const aRef = doc(admin, ...branch(A, NORTH), 'teacherAssignments', 'h1');
  const sRef = doc(admin, ...branch(A, NORTH), 'assignmentSlots', slotKey({}));
  const endFields = { status: 'ENDED', endDate: new Date('2026-12-01'), updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north' };

  // Ending without releasing the slot is refused, and so is releasing the slot without ending.
  await assertFails(updateDoc(aRef, endFields));
  await assertFails(deleteDoc(sRef));

  const end = writeBatch(admin);
  end.update(aRef, endFields);
  end.delete(sRef);
  await assertSucceeds(end.commit());

  // History is retained and cannot be deleted or revived.
  const kept = await assertSucceeds(getDoc(aRef));
  assert(kept.data().status === 'ENDED');
  await assertFails(deleteDoc(aRef));
  await assertFails(updateDoc(aRef, { status: 'ACTIVE', updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north' }));
  await assertFails(updateDoc(aRef, { teacherStaffId: 'staff-arun', updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north' }));

  // A different teacher can now hold the freed slot; the old row still exists.
  await assertSucceeds(assign(admin, { assignmentId: 'h2', uid: 'stf-bradmin-north', teacherStaffId: 'staff-arun' }));
  assert((await getDoc(aRef)).exists());
});

test('Year-aware history: the same teacher can hold different classes in different academic years', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  await seed(async (db) => {
    const n = branch(A, NORTH);
    const y2 = [...n, 'academicYears', 'year-2'];
    await setDoc(doc(db, ...y2), { schoolId: A, branchId: NORTH, name: '2027-28', status: 'ACTIVE', ...audit('seed') });
    await setDoc(doc(db, ...y2, 'classes', 'class-6'), { schoolId: A, branchId: NORTH, academicYearId: 'year-2', name: 'Class 6', status: 'ACTIVE', ...audit('seed') });
    await setDoc(doc(db, ...y2, 'classes', 'class-6', 'sections', 'sec-a'), { schoolId: A, branchId: NORTH, name: 'A', status: 'ACTIVE', ...audit('seed') });
    await setDoc(doc(db, ...y2, 'classes', 'class-6', 'classSubjects', MATH), { schoolId: A, branchId: NORTH, createdAt: serverTimestamp(), createdBy: 'seed' });
  });
  await assertSucceeds(assign(admin, { assignmentId: 'yr1', uid: 'stf-bradmin-north' }));

  const next = writeBatch(admin);
  const data = { ...assignmentDoc({ createdBy: 'stf-bradmin-north', classId: 'class-6' }), academicYearId: 'year-2' };
  next.set(doc(admin, ...branch(A, NORTH), 'teacherAssignments', 'yr2'), data);
  next.set(doc(admin, ...branch(A, NORTH), 'assignmentSlots', ['year-2', 'class-6', SEC_A, MATH].join('__')), slotDoc({ assignmentId: 'yr2', createdBy: 'stf-bradmin-north' }));
  await assertSucceeds(next.commit());

  const both = await getDocs(query(collection(admin, ...branch(A, NORTH), 'teacherAssignments'), where('teacherStaffId', '==', 'staff-priya')));
  assert(both.size >= 2);
});

test('A teacher reads their OWN assignments (by teacherStaffId) but not a colleague\'s', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  await assertSucceeds(assign(admin, { assignmentId: 'r-priya', uid: 'stf-bradmin-north' }));
  await assertSucceeds(assign(admin, { assignmentId: 'r-arun', uid: 'stf-bradmin-north', teacherStaffId: 'staff-arun', sectionId: SEC_B }));

  const priya = asUser('stf-teacher-priya');
  await assertSucceeds(getDoc(doc(priya, ...branch(A, NORTH), 'teacherAssignments', 'r-priya')));
  await assertSucceeds(getDocs(query(collection(priya, ...branch(A, NORTH), 'teacherAssignments'), where('teacherStaffId', '==', 'staff-priya'))));
  await assertFails(getDoc(doc(priya, ...branch(A, NORTH), 'teacherAssignments', 'r-arun')));
  await assertFails(getDocs(query(collection(priya, ...branch(A, NORTH), 'teacherAssignments'), where('teacherStaffId', '==', 'staff-arun'))));
  await assertFails(getDocs(collection(priya, ...branch(A, NORTH), 'teacherAssignments'))); // unfiltered list
  // And never writes.
  await assertFails(updateDoc(doc(priya, ...branch(A, NORTH), 'teacherAssignments', 'r-priya'), { status: 'ENDED', endDate: new Date(), updatedAt: serverTimestamp(), updatedBy: 'stf-teacher-priya' }));
  await assertFails(getDoc(doc(priya, ...branch(A, NORTH), 'assignmentSlots', slotKey({}))));
});

// ---------------------------------------------------------------------
// Documents
// ---------------------------------------------------------------------

test('Staff documents: managers create/soft-remove metadata for their own branch only; paths are pinned', async () => {
  await seedWorld();
  const admin = asUser('stf-bradmin-north');
  const docRef = (id, b = NORTH, s = 'staff-priya') => doc(admin, ...branch(A, b), 'staff', s, 'documents', id);
  const meta = (path) => ({
    schoolId: A, branchId: NORTH, staffId: 'staff-priya', type: 'ID_PROOF', title: 'Passport', fileName: 'p.pdf',
    contentType: 'application/pdf', sizeBytes: 10, storagePath: path, status: 'ACTIVE', ...audit('stf-bradmin-north'),
  });
  const good = `schools/${A}/branches/${NORTH}/staff/staff-priya/documents/d1/p.pdf`;

  await assertSucceeds(setDoc(docRef('d1'), meta(good)));
  await assertSucceeds(getDoc(docRef('d1')));
  await assertFails(setDoc(docRef('d2'), meta(`schools/${B}/branches/${NORTH}/staff/x/documents/d2/p.pdf`))); // someone else's storage path
  await assertFails(setDoc(docRef('d3'), { ...meta(good), staffId: 'staff-arun' })); // staffId mismatch

  const meta2 = { updatedAt: serverTimestamp(), updatedBy: 'stf-bradmin-north' };
  await assertSucceeds(updateDoc(docRef('d1'), { status: 'REMOVED', ...meta2 }));
  await assertFails(updateDoc(docRef('d1'), { storagePath: 'elsewhere', ...meta2 }));
  await assertFails(deleteDoc(docRef('d1')));

  await assertFails(getDoc(doc(asUser('stf-bradmin-south'), ...branch(A, NORTH), 'staff', 'staff-priya', 'documents', 'd1')));
  await assertFails(getDoc(doc(asUser('stf-teacher-priya'), ...branch(A, NORTH), 'staff', 'staff-priya', 'documents', 'd1'))); // even their own
});

function assert(condition) {
  if (!condition) throw new Error('assertion failed');
}

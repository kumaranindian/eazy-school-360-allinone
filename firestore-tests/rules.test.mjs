// Firestore security-rules tests, run against the local Firestore
// emulator — the actual demonstration of tenant isolation required by
// Milestone 1 (see ../SECURITY_ARCHITECTURE.md and
// ../FIRESTORE_ARCHITECTURE.md for the rules design these exercise).
//
// Run with: firebase emulators:exec --only firestore "npm test" (from
// this directory) — see ../DEVELOPMENT_GUIDE.md for the full command.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, writeBatch } from 'firebase/firestore';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: {
      rules: readFileSync('../firestore.rules', 'utf8'),
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

const SCHOOL_A = 'school-a';
const SCHOOL_B = 'school-b';
const MAIN = 'main';

function schoolDoc(schoolId, createdBy) {
  return {
    name: `School ${schoolId}`,
    email: `${schoolId}@example.com`,
    status: 'ACTIVE',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function branchDoc(schoolId, createdBy) {
  return {
    schoolId,
    name: 'Main Branch',
    status: 'ACTIVE',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function userDoc({ schoolId, branchId = null, role, status = 'ACTIVE', createdBy }) {
  return {
    schoolId,
    branchId,
    name: 'Test User',
    email: 'user@example.com',
    role,
    status,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy: createdBy ?? 'seed',
    updatedBy: createdBy ?? 'seed',
  };
}

/** Seeds fixture data by bypassing rules entirely (test setup only). */
async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await fn(context.firestore());
  });
}

function asUser(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function anonymous() {
  return testEnv.unauthenticatedContext().firestore();
}

// ---------------------------------------------------------------------
// Default-deny
// ---------------------------------------------------------------------

test('an unauthenticated caller cannot read anything', async () => {
  await seed(async (db) => setDoc(doc(db, 'schools', SCHOOL_A), schoolDoc(SCHOOL_A, 'seed')));
  await assertFails(getDoc(doc(anonymous(), 'schools', SCHOOL_A)));
});

test('an unmatched collection path default-denies even a signed-in, profiled caller', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users', 'teacher-a'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }));
  });
  await assertFails(getDoc(doc(asUser('teacher-a'), 'somethingNotCovered', 'x')));
});

// ---------------------------------------------------------------------
// Tenant isolation — the core requirement (brief §7, §9)
// ---------------------------------------------------------------------

test('School A user: School A read -> ALLOW; School B read -> DENY', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_A), schoolDoc(SCHOOL_A, 'seed'));
    await setDoc(doc(db, 'schools', SCHOOL_B), schoolDoc(SCHOOL_B, 'seed'));
    await setDoc(doc(db, 'users', 'teacher-a'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }));
  });

  const teacherA = asUser('teacher-a');
  await assertSucceeds(getDoc(doc(teacherA, 'schools', SCHOOL_A)));
  await assertFails(getDoc(doc(teacherA, 'schools', SCHOOL_B)));
});

test('Teacher cannot read another school\'s branch data', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_B), schoolDoc(SCHOOL_B, 'seed'));
    await setDoc(doc(db, 'schools', SCHOOL_B, 'branches', MAIN), branchDoc(SCHOOL_B, 'seed'));
    await setDoc(doc(db, 'users', 'teacher-a'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }));
  });

  await assertFails(getDoc(doc(asUser('teacher-a'), 'schools', SCHOOL_B, 'branches', MAIN)));
});

test('Parent cannot read another parent\'s profile, even in the same school', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'users', 'parent-1'),
      userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT' }),
    );
    await setDoc(
      doc(db, 'users', 'parent-2'),
      userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT' }),
    );
  });

  await assertFails(getDoc(doc(asUser('parent-1'), 'users', 'parent-2')));
  await assertSucceeds(getDoc(doc(asUser('parent-1'), 'users', 'parent-1')));
});

test('a disabled account is denied, even for its own school\'s data', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_A), schoolDoc(SCHOOL_A, 'seed'));
    await setDoc(
      doc(db, 'users', 'disabled-1'),
      userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER', status: 'DISABLED' }),
    );
  });

  const disabled = asUser('disabled-1');
  await assertFails(getDoc(doc(disabled, 'schools', SCHOOL_A)));
  // Even reading their own profile fails once the self-read fallback's
  // `isActiveCaller()` branches don't apply — but the literal
  // `request.auth.uid == userId` clause still allows self-read by design
  // (so the client can discover *why* it's disabled); confirm that's the
  // ONLY thing still available to them.
  await assertSucceeds(getDoc(doc(disabled, 'users', 'disabled-1')));
});

// ---------------------------------------------------------------------
// School creation (brief §12) — the two-phase self-signup write
// ---------------------------------------------------------------------

test('a brand-new account can self-signup: school + admin profile + default branch in ONE batch', async () => {
  const newAdmin = asUser('new-admin');
  const batch = writeBatch(newAdmin);
  batch.set(doc(newAdmin, 'schools', 'school-new'), schoolDoc('school-new', 'new-admin'));
  batch.set(
    doc(newAdmin, 'users', 'new-admin'),
    userDoc({ schoolId: 'school-new', branchId: MAIN, role: 'SCHOOL_ADMIN', createdBy: 'new-admin' }),
  );
  batch.set(doc(newAdmin, 'schools', 'school-new', 'branches', MAIN), branchDoc('school-new', 'new-admin'));
  await assertSucceeds(batch.commit());
});

test('self-signup writes made separately (not as one batch) are rejected', async () => {
  const loner = asUser('loner');
  await assertFails(setDoc(doc(loner, 'schools', 'school-loner'), schoolDoc('school-loner', 'loner')));
});

test('an account that already has a profile cannot self-signup a second school', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'users', 'existing-admin'),
      userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'SCHOOL_ADMIN' }),
    );
  });

  const existingAdmin = asUser('existing-admin');
  await assertFails(setDoc(doc(existingAdmin, 'schools', 'school-second'), schoolDoc('school-second', 'existing-admin')));
});

test('a school admin can add a branch to their own school, not to another school', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_A), schoolDoc(SCHOOL_A, 'seed'));
    await setDoc(doc(db, 'schools', SCHOOL_B), schoolDoc(SCHOOL_B, 'seed'));
    await setDoc(
      doc(db, 'users', 'admin-a'),
      userDoc({ schoolId: SCHOOL_A, branchId: null, role: 'SCHOOL_ADMIN' }),
    );
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(setDoc(doc(adminA, 'schools', SCHOOL_A, 'branches', 'north'), branchDoc(SCHOOL_A, 'admin-a')));
  await assertFails(setDoc(doc(adminA, 'schools', SCHOOL_B, 'branches', 'north'), branchDoc(SCHOOL_B, 'admin-a')));
});

// ---------------------------------------------------------------------
// Role/authorization integrity on /users updates
// ---------------------------------------------------------------------

test('a user cannot change their own role, schoolId, or status', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'users', 'teacher-a'),
      userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }),
    );
  });

  const teacherA = asUser('teacher-a');
  await assertFails(updateDoc(doc(teacherA, 'users', 'teacher-a'), { role: 'PLATFORM_ADMIN' }));
  await assertFails(updateDoc(doc(teacherA, 'users', 'teacher-a'), { schoolId: SCHOOL_B }));
  await assertFails(updateDoc(doc(teacherA, 'users', 'teacher-a'), { status: 'DISABLED' }));
  await assertSucceeds(updateDoc(doc(teacherA, 'users', 'teacher-a'), { name: 'New Name', updatedAt: serverTimestamp(), updatedBy: 'teacher-a' }));
});

test('a school admin can promote a subordinate but never to SCHOOL_ADMIN/PLATFORM_ADMIN, and never across schools', async () => {
  await seed(async (db) => {
    await setDoc(
      doc(db, 'users', 'admin-a'),
      userDoc({ schoolId: SCHOOL_A, branchId: null, role: 'SCHOOL_ADMIN' }),
    );
    await setDoc(
      doc(db, 'users', 'teacher-a'),
      userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }),
    );
    await setDoc(
      doc(db, 'users', 'teacher-b'),
      userDoc({ schoolId: SCHOOL_B, branchId: MAIN, role: 'TEACHER' }),
    );
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    updateDoc(doc(adminA, 'users', 'teacher-a'), {
      role: 'BRANCH_ADMIN',
      updatedAt: serverTimestamp(),
      updatedBy: 'admin-a',
    }),
  );
  await assertFails(
    updateDoc(doc(adminA, 'users', 'teacher-a'), {
      role: 'SCHOOL_ADMIN',
      updatedAt: serverTimestamp(),
      updatedBy: 'admin-a',
    }),
  );
  // Cross-school: admin-a has no authority over School B's users at all.
  await assertFails(
    updateDoc(doc(adminA, 'users', 'teacher-b'), {
      role: 'BRANCH_ADMIN',
      updatedAt: serverTimestamp(),
      updatedBy: 'admin-a',
    }),
  );
});

test('an admin cannot provision a subordinate with an escalated role', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_A), schoolDoc(SCHOOL_A, 'seed'));
    await setDoc(
      doc(db, 'users', 'admin-a'),
      userDoc({ schoolId: SCHOOL_A, branchId: null, role: 'SCHOOL_ADMIN' }),
    );
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    setDoc(
      doc(adminA, 'users', 'new-teacher'),
      userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER', createdBy: 'admin-a' }),
    ),
  );
  await assertFails(
    setDoc(
      doc(adminA, 'users', 'new-platform-admin'),
      userDoc({ schoolId: SCHOOL_A, branchId: null, role: 'PLATFORM_ADMIN', createdBy: 'admin-a' }),
    ),
  );
});

// ---------------------------------------------------------------------
// Validation-audit attack tests (added during M0/M1 validation)
// ---------------------------------------------------------------------

test('ATTACK: a fresh account cannot self-claim SCHOOL_ADMIN of an EXISTING school', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_B), schoolDoc(SCHOOL_B, 'owner-b'));
  });
  const attacker = asUser('attacker');
  await assertFails(
    setDoc(
      doc(attacker, 'users', 'attacker'),
      userDoc({ schoolId: SCHOOL_B, branchId: MAIN, role: 'SCHOOL_ADMIN', createdBy: 'attacker' }),
    ),
  );
});

test('ATTACK: a fresh account cannot create a profile pointing at a school it never created', async () => {
  const attacker = asUser('attacker-2');
  await assertFails(
    setDoc(
      doc(attacker, 'users', 'attacker-2'),
      userDoc({ schoolId: 'phantom-school', branchId: MAIN, role: 'SCHOOL_ADMIN', createdBy: 'attacker-2' }),
    ),
  );
});

test('Scenario 2: School A admin cannot create a document with schoolId = School B', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_B), schoolDoc(SCHOOL_B, 'seed'));
    await setDoc(doc(db, 'users', 'admin-a'), userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  });
  const adminA = asUser('admin-a');
  await assertFails(
    setDoc(doc(adminA, 'users', 'planted'), userDoc({ schoolId: SCHOOL_B, branchId: MAIN, role: 'TEACHER', createdBy: 'admin-a' })),
  );
  await assertFails(setDoc(doc(adminA, 'schools', SCHOOL_B, 'branches', 'x'), branchDoc(SCHOOL_B, 'admin-a')));
});

test('Scenario 3: School A admin cannot update a School B document', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_B), schoolDoc(SCHOOL_B, 'seed'));
    await setDoc(doc(db, 'schools', SCHOOL_B, 'branches', MAIN), branchDoc(SCHOOL_B, 'seed'));
    await setDoc(doc(db, 'users', 'admin-a'), userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  });
  const adminA = asUser('admin-a');
  await assertFails(updateDoc(doc(adminA, 'schools', SCHOOL_B), { name: 'pwned', updatedAt: serverTimestamp(), updatedBy: 'admin-a' }));
  await assertFails(updateDoc(doc(adminA, 'schools', SCHOOL_B, 'branches', MAIN), { name: 'pwned', updatedAt: serverTimestamp(), updatedBy: 'admin-a' }));
});

test('a school admin cannot change their own school status (e.g. lift a platform suspension)', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_A), { ...schoolDoc(SCHOOL_A, 'seed'), status: 'SUSPENDED' });
    await setDoc(doc(db, 'users', 'admin-a'), userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
  });
  const adminA = asUser('admin-a');
  await assertFails(updateDoc(doc(adminA, 'schools', SCHOOL_A), { status: 'ACTIVE', updatedAt: serverTimestamp(), updatedBy: 'admin-a' }));
  await assertSucceeds(updateDoc(doc(adminA, 'schools', SCHOOL_A), { name: 'Renamed', updatedAt: serverTimestamp(), updatedBy: 'admin-a' }));
});

test('audit fields cannot be forged on create or update', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_A), schoolDoc(SCHOOL_A, 'seed'));
    await setDoc(doc(db, 'users', 'admin-a'), userDoc({ schoolId: SCHOOL_A, role: 'SCHOOL_ADMIN' }));
    await setDoc(doc(db, 'users', 'teacher-a'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }));
  });
  const adminA = asUser('admin-a');
  // createdBy impersonating someone else
  await assertFails(setDoc(doc(adminA, 'schools', SCHOOL_A, 'branches', 'b2'), branchDoc(SCHOOL_A, 'someone-else')));
  // client-supplied (backdated) timestamp instead of server time
  await assertFails(setDoc(doc(adminA, 'schools', SCHOOL_A, 'branches', 'b3'), {
    ...branchDoc(SCHOOL_A, 'admin-a'),
    createdAt: new Date('2000-01-01'),
  }));
  // updatedBy impersonation on self-update
  await assertFails(updateDoc(doc(asUser('teacher-a'), 'users', 'teacher-a'), {
    name: 'x', updatedAt: serverTimestamp(), updatedBy: 'admin-a',
  }));
});

test('a branch admin can manage users only within their own branch, never escalate', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'users', 'badmin'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'BRANCH_ADMIN' }));
    await setDoc(doc(db, 'users', 'teacher-main'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }));
    await setDoc(doc(db, 'users', 'teacher-north'), userDoc({ schoolId: SCHOOL_A, branchId: 'north', role: 'TEACHER' }));
  });
  const badmin = asUser('badmin');
  await assertSucceeds(setDoc(doc(badmin, 'users', 'new-parent'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT', createdBy: 'badmin' })));
  await assertFails(setDoc(doc(badmin, 'users', 'new-parent-n'), userDoc({ schoolId: SCHOOL_A, branchId: 'north', role: 'PARENT', createdBy: 'badmin' })));
  await assertFails(setDoc(doc(badmin, 'users', 'new-badmin'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'BRANCH_ADMIN', createdBy: 'badmin' })));
  await assertSucceeds(updateDoc(doc(badmin, 'users', 'teacher-main'), { status: 'DISABLED', updatedAt: serverTimestamp(), updatedBy: 'badmin' }));
  await assertFails(updateDoc(doc(badmin, 'users', 'teacher-north'), { status: 'DISABLED', updatedAt: serverTimestamp(), updatedBy: 'badmin' }));
});

test('an INVITED (not yet active) account is denied tenant data, like a disabled one', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_A), schoolDoc(SCHOOL_A, 'seed'));
    await setDoc(doc(db, 'users', 'invited-1'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER', status: 'INVITED' }));
  });
  await assertFails(getDoc(doc(asUser('invited-1'), 'schools', SCHOOL_A)));
});

// ---------------------------------------------------------------------
// Milestone 2: academic setup (academic years, classes, sections,
// subjects, class-subject links, holidays, working days/settings)
// ---------------------------------------------------------------------

function academicYearDoc({ schoolId, branchId, name = '2026-2027', status = 'ACTIVE', createdBy }) {
  return {
    schoolId,
    branchId,
    name,
    startDate: new Date('2026-06-01'),
    endDate: new Date('2027-04-30'),
    status,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function classDoc({ schoolId, branchId, academicYearId, name = 'Class 5', displayOrder = 0, status = 'ACTIVE', createdBy }) {
  return {
    schoolId,
    branchId,
    academicYearId,
    name,
    code: name.replace(/\s/g, '').toUpperCase(),
    displayOrder,
    status,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function sectionDoc({ schoolId, branchId, academicYearId, classId, name = 'A', status = 'ACTIVE', createdBy }) {
  return {
    schoolId,
    branchId,
    academicYearId,
    classId,
    name,
    capacity: 40,
    status,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function subjectDoc({ schoolId, branchId, academicYearId, name = 'Mathematics', type = 'CORE', status = 'ACTIVE', createdBy }) {
  return {
    schoolId,
    branchId,
    academicYearId,
    name,
    code: name.toUpperCase(),
    shortName: name.slice(0, 4),
    type,
    displayOrder: 0,
    status,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function classSubjectDoc({ schoolId, branchId, academicYearId, classId, createdBy }) {
  return {
    schoolId,
    branchId,
    academicYearId,
    classId,
    subjectName: 'Mathematics',
    subjectCode: 'MATH',
    subjectType: 'CORE',
    createdAt: serverTimestamp(),
    createdBy,
  };
}

function holidayDoc({ schoolId, branchId, academicYearId, date = new Date('2026-10-02'), status = 'ACTIVE', createdBy }) {
  return {
    schoolId,
    branchId,
    academicYearId,
    date,
    name: 'Gandhi Jayanti',
    type: 'PUBLIC',
    description: '',
    status,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function workingDaysDoc({ schoolId, branchId, updatedBy }) {
  return {
    schoolId,
    branchId,
    isWorkingDay: {
      MONDAY: true, TUESDAY: true, WEDNESDAY: true, THURSDAY: true, FRIDAY: true, SATURDAY: false, SUNDAY: false,
    },
    updatedAt: serverTimestamp(),
    updatedBy,
  };
}

async function seedFullStructure(db, { schoolId, branchId, adminUid }) {
  await setDoc(doc(db, 'schools', schoolId), schoolDoc(schoolId, adminUid));
  await setDoc(doc(db, 'schools', schoolId, 'branches', branchId), branchDoc(schoolId, adminUid));
  await setDoc(doc(db, 'users', adminUid), userDoc({ schoolId, branchId, role: 'SCHOOL_ADMIN' }));
  const yearId = 'year-1';
  await setDoc(
    doc(db, 'schools', schoolId, 'branches', branchId, 'academicYears', yearId),
    academicYearDoc({ schoolId, branchId, createdBy: adminUid }),
  );
  return { yearId };
}

test('School A admin can manage their own academic years; School B admin is denied', async () => {
  await seed(async (db) => {
    await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    await setDoc(doc(db, 'users', 'admin-b'), userDoc({ schoolId: SCHOOL_B, branchId: MAIN, role: 'SCHOOL_ADMIN' }));
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    setDoc(
      doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', 'year-2'),
      academicYearDoc({ schoolId: SCHOOL_A, branchId: MAIN, name: '2027-2028', createdBy: 'admin-a' }),
    ),
  );

  const adminB = asUser('admin-b');
  await assertFails(
    setDoc(
      doc(adminB, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', 'year-3'),
      academicYearDoc({ schoolId: SCHOOL_A, branchId: MAIN, name: 'hijack', createdBy: 'admin-b' }),
    ),
  );
  await assertFails(getDoc(doc(adminB, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', 'year-1')));
});

test('teacher can READ classes/sections/subjects/holidays in their own branch but cannot write', async () => {
  let yearId;
  await seed(async (db) => {
    const result = await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    yearId = result.yearId;
    await setDoc(doc(db, 'users', 'teacher-a'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }));
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5'),
      classDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, createdBy: 'admin-a' }),
    );
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'subjects', 'math'),
      subjectDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, createdBy: 'admin-a' }),
    );
  });

  const teacherA = asUser('teacher-a');
  await assertSucceeds(getDoc(doc(teacherA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5')));
  await assertSucceeds(getDoc(doc(teacherA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'subjects', 'math')));
  await assertFails(
    setDoc(
      doc(teacherA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-6'),
      classDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, name: 'Class 6', createdBy: 'teacher-a' }),
    ),
  );
  await assertFails(
    updateDoc(doc(teacherA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5'), {
      name: 'Hacked', updatedAt: serverTimestamp(), updatedBy: 'teacher-a',
    }),
  );
});

test('parent has NO access to academic configuration, even read', async () => {
  let yearId;
  await seed(async (db) => {
    const result = await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    yearId = result.yearId;
    await setDoc(doc(db, 'users', 'parent-a'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT' }));
  });

  const parentA = asUser('parent-a');
  await assertFails(getDoc(doc(parentA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId)));
});

test('a teacher assigned to Branch North cannot read Branch South academic data in the same school', async () => {
  let yearId;
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_A), schoolDoc(SCHOOL_A, 'admin-a'));
    await setDoc(doc(db, 'schools', SCHOOL_A, 'branches', 'north'), branchDoc(SCHOOL_A, 'admin-a'));
    await setDoc(doc(db, 'schools', SCHOOL_A, 'branches', 'south'), branchDoc(SCHOOL_A, 'admin-a'));
    await setDoc(doc(db, 'users', 'admin-a'), userDoc({ schoolId: SCHOOL_A, branchId: 'north', role: 'SCHOOL_ADMIN' }));
    await setDoc(doc(db, 'users', 'teacher-north'), userDoc({ schoolId: SCHOOL_A, branchId: 'north', role: 'TEACHER' }));
    yearId = 'year-1';
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', 'south', 'academicYears', yearId),
      academicYearDoc({ schoolId: SCHOOL_A, branchId: 'south', createdBy: 'admin-a' }),
    );
  });

  const teacherNorth = asUser('teacher-north');
  await assertFails(getDoc(doc(teacherNorth, 'schools', SCHOOL_A, 'branches', 'south', 'academicYears', yearId)));
});

test('sections and class-subject links respect the same tenant/role rules as their parent class', async () => {
  let yearId;
  await seed(async (db) => {
    const result = await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    yearId = result.yearId;
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5'),
      classDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, createdBy: 'admin-a' }),
    );
    await setDoc(doc(db, 'users', 'admin-b'), userDoc({ schoolId: SCHOOL_B, branchId: MAIN, role: 'SCHOOL_ADMIN' }));
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    setDoc(
      doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5', 'sections', 'A'),
      sectionDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, classId: 'class-5', createdBy: 'admin-a' }),
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5', 'classSubjects', 'math'),
      classSubjectDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, classId: 'class-5', createdBy: 'admin-a' }),
    ),
  );

  const adminB = asUser('admin-b');
  await assertFails(
    setDoc(
      doc(adminB, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5', 'sections', 'B'),
      sectionDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, classId: 'class-5', name: 'B', createdBy: 'admin-b' }),
    ),
  );
  await assertFails(
    getDoc(doc(adminB, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5', 'classSubjects', 'math')),
  );
});

test('a class-subject link cannot be edited in place, only created or deleted', async () => {
  let yearId;
  await seed(async (db) => {
    const result = await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    yearId = result.yearId;
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5'),
      classDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, createdBy: 'admin-a' }),
    );
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5', 'classSubjects', 'math'),
      classSubjectDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, classId: 'class-5', createdBy: 'admin-a' }),
    );
  });

  const adminA = asUser('admin-a');
  await assertFails(
    updateDoc(doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5', 'classSubjects', 'math'), {
      subjectName: 'Changed',
    }),
  );
  await assertSucceeds(
    deleteDoc(doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'classes', 'class-5', 'classSubjects', 'math')),
  );
});

test('holidays: School A admin cannot write into School B\'s calendar', async () => {
  let yearId;
  await seed(async (db) => {
    const result = await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    yearId = result.yearId;
    const resultB = await seedFullStructure(db, { schoolId: SCHOOL_B, branchId: MAIN, adminUid: 'admin-b' });
    void resultB;
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    setDoc(
      doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'academicYears', yearId, 'holidays', 'h1'),
      holidayDoc({ schoolId: SCHOOL_A, branchId: MAIN, academicYearId: yearId, createdBy: 'admin-a' }),
    ),
  );
  await assertFails(
    setDoc(
      doc(adminA, 'schools', SCHOOL_B, 'branches', MAIN, 'academicYears', 'year-1', 'holidays', 'h2'),
      holidayDoc({ schoolId: SCHOOL_B, branchId: MAIN, academicYearId: 'year-1', createdBy: 'admin-a' }),
    ),
  );
});

test('working-days settings: only an admin of that branch can write it', async () => {
  await seed(async (db) => {
    await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    await setDoc(doc(db, 'users', 'teacher-a'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }));
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    setDoc(
      doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'settings', 'workingDays'),
      workingDaysDoc({ schoolId: SCHOOL_A, branchId: MAIN, updatedBy: 'admin-a' }),
    ),
  );

  const teacherA = asUser('teacher-a');
  await assertSucceeds(getDoc(doc(teacherA, 'schools', SCHOOL_A, 'branches', MAIN, 'settings', 'workingDays')));
  await assertFails(
    setDoc(
      doc(teacherA, 'schools', SCHOOL_A, 'branches', MAIN, 'settings', 'workingDays'),
      workingDaysDoc({ schoolId: SCHOOL_A, branchId: MAIN, updatedBy: 'teacher-a' }),
    ),
  );
});

// ---------------------------------------------------------------------
// Student + Parent management (Milestone 3)
// ---------------------------------------------------------------------

function studentDoc({ schoolId, branchId, admissionNumber = 'ADM-2026-001', status = 'ACTIVE', createdBy }) {
  return {
    schoolId,
    branchId,
    admissionNumber,
    studentCode: 'STU-00000001',
    firstName: 'Arun',
    middleName: null,
    lastName: 'Kumar',
    displayName: 'Arun Kumar',
    displayNameLower: 'arun kumar',
    dateOfBirth: new Date('2015-04-10'),
    gender: 'MALE',
    bloodGroup: null,
    photoUrl: null,
    email: null,
    phone: null,
    addressLine1: null,
    addressLine2: null,
    city: null,
    state: null,
    country: null,
    postalCode: null,
    admissionDate: new Date('2026-06-01'),
    status,
    statusChangeReason: null,
    statusChangeDate: null,
    statusChangeNotes: null,
    currentAcademicYearId: null,
    currentClassId: null,
    currentSectionId: null,
    currentRollNumber: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function academicRecordDoc({ schoolId, branchId, studentId, academicYearId, classId = 'class-5', sectionId = 'section-a', status = 'ACTIVE', createdBy }) {
  return {
    studentId,
    schoolId,
    branchId,
    academicYearId,
    classId,
    sectionId,
    rollNumber: '12',
    startDate: new Date('2026-06-01'),
    endDate: null,
    status,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function parentDoc({ schoolId, branchId, status = 'ACTIVE', createdBy }) {
  return {
    schoolId,
    branchId,
    firstName: 'Rekha',
    middleName: null,
    lastName: 'Kumar',
    displayName: 'Rekha Kumar',
    displayNameLower: 'rekha kumar',
    phone: '9999999999',
    alternatePhone: null,
    email: null,
    occupation: null,
    photoUrl: null,
    addressLine1: null,
    addressLine2: null,
    city: null,
    state: null,
    country: null,
    postalCode: null,
    status,
    linkedUserId: null,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

function parentLinkDoc({ schoolId, branchId, studentId, parentId, isPrimary = true, isEmergencyContact = true, canAccessPortal = false, status = 'ACTIVE', createdBy }) {
  return {
    schoolId,
    branchId,
    studentId,
    parentId,
    relationshipType: 'MOTHER',
    isPrimary,
    isEmergencyContact,
    canAccessPortal,
    status,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    createdBy,
    updatedBy: createdBy,
  };
}

test('School A admin can create a student in their own school; School B admin is denied', async () => {
  await seed(async (db) => {
    await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    await setDoc(doc(db, 'users', 'admin-b'), userDoc({ schoolId: SCHOOL_B, branchId: MAIN, role: 'SCHOOL_ADMIN' }));
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    setDoc(
      doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1'),
      studentDoc({ schoolId: SCHOOL_A, branchId: MAIN, createdBy: 'admin-a' }),
    ),
  );

  const adminB = asUser('admin-b');
  await assertFails(
    setDoc(
      doc(adminB, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-2'),
      studentDoc({ schoolId: SCHOOL_A, branchId: MAIN, createdBy: 'admin-b' }),
    ),
  );
  await assertFails(getDoc(doc(adminB, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1')));
});

test('a teacher can READ a student in their own branch but cannot create or update one', async () => {
  await seed(async (db) => {
    await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    await setDoc(doc(db, 'users', 'teacher-a'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'TEACHER' }));
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1'),
      studentDoc({ schoolId: SCHOOL_A, branchId: MAIN, createdBy: 'admin-a' }),
    );
  });

  const teacherA = asUser('teacher-a');
  await assertSucceeds(getDoc(doc(teacherA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1')));
  await assertFails(
    setDoc(
      doc(teacherA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-2'),
      studentDoc({ schoolId: SCHOOL_A, branchId: MAIN, createdBy: 'teacher-a' }),
    ),
  );
  await assertFails(
    updateDoc(doc(teacherA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1'), {
      status: 'LEFT', updatedAt: serverTimestamp(), updatedBy: 'teacher-a',
    }),
  );
});

test('a branch admin of Branch North cannot read or write a student in Branch South, same school', async () => {
  await seed(async (db) => {
    await setDoc(doc(db, 'schools', SCHOOL_A), schoolDoc(SCHOOL_A, 'admin-a'));
    await setDoc(doc(db, 'schools', SCHOOL_A, 'branches', 'north'), branchDoc(SCHOOL_A, 'admin-a'));
    await setDoc(doc(db, 'schools', SCHOOL_A, 'branches', 'south'), branchDoc(SCHOOL_A, 'admin-a'));
    await setDoc(doc(db, 'users', 'branch-admin-north'), userDoc({ schoolId: SCHOOL_A, branchId: 'north', role: 'BRANCH_ADMIN' }));
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', 'south', 'students', 'student-1'),
      studentDoc({ schoolId: SCHOOL_A, branchId: 'south', createdBy: 'admin-a' }),
    );
  });

  const branchAdminNorth = asUser('branch-admin-north');
  await assertFails(getDoc(doc(branchAdminNorth, 'schools', SCHOOL_A, 'branches', 'south', 'students', 'student-1')));
  await assertFails(
    setDoc(
      doc(branchAdminNorth, 'schools', SCHOOL_A, 'branches', 'south', 'students', 'student-2'),
      studentDoc({ schoolId: SCHOOL_A, branchId: 'south', createdBy: 'branch-admin-north' }),
    ),
  );
});

test('academic records: admin can create/close them; a placement change never edits classId/sectionId in place', async () => {
  let yearId;
  await seed(async (db) => {
    const result = await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    yearId = result.yearId;
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1'),
      studentDoc({ schoolId: SCHOOL_A, branchId: MAIN, createdBy: 'admin-a' }),
    );
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    setDoc(
      doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1', 'academicRecords', 'record-1'),
      academicRecordDoc({ schoolId: SCHOOL_A, branchId: MAIN, studentId: 'student-1', academicYearId: yearId, createdBy: 'admin-a' }),
    ),
  );
  // Closing a record (status/endDate only) is allowed...
  await assertSucceeds(
    updateDoc(doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1', 'academicRecords', 'record-1'), {
      status: 'COMPLETED', endDate: serverTimestamp(), updatedAt: serverTimestamp(), updatedBy: 'admin-a',
    }),
  );
  // ...but editing the placement itself (classId) in place is not — a
  // transfer must create a NEW record instead (brief §6).
  await assertFails(
    updateDoc(doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1', 'academicRecords', 'record-1'), {
      classId: 'class-6', updatedAt: serverTimestamp(), updatedBy: 'admin-a',
    }),
  );
});

test('parentLinks: admin can create/update; a parent can read ONLY their own link, never another parent\'s', async () => {
  await seed(async (db) => {
    await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1'),
      studentDoc({ schoolId: SCHOOL_A, branchId: MAIN, createdBy: 'admin-a' }),
    );
    await setDoc(
      doc(db, 'users', 'parent-mother'),
      { ...userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT' }), linkedParentId: 'parent-1' },
    );
    await setDoc(
      doc(db, 'users', 'parent-unrelated'),
      { ...userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT' }), linkedParentId: 'parent-2' },
    );
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    setDoc(
      doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1', 'parentLinks', 'parent-1'),
      parentLinkDoc({ schoolId: SCHOOL_A, branchId: MAIN, studentId: 'student-1', parentId: 'parent-1', createdBy: 'admin-a' }),
    ),
  );
  await assertSucceeds(
    updateDoc(doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1', 'parentLinks', 'parent-1'), {
      canAccessPortal: true, updatedAt: serverTimestamp(), updatedBy: 'admin-a',
    }),
  );

  await assertSucceeds(getDoc(doc(asUser('parent-mother'), 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1', 'parentLinks', 'parent-1')));
  await assertFails(getDoc(doc(asUser('parent-unrelated'), 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1', 'parentLinks', 'parent-1')));
});

test('Parent A -> own child ALLOW; Parent A -> child of Parent B DENY (brief §38)', async () => {
  await seed(async (db) => {
    await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-own'),
      studentDoc({ schoolId: SCHOOL_A, branchId: MAIN, admissionNumber: 'ADM-2026-001', createdBy: 'admin-a' }),
    );
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-other'),
      studentDoc({ schoolId: SCHOOL_A, branchId: MAIN, admissionNumber: 'ADM-2026-002', createdBy: 'admin-a' }),
    );
    // Parent A's own, ACTIVE, portal-enabled link to their own child.
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-own', 'parentLinks', 'parent-a'),
      parentLinkDoc({ schoolId: SCHOOL_A, branchId: MAIN, studentId: 'student-own', parentId: 'parent-a', canAccessPortal: true, createdBy: 'admin-a' }),
    );
    // A different parent's link to the OTHER student — proves Parent A
    // cannot read it just by knowing the student id.
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-other', 'parentLinks', 'parent-b'),
      parentLinkDoc({ schoolId: SCHOOL_A, branchId: MAIN, studentId: 'student-other', parentId: 'parent-b', canAccessPortal: true, createdBy: 'admin-a' }),
    );
    await setDoc(
      doc(db, 'users', 'parent-a-uid'),
      { ...userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT' }), linkedParentId: 'parent-a' },
    );
  });

  const parentA = asUser('parent-a-uid');
  await assertSucceeds(getDoc(doc(parentA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-own')));
  await assertFails(getDoc(doc(parentA, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-other')));
});

test('a parent whose link has canAccessPortal=false is denied, even though the link itself exists and is ACTIVE', async () => {
  await seed(async (db) => {
    await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1'),
      studentDoc({ schoolId: SCHOOL_A, branchId: MAIN, createdBy: 'admin-a' }),
    );
    await setDoc(
      doc(db, 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1', 'parentLinks', 'parent-1'),
      parentLinkDoc({ schoolId: SCHOOL_A, branchId: MAIN, studentId: 'student-1', parentId: 'parent-1', canAccessPortal: false, createdBy: 'admin-a' }),
    );
    await setDoc(
      doc(db, 'users', 'parent-1-uid'),
      { ...userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT' }), linkedParentId: 'parent-1' },
    );
  });

  await assertFails(getDoc(doc(asUser('parent-1-uid'), 'schools', SCHOOL_A, 'branches', MAIN, 'students', 'student-1')));
});

test('parents collection: School A admin can create/update; School B admin is denied; a parent can read only their own record', async () => {
  await seed(async (db) => {
    await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    await setDoc(doc(db, 'users', 'admin-b'), userDoc({ schoolId: SCHOOL_B, branchId: MAIN, role: 'SCHOOL_ADMIN' }));
    await setDoc(
      doc(db, 'users', 'parent-1-uid'),
      { ...userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT' }), linkedParentId: 'parent-1' },
    );
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    setDoc(
      doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'parents', 'parent-1'),
      parentDoc({ schoolId: SCHOOL_A, branchId: MAIN, createdBy: 'admin-a' }),
    ),
  );
  await assertSucceeds(
    updateDoc(doc(adminA, 'schools', SCHOOL_A, 'branches', MAIN, 'parents', 'parent-1'), {
      phone: '8888888888', updatedAt: serverTimestamp(), updatedBy: 'admin-a',
    }),
  );

  const adminB = asUser('admin-b');
  await assertFails(
    setDoc(
      doc(adminB, 'schools', SCHOOL_A, 'branches', MAIN, 'parents', 'parent-2'),
      parentDoc({ schoolId: SCHOOL_A, branchId: MAIN, createdBy: 'admin-b' }),
    ),
  );

  await assertSucceeds(getDoc(doc(asUser('parent-1-uid'), 'schools', SCHOOL_A, 'branches', MAIN, 'parents', 'parent-1')));
});

test('a school admin granting portal access writes linkedParentId on /users, but cannot also change the user\'s role in the same write', async () => {
  await seed(async (db) => {
    await seedFullStructure(db, { schoolId: SCHOOL_A, branchId: MAIN, adminUid: 'admin-a' });
    await setDoc(doc(db, 'users', 'parent-1-uid'), userDoc({ schoolId: SCHOOL_A, branchId: MAIN, role: 'PARENT' }));
  });

  const adminA = asUser('admin-a');
  await assertSucceeds(
    updateDoc(doc(adminA, 'users', 'parent-1-uid'), {
      linkedParentId: 'parent-1', updatedAt: serverTimestamp(), updatedBy: 'admin-a',
    }),
  );
  await assertFails(
    updateDoc(doc(adminA, 'users', 'parent-1-uid'), {
      linkedParentId: 'parent-1', role: 'SCHOOL_ADMIN', updatedAt: serverTimestamp(), updatedBy: 'admin-a',
    }),
  );
});

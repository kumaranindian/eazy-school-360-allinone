// Milestone 12 — generic tenant-isolation sweep.
//
// Rather than hand-picking collections, this reads the rules file itself and
// attacks EVERY branch-level collection (anything declared directly under
// `match /branches/{branchId}`): a document is seeded in School A / North, and
// each foreign actor then tries to get, list, create, update and delete.
// A new collection added by a later milestone is covered automatically.
//
// Foreign actors: signed-out; every role of another school; every role of
// another branch of the same school. All operations must be refused. The only
// reads that may succeed are listed in ALLOWED_CROSS_BRANCH_READS with the
// reason, and each must stay branch-bound for writes.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, limit, query, serverTimestamp, setDoc, updateDoc, deleteDoc } from 'firebase/firestore';

const rules = readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8');
// Branch-level collections are declared with exactly eight spaces of indentation.
// Collections are discovered from the indented SOURCE (branch-level matches sit at
// 8 spaces); the ruleset under test may be the minified build (RULES_FILE).
const source = readFileSync('../firestore.rules', 'utf8');
const COLLECTIONS = [...source.matchAll(/^ {8}match \/([A-Za-z]+)\/\{[A-Za-z]+\} \{/gm)].map((m) => m[1]);
const UNIQUE = [...new Set(COLLECTIONS)];

const A = 'sw-a';
const B = 'sw-b';
const NORTH = 'north';
const SOUTH = 'south';

// Note: an announcement addressed to ALL is school-wide on purpose, so the
// "visible" seed uses a branch-scoped audience.
// Same-school, other-branch reads that are intentional (documented).
// leaveTypes: school-wide configuration (names of leave types, no personal
//   data) that parents and staff of every branch pick from.
// (Milestone 12A closed F-SEC-3: parents are now tied to their children's
// sections through the parentAccess index, so schedules, homework,
// examinations and class announcements are no longer allowed here.)
const ALLOWED_CROSS_BRANCH_READS = new Set(['leaveTypes']);

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules },
  });
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
    for (const s of [A, B]) {
      await setDoc(doc(db, 'schools', s), { name: s, status: 'ACTIVE', ...base });
    }
    await setDoc(doc(db, 'schools', A, 'branches', NORTH), { schoolId: A, name: NORTH, status: 'ACTIVE', ...base });
    await setDoc(doc(db, 'schools', A, 'branches', SOUTH), { schoolId: A, name: SOUTH, status: 'ACTIVE', ...base });
    await setDoc(doc(db, 'schools', B, 'branches', NORTH), { schoolId: B, name: NORTH, status: 'ACTIVE', ...base });
    const users = {
      'sw-b-admin': { schoolId: B, branchId: null, role: 'SCHOOL_ADMIN' },
      'sw-b-branch': { schoolId: B, branchId: NORTH, role: 'BRANCH_ADMIN' },
      'sw-b-teacher': { schoolId: B, branchId: NORTH, role: 'TEACHER' },
      'sw-b-finance': { schoolId: B, branchId: NORTH, role: 'FINANCE' },
      'sw-b-parent': { schoolId: B, branchId: NORTH, role: 'PARENT', linkedParentId: 'par-b' },
      'sw-s-branch': { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' },
      'sw-s-teacher': { schoolId: A, branchId: SOUTH, role: 'TEACHER' },
      'sw-s-finance': { schoolId: A, branchId: SOUTH, role: 'FINANCE' },
      'sw-s-parent': { schoolId: A, branchId: SOUTH, role: 'PARENT', linkedParentId: 'par-s' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(db, 'users', uid), { name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    for (const name of UNIQUE) {
      const common = { schoolId: A, branchId: NORTH, studentId: 'x', parentUserId: 'nobody', participants: ['nobody'], recipientUserId: 'nobody', ...base };
      await setDoc(doc(db, 'schools', A, 'branches', NORTH, name, 'seed-doc'), { ...common, status: 'ACTIVE', audience: 'USER' });
      // A "visible" variant: the flags that make a document readable to a wider
      // audience (published results, live timetable, broadcast notices ...).
      await setDoc(doc(db, 'schools', A, 'branches', NORTH, name, 'seed-pub'), {
        ...common, status: 'PUBLISHED', live: true, audience: 'BRANCH', audienceKind: 'BRANCH', published: true, flagged: false,
      });
    }
  });
});
after(async () => testEnv.cleanup());

const ACTORS = {
  'signed out': () => testEnv.unauthenticatedContext().firestore(),
  'other-school SCHOOL_ADMIN': () => testEnv.authenticatedContext('sw-b-admin').firestore(),
  'other-school BRANCH_ADMIN': () => testEnv.authenticatedContext('sw-b-branch').firestore(),
  'other-school TEACHER': () => testEnv.authenticatedContext('sw-b-teacher').firestore(),
  'other-school FINANCE': () => testEnv.authenticatedContext('sw-b-finance').firestore(),
  'other-school PARENT': () => testEnv.authenticatedContext('sw-b-parent').firestore(),
  'other-branch BRANCH_ADMIN': () => testEnv.authenticatedContext('sw-s-branch').firestore(),
  'other-branch TEACHER': () => testEnv.authenticatedContext('sw-s-teacher').firestore(),
  'other-branch FINANCE': () => testEnv.authenticatedContext('sw-s-finance').firestore(),
  'other-branch PARENT': () => testEnv.authenticatedContext('sw-s-parent').firestore(),
};

const settled = async (p) => {
  try { await p; return true; } catch { return false; }
};

test('the sweep actually covers the collections declared in the rules', () => {
  // Guards against the regex silently matching nothing after a rules refactor.
  for (const expected of ['students', 'invoices', 'payments', 'leaveApplications', 'homeworkSubmissions', 'conversations', 'marksEntries', 'notifications']) {
    if (!UNIQUE.includes(expected)) throw new Error(`collection ${expected} not found by the sweep`);
  }
  if (UNIQUE.length < 50) throw new Error(`only ${UNIQUE.length} collections found`);
});

for (const [actorName, make] of Object.entries(ACTORS)) {
  test(`${actorName}: no read, list, create, update or delete in any branch collection of School A / North`, async () => {
    const db = make();
    const leaks = [];
    for (const name of UNIQUE) {
      const path = ['schools', A, 'branches', NORTH, name];
      const checks = {
        get: () => getDoc(doc(db, ...path, 'seed-doc')),
        getVisible: () => getDoc(doc(db, ...path, 'seed-pub')),
        list: () => getDocs(query(collection(db, ...path), limit(1))),
        create: () => setDoc(doc(db, ...path, `sweep-${actorName.replace(/\W/g, '')}`), { schoolId: A, branchId: NORTH, status: 'ACTIVE', createdAt: serverTimestamp() }),
        update: () => updateDoc(doc(db, ...path, 'seed-doc'), { status: 'DISABLED', updatedAt: serverTimestamp() }),
        delete: () => deleteDoc(doc(db, ...path, 'seed-doc')),
      };
      for (const [op, run] of Object.entries(checks)) {
        const isRead = op === 'get' || op === 'getVisible' || op === 'list';
        if (isRead && ALLOWED_CROSS_BRANCH_READS.has(name) && actorName.startsWith('other-branch')) continue;
        if (await settled(run())) leaks.push(`${name}.${op}`);
      }
    }
    if (leaks.length) throw new Error(`${actorName} was allowed: ${leaks.join(', ')}`);
  });
}

// Milestone 12 — Storage tenant sweep: objects under every Storage path
// pattern of School A / North must be unreadable, unwritable and undeletable
// by signed-out users, any role of another school, and any role of another
// branch of the same school. (Guessing a path never grants access.)
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

const A = 'ss-a';
const B = 'ss-b';
const N = 'north';
const S = 'south';
const base = `schools/${A}/branches/${N}`;
// One concrete object per rule in storage.rules.
const OBJECTS = [
  `schools/${A}/logo`,
  `${base}/students/s1/photo`,
  `${base}/parents/p1/photo`,
  `${base}/staff/st1/photo`,
  `${base}/staff/st1/documents/d1/file.pdf`,
  `${base}/leaveDocs/u1/app1/note.pdf`,
  `${base}/homework/h1/files/sheet.pdf`,
  `${base}/homework/h1/submissions/s1/work.pdf`,
  `${base}/announcements/a1/files/notice.pdf`,
  `${base}/conversations/cv1/files/msg.pdf`,
];

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
    storage: { rules: readFileSync('../storage.rules', 'utf8') },
  });
  await env.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const audit = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
    for (const [uid, u] of Object.entries({
      'ss-b-admin': { schoolId: B, branchId: null, role: 'SCHOOL_ADMIN' },
      'ss-b-teacher': { schoolId: B, branchId: N, role: 'TEACHER' },
      'ss-b-parent': { schoolId: B, branchId: N, role: 'PARENT', linkedParentId: 'pb' },
      'ss-s-admin': { schoolId: A, branchId: S, role: 'BRANCH_ADMIN' },
      'ss-s-teacher': { schoolId: A, branchId: S, role: 'TEACHER' },
      'ss-s-parent': { schoolId: A, branchId: S, role: 'PARENT', linkedParentId: 'ps' },
    })) {
      await setDoc(doc(db, 'users', uid), { name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...audit });
    }
    await setDoc(doc(db, 'schools', A, 'branches', N, 'conversations', 'cv1'), {
      schoolId: A, branchId: N, participants: ['nobody'], status: 'OPEN', ...audit,
    });
    const st = c.storage();
    for (const path of OBJECTS) {
      await uploadBytes(ref(st, path), new Uint8Array([1, 2, 3]), { contentType: 'application/pdf' });
    }
  });
});
after(async () => env.cleanup());

const ok = async (p) => { try { await p; return true; } catch { return false; } };

const ACTORS = {
  'signed out': () => env.unauthenticatedContext().storage(),
  'other-school SCHOOL_ADMIN': () => env.authenticatedContext('ss-b-admin').storage(),
  'other-school TEACHER': () => env.authenticatedContext('ss-b-teacher').storage(),
  'other-school PARENT': () => env.authenticatedContext('ss-b-parent').storage(),
  'other-branch BRANCH_ADMIN': () => env.authenticatedContext('ss-s-admin').storage(),
  'other-branch TEACHER': () => env.authenticatedContext('ss-s-teacher').storage(),
  'other-branch PARENT': () => env.authenticatedContext('ss-s-parent').storage(),
};

// Same-school, other-branch reads that are intentional: the school logo is
// shown to every member of the school.
const SCHOOL_WIDE = new Set([`schools/${A}/logo`]);

for (const [actor, make] of Object.entries(ACTORS)) {
  test(`${actor}: cannot read, overwrite, add or delete any School A / North object`, async () => {
    const st = make();
    const leaks = [];
    for (const path of OBJECTS) {
      const sameSchoolActor = actor.startsWith('other-branch');
      if (!(sameSchoolActor && SCHOOL_WIDE.has(path))) {
        if (await ok(getBytes(ref(st, path)))) leaks.push(`read ${path}`);
      }
      const dir = path.slice(0, path.lastIndexOf('/'));
      if (await ok(uploadBytes(ref(st, `${dir}/intruder.pdf`), new Uint8Array([9]), { contentType: 'application/pdf' }))) leaks.push(`add ${dir}`);
      if (await ok(uploadBytes(ref(st, path), new Uint8Array([9]), { contentType: 'application/pdf' }))) leaks.push(`overwrite ${path}`);
      if (await ok(deleteObject(ref(st, path)))) leaks.push(`delete ${path}`);
    }
    if (leaks.length) throw new Error(`${actor} was allowed: ${leaks.join('; ')}`);
  });
}

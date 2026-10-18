// Storage rules tests for Milestone 9 — homework, submission and announcement
// files (see ../storage.rules). Own ids so it runs next to the other suites.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytes, getBytes, deleteObject } from 'firebase/storage';

let testEnv;
before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
    storage: { rules: readFileSync(process.env.STORAGE_RULES_FILE || '../storage.rules', 'utf8') },
  });
});
after(async () => testEnv.cleanup());

const A = 'hst-a';
const B = 'hst-b';
const NORTH = 'north';
const SOUTH = 'south';
const stamp = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const storageFor = (uid) => testEnv.authenticatedContext(uid).storage();
const BYTES = new Uint8Array([1, 2, 3, 4]);
const PDF = { contentType: 'application/pdf' };

const hwFile = (f = 'a.pdf', hw = 'hw1', b = NORTH, s = A) => `schools/${s}/branches/${b}/homework/${hw}/files/${f}`;
const subFile = (student = 'hst-stu1', f = 'a.pdf', hw = 'hw1') => `schools/${A}/branches/${NORTH}/homework/${hw}/submissions/${student}/${f}`;
const annFile = (f = 'a.pdf', id = 'an1') => `schools/${A}/branches/${NORTH}/announcements/${id}/files/${f}`;

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const user = (uid, o) => setDoc(doc(db, 'users', uid), { branchId: NORTH, name: 'T', email: 't@x.com', status: 'ACTIVE', linkedParentId: null, ...o, ...stamp });
    await user('hst-admin', { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' });
    await user('hst-br-north', { schoolId: A, role: 'BRANCH_ADMIN' });
    await user('hst-br-south', { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' });
    await user('hst-t1', { schoolId: A, role: 'TEACHER' });
    await user('hst-t2', { schoolId: A, role: 'TEACHER' });
    await user('hst-t-south', { schoolId: A, branchId: SOUTH, role: 'TEACHER' });
    await user('hst-p1', { schoolId: A, role: 'PARENT', linkedParentId: 'par1' });
    await user('hst-p2', { schoolId: A, role: 'PARENT', linkedParentId: 'par2' });
    await user('hst-admin-b', { schoolId: B, role: 'SCHOOL_ADMIN' });
    await user('hst-p-off', { schoolId: A, role: 'PARENT', linkedParentId: 'par-off' });
    const n = ['schools', A, 'branches', NORTH];
    await setDoc(doc(db, ...n, 'homework', 'hw1'), { ...stamp, status: 'PUBLISHED', createdBy: 'hst-t1', teacherStaffId: 'st1' });
    await setDoc(doc(db, ...n, 'homework', 'hwd'), { ...stamp, status: 'DRAFT', createdBy: 'hst-t1', teacherStaffId: 'st1' });
    await setDoc(doc(db, ...n, 'students', 'hst-stu1', 'parentLinks', 'par1'), { status: 'ACTIVE', canAccessPortal: true, ...stamp });
    await setDoc(doc(db, ...n, 'students', 'hst-stu1', 'parentLinks', 'par-off'), { status: 'INACTIVE', canAccessPortal: true, ...stamp });
    await setDoc(doc(db, ...n, 'announcements', 'an1'), { status: 'PUBLISHED', authorId: 'hst-t1', ...stamp });
    await setDoc(doc(db, ...n, 'announcements', 'and'), { status: 'DRAFT', authorId: 'hst-t1', ...stamp });
  });
}

test('homework files: the creating teacher or an admin uploads; create-only; types and size enforced', async () => {
  await seed();
  await assertSucceeds(uploadBytes(ref(storageFor('hst-t1'), hwFile('a.pdf')), BYTES, PDF));
  // no overwrite, no delete
  await assertFails(uploadBytes(ref(storageFor('hst-t1'), hwFile('a.pdf')), BYTES, PDF));
  await assertFails(deleteObject(ref(storageFor('hst-t1'), hwFile('a.pdf'))));
  await assertFails(uploadBytes(ref(storageFor('hst-admin'), hwFile('a.pdf')), BYTES, PDF));
  // another teacher, a parent, other branch, other school
  for (const uid of ['hst-t2', 'hst-p1', 'hst-t-south', 'hst-admin-b', 'hst-br-south']) {
    await assertFails(uploadBytes(ref(storageFor(uid), hwFile('b.pdf')), BYTES, PDF));
  }
  await assertSucceeds(uploadBytes(ref(storageFor('hst-br-north'), hwFile('c.pdf')), BYTES, PDF));
  // type / size
  await assertFails(uploadBytes(ref(storageFor('hst-t1'), hwFile('x.exe')), BYTES, { contentType: 'application/x-msdownload' }));
  await assertFails(uploadBytes(ref(storageFor('hst-t1'), hwFile('x.html')), BYTES, { contentType: 'text/html' }));
  await assertFails(uploadBytes(ref(storageFor('hst-t1'), hwFile('big.pdf')), new Uint8Array(10 * 1024 * 1024 + 1), PDF));
  await assertSucceeds(uploadBytes(ref(storageFor('hst-t1'), hwFile('ok.png')), BYTES, { contentType: 'image/png' }));
});

test('homework files: published ones are readable by branch teachers and parents; drafts only by author/admin', async () => {
  await seed();
  await assertSucceeds(uploadBytes(ref(storageFor('hst-t1'), hwFile('pub.pdf', 'hw1')), BYTES, PDF));
  await assertSucceeds(uploadBytes(ref(storageFor('hst-t1'), hwFile('d.pdf', 'hwd')), BYTES, PDF));
  for (const uid of ['hst-t1', 'hst-t2', 'hst-p1', 'hst-br-north', 'hst-admin']) {
    await assertSucceeds(getBytes(ref(storageFor(uid), hwFile('pub.pdf', 'hw1'))));
  }
  for (const uid of ['hst-t-south', 'hst-admin-b']) await assertFails(getBytes(ref(storageFor(uid), hwFile('pub.pdf', 'hw1'))));
  await assertSucceeds(getBytes(ref(storageFor('hst-t1'), hwFile('d.pdf', 'hwd'))));
  await assertSucceeds(getBytes(ref(storageFor('hst-admin'), hwFile('d.pdf', 'hwd'))));
  for (const uid of ['hst-t2', 'hst-p1']) await assertFails(getBytes(ref(storageFor(uid), hwFile('d.pdf', 'hwd'))));
});

test('submission files: only a LINKED parent writes under their child; create-only; teacher/parent isolation on read', async () => {
  await seed();
  await assertSucceeds(uploadBytes(ref(storageFor('hst-p1'), subFile('hst-stu1', 'work.pdf')), BYTES, PDF));
  await assertFails(uploadBytes(ref(storageFor('hst-p1'), subFile('hst-stu1', 'work.pdf')), BYTES, PDF)); // overwrite
  await assertFails(deleteObject(ref(storageFor('hst-p1'), subFile('hst-stu1', 'work.pdf'))));
  // another parent, a teacher, an admin, other tenant cannot upload as the student
  for (const uid of ['hst-p2', 'hst-t1', 'hst-br-north', 'hst-admin-b']) {
    await assertFails(uploadBytes(ref(storageFor(uid), subFile('hst-stu1', 'x.pdf')), BYTES, PDF));
  }
  // a parent whose link is not ACTIVE (even if portal access was set) cannot
  await assertFails(uploadBytes(ref(storageFor('hst-p-off'), subFile('hst-stu1', 'off.pdf')), BYTES, PDF));
  // type restriction applies to submissions too
  await assertFails(uploadBytes(ref(storageFor('hst-p1'), subFile('hst-stu1', 'x.js')), BYTES, { contentType: 'text/javascript' }));

  // read: own child's parent, the homework's creator, admins — not others
  for (const uid of ['hst-p1', 'hst-t1', 'hst-br-north', 'hst-admin']) {
    await assertSucceeds(getBytes(ref(storageFor(uid), subFile('hst-stu1', 'work.pdf'))));
  }
  for (const uid of ['hst-p2', 'hst-t2', 'hst-t-south', 'hst-br-south', 'hst-admin-b']) {
    await assertFails(getBytes(ref(storageFor(uid), subFile('hst-stu1', 'work.pdf'))));
  }
});

test('announcement files: author/admin upload; published readable school-wide; drafts only by author/admin', async () => {
  await seed();
  await assertSucceeds(uploadBytes(ref(storageFor('hst-t1'), annFile('a.pdf', 'an1')), BYTES, PDF));
  await assertSucceeds(uploadBytes(ref(storageFor('hst-t1'), annFile('d.pdf', 'and')), BYTES, PDF));
  await assertFails(uploadBytes(ref(storageFor('hst-t2'), annFile('b.pdf', 'an1')), BYTES, PDF));
  await assertFails(uploadBytes(ref(storageFor('hst-p1'), annFile('b.pdf', 'an1')), BYTES, PDF));
  await assertFails(uploadBytes(ref(storageFor('hst-t1'), annFile('a.pdf', 'an1')), BYTES, PDF)); // overwrite
  for (const uid of ['hst-p1', 'hst-t2', 'hst-t1']) await assertSucceeds(getBytes(ref(storageFor(uid), annFile('a.pdf', 'an1'))));
  await assertFails(getBytes(ref(storageFor('hst-admin-b'), annFile('a.pdf', 'an1'))));
  await assertSucceeds(getBytes(ref(storageFor('hst-t1'), annFile('d.pdf', 'and'))));
  for (const uid of ['hst-p1', 'hst-t2']) await assertFails(getBytes(ref(storageFor(uid), annFile('d.pdf', 'and'))));
});

test('unauthenticated and unknown paths are denied', async () => {
  await seed();
  const anon = testEnv.unauthenticatedContext().storage();
  await assertFails(getBytes(ref(anon, hwFile('a.pdf'))));
  await assertFails(uploadBytes(ref(anon, hwFile('z.pdf')), BYTES, PDF));
  await assertFails(uploadBytes(ref(storageFor('hst-admin'), `schools/${A}/branches/${NORTH}/homework/hw1/other/a.pdf`), BYTES, PDF));
});

// Storage rules for announcement attachments (see ../storage.rules): types,
// size, names, create/delete rights, and who may read which announcement's
// files. Own ids so it runs next to the other suites on one emulator.
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

const A = 'aas-a';
const B = 'aas-b';
const NORTH = 'north';
const SOUTH = 'south';
const stamp = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const st = (uid) => testEnv.authenticatedContext(uid).storage();
const BYTES = new Uint8Array([1, 2, 3, 4]);
const f = (name, id = 'pub', school = A, branch = NORTH) => `schools/${school}/branches/${branch}/announcements/${id}/files/${name}`;
const type = (contentType) => ({ contentType });

async function seed() {
  await testEnv.withSecurityRulesDisabled(async (c) => {
    const db = c.firestore();
    const user = (uid, o) => setDoc(doc(db, 'users', uid), { branchId: NORTH, name: 'T', email: 't@x.com', status: 'ACTIVE', linkedParentId: null, ...o, ...stamp });
    await user('aas-admin', { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' });
    await user('aas-br-north', { schoolId: A, role: 'BRANCH_ADMIN' });
    await user('aas-br-south', { schoolId: A, branchId: SOUTH, role: 'BRANCH_ADMIN' });
    await user('aas-t1', { schoolId: A, role: 'TEACHER' });
    await user('aas-t2', { schoolId: A, role: 'TEACHER' });
    await user('aas-p1', { schoolId: A, role: 'PARENT', linkedParentId: 'par1' });
    await user('aas-admin-b', { schoolId: B, role: 'SCHOOL_ADMIN' });
    await user('aas-p-b', { schoolId: B, role: 'PARENT', linkedParentId: 'parb' });
    const n = ['schools', A, 'branches', NORTH, 'announcements'];
    const ann = (id, o) => setDoc(doc(db, ...n, id), { authorId: 'aas-t1', audienceKind: 'BRANCH', status: 'PUBLISHED', publishAt: new Date('2020-01-01'), ...o, ...stamp });
    await ann('pub', {});
    await ann('draft', { status: 'DRAFT', publishAt: null });
    await ann('future', { publishAt: new Date('2999-01-01') });
    await ann('staff', { audienceKind: 'STAFF' });
    await ann('parents', { audienceKind: 'PARENTS' });
  });
}

test('allowed types and names upload; executables, scripts and odd names are refused', async () => {
  await seed();
  const ok = [
    ['photo.jpg', 'image/jpeg'], ['photo2.jpeg', 'image/jpeg'], ['p.png', 'image/png'], ['p.webp', 'image/webp'],
    ['c.pdf', 'application/pdf'], ['d.doc', 'application/msword'],
    ['d.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'],
    ['x.xls', 'application/vnd.ms-excel'],
    ['x.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],
    ['n.txt', 'text/plain'],
  ];
  for (const [name, ct] of ok) await assertSucceeds(uploadBytes(ref(st('aas-t1'), f(name)), BYTES, type(ct)));
  await assertFails(uploadBytes(ref(st('aas-t1'), f('run.exe')), BYTES, type('application/x-msdownload')));
  await assertFails(uploadBytes(ref(st('aas-t1'), f('page.html')), BYTES, type('text/html')));
  await assertFails(uploadBytes(ref(st('aas-t1'), f('s.svg')), BYTES, type('image/svg+xml')));
  // a script named like an image, or an image type on a script name
  await assertFails(uploadBytes(ref(st('aas-t1'), f('evil.js')), BYTES, type('image/png')));
  await assertFails(uploadBytes(ref(st('aas-t1'), f('evil.pdf.exe')), BYTES, type('application/pdf')));
  await assertFails(uploadBytes(ref(st('aas-t1'), f('noext')), BYTES, type('application/pdf')));
  await assertFails(uploadBytes(ref(st('aas-t1'), f('a b.pdf')), BYTES, type('application/pdf')));
});

test('size: 10 MB is accepted, one byte more is not; empty is refused', async () => {
  await seed();
  await assertSucceeds(uploadBytes(ref(st('aas-t1'), f('big.pdf')), new Uint8Array(10 * 1024 * 1024), type('application/pdf')));
  await assertFails(uploadBytes(ref(st('aas-t1'), f('toobig.pdf')), new Uint8Array(10 * 1024 * 1024 + 1), type('application/pdf')));
  await assertFails(uploadBytes(ref(st('aas-t1'), f('empty.pdf')), new Uint8Array(0), type('application/pdf')));
});

test('only the author or a branch admin of that branch may add or remove files; no overwrite', async () => {
  await seed();
  await assertSucceeds(uploadBytes(ref(st('aas-t1'), f('mine.pdf')), BYTES, type('application/pdf')));
  await assertFails(uploadBytes(ref(st('aas-t1'), f('mine.pdf')), BYTES, type('application/pdf'))); // overwrite
  await assertSucceeds(uploadBytes(ref(st('aas-br-north'), f('adm.pdf')), BYTES, type('application/pdf')));
  await assertSucceeds(uploadBytes(ref(st('aas-admin'), f('sch.pdf')), BYTES, type('application/pdf')));
  for (const uid of ['aas-t2', 'aas-p1', 'aas-br-south', 'aas-admin-b', 'aas-p-b']) {
    await assertFails(uploadBytes(ref(st(uid), f(`x${uid.replace(/\W/g, '')}.pdf`)), BYTES, type('application/pdf')));
  }
  // delete: author / admin yes; others no
  for (const uid of ['aas-t2', 'aas-p1', 'aas-br-south', 'aas-admin-b']) await assertFails(deleteObject(ref(st(uid), f('mine.pdf'))));
  await assertSucceeds(deleteObject(ref(st('aas-t1'), f('mine.pdf'))));
  await assertSucceeds(deleteObject(ref(st('aas-br-north'), f('adm.pdf'))));
});

test('reading: published and due is readable in school; drafts, future and wrong-audience files are not', async () => {
  await seed();
  const put = (id, name, uid = 'aas-t1') => uploadBytes(ref(st(uid), f(name, id)), BYTES, type('application/pdf'));
  for (const id of ['pub', 'draft', 'future', 'staff', 'parents']) await assertSucceeds(put(id, 'a.pdf'));
  // everyone in the school reads a published, due, branch-wide file
  for (const uid of ['aas-p1', 'aas-t2', 'aas-t1', 'aas-br-north', 'aas-admin']) await assertSucceeds(getBytes(ref(st(uid), f('a.pdf', 'pub'))));
  // drafts / scheduled: author and admins only
  for (const id of ['draft', 'future']) {
    for (const uid of ['aas-p1', 'aas-t2']) await assertFails(getBytes(ref(st(uid), f('a.pdf', id))));
    for (const uid of ['aas-t1', 'aas-br-north', 'aas-admin']) await assertSucceeds(getBytes(ref(st(uid), f('a.pdf', id))));
  }
  // audience: staff notices are not for parents, parent notices not for teachers
  await assertFails(getBytes(ref(st('aas-p1'), f('a.pdf', 'staff'))));
  await assertSucceeds(getBytes(ref(st('aas-t2'), f('a.pdf', 'staff'))));
  await assertFails(getBytes(ref(st('aas-t2'), f('a.pdf', 'parents'))));
  await assertSucceeds(getBytes(ref(st('aas-p1'), f('a.pdf', 'parents'))));
});

test('another school (or branch admin of another branch) cannot read, even knowing the path', async () => {
  await seed();
  await assertSucceeds(uploadBytes(ref(st('aas-t1'), f('sec.pdf')), BYTES, type('application/pdf')));
  for (const uid of ['aas-admin-b', 'aas-p-b']) await assertFails(getBytes(ref(st(uid), f('sec.pdf'))));
  await assertFails(getBytes(ref(testEnv.unauthenticatedContext().storage(), f('sec.pdf'))));
  // a file under an announcement that does not exist cannot be created or read
  await assertFails(uploadBytes(ref(st('aas-t1'), f('ghost.pdf', 'nope')), BYTES, type('application/pdf')));
});

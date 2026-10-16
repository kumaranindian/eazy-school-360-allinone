// School-wide academic years: a registry at schools/{s}/academicYears and the
// branch copies that must match it. Prefix: sy-.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, doc, getDoc, getDocs, serverTimestamp, setDoc, Timestamp, updateDoc, writeBatch,
} from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await seed();
});
after(async () => env.cleanup());

const A = 'sy-a';
const Z = 'sy-z';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const D1 = Timestamp.fromDate(new Date('2026-06-01T00:00:00Z'));
const D2 = Timestamp.fromDate(new Date('2027-03-31T00:00:00Z'));
const audit = (uid) => ({ createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
const regRef = (d, s, id) => doc(d, 'schools', s, 'academicYears', id);
const yearRef = (d, s, b, id) => doc(d, 'schools', s, 'branches', b, 'academicYears', id);
const reg = (s, o = {}) => ({ schoolId: s, name: '2026-27', startDate: D1, endDate: D2, status: 'ACTIVE', ...o });
const branchYear = (s, b, o = {}) => ({
  schoolId: s, branchId: b, name: '2026-27', startDate: D1, endDate: D2, status: 'DRAFT', schoolYearId: 'y2026', ...o,
});

async function seed() {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, Z]) {
      await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...base });
      for (const b of ['north', 'south']) await setDoc(doc(d, 'schools', s, 'branches', b), { schoolId: s, name: b, status: 'ACTIVE', ...base });
    }
    const users = {
      'sy-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'sy-ba-n': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN' },
      'sy-ba-s': { schoolId: A, branchId: 'south', role: 'BRANCH_ADMIN' },
      'sy-t': { schoolId: A, branchId: 'north', role: 'TEACHER' },
      'sy-multi': { schoolId: A, branchId: 'north', role: 'TEACHER', branchRoles: { south: 'BRANCH_ADMIN' } },
      'sy-p': { schoolId: A, branchId: 'north', role: 'PARENT', linkedParentId: 'pp' },
      'sy-admin-z': { schoolId: Z, branchId: null, role: 'SCHOOL_ADMIN' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    // a registry year (and one archived) to open from
    await setDoc(regRef(d, A, 'y2026'), { ...reg(A), ...base });
    await setDoc(regRef(d, A, 'y-old'), { ...reg(A, { name: '2019-20', status: 'ARCHIVED' }), ...base });
    // a legacy branch-only year
    await setDoc(yearRef(d, A, 'north', 'legacy'), { schoolId: A, branchId: 'north', name: 'Old', startDate: D1, endDate: D2, status: 'ACTIVE', ...base });
  });
}

test('only a school admin defines school-wide years; staff read them; parents and strangers do not', async () => {
  await assertSucceeds(setDoc(regRef(as('sy-admin'), A, 'y2027'), { ...reg(A, { name: '2027-28' }), ...audit('sy-admin') }));
  for (const uid of ['sy-ba-n', 'sy-t', 'sy-multi', 'sy-p']) {
    await assertFails(setDoc(regRef(as(uid), A, `x-${uid}`), { ...reg(A), ...audit(uid) }));
  }
  await assertFails(setDoc(regRef(as('sy-admin-z'), A, 'cross'), { ...reg(A), ...audit('sy-admin-z') }));
  for (const uid of ['sy-admin', 'sy-ba-n', 'sy-t', 'sy-multi']) await assertSucceeds(getDoc(regRef(as(uid), A, 'y2026')));
  await assertSucceeds(getDocs(collection(as('sy-t'), 'schools', A, 'academicYears')));
  await assertFails(getDoc(regRef(as('sy-p'), A, 'y2026')));
  await assertFails(getDoc(regRef(as('sy-admin-z'), A, 'y2026')));
});

test('registry validation: dates, name, status, extra fields, tenant', async () => {
  const a = as('sy-admin');
  const ok = (id, o) => setDoc(regRef(a, A, id), { ...reg(A), ...audit('sy-admin'), ...o });
  await assertFails(ok('v1', { endDate: D1 })); // not after start
  await assertFails(ok('v2', { name: '' }));
  await assertFails(ok('v3', { name: 'x'.repeat(101) }));
  await assertFails(ok('v4', { status: 'ARCHIVED' })); // born archived
  await assertFails(ok('v5', { schoolId: Z }));
  await assertFails(ok('v6', { extra: 1 }));
  await assertFails(ok('v7', { startDate: 'tomorrow' }));
  await assertSucceeds(ok('v8', { name: 'fine' }));
});

test('a registry year is immutable except for archiving; never deleted', async () => {
  const a = as('sy-admin');
  await assertFails(updateDoc(regRef(a, A, 'y2026'), { name: 'renamed', updatedAt: serverTimestamp(), updatedBy: 'sy-admin' }));
  await assertFails(updateDoc(regRef(a, A, 'y2026'), { endDate: D1, updatedAt: serverTimestamp(), updatedBy: 'sy-admin' }));
  await assertFails(updateDoc(regRef(a, A, 'y2026'), { status: 'DELETED', updatedAt: serverTimestamp(), updatedBy: 'sy-admin' }));
  await assertFails(updateDoc(regRef(as('sy-ba-n'), A, 'y2026'), { status: 'ARCHIVED', updatedAt: serverTimestamp(), updatedBy: 'sy-ba-n' }));
  await assertSucceeds(updateDoc(regRef(a, A, 'y-old'), { status: 'ACTIVE', updatedAt: serverTimestamp(), updatedBy: 'sy-admin' }));
  await assertSucceeds(updateDoc(regRef(a, A, 'y-old'), { status: 'ARCHIVED', updatedAt: serverTimestamp(), updatedBy: 'sy-admin' }));
  await assertFails((await import('firebase/firestore')).deleteDoc(regRef(a, A, 'y2026')));
});

test('a branch opens a registry year: matching copy only, in its own branch', async () => {
  // branch admin of north opens it
  await assertSucceeds(setDoc(yearRef(as('sy-ba-n'), A, 'north', 'y2026'), { ...branchYear(A, 'north'), ...audit('sy-ba-n') }));
  // a different branch admin cannot open it in north; but can in south
  await assertFails(setDoc(yearRef(as('sy-ba-s'), A, 'north', 'y2026b'), { ...branchYear(A, 'north', { schoolYearId: 'y2026' }), ...audit('sy-ba-s') }));
  await assertSucceeds(setDoc(yearRef(as('sy-ba-s'), A, 'south', 'y2026'), { ...branchYear(A, 'south'), ...audit('sy-ba-s') }));
  // a teacher cannot
  await assertFails(setDoc(yearRef(as('sy-t'), A, 'south', 'y2026'), { ...branchYear(A, 'south'), ...audit('sy-t') }));
});

test('a school admin can open a year for several branches in one batch', async () => {
  await env.withSecurityRulesDisabled(async (c) => setDoc(regRef(c.firestore(), A, 'y-batch'), { ...reg(A, { name: 'Batch' }), ...base }));
  const d = as('sy-admin');
  const batch = writeBatch(d);
  for (const b of ['north', 'south']) {
    batch.set(yearRef(d, A, b, 'y-batch'), { ...branchYear(A, b, { name: 'Batch', schoolYearId: 'y-batch' }), ...audit('sy-admin') });
  }
  await assertSucceeds(batch.commit());
});

test('a per-branch branch admin can open the year in that branch only', async () => {
  await env.withSecurityRulesDisabled(async (c) => setDoc(regRef(c.firestore(), A, 'y-multi'), { ...reg(A, { name: 'Multi' }), ...base }));
  const d = as('sy-multi');
  await assertSucceeds(setDoc(yearRef(d, A, 'south', 'y-multi'), { ...branchYear(A, 'south', { name: 'Multi', schoolYearId: 'y-multi' }), ...audit('sy-multi') }));
  await assertFails(setDoc(yearRef(d, A, 'north', 'y-multi'), { ...branchYear(A, 'north', { name: 'Multi', schoolYearId: 'y-multi' }), ...audit('sy-multi') }));
});

test('a branch year cannot be invented, mismatched or built from an archived/foreign year', async () => {
  const d = as('sy-ba-s');
  const put = (id, o) => setDoc(yearRef(d, A, 'south', id), { ...branchYear(A, 'south'), ...audit('sy-ba-s'), ...o });
  await assertFails(put('free', { schoolYearId: null })); // claims no registry year
  await assertFails(setDoc(yearRef(d, A, 'south', 'free2'), (({ schoolYearId, ...r }) => ({ ...r, ...audit('sy-ba-s') }))(branchYear(A, 'south'))));
  await assertFails(put('y2026', { name: 'Different name' }));
  await assertFails(put('y2026', { endDate: D1 }));
  await assertFails(put('y2026', { schoolYearId: 'other' })); // id must equal the registry id
  await assertFails(put('y-old', { schoolYearId: 'y-old', name: '2019-20' })); // archived
  await assertFails(put('missing', { schoolYearId: 'missing' }));
  await assertFails(put('y2026', { branchId: 'north' })); // wrong branch in the body
});

test('a linked branch year keeps the school\'s name and dates; only its own status moves', async () => {
  const d = as('sy-ba-n');
  const r = yearRef(d, A, 'north', 'y2026');
  const upd = (o) => updateDoc(r, { updatedAt: serverTimestamp(), updatedBy: 'sy-ba-n', ...o });
  await assertFails(upd({ name: 'Renamed' }));
  await assertFails(upd({ startDate: D2 }));
  await assertFails(upd({ schoolYearId: null }));
  await assertSucceeds(upd({ status: 'ACTIVE' }));
  await assertSucceeds(upd({ status: 'CLOSED' }));
});

test('legacy branch years stay editable', async () => {
  const d = as('sy-ba-n');
  await assertSucceeds(updateDoc(yearRef(d, A, 'north', 'legacy'), { name: 'Old renamed', updatedAt: serverTimestamp(), updatedBy: 'sy-ba-n' }));
});

test('opening a year in another school is impossible even for a school admin there', async () => {
  const d = as('sy-admin-z');
  await assertFails(setDoc(yearRef(d, Z, 'north', 'y2026'), { ...branchYear(Z, 'north'), ...audit('sy-admin-z') })); // Z has no such registry year
  await assertFails(setDoc(yearRef(d, A, 'north', 'zz'), { ...branchYear(A, 'north'), ...audit('sy-admin-z') }));
});

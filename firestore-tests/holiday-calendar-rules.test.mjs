// Weekly offs (Saturday patterns, effective dates) and the holiday calendar
// (single days, vacations): who may write them, and that malformed documents
// are refused. Own school ids (`hc-`) so it shares the emulator with the
// other files.
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, orderBy, query, serverTimestamp, setDoc, updateDoc,
} from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await seedAll();
});
after(async () => env.cleanup());

const A = 'hc-a';
const B = 'hc-b';
const N = 'north';
const S = 'south';
const YEAR = 'y1';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const nb = (s = A, b = N) => ['schools', s, 'branches', b];
const db = (uid) => env.authenticatedContext(uid).firestore();
const wdRef = (d, b = N, s = A) => doc(d, ...nb(s, b), 'settings', 'workingDays');
const holRef = (d, id, b = N, s = A) => doc(d, ...nb(s, b), 'academicYears', YEAR, 'holidays', id);
const holCol = (d, b = N, s = A) => collection(d, ...nb(s, b), 'academicYears', YEAR, 'holidays');

const DAYS = { MONDAY: true, TUESDAY: true, WEDNESDAY: true, THURSDAY: true, FRIDAY: true, SATURDAY: true, SUNDAY: false };
const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: uid });
const weekly = (uid, o = {}, s = A, b = N) => ({ schoolId: s, branchId: b, isWorkingDay: DAYS, ...stamp(uid), ...o });
const holiday = (uid, o = {}, s = A, b = N) => ({
  schoolId: s, branchId: b, academicYearId: YEAR, date: new Date('2026-08-12T00:00:00Z'), name: 'Founders day',
  type: 'SCHOOL', description: '', status: 'ACTIVE', createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  createdBy: uid, updatedBy: uid, ...o,
});

async function seedAll() {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, B]) await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...base });
    for (const [s, b] of [[A, N], [A, S], [B, N]]) await setDoc(doc(d, ...nb(s, b)), { schoolId: s, name: b, status: 'ACTIVE', ...base });
    const users = {
      'hc-school-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'hc-br-north': { schoolId: A, branchId: N, role: 'BRANCH_ADMIN' },
      'hc-br-south': { schoolId: A, branchId: S, role: 'BRANCH_ADMIN' },
      'hc-teacher': { schoolId: A, branchId: N, role: 'TEACHER' },
      'hc-finance': { schoolId: A, branchId: N, role: 'FINANCE' },
      'hc-parent': { schoolId: A, branchId: N, role: 'PARENT', linkedParentId: 'par1' },
      'hc-admin-b': { schoolId: B, branchId: null, role: 'SCHOOL_ADMIN' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: 't@example.com', status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
    await setDoc(doc(d, ...nb(A, N), 'parentAccess', 'par1'), {
      schoolId: A, branchId: N, parentId: 'par1', classKeys: ['c5'], sectionKeys: ['c5__sa'], updatedAt: serverTimestamp(), updatedBy: 'seed',
    });
    await setDoc(doc(d, ...nb(A, N), 'academicYears', YEAR), { schoolId: A, branchId: N, name: '2026-27', status: 'ACTIVE', ...base });
    await setDoc(doc(d, ...nb(B, N), 'academicYears', YEAR), { schoolId: B, branchId: N, name: '2026-27', status: 'ACTIVE', ...base });
  });
}

// ------------------------------------------------------------ weekly offs

test('weekly offs: a branch admin and the school admin may save a Saturday pattern', async () => {
  for (const uid of ['hc-br-north', 'hc-school-admin']) {
    await assertSucceeds(setDoc(wdRef(db(uid)), weekly(uid, { saturdayOffWeeks: [2, 4], effectiveFrom: '2026-09-01', history: [] })));
  }
});

test('weekly offs: a pattern with history and every Saturday in the month is accepted', async () => {
  const admin = db('hc-br-north');
  const hist = [{ effectiveFrom: null, isWorkingDay: DAYS, saturdayOffWeeks: [] }];
  await assertSucceeds(setDoc(wdRef(admin), weekly('hc-br-north', { saturdayOffWeeks: [1, 2, 3, 4, 5], effectiveFrom: '2026-09-01', history: hist })));
});

test('weekly offs: documents saved before Saturday patterns existed are still valid', async () => {
  await assertSucceeds(setDoc(wdRef(db('hc-br-north')), weekly('hc-br-north')));
});

test('weekly offs: malformed patterns are refused', async () => {
  const admin = db('hc-br-north');
  const w = (o) => setDoc(wdRef(admin), weekly('hc-br-north', o));
  await assertFails(w({ saturdayOffWeeks: [6] })); // there is no 6th Saturday
  await assertFails(w({ saturdayOffWeeks: [0] }));
  await assertFails(w({ saturdayOffWeeks: [1, 2, 3, 4, 5, 1] })); // too many
  await assertFails(w({ saturdayOffWeeks: 'ALL' }));
  await assertFails(w({ effectiveFrom: 'next month' }));
  await assertFails(w({ effectiveFrom: 20260901 }));
  await assertFails(w({ history: Array.from({ length: 13 }, () => ({})) })); // history is bounded
  await assertFails(w({ history: 'none' }));
  await assertFails(w({ isWorkingDay: { ...DAYS, SATURDAY: 'yes' } })); // not a bool
  await assertFails(w({ isWorkingDay: { MONDAY: true } })); // a day is missing
  await assertFails(w({ isWorkingDay: { ...DAYS, FUNDAY: true } })); // an unknown day
  await assertFails(w({ isWorkingDay: 'all' }));
});

test('weekly offs: nobody else may write them, in this branch or another school', async () => {
  for (const uid of ['hc-teacher', 'hc-finance', 'hc-parent']) {
    await assertFails(setDoc(wdRef(db(uid)), weekly(uid)));
  }
  await assertFails(setDoc(wdRef(db('hc-br-south')), weekly('hc-br-south'))); // another branch's admin
  await assertFails(setDoc(wdRef(db('hc-admin-b')), weekly('hc-admin-b'))); // another school's admin
  await assertFails(setDoc(wdRef(db('hc-br-north'), N, B), weekly('hc-br-north', {}, B))); // into school B
  await assertFails(setDoc(wdRef(db('hc-admin-b'), N, A), weekly('hc-admin-b')));
});

test('weekly offs: the write must be stamped by its writer and carry its own tenant', async () => {
  const admin = db('hc-br-north');
  await assertFails(setDoc(wdRef(admin), weekly('someone-else')));
  await assertFails(setDoc(wdRef(admin), weekly('hc-br-north', { schoolId: B })));
  await assertFails(setDoc(wdRef(admin), weekly('hc-br-north', { branchId: S })));
});

test('weekly offs: it cannot be deleted', async () => {
  await assertFails(deleteDoc(wdRef(db('hc-school-admin'))));
});

test('weekly offs: staff and a family with a child here read them; others do not', async () => {
  await env.withSecurityRulesDisabled(async (c) => setDoc(wdRef(c.firestore()), weekly('seed')));
  for (const uid of ['hc-school-admin', 'hc-br-north', 'hc-teacher', 'hc-finance', 'hc-parent']) {
    await assertSucceeds(getDoc(wdRef(db(uid))));
  }
  await assertFails(getDoc(wdRef(db('hc-admin-b'))));
  await assertFails(getDoc(wdRef(db('hc-br-south'))));
});

// -------------------------------------------------------------- holidays

test('holidays: an admin adds a single day, a vacation and a festival', async () => {
  const admin = db('hc-br-north');
  await assertSucceeds(setDoc(holRef(admin, 'one'), holiday('hc-br-north')));
  await assertSucceeds(setDoc(holRef(admin, 'vac'), holiday('hc-br-north', {
    name: 'Summer vacation', type: 'VACATION', date: new Date('2026-05-04T00:00:00Z'), endDate: new Date('2026-06-14T00:00:00Z'),
  })));
  await assertSucceeds(setDoc(holRef(admin, 'fest'), holiday('hc-br-north', { name: 'Diwali', type: 'FESTIVAL', endDate: null })));
  await assertSucceeds(setDoc(holRef(db('hc-school-admin'), 'swd'), holiday('hc-school-admin', {
    name: 'Make-up day', type: 'SPECIAL_WORKING_DAY',
  })));
});

test('holidays: a range must end on or after it starts and stay within a year', async () => {
  const admin = db('hc-br-north');
  const h = (id, o) => setDoc(holRef(admin, id), holiday('hc-br-north', o));
  await assertSucceeds(h('same-day', { endDate: new Date('2026-08-12T00:00:00Z') }));
  await assertFails(h('backwards', { endDate: new Date('2026-08-11T00:00:00Z') }));
  await assertSucceeds(h('year', { endDate: new Date('2027-08-12T00:00:00Z') })); // 365 days apart = 366 days inclusive
  await assertFails(h('too-long', { endDate: new Date('2027-08-13T00:00:00Z') }));
  await assertFails(h('not-a-date', { endDate: 'tomorrow' }));
});

test('holidays: malformed documents are refused', async () => {
  const admin = db('hc-br-north');
  const h = (id, o) => setDoc(holRef(admin, id), holiday('hc-br-north', o));
  await assertFails(h('no-name', { name: '' }));
  await assertFails(h('long-name', { name: 'x'.repeat(101) }));
  await assertFails(h('bad-type', { type: 'PARTY' }));
  await assertFails(h('bad-status', { status: 'DELETED' }));
  await assertFails(h('bad-date', { date: '2026-08-12' }));
  await assertFails(h('long-desc', { description: 'x'.repeat(501) }));
  await assertFails(h('other-year', { academicYearId: 'y2' }));
  await assertFails(h('other-school', { schoolId: B }));
});

test('holidays: editing a range, and removing one by making it inactive', async () => {
  const admin = db('hc-br-north');
  await env.withSecurityRulesDisabled(async (c) => setDoc(holRef(c.firestore(), 'edit'), holiday('seed')));
  const edit = (o) => updateDoc(holRef(admin, 'edit'), { ...o, updatedAt: serverTimestamp(), updatedBy: 'hc-br-north' });
  await assertSucceeds(edit({ endDate: new Date('2026-08-14T00:00:00Z'), type: 'VACATION' }));
  await assertFails(edit({ endDate: new Date('2026-08-01T00:00:00Z') })); // before the start
  await assertSucceeds(edit({ status: 'INACTIVE' }));
  await assertSucceeds(edit({ status: 'ACTIVE' })); // restored
  await assertFails(edit({ status: 'DELETED' }));
  await assertFails(edit({ schoolId: B })); // not an editable field
  await assertFails(edit({ academicYearId: 'y2' }));
});

test('holidays: they are never deleted', async () => {
  await env.withSecurityRulesDisabled(async (c) => setDoc(holRef(c.firestore(), 'keep'), holiday('seed')));
  for (const uid of ['hc-br-north', 'hc-school-admin']) await assertFails(deleteDoc(holRef(db(uid), 'keep')));
});

test('holidays: nobody else may write them', async () => {
  for (const uid of ['hc-teacher', 'hc-finance', 'hc-parent']) {
    await assertFails(setDoc(holRef(db(uid), `w-${uid}`), holiday(uid)));
  }
  await env.withSecurityRulesDisabled(async (c) => setDoc(holRef(c.firestore(), 'locked'), holiday('seed')));
  for (const uid of ['hc-teacher', 'hc-parent', 'hc-br-south', 'hc-admin-b']) {
    await assertFails(updateDoc(holRef(db(uid), 'locked'), { name: 'hijack', updatedAt: serverTimestamp(), updatedBy: uid }));
  }
  await assertFails(setDoc(holRef(db('hc-br-south'), 'x'), holiday('hc-br-south')));
  await assertFails(setDoc(holRef(db('hc-admin-b'), 'x'), holiday('hc-admin-b')));
  await assertFails(setDoc(holRef(db('hc-br-north'), 'x', N, B), holiday('hc-br-north', {}, B)));
});

test('holidays: staff and a family with a child here can list them in date order', async () => {
  await env.withSecurityRulesDisabled(async (c) => setDoc(holRef(c.firestore(), 'listed'), holiday('seed')));
  for (const uid of ['hc-school-admin', 'hc-br-north', 'hc-teacher', 'hc-finance', 'hc-parent']) {
    await assertSucceeds(getDocs(query(holCol(db(uid)), orderBy('date'))));
  }
  await assertFails(getDocs(query(holCol(db('hc-admin-b')), orderBy('date'))));
  await assertFails(getDocs(query(holCol(db('hc-br-south')), orderBy('date'))));
});

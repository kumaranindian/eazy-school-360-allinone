// Multi-country: country / currency / time zone / date format on the school
// document, and the currency lock set by the server. Prefix: rg-.
import { readFileSync } from 'node:fs';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync(process.env.RULES_FILE || '../firestore.rules', 'utf8') },
  });
});
after(async () => env.cleanup());

const A = 'rg-a';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: uid });
const as = (uid) => env.authenticatedContext(uid, { firebase: { sign_in_provider: 'password' } }).firestore();
const school = (d) => doc(d, 'schools', A);
const regional = (o = {}) => ({ countryCode: 'AE', currency: 'AED', timezone: 'Asia/Dubai', dateFormat: 'dd/MM/yyyy', ...o });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    await setDoc(school(d), { name: A, email: 'a@example.com', status: 'ACTIVE', ...base });
    const users = {
      'rg-admin': { schoolId: A, branchId: null, role: 'SCHOOL_ADMIN' },
      'rg-ba': { schoolId: A, branchId: 'north', role: 'BRANCH_ADMIN' },
      'rg-teacher': { schoolId: A, branchId: 'north', role: 'TEACHER' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', email: `${uid}@example.com`, status: 'ACTIVE', linkedParentId: null, ...u, ...base });
    }
  });
});

const lock = () => env.withSecurityRulesDisabled(async (c) => updateDoc(school(c.firestore()), { currencyLocked: true }));

test('a school admin sets country, currency, time zone and date format', async () => {
  await assertSucceeds(updateDoc(school(as('rg-admin')), { ...regional(), ...stamp('rg-admin') }));
});

test('branch admins, teachers and other schools cannot change them', async () => {
  await assertFails(updateDoc(school(as('rg-ba')), { ...regional(), ...stamp('rg-ba') }));
  await assertFails(updateDoc(school(as('rg-teacher')), { ...regional(), ...stamp('rg-teacher') }));
});

test('malformed values are refused', async () => {
  const db = as('rg-admin');
  for (const bad of [
    { countryCode: 'ae' }, { countryCode: 'ARE' }, { currency: 'aed' }, { currency: 'DOLLAR' }, { currency: 5 },
    { timezone: 'Dubai' }, { timezone: '../etc' }, { timezone: 'Asia/Dubai/x/y' }, { timezone: 'x'.repeat(70) },
    { dateFormat: 'yy-dd-MM' }, { dateFormat: 'dd/MM/yyyy; drop' },
  ]) {
    await assertFails(updateDoc(school(db), { ...bad, ...stamp('rg-admin') }));
  }
});

test('the currency can change while no money exists', async () => {
  const db = as('rg-admin');
  await assertSucceeds(updateDoc(school(db), { ...regional(), ...stamp('rg-admin') }));
  await assertSucceeds(updateDoc(school(db), { currency: 'USD', ...stamp('rg-admin') }));
});

test('once money exists the currency is locked, but time zone and date format are not', async () => {
  const db = as('rg-admin');
  await assertSucceeds(updateDoc(school(db), { ...regional(), ...stamp('rg-admin') }));
  await lock();
  await assertFails(updateDoc(school(db), { currency: 'USD', ...stamp('rg-admin') }));
  await assertSucceeds(updateDoc(school(db), { currency: 'AED', timezone: 'Asia/Muscat', dateFormat: 'yyyy-MM-dd', ...stamp('rg-admin') }));
});

test('a locked school that never set a currency is implicitly INR and stays INR', async () => {
  await lock();
  const db = as('rg-admin');
  await assertFails(updateDoc(school(db), { currency: 'USD', ...stamp('rg-admin') }));
  await assertSucceeds(updateDoc(school(db), { currency: 'INR', countryCode: 'IN', ...stamp('rg-admin') }));
});

test('a school admin cannot set or clear the lock', async () => {
  const db = as('rg-admin');
  await assertFails(updateDoc(school(db), { currencyLocked: true, ...stamp('rg-admin') }));
  await lock();
  await assertFails(updateDoc(school(db), { currencyLocked: false, ...stamp('rg-admin') }));
});

test('self sign-up may carry regional settings, never a pre-set lock', async () => {
  const uid = 'rg-new';
  const s = 'rg-new-school';
  const make = async (extra) => {
    const db = as(uid);
    const { writeBatch } = await import('firebase/firestore');
    const b = writeBatch(db);
    b.set(doc(db, 'schools', s), { name: 'N', email: 'n@example.com', status: 'ACTIVE', ...regional(), ...extra, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
    b.set(doc(db, 'users', uid), { name: 'N', email: 'n@example.com', schoolId: s, branchId: null, role: 'SCHOOL_ADMIN', status: 'ACTIVE', linkedParentId: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: uid, updatedBy: uid });
    return b.commit();
  };
  await assertFails(make({ currencyLocked: true }));
  await assertFails(make({ currency: 'dollars' }));
  await assertSucceeds(make({}));
});

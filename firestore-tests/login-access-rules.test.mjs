// Authentication feature: the server-written `login` map on /users/{uid} is
// enforced by the rules on every request. Probe = reading the caller's own
// school document (allowed only to an ACTIVE caller who may sign in).
import { readFileSync } from 'node:fs';
import { test, before, after } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';

let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-eazy-school-360',
    firestore: { rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await seed();
});
after(async () => env.cleanup());

const A = 'la-a';
const Z = 'la-z';
const base = { createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'seed', updatedBy: 'seed' };
const login = (enabled, effective, extra = {}) => ({ enabled, methods: effective, effective, phone: null, ...extra });

async function seed() {
  await env.withSecurityRulesDisabled(async (c) => {
    const d = c.firestore();
    for (const s of [A, Z]) await setDoc(doc(d, 'schools', s), { name: s, status: 'ACTIVE', ...base });
    const users = {
      'la-legacy': { schoolId: A, role: 'TEACHER', email: 'legacy@x.com' },
      'la-pw': { schoolId: A, role: 'TEACHER', email: 'pw@x.com', login: login(true, ['PASSWORD']) },
      'la-google': { schoolId: A, role: 'TEACHER', email: 'g@x.com', login: login(true, ['GOOGLE']) },
      'la-phone': { schoolId: A, role: 'PARENT', email: null, login: login(true, ['PHONE_OTP'], { phone: '+919876543210' }) },
      'la-off': { schoolId: A, role: 'TEACHER', email: 'off@x.com', login: login(false, []) },
      'la-multi': { schoolId: A, role: 'TEACHER', email: 'm@x.com', login: login(true, ['PASSWORD', 'PHONE_OTP']) },
      'la-admin': { schoolId: A, role: 'SCHOOL_ADMIN', email: 'admin@x.com', login: login(true, ['PASSWORD']) },
      'la-zteacher': { schoolId: Z, role: 'TEACHER', email: 'z@x.com' },
    };
    for (const [uid, u] of Object.entries(users)) {
      await setDoc(doc(d, 'users', uid), { name: 'T', status: 'ACTIVE', branchId: null, linkedParentId: null, ...u, ...base });
    }
    await setDoc(doc(d, 'schools', A, 'authSettings', 'methods'), { methods: ['PASSWORD'], ...base });
    await setDoc(doc(d, 'schools', A, 'authAudit', 'e1'), { type: 'LOGIN_ENABLED', ...base });
  });
}

const as = (uid, provider, extra = {}) =>
  env.authenticatedContext(uid, { firebase: { sign_in_provider: provider }, ...extra }).firestore();
const school = (d, s = A) => getDoc(doc(d, 'schools', s));
const pw = (uid) => as(uid, 'password', { email: 'x@x.com', email_verified: true });
const google = (uid, email) => as(uid, 'google.com', { email, email_verified: true });
const otp = (uid) => as(uid, 'custom', { via: 'PHONE_OTP' });

test('legacy accounts (no login map) keep working with any provider', async () => {
  await assertSucceeds(school(pw('la-legacy')));
  await assertSucceeds(school(google('la-legacy', 'legacy@x.com')));
});

test('password-only user: password works, google and OTP do not', async () => {
  await assertSucceeds(school(pw('la-pw')));
  await assertFails(school(google('la-pw', 'pw@x.com')));
  await assertFails(school(otp('la-pw')));
});

test('google-only user: only the registered, verified google account works', async () => {
  await assertSucceeds(school(google('la-google', 'g@x.com')));
  await assertSucceeds(school(google('la-google', 'G@X.com')));
  await assertFails(school(google('la-google', 'someone-else@x.com')));
  await assertFails(school(as('la-google', 'google.com', { email: 'g@x.com', email_verified: false })));
  await assertFails(school(pw('la-google')));
});

test('phone-OTP-only user: needs the server-minted OTP claim', async () => {
  await assertSucceeds(school(otp('la-phone')));
  await assertFails(school(as('la-phone', 'custom')), 'a custom token without via=PHONE_OTP');
  await assertFails(school(pw('la-phone')));
  await assertFails(school(as('la-phone', 'anonymous')));
});

test('multiple permitted methods: each works independently', async () => {
  await assertSucceeds(school(pw('la-multi')));
  await assertSucceeds(school(otp('la-multi')));
  await assertFails(school(google('la-multi', 'm@x.com')));
});

test('disabled login: nothing works, but the user can read their own profile', async () => {
  await assertFails(school(pw('la-off')));
  await assertFails(school(otp('la-off')));
  await assertSucceeds(getDoc(doc(pw('la-off'), 'users', 'la-off')));
  await assertFails(getDoc(doc(pw('la-off'), 'users', 'la-pw')));
});

test('a disabled school admin loses admin powers immediately', async () => {
  await assertSucceeds(getDoc(doc(pw('la-admin'), 'schools', A, 'authSettings', 'methods')));
  await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'users', 'la-admin'), { 'login.enabled': false }));
  await assertFails(getDoc(doc(pw('la-admin'), 'schools', A, 'authSettings', 'methods')));
  await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'users', 'la-admin'), { 'login.enabled': true }));
});

test('other schools are isolated', async () => {
  await assertFails(school(pw('la-pw'), Z));
  await assertFails(school(pw('la-zteacher'), A));
});

test('login map and auth settings/audit/otp collections are not client-writable', async () => {
  const admin = pw('la-admin');
  await assertFails(updateDoc(doc(admin, 'users', 'la-pw'), { login: login(true, ['PASSWORD', 'GOOGLE']), updatedAt: serverTimestamp(), updatedBy: 'la-admin' }));
  await assertFails(updateDoc(doc(pw('la-pw'), 'users', 'la-pw'), { login: login(true, ['GOOGLE', 'PASSWORD', 'PHONE_OTP']), updatedAt: serverTimestamp(), updatedBy: 'la-pw' }));
  await assertFails(setDoc(doc(admin, 'schools', A, 'authSettings', 'methods'), { methods: ['PASSWORD', 'GOOGLE', 'PHONE_OTP'] }));
  await assertFails(setDoc(doc(admin, 'schools', A, 'authAudit', 'forged'), { type: 'x' }));
  await assertFails(setDoc(doc(admin, 'otpChallenges', 'c1'), { status: 'CONSUMED' }));
  await assertFails(getDoc(doc(admin, 'otpChallenges', 'c1')));
  await assertFails(getDoc(doc(admin, 'otpRate', 'p_1')));
  await assertFails(getDoc(doc(pw('la-pw'), 'schools', A, 'authSettings', 'methods')), 'non-admins cannot read');
  await assertSucceeds(getDocs(collection(admin, 'schools', A, 'authAudit')));
});

test('a new profile cannot be created with a login map by a client', async () => {
  const admin = pw('la-admin');
  await assertFails(setDoc(doc(admin, 'users', 'la-new'), {
    schoolId: A, branchId: null, name: 'N', email: 'n@x.com', role: 'TEACHER', status: 'ACTIVE', linkedParentId: null,
    login: login(true, ['PASSWORD', 'GOOGLE', 'PHONE_OTP']),
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), createdBy: 'la-admin', updatedBy: 'la-admin',
  }));
});

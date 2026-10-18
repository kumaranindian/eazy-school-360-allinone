'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { provisionLogins } = require('./provision');

// Minimal in-memory Firestore/Auth fake: just what provision.js touches.
function fakeDb(seed) {
  const store = new Map(Object.entries(seed));
  const ref = (path) => ({
    path,
    id: path.split('/').pop(),
    get: async () => ({ exists: store.has(path), id: path.split('/').pop(), data: () => store.get(path) }),
    collection: (c) => coll(`${path}/${c}`),
    update: async (d) => store.set(path, { ...store.get(path), ...d }),
    set: async (d) => store.set(path, d),
  });
  const coll = (path) => {
    const conds = [];
    const q = {
      doc: (i) => ref(`${path}/${i}`),
      where: (f, op, v) => (conds.push([f, v]), q),
      limit: () => q,
      get: async () => ({
        docs: [...store.entries()]
          .filter(([k]) => k.startsWith(`${path}/`) && k.split('/').length === path.split('/').length + 1)
          .filter(([, d]) => conds.every(([f, v]) => d[f] === v))
          .map(([k, d]) => ({ id: k.split('/').pop(), data: () => d, ref: ref(k) })),
      }),
    };
    return q;
  };
  return {
    store,
    collection: (c) => coll(c),
    // Only what provision.js uses: equality filters over every doc whose
    // path has a `/<name>/<id>` tail.
    collectionGroup: (name) => {
      const conds = [];
      const q = {
        where: (f, op, v) => { conds.push([f, v]); return q; },
        get: async () => ({
          docs: [...store.entries()]
            .filter(([k]) => k.split('/').slice(-2)[0] === name)
            .filter(([, d]) => conds.every(([f, v]) => d[f] === v))
            .map(([k, d]) => ({ id: k.split('/').pop(), data: () => d, ref: ref(k) })),
        }),
      };
      return q;
    },
    batch: () => {
      const ops = [];
      return {
        set: (r, d) => ops.push(() => r.set(d)),
        update: (r, d) => ops.push(() => r.update(d)),
        commit: async () => { for (const o of ops) await o(); },
      };
    },
  };
}
let auth_calls = {};
function fakeAuth(existing = {}) {
  auth_calls = {};
  const users = { ...existing };
  let n = 0;
  return {
    users,
    getUserByEmail: async (e) => {
      if (users[e]) return { uid: users[e] };
      const err = new Error('nf'); err.code = 'auth/user-not-found'; throw err;
    },
    createUser: async ({ email, password }) => { users[email] = `uid${++n}`; (auth_calls.created ||= []).push({ email, password }); return { uid: users[email] }; },
    updateUser: async (uid, patch) => {
      (auth_calls.updated ||= []).push({ uid, patch });
      if (patch.email) {
        for (const [e, u] of Object.entries(users)) if (u === uid) delete users[e];
        users[patch.email] = uid;
      }
    },
    revokeRefreshTokens: async (uid) => { (auth_calls.revoked ||= []).push(uid); },
  };
}
const B = 'schools/s1/branches/b1';
const base = () => ({
  'users/admin': { status: 'ACTIVE', schoolId: 's1', role: 'SCHOOL_ADMIN' },
  [`${B}/staff/t1`]: { firstName: 'Asha', lastName: 'K', email: 'Asha@x.com', status: 'ACTIVE', isTeacher: true },
  [`${B}/staff/t2`]: { firstName: 'No', lastName: 'Mail', status: 'ACTIVE', isTeacher: true },
  [`${B}/staff/t3`]: { firstName: 'Linked', lastName: 'Already', email: 'l@x.com', status: 'ACTIVE', userId: 'u9' },
  [`${B}/staff/t4`]: { firstName: 'Clash', lastName: 'Er', email: 'taken@x.com', status: 'ACTIVE', isTeacher: true },
});
const call = (db, auth, data, uid = 'admin') =>
  provisionLogins({ db, auth, now: 'NOW' }, uid, { schoolId: 's1', branchId: 'b1', kind: 'STAFF', ...data });

test('creates login, profile and link; reports each skip reason', async () => {
  const db = fakeDb({ ...base(), 'users/other': { schoolId: 's2' } });
  const auth = fakeAuth({ 'taken@x.com': 'other' });
  const { results } = await call(db, auth, { ids: ['t1', 't2', 't3', 't4', 'nope'] });
  const by = Object.fromEntries(results.map((r) => [r.id, r.outcome]));
  assert.deepStrictEqual(by, { t1: 'CREATED', t2: 'NO_EMAIL', t3: 'ALREADY_LINKED', t4: 'EMAIL_IN_USE', nope: 'NOT_FOUND' });
  const uid = results.find((r) => r.id === 't1').uid;
  assert.strictEqual(db.store.get(`${B}/staff/t1`).userId, uid);
  const prof = db.store.get(`users/${uid}`);
  assert.strictEqual(prof.role, 'TEACHER');
  assert.strictEqual(prof.status, 'ACTIVE');
  assert.strictEqual(prof.email, 'asha@x.com');
});

test('only an admin of that school may provision; branch admins cannot mint branch admins', async () => {
  const db = fakeDb({ ...base(), 'users/ba': { status: 'ACTIVE', schoolId: 's1', branchId: 'b1', role: 'BRANCH_ADMIN' },
    'users/t': { status: 'ACTIVE', schoolId: 's1', branchId: 'b1', role: 'TEACHER' },
    'users/foreign': { status: 'ACTIVE', schoolId: 's2', role: 'SCHOOL_ADMIN' } });
  const auth = fakeAuth();
  assert.strictEqual((await call(db, auth, { ids: ['t1'] }, 't')).error, 'PERMISSION_DENIED');
  assert.strictEqual((await call(db, auth, { ids: ['t1'] }, 'foreign')).error, 'PERMISSION_DENIED');
  assert.strictEqual((await call(db, auth, { ids: ['t1'], role: 'BRANCH_ADMIN' }, 'ba')).error, 'PERMISSION_DENIED');
  assert.strictEqual((await call(db, auth, { ids: ['t1'] }, 'ba')).results[0].outcome, 'CREATED');
});

test('rejects bad input and oversize batches', async () => {
  const db = fakeDb(base());
  const auth = fakeAuth();
  assert.strictEqual((await call(db, auth, { ids: [] })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await call(db, auth, { ids: Array.from({ length: 51 }, (_, i) => `i${i}`) })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await call(db, auth, { ids: ['t1'], kind: 'X' })).error, 'INVALID_ARGUMENT');
});

test('one parent of several children: one login, access spans every child', async () => {
  const link = (studentId) => ({ schoolId: 's1', branchId: 'b1', parentId: 'p1', studentId, status: 'ACTIVE', canAccessPortal: false });
  const db = fakeDb({
    ...base(),
    [`${B}/parents/p1`]: { firstName: 'Ravi', lastName: 'Kumar', email: 'ravi@x.com', status: 'ACTIVE', phone: '99' },
    [`${B}/students/st1`]: { status: 'ACTIVE', currentClassId: 'c1', currentSectionId: 'A' },
    [`${B}/students/st2`]: { status: 'ACTIVE', currentClassId: 'c1', currentSectionId: 'B' },
    [`${B}/students/st3`]: { status: 'ACTIVE', currentClassId: 'c2', currentSectionId: 'A' },
    [`${B}/students/st4`]: { status: 'INACTIVE', currentClassId: 'c9', currentSectionId: 'Z' },
    [`${B}/students/st1/parentLinks/p1`]: link('st1'),
    [`${B}/students/st2/parentLinks/p1`]: link('st2'),
    [`${B}/students/st3/parentLinks/p1`]: link('st3'),
    [`${B}/students/st4/parentLinks/p1`]: link('st4'),
  });
  const auth = fakeAuth();
  const data = { kind: 'PARENT', ids: ['p1'], enablePortal: true };
  const { results } = await call(db, auth, data);
  assert.strictEqual(results.length, 1);
  assert.strictEqual(results[0].outcome, 'CREATED');
  assert.strictEqual(Object.keys(auth.users).length, 1);
  assert.strictEqual(db.store.get(`users/${results[0].uid}`).linkedParentId, 'p1');
  assert.strictEqual(db.store.get(`${B}/parents/p1`).linkedUserId, results[0].uid);
  for (const s of ['st1', 'st2', 'st3', 'st4']) {
    assert.strictEqual(db.store.get(`${B}/students/${s}/parentLinks/p1`).canAccessPortal, true);
  }
  const access = db.store.get(`${B}/parentAccess/p1`);
  assert.deepStrictEqual(access.classKeys, ['c1', 'c2']);
  assert.deepStrictEqual(access.sectionKeys, ['c1__A', 'c1__B', 'c2__A']); // inactive child contributes nothing
  // Selecting the same parent again (e.g. via a second child) changes nothing.
  const again = await call(db, auth, data);
  assert.strictEqual(again.results[0].outcome, 'ALREADY_LINKED');
  assert.strictEqual(Object.keys(auth.users).length, 1);
});

test('an email typed by the admin is used and saved on a record that had none', async () => {
  const db = fakeDb({ ...base(), [`${B}/parents/p2`]: { firstName: 'No', lastName: 'Email', status: 'ACTIVE' } });
  const auth = fakeAuth();
  const { results } = await call(db, auth, { kind: 'PARENT', ids: ['p2'], emails: { p2: 'Typed@X.com' } });
  assert.strictEqual(results[0].outcome, 'CREATED');
  assert.strictEqual(db.store.get(`${B}/parents/p2`).email, 'typed@x.com');
});

test('two parent records sharing one email: second is refused, not merged', async () => {
  const db = fakeDb({
    ...base(),
    [`${B}/parents/pa`]: { firstName: 'A', lastName: 'One', email: 'same@x.com', status: 'ACTIVE' },
    [`${B}/parents/pb`]: { firstName: 'B', lastName: 'Two', email: 'same@x.com', status: 'ACTIVE' },
  });
  const { results } = await call(db, fakeAuth(), { kind: 'PARENT', ids: ['pa', 'pb'] });
  assert.deepStrictEqual(results.map((r) => r.outcome), ['CREATED', 'EMAIL_IN_USE']);
});

test('an existing /users profile for the email is mapped to the record, not refused', async () => {
  const db = fakeDb({
    ...base(),
    'users/pre-t': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', status: 'ACTIVE', email: 'asha@x.com' },
    'users/pre-p': { schoolId: 's1', branchId: 'b1', role: 'PARENT', status: 'ACTIVE', email: 'par@x.com' },
    [`${B}/parents/p1`]: { firstName: 'P', lastName: 'One', email: 'par@x.com', status: 'ACTIVE' },
  });
  const auth = fakeAuth({ 'asha@x.com': 'pre-t', 'par@x.com': 'pre-p' });
  const st = await call(db, auth, { ids: ['t1'] });
  assert.strictEqual(st.results[0].outcome, 'CREATED');
  assert.strictEqual(st.results[0].mapped, true);
  assert.strictEqual(db.store.get(`${B}/staff/t1`).userId, 'pre-t');
  assert.strictEqual(db.store.get('users/pre-t').role, 'TEACHER');
  const pa = await call(db, auth, { kind: 'PARENT', ids: ['p1'] });
  assert.strictEqual(pa.results[0].mapped, true);
  assert.strictEqual(db.store.get(`${B}/parents/p1`).linkedUserId, 'pre-p');
  assert.strictEqual(db.store.get('users/pre-p').linkedParentId, 'p1');
});

test('a profile of another school, another role or another person is still EMAIL_IN_USE', async () => {
  const db = fakeDb({
    ...base(),
    'users/x1': { schoolId: 's2', role: 'TEACHER' },
    'users/x2': { schoolId: 's1', branchId: 'b1', role: 'SCHOOL_ADMIN' },
    [`${B}/staff/t5`]: { firstName: 'O', lastName: 'Wner', email: 'o@x.com', status: 'ACTIVE', userId: 'x3' },
    'users/x3': { schoolId: 's1', branchId: 'b1', role: 'TEACHER' },
    [`${B}/staff/ta`]: { firstName: 'A', lastName: 'A', email: 'a@x.com', status: 'ACTIVE', isTeacher: true },
    [`${B}/staff/tb`]: { firstName: 'B', lastName: 'B', email: 'b@x.com', status: 'ACTIVE', isTeacher: true },
    [`${B}/staff/tc`]: { firstName: 'C', lastName: 'C', email: 'o@x.com', status: 'ACTIVE', isTeacher: true },
  });
  const auth = fakeAuth({ 'a@x.com': 'x1', 'b@x.com': 'x2', 'o@x.com': 'x3' });
  const { results } = await call(db, auth, { ids: ['ta', 'tb', 'tc'] });
  assert.deepStrictEqual(results.map((r) => r.outcome), ['EMAIL_IN_USE', 'EMAIL_IN_USE', 'EMAIL_IN_USE']);
});

test('the same person in a second branch gets a per-branch role, not a second account (school admin only)', async () => {
  const S2 = 'schools/s1/branches/b2';
  const seed = () => ({
    ...base(),
    'users/ba2': { status: 'ACTIVE', schoolId: 's1', branchId: 'b2', role: 'BRANCH_ADMIN' },
    'users/home': { status: 'ACTIVE', schoolId: 's1', branchId: 'b1', role: 'TEACHER', email: 'asha@x.com' },
    [`${B}/staff/home`]: { userId: 'home', status: 'ACTIVE', isTeacher: true },
    [`${S2}/staff/x1`]: { firstName: 'Asha', lastName: 'K', email: 'asha@x.com', status: 'ACTIVE', isTeacher: true },
  });
  const run = (db, uid) => provisionLogins({ db, auth: fakeAuth({ 'asha@x.com': 'home' }), now: 'NOW' }, uid,
    { schoolId: 's1', branchId: 'b2', kind: 'STAFF', ids: ['x1'] });

  // a branch admin of the second branch must not attach someone else's login
  const denied = fakeDb(seed());
  assert.strictEqual((await run(denied, 'ba2')).results[0].outcome, 'EMAIL_IN_USE');
  assert.strictEqual(denied.store.get(`${S2}/staff/x1`).userId, undefined);

  const db = fakeDb(seed());
  const { results } = await run(db, 'admin');
  assert.strictEqual(results[0].outcome, 'CREATED');
  assert.strictEqual(results[0].crossBranch, true);
  const u = db.store.get('users/home');
  assert.deepStrictEqual(u.branchRoles, { b2: 'TEACHER' });
  assert.strictEqual(u.branchId, 'b1');
  assert.strictEqual(u.role, 'TEACHER');
  assert.strictEqual(db.store.get(`${S2}/staff/x1`).userId, 'home');
});

test('cross-branch mapping never merges admins, parents or other schools', async () => {
  const S2 = 'schools/s1/branches/b2';
  for (const home of [
    { role: 'SCHOOL_ADMIN', schoolId: 's1', branchId: 'b1' },
    { role: 'PARENT', schoolId: 's1', branchId: 'b1' },
    { role: 'TEACHER', schoolId: 's2', branchId: 'b1' },
  ]) {
    const db = fakeDb({ ...base(), 'users/home': { status: 'ACTIVE', ...home },
      [`${S2}/staff/x1`]: { firstName: 'A', lastName: 'K', email: 'asha@x.com', status: 'ACTIVE', isTeacher: true } });
    const { results } = await provisionLogins({ db, auth: fakeAuth({ 'asha@x.com': 'home' }), now: 'NOW' }, 'admin',
      { schoolId: 's1', branchId: 'b2', kind: 'STAFF', ids: ['x1'] });
    assert.strictEqual(results[0].outcome, 'EMAIL_IN_USE', JSON.stringify(home));
  }
});


// ---- password setup options & email change --------------------------------
const { nameMobilePassword, randomTempPassword, passwordPolicyOk } = require('./provision');

test('NAME_MOBILE: first four letters upper-cased + last five digits', () => {
  assert.strictEqual(nameMobilePassword('Karthikeyan', '9876543210'), 'KART43210');
  assert.strictEqual(nameMobilePassword('K. Ra', '+91 98765-43210'), null);
  assert.strictEqual(nameMobilePassword('Ka Rthik', '+91 98765-43210'), 'KART43210');
  assert.strictEqual(nameMobilePassword('Ann', '9876543210'), null);
  assert.strictEqual(nameMobilePassword('Karthik', '1234'), null);
});

test('RANDOM_TEMP passwords satisfy the policy and differ', () => {
  const a = randomTempPassword();
  const b = randomTempPassword();
  assert.ok(passwordPolicyOk(a));
  assert.notStrictEqual(a, b);
});

const withPhone = () => ({ ...base(), [`${B}/staff/t1`]: { ...base()[`${B}/staff/t1`], phone: '9876543210', firstName: 'Karthikeyan' } });

test('NAME_MOBILE sets the derived password server-side, flags a forced change, never stores it', async () => {
  const db = fakeDb(withPhone());
  const auth = fakeAuth();
  const { results } = await call(db, auth, { ids: ['t1'], passwordSetup: { option: 'NAME_MOBILE' } });
  assert.strictEqual(results[0].outcome, 'CREATED');
  assert.strictEqual(auth_calls.created[0].password, 'KART43210');
  assert.strictEqual(results[0].tempPassword, undefined);
  assert.strictEqual(db.store.get(`users/${results[0].uid}`).login.mustChangePassword, true);
  assert.ok(!JSON.stringify([...db.store.entries()]).includes('KART43210'));
});

test('NAME_MOBILE with a missing mobile is refused for that row, not weakened', async () => {
  const db = fakeDb(base());
  const { results } = await call(db, fakeAuth(), { ids: ['t1'], passwordSetup: { option: 'NAME_MOBILE' } });
  assert.strictEqual(results[0].outcome, 'PASSWORD_INPUT_MISSING');
  assert.strictEqual(db.store.get(`${B}/staff/t1`).userId, undefined);
});

test('RANDOM_TEMP returns the password once to the admin and stores nothing', async () => {
  const db = fakeDb(base());
  const { results } = await call(db, fakeAuth(), { ids: ['t1'], passwordSetup: { option: 'RANDOM_TEMP' } });
  const pw = results[0].tempPassword;
  assert.ok(passwordPolicyOk(pw));
  assert.ok(!JSON.stringify([...db.store.entries()]).includes(pw));
});

test('ADMIN_DEFINED validates the policy, applies it, and never echoes or stores it', async () => {
  const bad = await call(fakeDb(base()), fakeAuth(), { ids: ['t1'], passwordSetup: { option: 'ADMIN_DEFINED', password: 'short' } });
  assert.strictEqual(bad.error, 'INVALID_ARGUMENT');
  const db = fakeDb(base());
  const { results } = await call(db, fakeAuth(), { ids: ['t1'], passwordSetup: { option: 'ADMIN_DEFINED', password: 'Welcome2026' } });
  assert.strictEqual(auth_calls.created[0].password, 'Welcome2026');
  assert.strictEqual(results[0].tempPassword, undefined);
  assert.ok(!JSON.stringify([...db.store.entries()]).includes('Welcome2026'));
});

test('link-based options set no known password and no forced change', async () => {
  for (const option of ['ACTIVATION_EMAIL', 'RESET_LINK']) {
    const db = fakeDb(base());
    const { results } = await call(db, fakeAuth(), { ids: ['t1'], passwordSetup: { option } });
    assert.strictEqual(results[0].passwordSet, false);
    assert.strictEqual(db.store.get(`users/${results[0].uid}`).login.mustChangePassword, undefined);
  }
});

test('an unknown option is rejected', async () => {
  const out = await call(fakeDb(base()), fakeAuth(), { ids: ['t1'], passwordSetup: { option: 'NOPE' } });
  assert.strictEqual(out.error, 'INVALID_ARGUMENT');
});

test('schools without password sign-in get accounts but no password', async () => {
  const db = fakeDb({ ...withPhone(), 'schools/s1/authSettings/methods': { methods: ['GOOGLE'] } });
  const { results } = await call(db, fakeAuth(), { ids: ['t1'], passwordSetup: { option: 'NAME_MOBILE' } });
  assert.strictEqual(results[0].outcome, 'CREATED');
  assert.notStrictEqual(auth_calls.created[0].password, 'KART43210');
  assert.strictEqual(results[0].passwordSet, false);
});

test('changing a linked email activates the new one, drops the old, revokes sessions, keeps history', async () => {
  const db = fakeDb({
    ...base(),
    'users/u9': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', email: 'l@x.com', status: 'ACTIVE' },
  });
  const auth = fakeAuth({ 'l@x.com': 'u9' });
  const { results } = await call(db, auth, { ids: ['t3'], emails: { t3: 'New@X.com' } });
  assert.strictEqual(results[0].outcome, 'EMAIL_UPDATED');
  assert.strictEqual(auth.users['new@x.com'], 'u9');
  assert.strictEqual(auth.users['l@x.com'], undefined);
  assert.deepStrictEqual(auth_calls.revoked, ['u9']);
  const prof = db.store.get('users/u9');
  assert.strictEqual(prof.email, 'new@x.com');
  assert.strictEqual(prof.previousEmails[0].email, 'l@x.com');
  assert.strictEqual(db.store.get(`${B}/staff/t3`).email, 'new@x.com');
});

test('changing to an email that belongs to another login is refused and changes nothing', async () => {
  const db = fakeDb({ ...base(), 'users/u9': { schoolId: 's1', role: 'TEACHER', email: 'l@x.com' } });
  const auth = fakeAuth({ 'l@x.com': 'u9', 'taken@x.com': 'other' });
  const { results } = await call(db, auth, { ids: ['t3'], emails: { t3: 'taken@x.com' } });
  assert.strictEqual(results[0].outcome, 'EMAIL_IN_USE');
  assert.strictEqual(db.store.get('users/u9').email, 'l@x.com');
  assert.strictEqual(auth_calls.updated, undefined);
});

test('a branch admin cannot move the email of a branch admin account', async () => {
  const db = fakeDb({
    ...base(),
    'users/ba': { status: 'ACTIVE', schoolId: 's1', branchId: 'b1', role: 'BRANCH_ADMIN' },
    'users/u9': { schoolId: 's1', branchId: 'b1', role: 'BRANCH_ADMIN', email: 'l@x.com' },
  });
  const { results } = await call(db, fakeAuth({ 'l@x.com': 'u9' }), { ids: ['t3'], emails: { t3: 'n@x.com' } }, 'ba');
  assert.strictEqual(results[0].outcome, 'EMAIL_IN_USE');
});


const { changeInitialPassword } = require('./provision');
test('changeInitialPassword: only while flagged, policy enforced, flag cleared, sessions revoked', async () => {
  const db = fakeDb({ 'users/u1': { login: { mustChangePassword: true, enabled: true } }, 'users/u2': { login: { enabled: true } } });
  const auth = fakeAuth();
  const ctx = { db, auth, now: 'NOW' };
  assert.deepStrictEqual(await changeInitialPassword(ctx, 'u1', { newPassword: 'short' }), { error: 'INVALID_ARGUMENT' });
  assert.deepStrictEqual(await changeInitialPassword(ctx, 'u2', { newPassword: 'Another2026' }), { error: 'NOT_REQUIRED' });
  assert.deepStrictEqual(await changeInitialPassword(ctx, 'u1', { newPassword: 'Another2026' }), { ok: true });
  assert.strictEqual(auth_calls.updated[0].patch.password, 'Another2026');
  assert.deepStrictEqual(auth_calls.revoked, ['u1']);
  assert.strictEqual(db.store.get('users/u1').login.mustChangePassword, undefined);
});

const { resetLoginPassword } = require('./provision');
const resetSeed = () => ({
  ...base(),
  [`${B}/staff/t5`]: { firstName: 'Meera', lastName: 'S', phone: '+91 98765 43210', status: 'ACTIVE', userId: 'u5' },
  'users/u5': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', login: { enabled: true } },
  'users/ba': { status: 'ACTIVE', schoolId: 's1', branchId: 'b1', role: 'BRANCH_ADMIN' },
  'users/u9': { schoolId: 's1', branchId: 'b1', role: 'BRANCH_ADMIN' },
});
const reset = (db, auth, extra = {}, uid = 'admin') =>
  resetLoginPassword({ db, auth, now: 'NOW' }, uid, { schoolId: 's1', branchId: 'b1', kind: 'STAFF', id: 't5', passwordSetup: { option: 'NAME_MOBILE' }, ...extra }, {});

test('resetLoginPassword: sets the chosen password, flags must-change, revokes sessions, audits', async () => {
  const db = fakeDb(resetSeed());
  const auth = fakeAuth();
  assert.deepStrictEqual(await reset(db, auth), { result: { ok: true } });
  assert.strictEqual(auth_calls.updated[0].patch.password, 'MEER43210');
  assert.deepStrictEqual(auth_calls.revoked, ['u5']);
  assert.strictEqual(db.store.get('users/u5').login.mustChangePassword, true);
  assert.ok([...db.store.keys()].some((k) => k.startsWith('schools/s1/authAudit/')));

  const r = await reset(db, fakeAuth(), { passwordSetup: { option: 'RANDOM_TEMP' } });
  assert.ok(/^[A-Za-z2-9]{12}$/.test(r.result.tempPassword));
  const a = fakeAuth();
  assert.deepStrictEqual(await reset(db, a, { passwordSetup: { option: 'ADMIN_DEFINED', password: 'Welcome2026' } }), { result: { ok: true } });
  assert.strictEqual(auth_calls.updated[0].patch.password, 'Welcome2026');
});

test('resetLoginPassword: validation, permissions and targets', async () => {
  const db = fakeDb(resetSeed());
  const auth = fakeAuth();
  assert.strictEqual((await reset(db, auth, { passwordSetup: { option: 'RESET_LINK' } })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await reset(db, auth, { passwordSetup: { option: 'ADMIN_DEFINED', password: 'short' } })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await reset(db, auth, { id: 'nope' })).error, 'NOT_FOUND');
  assert.strictEqual((await reset(db, auth, { id: 't1' })).error, 'NO_ACCOUNT');
  assert.strictEqual((await reset(db, auth, {}, 'u5')).error, 'PERMISSION_DENIED');
  // a branch admin cannot touch a branch admin; nobody resets themselves
  assert.strictEqual((await reset(db, auth, { id: 't3' }, 'ba')).error, 'PERMISSION_DENIED');
  assert.strictEqual((await reset(db, auth, { id: 't3', passwordSetup: { option: 'RANDOM_TEMP' } }, 'admin')).result.ok, true);
  assert.strictEqual((await reset(db, auth, { id: 't3' }, 'u9')).error, 'PERMISSION_DENIED');
  // NAME_MOBILE needs the record data
  const db2 = fakeDb({ ...resetSeed(), [`${B}/staff/t5`]: { firstName: 'Al', status: 'ACTIVE', userId: 'u5' } });
  assert.strictEqual((await reset(db2, fakeAuth())).error, 'PASSWORD_INPUT_MISSING');
});

test('resetLoginPassword (bulk): one outcome per person, bad rows do not stop the rest', async () => {
  const db = fakeDb({
    ...resetSeed(),
    [`${B}/staff/t6`]: { firstName: 'Ravi', lastName: 'K', phone: '9000012345', status: 'ACTIVE', userId: 'u6' },
    'users/u6': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', login: { enabled: true } },
  });
  const auth = fakeAuth();
  const r = await reset(db, auth, { id: undefined, ids: ['t5', 't6', 't1', 'nope', 't3'], passwordSetup: { option: 'NAME_MOBILE' } }, 'ba');
  const by = Object.fromEntries(r.result.results.map((x) => [x.id, x.outcome]));
  // t1 has no login; t3 is a branch admin (a branch admin may not touch one)
  assert.deepStrictEqual(by, { t5: 'RESET', t6: 'RESET', t1: 'NO_ACCOUNT', nope: 'NOT_FOUND', t3: 'PERMISSION_DENIED' });
  assert.deepStrictEqual(auth_calls.updated.map((u) => u.patch.password), ['MEER43210', 'RAVI12345']);
  assert.strictEqual(db.store.get('users/u6').login.mustChangePassword, true);
});

test('resetLoginPassword (bulk): random passwords are distinct and returned per person; limits enforced', async () => {
  const db = fakeDb({
    ...resetSeed(),
    [`${B}/staff/t6`]: { firstName: 'Ravi', lastName: 'K', phone: '9000012345', status: 'ACTIVE', userId: 'u6' },
    'users/u6': { schoolId: 's1', branchId: 'b1', role: 'TEACHER', login: { enabled: true } },
  });
  const r = await reset(db, fakeAuth(), { id: undefined, ids: ['t5', 't6'], passwordSetup: { option: 'RANDOM_TEMP' } });
  const temps = r.result.results.map((x) => x.tempPassword);
  assert.ok(temps.every((t) => /^[A-Za-z2-9]{12}$/.test(t)));
  assert.notStrictEqual(temps[0], temps[1]);
  assert.strictEqual((await reset(db, fakeAuth(), { id: undefined, ids: [] })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await reset(db, fakeAuth(), { id: undefined, ids: Array.from({ length: 51 }, (_, i) => `i${i}`) })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await reset(db, fakeAuth(), { id: undefined, ids: ['t5'] }, 'u5')).error, 'PERMISSION_DENIED');
});

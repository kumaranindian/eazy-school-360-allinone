'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { createSchoolAdmin } = require('./provision');

// Minimal in-memory Firestore/Auth fake: just what createSchoolAdmin touches.
function fakeDb(seed) {
  const store = new Map(Object.entries(seed));
  let auto = 0;
  const ref = (path) => ({
    path,
    id: path.split('/').pop(),
    get: async () => ({ exists: store.has(path), id: path.split('/').pop(), data: () => store.get(path) }),
    collection: (c) => coll(`${path}/${c}`),
    update: async (d) => store.set(path, { ...store.get(path), ...d }),
    set: async (d) => store.set(path, d),
  });
  const coll = (path) => ({
    doc: (i) => ref(`${path}/${i === undefined ? `auto${++auto}` : i}`),
  });
  return {
    store,
    collection: (c) => coll(c),
    batch: () => {
      const ops = [];
      return {
        set: (r, d) => ops.push(() => r.set(d)),
        update: (r, d) => ops.push(() => r.update(d)),
        commit: async () => {
          for (const o of ops) await o();
        },
      };
    },
  };
}
function fakeAuth(existing = {}) {
  const users = { ...existing };
  const calls = { created: [], updated: [], revoked: [] };
  let n = 0;
  return {
    users,
    calls,
    getUserByEmail: async (e) => {
      if (users[e]) return { uid: users[e] };
      const err = new Error('nf');
      err.code = 'auth/user-not-found';
      throw err;
    },
    createUser: async ({ email, password }) => {
      users[email] = `new${++n}`;
      calls.created.push({ email, password });
      return { uid: users[email] };
    },
    updateUser: async (uid, patch) => calls.updated.push({ uid, patch }),
    revokeRefreshTokens: async (uid) => calls.revoked.push(uid),
  };
}

const base = () => ({
  'users/boss': { status: 'ACTIVE', schoolId: 's1', branchId: 'main', role: 'SCHOOL_ADMIN' },
  'users/branch': { status: 'ACTIVE', schoolId: 's1', branchId: 'main', role: 'BRANCH_ADMIN' },
  'users/teacher': { status: 'ACTIVE', schoolId: 's1', branchId: 'main', role: 'TEACHER' },
  'users/other-boss': { status: 'ACTIVE', schoolId: 's2', branchId: 'main', role: 'SCHOOL_ADMIN' },
  'users/disabled-boss': { status: 'DISABLED', schoolId: 's1', branchId: 'main', role: 'SCHOOL_ADMIN' },
  'users/parent-uid': { status: 'ACTIVE', schoolId: 's1', role: 'PARENT', email: 'p@x.com' },
});
const run = (db, auth, data, uid = 'boss') =>
  createSchoolAdmin({ db, auth, now: 'NOW' }, uid, { schoolId: 's1', name: 'New Admin', email: 'New@X.com', ...data }, undefined);

test('a school admin creates another SCHOOL_ADMIN in their own school, with an audit entry', async () => {
  const db = fakeDb(base());
  const auth = fakeAuth();
  const out = await run(db, auth, {});
  assert.strictEqual(out.outcome, 'CREATED');
  assert.strictEqual(out.email, 'new@x.com');
  const profile = db.store.get(`users/${out.uid}`);
  assert.strictEqual(profile.role, 'SCHOOL_ADMIN');
  assert.strictEqual(profile.schoolId, 's1');
  assert.strictEqual(profile.branchId, 'main');
  assert.strictEqual(profile.status, 'ACTIVE');
  assert.strictEqual(profile.createdBy, 'boss');
  // Activation email: no password anyone knows, nothing to change at sign-in.
  assert.strictEqual(out.passwordSet, false);
  assert.strictEqual(out.tempPassword, undefined);
  assert.strictEqual(profile.login.mustChangePassword, undefined);
  const audit = [...db.store.entries()].find(([k]) => k.startsWith('schools/s1/authAudit/'));
  assert.strictEqual(audit[1].type, 'SCHOOL_ADMIN_CREATED');
  assert.strictEqual(audit[1].targetUid, out.uid);
});

test('only an active school admin of that school may do it', async () => {
  for (const uid of ['branch', 'teacher', 'other-boss', 'disabled-boss', 'parent-uid', 'nobody']) {
    const db = fakeDb(base());
    const auth = fakeAuth();
    const out = await run(db, auth, {}, uid);
    assert.strictEqual(out.error, 'PERMISSION_DENIED', uid);
    assert.deepStrictEqual(auth.calls.created, [], uid);
  }
});

test('an email that already has a login is refused — nobody is promoted or merged', async () => {
  const db = fakeDb(base());
  const auth = fakeAuth({ 'p@x.com': 'parent-uid' });
  const out = await run(db, auth, { email: 'p@x.com' });
  assert.strictEqual(out.error, 'EMAIL_IN_USE');
  assert.strictEqual(db.store.get('users/parent-uid').role, 'PARENT');
  assert.deepStrictEqual(auth.calls.created, []);
});

test('a random temporary password is returned once and the admin must change it', async () => {
  const db = fakeDb(base());
  const auth = fakeAuth();
  const out = await run(db, auth, { passwordSetup: { option: 'RANDOM_TEMP' } });
  assert.strictEqual(out.passwordSet, true);
  assert.match(out.tempPassword, /^(?=.*[A-Za-z])(?=.*\d).{12}$/);
  assert.strictEqual(db.store.get(`users/${out.uid}`).login.mustChangePassword, true);
  assert.strictEqual(auth.calls.created[0].password, out.tempPassword);
});

test('an admin-defined password must meet the policy and is never echoed back', async () => {
  const bad = await run(fakeDb(base()), fakeAuth(), { passwordSetup: { option: 'ADMIN_DEFINED', password: 'short' } });
  assert.strictEqual(bad.error, 'INVALID_ARGUMENT');
  const db = fakeDb(base());
  const out = await run(db, fakeAuth(), { passwordSetup: { option: 'ADMIN_DEFINED', password: 'Welcome123' } });
  assert.strictEqual(out.passwordSet, true);
  assert.strictEqual(out.tempPassword, undefined);
  assert.ok(!JSON.stringify(out).includes('Welcome123'));
});

test('bad input changes nothing', async () => {
  for (const data of [{ name: '' }, { name: 'A' }, { email: 'nope' }, { email: '' }, { passwordSetup: { option: 'RESET_LINK' } }, { phone: 5 }]) {
    const auth = fakeAuth();
    const out = await run(fakeDb(base()), auth, data);
    assert.strictEqual(out.error, 'INVALID_ARGUMENT', JSON.stringify(data));
    assert.deepStrictEqual(auth.calls.created, []);
  }
  const out = await createSchoolAdmin({ db: fakeDb(base()), auth: fakeAuth(), now: 'NOW' }, 'boss', { name: 'X Y', email: 'a@b.co' });
  assert.strictEqual(out.error, 'INVALID_ARGUMENT'); // no schoolId
});

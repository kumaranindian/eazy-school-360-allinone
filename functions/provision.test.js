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
function fakeAuth(existing = {}) {
  const users = { ...existing };
  let n = 0;
  return {
    users,
    getUserByEmail: async (e) => {
      if (users[e]) return { uid: users[e] };
      const err = new Error('nf'); err.code = 'auth/user-not-found'; throw err;
    },
    createUser: async ({ email }) => { users[email] = `uid${++n}`; return { uid: users[email] }; },
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

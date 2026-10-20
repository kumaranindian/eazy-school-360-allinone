'use strict';

// In-memory Firestore/Auth fakes shared by the node:test suites. Supports the
// subset the auth code uses: paths, equality `where` (incl. dotted fields),
// orderBy('__name__'), limit, startAfter, batch, transactions, dotted update.

const getPath = (o, p) => p.split('.').reduce((a, k) => (a == null ? undefined : a[k]), o);
const num = (v) => (v instanceof Date ? v.getTime() : v && v.toMillis ? v.toMillis() : v);
// Supports ==, <, <=, >, >=, in, array-contains on (dotted) fields.
function matches(doc, [field, op, want]) {
  const have = getPath(doc, field);
  switch (op) {
    case '<': return num(have) < num(want);
    case '<=': return have != null && num(have) <= num(want);
    case '>': return num(have) > num(want);
    case '>=': return have != null && num(have) >= num(want);
    case 'in': return Array.isArray(want) && want.includes(have);
    case 'array-contains': return Array.isArray(have) && have.includes(want);
    default: return have === want;
  }
}
function setPath(o, p, v) {
  const ks = p.split('.');
  let c = o;
  for (const k of ks.slice(0, -1)) c = c[k] = { ...(c[k] || {}) };
  c[ks[ks.length - 1]] = v;
}

// A Map that counts writes per key, so transactions can detect a conflicting
// commit the way Firestore does (optimistic concurrency).
class VersionedStore extends Map {
  versions = new Map();
  bump(k) {
    this.versions.set(k, (this.versions.get(k) || 0) + 1);
  }
  set(k, v) {
    this.bump(k);
    return super.set(k, v);
  }
  delete(k) {
    this.bump(k);
    return super.delete(k);
  }
}

function fakeDb(seed = {}) {
  const store = new VersionedStore();
  for (const [k, v] of Object.entries(seed)) store.set(k, structuredClone(v));
  let auto = 0;
  const snap = (path) => ({
    exists: store.has(path),
    id: path.split('/').pop(),
    ref: ref(path),
    data: () => (store.has(path) ? structuredClone(store.get(path)) : undefined),
  });
  const ref = (path) => ({
    path,
    id: path.split('/').pop(),
    get: async () => snap(path),
    set: async (d) => void store.set(path, structuredClone(d)),
    // Like Firestore: fails when the document already exists (atomically).
    create: async (d) => {
      if (store.has(path)) throw Object.assign(new Error('Document already exists'), { code: 6 });
      store.set(path, structuredClone(d));
    },
    delete: async () => void store.delete(path),
    update: async (d) => {
      if (!store.has(path)) throw new Error(`no doc ${path}`);
      const cur = structuredClone(store.get(path));
      for (const [k, v] of Object.entries(d)) setPath(cur, k, v);
      store.set(path, cur);
    },
    collection: (c) => coll(`${path}/${c}`),
  });
  const coll = (path) => {
    const conds = [];
    let lim = Infinity;
    let after = null;
    const q = {
      doc: (id) => ref(`${path}/${id || `auto${++auto}`}`),
      where: (f, op, v) => (conds.push([f, op, v]), q),
      add: async (d) => {
        const r = ref(`${path}/auto${++auto}`);
        await r.set(d);
        return r;
      },
      orderBy: () => q,
      limit: (n) => ((lim = n), q),
      startAfter: (d) => ((after = d.ref.path), q),
      get: async () => {
        const depth = path.split('/').length + 1;
        let rows = [...store.keys()]
          .filter((k) => k.startsWith(`${path}/`) && k.split('/').length === depth)
          .sort()
          .filter((k) => !after || k > after)
          .filter((k) => conds.every((c) => matches(store.get(k), c)));
        rows = rows.slice(0, lim);
        return { docs: rows.map(snap) };
      },
    };
    return q;
  };
  const group = (name) => {
    const conds = [];
    let lim = Infinity;
    let after = null;
    const q = {
      where: (f, op, v) => (conds.push([f, op, v]), q),
      orderBy: () => q,
      limit: (n) => ((lim = n), q),
      startAfter: (d) => ((after = d.ref.path), q),
      get: async () => ({
        docs: [...store.keys()]
          .filter((k) => k.split('/').slice(-2)[0] === name)
          .filter((k) => conds.every((c) => matches(store.get(k), c)))
          .sort()
          .filter((k) => !after || k > after)
          .slice(0, lim)
          .map(snap),
      }),
    };
    return q;
  };
  const writer = (ops) => ({
    set: (r, d) => ops.push(() => r.set(d)),
    update: (r, d) => ops.push(() => r.update(d)),
    delete: (r) => ops.push(() => r.delete()),
  });
  return {
    store,
    collection: coll,
    getAll: async (...refs) => Promise.all(refs.map((r) => r.get())),
    collectionGroup: group,
    batch: () => {
      const ops = [];
      return { ...writer(ops), commit: async () => { for (const o of ops) await o(); } };
    },
    // Optimistic transaction: reads are versioned; if another commit touched a
    // document it read, the function re-runs (like the real SDK). The commit
    // check and the writes happen in one synchronous block, so they are atomic.
    runTransaction: async (fn) => {
      for (let attempt = 0; attempt < 8; attempt++) {
        const reads = new Map();
        const ops = [];
        const tx = {
          ...writer(ops),
          get: async (r) => {
            if (r.path) reads.set(r.path, store.versions.get(r.path) || 0);
            return r.get ? r.get() : r;
          },
        };
        const out = await fn(tx);
        if ([...reads].some(([p, v]) => (store.versions.get(p) || 0) !== v)) continue;
        await Promise.all(ops.map((o) => o()));
        return out;
      }
      throw Object.assign(new Error('transaction aborted: too much contention'), { code: 10 });
    },
  };
}

function fakeAuth(existing = {}) {
  const users = {};
  const byEmail = {};
  let n = 0;
  const revoked = [];
  const add = (uid, o) => (users[uid] = { uid, emailVerified: false, metadata: {}, ...o }, o.email && (byEmail[o.email] = uid));
  for (const [email, uid] of Object.entries(existing)) add(uid, { email });
  return {
    users,
    revoked,
    getUser: async (uid) => {
      if (!users[uid]) throw Object.assign(new Error('nf'), { code: 'auth/user-not-found' });
      return users[uid];
    },
    getUserByEmail: async (e) => {
      if (byEmail[e]) return users[byEmail[e]];
      throw Object.assign(new Error('nf'), { code: 'auth/user-not-found' });
    },
    createUser: async (o) => {
      const uid = `uid${++n}`;
      add(uid, o);
      return { uid };
    },
    updateUser: async (uid, o) => {
      if (!users[uid]) throw Object.assign(new Error('nf'), { code: 'auth/user-not-found' });
      Object.assign(users[uid], o, { passwordReset: !!o.password });
    },
    deleteUser: async (uid) => {
      if (!users[uid]) throw Object.assign(new Error('nf'), { code: 'auth/user-not-found' });
      delete users[uid];
    },
    revokeRefreshTokens: async (uid) => void revoked.push(uid),
    createCustomToken: async (uid, claims) => `token:${uid}:${claims.via}`,
  };
}

module.exports = { fakeDb, fakeAuth };

'use strict';

// In-memory Firestore/Auth fakes shared by the node:test suites. Supports the
// subset the auth code uses: paths, equality `where` (incl. dotted fields),
// orderBy('__name__'), limit, startAfter, batch, transactions, dotted update.

const getPath = (o, p) => p.split('.').reduce((a, k) => (a == null ? undefined : a[k]), o);
function setPath(o, p, v) {
  const ks = p.split('.');
  let c = o;
  for (const k of ks.slice(0, -1)) c = c[k] = { ...(c[k] || {}) };
  c[ks[ks.length - 1]] = v;
}

function fakeDb(seed = {}) {
  const store = new Map(Object.entries(seed).map(([k, v]) => [k, structuredClone(v)]));
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
      where: (f, op, v) => (conds.push([f, v]), q),
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
          .filter((k) => conds.every(([f, v]) => getPath(store.get(k), f) === v));
        rows = rows.slice(0, lim);
        return { docs: rows.map(snap) };
      },
    };
    return q;
  };
  const group = (name) => {
    const conds = [];
    let lim = Infinity;
    const q = {
      where: (f, op, v) => (conds.push([f, v]), q),
      limit: (n) => ((lim = n), q),
      get: async () => ({
        docs: [...store.keys()]
          .filter((k) => k.split('/').slice(-2)[0] === name)
          .filter((k) => conds.every(([f, v]) => getPath(store.get(k), f) === v))
          .slice(0, lim)
          .map(snap),
      }),
    };
    return q;
  };
  const writer = (ops) => ({
    set: (r, d) => ops.push(() => r.set(d)),
    update: (r, d) => ops.push(() => r.update(d)),
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
    runTransaction: async (fn) => {
      const ops = [];
      const tx = {
        ...writer(ops),
        get: async (r) => (r.get ? r.get() : r),
      };
      const out = await fn(tx);
      for (const o of ops) await o();
      return out;
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
    updateUser: async (uid, o) => void Object.assign(users[uid], o, { passwordReset: !!o.password }),
    revokeRefreshTokens: async (uid) => void revoked.push(uid),
    createCustomToken: async (uid, claims) => `token:${uid}:${claims.via}`,
  };
}

module.exports = { fakeDb, fakeAuth };

'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const pa = require('./parent_access');

const B = 'schools/s1/branches/b1';
const link = (o) => ({ schoolId: 's1', branchId: 'b1', parentId: 'p1', status: 'ACTIVE', canAccessPortal: true, ...o });
const seed = (extra = {}) => ({
  [`${B}/parents/p1`]: { status: 'ACTIVE' },
  [`${B}/parents/p2`]: { status: 'ACTIVE' },
  [`${B}/students/st1`]: { status: 'ACTIVE', currentClassId: 'c1', currentSectionId: 'A' },
  [`${B}/students/st2`]: { status: 'ACTIVE', currentClassId: 'c2', currentSectionId: 'B' },
  [`${B}/students/st1/parentLinks/p1`]: link({ studentId: 'st1' }),
  [`${B}/students/st2/parentLinks/p1`]: link({ studentId: 'st2' }),
  ...extra,
});
const ctx = (db) => ({ db, now: 'NOW', by: 'system' });

test('backfill builds the index of a family that never had one', async () => {
  const db = fakeDb(seed());
  const r = await pa.refreshBranchParents(ctx(db), 's1', 'b1');
  assert.deepStrictEqual(r, { parents: 2, written: 2 });
  const d = db.store.get(`${B}/parentAccess/p1`);
  assert.deepStrictEqual(d.classKeys, ['c1', 'c2']);
  assert.deepStrictEqual(d.sectionKeys, ['c1__A', 'c2__B']);
  assert.deepStrictEqual(db.store.get(`${B}/parentAccess/p2`).classKeys, []);
});

test('a child moving section refreshes every family linked to them', async () => {
  const db = fakeDb(seed({ [`${B}/students/st1/parentLinks/p2`]: link({ studentId: 'st1', parentId: 'p2' }) }));
  await pa.refreshFamiliesOfStudent(ctx(db), 's1', 'b1', 'st1');
  assert.deepStrictEqual(db.store.get(`${B}/parentAccess/p2`).sectionKeys, ['c1__A']);
  db.store.set(`${B}/students/st1`, { status: 'ACTIVE', currentClassId: 'c1', currentSectionId: 'C' });
  await pa.refreshFamiliesOfStudent(ctx(db), 's1', 'b1', 'st1');
  assert.deepStrictEqual(db.store.get(`${B}/parentAccess/p2`).sectionKeys, ['c1__C']);
  assert.deepStrictEqual(db.store.get(`${B}/parentAccess/p1`).sectionKeys, ['c1__C', 'c2__B']);
});

test('a switched-off link leaves the index', async () => {
  const db = fakeDb(seed());
  db.store.set(`${B}/students/st2/parentLinks/p1`, link({ studentId: 'st2', canAccessPortal: false }));
  await pa.refreshParents(ctx(db), 's1', 'b1', ['p1']);
  assert.deepStrictEqual(db.store.get(`${B}/parentAccess/p1`).classKeys, ['c1']);
});

test('only relevant changes trigger a refresh', () => {
  const l = link({});
  assert.strictEqual(pa.linkChanged(l, { ...l, note: 'x' }), false);
  assert.strictEqual(pa.linkChanged(l, { ...l, canAccessPortal: false }), true);
  assert.strictEqual(pa.linkChanged(null, l), true);
  const s = { status: 'ACTIVE', currentClassId: 'c1', currentSectionId: 'A' };
  assert.strictEqual(pa.placementChanged(s, { ...s, firstName: 'x' }), false);
  assert.strictEqual(pa.placementChanged(s, { ...s, currentSectionId: 'B' }), true);
  assert.strictEqual(pa.placementChanged(s, null), true);
});

test('a parent can rebuild only their own index, from the data', async () => {
  const db = fakeDb(seed({ 'users/u1': { role: 'PARENT', status: 'ACTIVE', schoolId: 's1', linkedParentId: 'p1' } }));
  const r = await pa.refreshOwnFamily({ db, now: 'NOW' }, 'u1');
  assert.deepStrictEqual(r, { branches: 1, written: 1, stamped: 0 });
  assert.deepStrictEqual(db.store.get(`${B}/parentAccess/p1`).classKeys, ['c1', 'c2']);
  assert.strictEqual(db.store.get(`${B}/parentAccess/p2`), undefined);
});

test('non-parents and inactive parents cannot use the self-heal', async () => {
  const db = fakeDb(seed({
    'users/t1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1', linkedParentId: 'p1' },
    'users/u2': { role: 'PARENT', status: 'INACTIVE', schoolId: 's1', linkedParentId: 'p1' },
  }));
  for (const uid of ['t1', 'u2', 'nobody']) {
    assert.deepStrictEqual(await pa.refreshOwnFamily({ db, now: 'NOW' }, uid), { error: 'PERMISSION_DENIED' });
  }
});

test('the self-heal also stamps the sectionScope of examinations that predate it', async () => {
  const db = fakeDb(seed({
    'users/u1': { role: 'PARENT', status: 'ACTIVE', schoolId: 's1', linkedParentId: 'p1' },
    [`${B}/examinations/y1__c1__ALL__final`]: { classId: 'c1', sectionId: null, status: 'PUBLISHED' },
    [`${B}/examinations/y1__c1__A__unit`]: { classId: 'c1', sectionId: 'A', status: 'PUBLISHED' },
    [`${B}/examinations/y1__c1__B__ok`]: { classId: 'c1', sectionId: 'B', sectionScope: 'B', status: 'PUBLISHED' },
    [`${B}/examinations/y1__c9__ALL__other`]: { classId: 'c9', sectionId: null, status: 'PUBLISHED' },
  }));
  const r = await pa.refreshOwnFamily({ db, now: 'NOW' }, 'u1');
  assert.strictEqual(r.stamped, 2);
  assert.strictEqual(db.store.get(`${B}/examinations/y1__c1__ALL__final`).sectionScope, 'ALL');
  assert.strictEqual(db.store.get(`${B}/examinations/y1__c1__A__unit`).sectionScope, 'A');
  // a class the family has no child in is left alone
  assert.strictEqual(db.store.get(`${B}/examinations/y1__c9__ALL__other`).sectionScope, undefined);
});

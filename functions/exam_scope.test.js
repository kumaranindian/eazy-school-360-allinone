'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const { scopeOf, stampExam, stampClasses } = require('./exam_scope');

const B = 'schools/s1/branches/b1';

test('scopeOf is the section id, or ALL when the examination has no section', () => {
  assert.strictEqual(scopeOf({ sectionId: 'sa' }), 'sa');
  assert.strictEqual(scopeOf({ sectionId: null }), 'ALL');
  assert.strictEqual(scopeOf({}), 'ALL');
  assert.strictEqual(scopeOf({ sectionId: '' }), 'ALL');
});

test('stampExam writes only when the value is missing or wrong', async () => {
  const db = fakeDb({
    [`${B}/examinations/a`]: { sectionId: null },
    [`${B}/examinations/b`]: { sectionId: 'sa', sectionScope: 'sa' },
    [`${B}/examinations/c`]: { sectionId: 'sa', sectionScope: 'ALL' },
  });
  const ref = (id) => db.collection('schools').doc('s1').collection('branches').doc('b1').collection('examinations').doc(id);
  assert.strictEqual(await stampExam(ref('a'), db.store.get(`${B}/examinations/a`)), true);
  assert.strictEqual(await stampExam(ref('b'), db.store.get(`${B}/examinations/b`)), false);
  assert.strictEqual(await stampExam(ref('c'), db.store.get(`${B}/examinations/c`)), true);
  assert.strictEqual(await stampExam(ref('a'), null), false);
  assert.strictEqual(db.store.get(`${B}/examinations/a`).sectionScope, 'ALL');
  assert.strictEqual(db.store.get(`${B}/examinations/c`).sectionScope, 'sa');
});

test('stampClasses is idempotent and ignores blank ids', async () => {
  const db = fakeDb({ [`${B}/examinations/a`]: { classId: 'c1', sectionId: null } });
  assert.strictEqual(await stampClasses(db, 's1', 'b1', ['c1', 'c1', '', null]), 1);
  assert.strictEqual(await stampClasses(db, 's1', 'b1', ['c1']), 0);
});

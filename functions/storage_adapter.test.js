'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { bucketStorage } = require('./storage_adapter');

function fakeBucket(names) {
  const live = new Set(names);
  const deleted = [];
  const file = (name) => ({
    name,
    delete: async (opts) => {
      assert.deepStrictEqual(opts, { ignoreNotFound: true }); // a repeat run must not fail
      live.delete(name);
      deleted.push(name);
    },
  });
  return {
    deleted,
    live,
    getFiles: async ({ prefix }) => [[...live].filter((n) => n.startsWith(prefix)).map(file)],
    file,
  };
}

test('deletes only objects under the prefix and counts them', async () => {
  const b = fakeBucket(['a/1', 'a/2', 'ab/3', 'b/1']);
  const s = bucketStorage(b);
  assert.strictEqual(await s.deletePrefix('a/'), 2);
  assert.deepStrictEqual([...b.live].sort(), ['ab/3', 'b/1']);
  assert.strictEqual(await s.deletePrefix('a/'), 0);
});

test('lists names and deletes one object tolerantly', async () => {
  const b = fakeBucket(['x/1', 'x/2']);
  const s = bucketStorage(b);
  assert.deepStrictEqual((await s.list('x/')).sort(), ['x/1', 'x/2']);
  await s.deleteFile('x/1');
  assert.deepStrictEqual(await s.list('x/'), ['x/2']);
});

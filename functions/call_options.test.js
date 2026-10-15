'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { appCheckEnforced, callOptions } = require('./call_options');

test('App Check is not enforced unless explicitly enabled', () => {
  assert.equal(appCheckEnforced({}), false);
  assert.equal(appCheckEnforced({ ENFORCE_APP_CHECK: 'false' }), false);
  assert.equal(appCheckEnforced({ ENFORCE_APP_CHECK: '1' }), false);
  assert.equal(appCheckEnforced({ ENFORCE_APP_CHECK: 'TRUE' }), true);
});

test('callOptions keeps caller options and adds the enforcement flag', () => {
  assert.deepEqual(callOptions({ secrets: ['S'] }, { ENFORCE_APP_CHECK: 'true' }), {
    secrets: ['S'],
    enforceAppCheck: true,
  });
  assert.deepEqual(callOptions({}, {}), { enforceAppCheck: false });
});

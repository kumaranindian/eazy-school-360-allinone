'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { pushToUsers, STALE } = require('./push');

function setup(errorCode) {
  const deleted = [];
  const devices = [{ data: () => ({ token: 't1' }), ref: { delete: async () => deleted.push('t1') } }];
  const doc = (exists) => ({ exists, data: () => ({}) });
  const db = {
    getAll: async (...refs) => refs.map(() => doc(false)),
    collection: () => ({ doc: () => ({ collection: () => ({ doc: () => ({}), get: async () => ({ docs: devices }) }) }) }),
  };
  const messaging = {
    sendEachForMulticast: async ({ tokens }) => ({
      successCount: 0,
      responses: tokens.map(() => ({ success: false, error: { code: errorCode } })),
    }),
  };
  return { db, messaging, deleted };
}
const run = async (code) => {
  const { db, messaging, deleted } = setup(code);
  await pushToUsers({ db, messaging, userIds: new Set(['u1']), type: 'ANNOUNCEMENT_PUBLISHED', title: 't', body: 'b' });
  return deleted;
};

test('invalid-argument (bad payload) never deletes a device token', async () => {
  assert.ok(!STALE.has('messaging/invalid-argument'));
  assert.deepStrictEqual(await run('messaging/invalid-argument'), []);
});

test('tokens FCM reports as unregistered or invalid are removed', async () => {
  assert.deepStrictEqual(await run('messaging/registration-token-not-registered'), ['t1']);
  assert.deepStrictEqual(await run('messaging/invalid-registration-token'), ['t1']);
});

'use strict';
// Deploy-readiness checks that need no network: every exported function must be something Firebase can
// deploy. A bad name, a duplicate id, an unbalanced trigger path or a missing trigger fails the WHOLE deploy.
const test = require('node:test');
const assert = require('node:assert');

const m = require('./index.js');
const endpoints = Object.entries(m).map(([name, fn]) => ({ name, ep: fn && fn.__endpoint }));

test('every export is a deployable function with exactly one kind of trigger', () => {
  for (const { name, ep } of endpoints) {
    assert.ok(ep, `${name} has no __endpoint (not a Cloud Function)`);
    const kinds = ['callableTrigger', 'eventTrigger', 'scheduleTrigger', 'httpsTrigger'].filter((k) => ep[k]);
    assert.equal(kinds.length, 1, `${name} has ${kinds.length} trigger kinds`);
    assert.equal(ep.platform, 'gcfv2', name);
  }
});

test('function names are legal and unique once Google normalises them (lowercase, underscores become hyphens)', () => {
  const seen = new Map();
  for (const { name } of endpoints) {
    assert.match(name, /^[A-Za-z][A-Za-z0-9_]{0,62}$/, name);
    const id = name.toLowerCase().replace(/_/g, '-');
    assert.ok(!seen.has(id), `${name} collides with ${seen.get(id)} after normalisation`);
    seen.set(id, name);
  }
});

test('all functions share the project region, and timeouts are within the 2nd-gen limits', () => {
  for (const { name, ep } of endpoints) {
    assert.deepEqual(ep.region, ['asia-south1'], name);
    if (typeof ep.timeoutSeconds === 'number') assert.ok(ep.timeoutSeconds <= 540, `${name} timeout ${ep.timeoutSeconds}`);
    if (ep.maxInstances) assert.ok(ep.maxInstances <= 100, name);
  }
});

test('Firestore triggers watch well-formed document paths', () => {
  for (const { name, ep } of endpoints) {
    if (!ep.eventTrigger) continue;
    const path = ep.eventTrigger.eventFilterPathPatterns && ep.eventTrigger.eventFilterPathPatterns.document;
    assert.ok(path, `${name} has no document pattern`);
    const parts = path.split('/');
    assert.equal(parts.length % 2, 0, `${name}: ${path} is not a document path (needs collection/doc pairs)`);
    for (const p of parts) assert.match(p, /^(\{[A-Za-z]+\}|[A-Za-z][A-Za-z0-9]*)$/, `${name}: bad segment "${p}" in ${path}`);
    assert.ok(/(created|updated|written|deleted)$/.test(ep.eventTrigger.eventType), `${name}: ${ep.eventTrigger.eventType}`);
  }
});

test('scheduled functions have a real schedule', () => {
  for (const { name, ep } of endpoints) {
    if (!ep.scheduleTrigger) continue;
    assert.ok(ep.scheduleTrigger.schedule, name);
  }
});

test('the governance functions are all present (a rename would silently orphan the deployed one)', () => {
  const have = new Set(endpoints.map((e) => e.name));
  for (const n of ['subscriptionMonitor', 'auditRetention', 'schoolCreated', 'auditMirrorPlatform', 'auditMirrorAuth', 'schoolStatusChanged', 'moduleWatch_students', 'moduleWatch_invoices', 'moduleWatch_homework']) {
    assert.ok(have.has(n), n);
  }
});

test('function count and breakdown (printed for the deployment checklist)', () => {
  const by = { callable: 0, event: 0, schedule: 0, https: 0 };
  for (const { ep } of endpoints) {
    if (ep.callableTrigger) by.callable++;
    else if (ep.eventTrigger) by.event++;
    else if (ep.scheduleTrigger) by.schedule++;
    else by.https++;
  }
  console.log(`# functions: ${endpoints.length} total`, JSON.stringify(by));
  // 2nd-gen projects default to a quota of 1,000 functions per region; stay well inside it.
  assert.ok(endpoints.length < 500);
});

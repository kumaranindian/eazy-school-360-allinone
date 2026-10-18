'use strict';
// CFG-4: the hosting CSP. It is shipped as Report-Only until it has been
// watched in the browser console on the dev site (see FIX_TRACKER); this test
// pins the parts that must never loosen, in either mode.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'firebase.json'), 'utf8'));
const headers = cfg.hosting.headers.find((h) => h.source === '**').headers;
const header = headers.find((h) => /^Content-Security-Policy(-Report-Only)?$/.test(h.key));

test('a Content-Security-Policy is configured for every page', () => {
  assert.ok(header, 'no CSP header');
});

test('it never allows unsafe-eval or arbitrary script sources', () => {
  const dir = Object.fromEntries(header.value.split(';').map((d) => d.trim().split(/\s+/)).filter((p) => p[0]).map((p) => [p[0], p.slice(1)]));
  assert.deepStrictEqual(dir['object-src'], ["'none'"]);
  assert.deepStrictEqual(dir['frame-ancestors'], ["'none'"]);
  assert.deepStrictEqual(dir['base-uri'], ["'self'"]);
  assert.ok(!dir['script-src'].includes("'unsafe-eval'"));
  assert.ok(!dir['script-src'].includes("'unsafe-inline'"));
  assert.ok(!dir['script-src'].includes('*'));
  assert.ok(dir['script-src'].includes("'wasm-unsafe-eval'"), 'CanvasKit needs wasm');
});

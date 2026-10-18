'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { minify } = require('./build_rules');

test('removes comments and indentation but keeps structure', () => {
  const out = minify("  // header\nservice x {\n    allow read: if a; // trailing\n    /* block\n  comment */\n}\n");
  assert.equal(out, 'service x {\nallow read: if a;\n}\n');
});

test('never touches comment markers inside string literals', () => {
  const src = "allow read: if u.matches('^https://x//y$') && v == \"a // b\";\n";
  assert.equal(minify(src), src);
});

test('handles escaped quotes inside strings', () => {
  const src = "x == 'it\\'s // fine' // real comment\n";
  assert.equal(minify(src), "x == 'it\\'s // fine'\n");
});

test('rejects unterminated constructs instead of emitting broken rules', () => {
  assert.throws(() => minify("x == 'abc\n"), /unterminated string/);
  assert.throws(() => minify('/* never closed'), /unterminated block comment/);
});

test('the real rules still contain every function and match block after minifying', () => {
  const fs = require('fs');
  const path = require('path');
  const src = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
  const min = minify(src);
  const count = (t, re) => (t.match(re) || []).length;
  assert.equal(count(min, /\bfunction \w+\(/g), count(src.replace(/\/\/.*$/gm, ''), /\bfunction \w+\(/g));
  assert.equal(count(min, /\bmatch \//g), count(src.replace(/\/\/.*$/gm, ''), /\bmatch \//g));
  assert.equal(count(min, /\ballow /g), count(src.replace(/\/\/.*$/gm, ''), /\ballow /g));
  assert.ok(min.length < src.length * 0.75);
});

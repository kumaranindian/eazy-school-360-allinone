#!/usr/bin/env node
'use strict';
// Builds the DEPLOYABLE Firestore ruleset from the commented source.
//
// Why: `firestore.rules` is heavily commented and indented (≈223 KB) and sits
// at the service's release-size limit (see docs/production-audit SEC-1). The
// comments and indentation carry no meaning for the rules engine, so the
// artifact that is released drops them (≈145 KB). The source stays the single
// reviewed file; `build/rules/firestore.rules` is generated, never edited.
//
//   node tool/build_rules.js            write build/rules/firestore.rules + report sizes
//   node tool/build_rules.js --check    also fail when the artifact is over the budget
//
// Safety: comments are removed with a tokenizer that understands string
// literals and escapes (a `//` inside quotes is kept). The whole rules test
// suite is run against the artifact in CI (RULES_FILE=…), so a minifier bug
// cannot ship unnoticed.

const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
// Service limit is 256 KiB; keep a wide margin. WARN at 70 %, FAIL at 85 %.
const LIMIT = 256 * 1024;
const WARN = Math.floor(LIMIT * 0.7);
const FAIL = Math.floor(LIMIT * 0.85);

function minify(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === "'" || c === '"') {
      const q = c;
      let j = i + 1;
      while (j < n && src[j] !== q) {
        if (src[j] === '\\') j++;
        if (src[j] === '\n') throw new Error('unterminated string literal');
        j++;
      }
      out += src.slice(i, j + 1);
      i = j + 1;
    } else if (c === '/' && d === '/') {
      while (i < n && src[i] !== '\n') i++;
    } else if (c === '/' && d === '*') {
      const end = src.indexOf('*/', i + 2);
      if (end < 0) throw new Error('unterminated block comment');
      i = end + 2;
    } else {
      out += c;
      i++;
    }
  }
  // Drop indentation, trailing blanks and empty lines; keep line structure.
  return (
    out
      .split('\n')
      .map((l) => l.trim())
      .filter((l) => l.length > 0)
      .join('\n') + '\n'
  );
}

function build(srcPath, outPath) {
  const src = fs.readFileSync(srcPath, 'utf8');
  const min = minify(src);
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, min);
  return { source: Buffer.byteLength(src), built: Buffer.byteLength(min) };
}

module.exports = { minify, build, LIMIT, WARN, FAIL };

if (require.main === module) {
  const check = process.argv.includes('--check');
  const files = [
    ['firestore.rules', 'build/rules/firestore.rules'],
    ['storage.rules', 'build/rules/storage.rules'],
  ];
  let failed = false;
  for (const [src, out] of files) {
    const r = build(path.join(ROOT, src), path.join(ROOT, out));
    const pct = ((100 * r.built) / LIMIT).toFixed(1);
    console.log(`${src}: source ${r.source} B -> ${out} ${r.built} B (${pct} % of the 256 KiB limit)`);
    if (r.built > WARN) console.log(`  WARNING: over ${WARN} B (70 % of the limit) — slim the rules before adding more`);
    if (check && r.built > FAIL) {
      console.error(`  FAIL: over ${FAIL} B (85 % of the limit)`);
      failed = true;
    }
  }
  process.exit(failed ? 1 : 0);
}

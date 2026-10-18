'use strict';
// CFG-3 regression: the main Android manifest declares INTERNET (release
// builds) and switches off Auto Backup.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const manifest = fs.readFileSync(path.join(__dirname, '..', 'android', 'app', 'src', 'main', 'AndroidManifest.xml'), 'utf8');

test('release builds declare INTERNET', () => {
  assert.match(manifest, /<uses-permission android:name="android.permission.INTERNET"\/>/);
});

test('Auto Backup is off', () => {
  assert.match(manifest, /<application[^>]*android:allowBackup="false"/);
});

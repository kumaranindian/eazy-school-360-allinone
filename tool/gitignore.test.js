'use strict';
// CFG-9 regression: key and credential files stay out of git.
const test = require('node:test');
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const root = path.join(__dirname, '..');
const ignored = (file) => {
  try {
    execFileSync('git', ['check-ignore', '-q', '--no-index', file], { cwd: root });
    return true;
  } catch {
    return false;
  }
};

test('secret-looking files are ignored', () => {
  for (const f of [
    'android/key.properties',
    'android/app/upload.jks',
    'ios/Runner/AuthKey_ABC123.p8',
    'certs/signing.p12',
    'certs/server.pem',
    'ios/dev.mobileprovision',
    'functions/serviceAccountKey.json',
    'tool/my-project-adminsdk-abcde-1234.json',
    'functions/.env',
  ]) {
    assert.ok(ignored(f), `${f} should be git-ignored`);
  }
});

test('normal project files are not', () => {
  for (const f of ['firebase.json', 'functions/package.json', 'lib/main.dart']) {
    assert.ok(!ignored(f), `${f} must not be ignored`);
  }
});

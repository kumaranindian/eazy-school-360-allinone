'use strict';
// CFG-1 regression: the Android release build must never fall back to the debug
// key without an explicit opt-in. (A real Gradle run needs the Android SDK, so
// this pins the guard in the build script.)
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');

const gradle = fs.readFileSync(path.join(__dirname, '..', 'android', 'app', 'build.gradle.kts'), 'utf8');

test('debug signing of a release needs an explicit opt-in', () => {
  assert.strictEqual([...gradle.matchAll(/getByName\("debug"\)/g)].length, 1);
  assert.match(gradle, /else if \(allowDebugSignedRelease\)\s*\{[^}]*getByName\("debug"\)/s);
});

test('a release build without key.properties is refused', () => {
  assert.match(gradle, /gradle\.taskGraph\.whenReady/);
  assert.match(gradle, /buildsRelease && !hasReleaseKey && !allowDebugSignedRelease/);
  assert.match(gradle, /throw GradleException/);
});

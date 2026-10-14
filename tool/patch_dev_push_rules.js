#!/usr/bin/env node
// One-off: let push notifications work on a project whose live Firestore
// rules predate them, without needing the full firestore.rules to release.
//
// Takes the rules that are LIVE, changes only two things, and releases the
// result:
//   1. users/{uid}/preferences: pushEnabled may be true or false
//      (old rule only allowed `== false`, so the switch could never stay on)
//   2. adds users/{uid}/devices (copied verbatim from firestore.rules) so the
//      FCM token can be stored
//
// Usage (needs `firebase login`; run from the repo root):
//   node tool/patch_dev_push_rules.js <project-id>            # dry run: diff only
//   node tool/patch_dev_push_rules.js <project-id> --release  # create + release
//   add --pref-only to change just the preferences rule (diagnostic)
//   add --compact to also drop comment-only lines so the result stays small
//
// Why this exists: the full firestore.rules (~227 KB) is currently refused at
// release time (INVALID_ARGUMENT; the CLI sees 503). Slimming that file is the
// real fix; this unblocks push in the meantime.
'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const project = process.argv[2];
const release = process.argv.includes('--release');
// Diagnostic: change ONLY the preferences rule (-1 byte vs live). If this
// releases, the full patch is being refused for size/complexity; if even this
// is refused, Google is refusing every new ruleset for the project.
const prefOnly = process.argv.includes('--pref-only');
// Drop comment-only lines from the released text. Comments do not affect what
// the rules allow, and the released ruleset appears to sit right at a size
// limit (+773 bytes was refused, -1 byte was accepted), so this makes room for
// the devices rule. firestore.rules in the repo keeps its comments.
const compact = process.argv.includes('--compact');
if (!project || project.startsWith('--')) {
  console.error('usage: node tool/patch_dev_push_rules.js <project-id> [--release]');
  process.exit(1);
}

const root = path.join(execSync('npm root -g').toString().trim(), 'firebase-tools');
const fallback = '/usr/local/lib/node_modules/firebase-tools';
const base = fs.existsSync(root) ? root : fallback;
const auth = require(path.join(base, 'lib/auth'));
const { requireAuth } = require(path.join(base, 'lib/requireAuth'));
const { configstore } = require(path.join(base, 'lib/configstore'));
const rules = require(path.join(base, 'lib/gcp/rules'));

const RELEASE = 'cloud.firestore';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function patch(live, repo) {
  const old = 'request.resource.data.pushEnabled == false';
  if (live.split(old).length !== 2) {
    throw new Error('expected exactly one `pushEnabled == false` in the live rules; aborting');
  }
  let out = live.replace(old, 'request.resource.data.pushEnabled is bool');
  if (prefOnly) return out;

  if (/devices\/\{deviceId\}/.test(out)) {
    console.log('live rules already have a devices rule; leaving it alone');
    return out;
  }
  const m = repo.match(/ {4}\/\/ Push devices: one document per device[\s\S]*?\n {4}}\n/);
  if (!m || !/devices\/\{deviceId\}/.test(m[0])) {
    throw new Error('could not find the devices rule in firestore.rules; aborting');
  }
  const marker = '    // Default-deny everything else.';
  if (out.split(marker).length !== 2) {
    throw new Error('could not find the default-deny marker in the live rules; aborting');
  }
  out = out.replace(marker, m[0] + '\n' + marker);
  if (!compact) return out;
  const kept = out.split('\n').filter((line) => !/^\s*\/\//.test(line));
  return kept.join('\n');
}

(async () => {
  const opts = { projectRoot: process.cwd(), project, nonInteractive: true };
  auth.setActiveAccount(opts, {
    user: configstore.get('user'),
    tokens: configstore.get('tokens'),
  });
  await requireAuth(opts);

  const liveName = await rules.getLatestRulesetName(project, 'cloud.firestore');
  const live = (await rules.getRulesetContent(liveName))[0].content;
  const repo = fs.readFileSync('firestore.rules', 'utf8');
  const patched = patch(live, repo);

  const tmp = path.join(require('os').tmpdir(), `live-${project}.rules`);
  const tmp2 = path.join(require('os').tmpdir(), `patched-${project}.rules`);
  fs.writeFileSync(tmp, live);
  fs.writeFileSync(tmp2, patched);
  console.log(`live ${live.length} bytes -> patched ${patched.length} bytes (+${patched.length - live.length})`);
  try {
    execSync(`diff ${tmp} ${tmp2}`, { stdio: 'inherit' });
  } catch (_) {
    /* diff exits 1 when files differ: that is the expected output */
  }

  if (!release) {
    console.log('\nDry run only. Re-run with --release to apply.');
    return;
  }

  let name;
  for (let i = 1; i <= 4 && !name; i++) {
    try {
      name = await rules.createRuleset(project, [{ name: 'firestore.rules', content: patched }]);
      console.log('ruleset created:', name);
    } catch (e) {
      console.log(`create attempt ${i} failed: ${String(e.message || e).slice(0, 160)}`);
      await sleep(15000);
    }
  }
  if (!name) throw new Error('could not create the ruleset');

  for (let i = 1; i <= 5; i++) {
    try {
      await rules.updateRelease(project, name, RELEASE);
      console.log('RELEASED', RELEASE, '->', name);
      break;
    } catch (e) {
      console.log(`release attempt ${i} failed: ${String(e.message || e).slice(0, 160)}`);
      if (i === 5) throw new Error('release was refused; live rules are unchanged');
      await sleep(15000);
    }
  }
  const now = await rules.getLatestRulesetName(project, 'cloud.firestore');
  console.log('live ruleset now:', now, now === name ? '(matches)' : '(MISMATCH)');
})().catch((e) => {
  console.error('ERROR:', e.message || e);
  process.exit(1);
});

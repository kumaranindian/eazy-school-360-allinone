#!/usr/bin/env node
'use strict';

// READ-ONLY dry run of the governance rollout against a project's data (docs/platform-governance/DEPLOYMENT_GUIDE.md).
//
//   node tool/governance_dry_run.js --project <firebase-project-id> [--sample 50] [--json]
//        [--read-prod]   (required when the project id contains "prod": reading production data needs your approval)
//
// It answers: "if the new functions, indexes and app are deployed, what happens to the schools and users that exist
// today?" It NEVER writes: the database handle it uses throws on every write method (and a test proves it).
// Credentials: Application Default Credentials (`gcloud auth application-default login`) or
// GOOGLE_APPLICATION_CREDENTIALS. Against the emulator: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080.

const features = require('../functions/features');
const subscriptions = require('../functions/subscriptions');
const { mirrorFor } = subscriptions;

const STATES = ['INACTIVE', 'ACTIVE', 'SUSPENDED', 'EXPIRED', 'CLOSED'];
const WRITE_METHODS = ['set', 'update', 'delete', 'create', 'add', 'batch', 'runTransaction', 'bulkWriter', 'recursiveDelete'];

/** A view of [db] that refuses every write. */
function readOnly(db) {
  const guard = (target) =>
    new Proxy(target, {
      get(t, prop) {
        if (WRITE_METHODS.includes(prop)) {
          return () => {
            throw new Error(`dry run: refused to call ${String(prop)} (this tool never writes)`);
          };
        }
        const v = t[prop];
        if (typeof v !== 'function') return v;
        return (...args) => {
          const out = v.apply(t, args);
          return out && typeof out === 'object' && !Array.isArray(out) && typeof out.then !== 'function' ? guard(out) : out;
        };
      },
    });
  return guard(db);
}

const toMs = (t) => (t && typeof t.toMillis === 'function' ? t.toMillis() : null);

/**
 * Reads the schools, a bounded sample of each school's users and the governance collections, and reports what
 * the rollout would do. Pure over a Firestore-like [db]; `now` is injectable for tests.
 */
async function analyse(rawDb, { sample = 50, now = new Date() } = {}) {
  const db = readOnly(rawDb);
  const report = {
    schools: { total: 0, byState: Object.fromEntries(STATES.map((s) => [s, 0])), noStatus: [], noFeatures: 0, noLifecycleVersion: 0, noTimezone: [] },
    features: { unknownKeys: [], inconsistent: [] },
    subscriptions: { total: 0, byStatus: {}, willBlockOnDeploy: [], notStarted: [], noSchool: [] },
    users: { platformAdmins: 0, platformAdminsWithoutRole: 0, schoolUsersSampled: 0, mirrorMissing: [], mirrorStale: [] },
    collectionsAlreadyPresent: {},
    findings: [],
  };

  const schools = await db.collection('schools').get();
  const schoolById = new Map();
  for (const d of schools.docs) {
    const s = d.data();
    schoolById.set(d.id, s);
    report.schools.total++;
    if (!STATES.includes(s.status)) report.schools.noStatus.push(d.id);
    else report.schools.byState[s.status]++;
    if (!s.features) report.schools.noFeatures++;
    if (s.lifecycleVersion === undefined) report.schools.noLifecycleVersion++;
    if (!s.timezone) report.schools.noTimezone.push(d.id);
    const f = s.features || {};
    for (const k of Object.keys(f)) if (!Object.prototype.hasOwnProperty.call(features.BY_KEY, k)) report.features.unknownKeys.push(`${d.id}:${k}`);
    // A module is off if a dependency is off: list schools whose stored switches disagree with that.
    for (const k of features.KEYS) {
      if (f[k] !== false && !features.usable(f, k)) report.features.inconsistent.push(`${d.id}:${k}`);
    }
  }

  const subs = await db.collection('schoolSubscriptions').get();
  for (const d of subs.docs) {
    report.subscriptions.total++;
    const school = schoolById.get(d.id);
    if (!school) {
      report.subscriptions.noSchool.push(d.id);
      continue;
    }
    const live = subscriptions.statusAt(d.data(), now, subscriptions.zoneOf(school)) || 'UNREADABLE';
    report.subscriptions.byStatus[live] = (report.subscriptions.byStatus[live] || 0) + 1;
    if (live === 'NOT_STARTED') report.subscriptions.notStarted.push(d.id);
    if ((live === 'EXPIRED' || live === 'CANCELLED') && (school.status || 'ACTIVE') === 'ACTIVE') report.subscriptions.willBlockOnDeploy.push(d.id);
  }

  const users = await db.collection('users').get();
  const perSchool = new Map();
  for (const d of users.docs) {
    const u = d.data();
    if (u.role === 'PLATFORM_ADMIN') {
      report.users.platformAdmins++;
      if (!u.platformRole) report.users.platformAdminsWithoutRole++;
      continue;
    }
    if (!u.schoolId || !schoolById.has(u.schoolId)) continue;
    const n = perSchool.get(u.schoolId) || 0;
    if (n >= sample) continue;
    perSchool.set(u.schoolId, n + 1);
    report.users.schoolUsersSampled++;
    const school = schoolById.get(u.schoolId);
    const want = mirrorFor({ ...school, subscriptionStatus: undefined });
    const have = typeof u.schoolAccess === 'string' ? u.schoolAccess : 'ACTIVE';
    if (want !== 'ACTIVE' && have === 'ACTIVE') report.users.mirrorMissing.push(`${u.schoolId}:${d.id}`);
    if (want === 'ACTIVE' && have !== 'ACTIVE' && have !== 'SUBSCRIPTION_NOT_STARTED') report.users.mirrorStale.push(`${u.schoolId}:${d.id}`);
  }

  for (const c of ['platformPlans', 'platformNotifications', 'platformFeatureDefaults', 'schoolFeatureHistory', 'schoolLifecycleHistory', 'schoolRecovery']) {
    const n = (await db.collection(c).limit(1).get()).docs.length;
    report.collectionsAlreadyPresent[c] = n > 0;
  }
  const audit = await db.collection('auditEvents').limit(1).get();
  report.collectionsAlreadyPresent.auditEvents = audit.docs.length > 0;

  // ---- what it means ----
  const f = report.findings;
  const r = report;
  f.push(`${r.schools.total} school(s): ${STATES.map((s) => `${r.schools.byState[s]} ${s.toLowerCase()}`).join(', ')}.`);
  if (r.schools.noStatus.length) f.push(`ATTENTION: ${r.schools.noStatus.length} school(s) have no recognised status and will be treated as ACTIVE: ${r.schools.noStatus.slice(0, 5).join(', ')}.`);
  if (r.schools.noFeatures) f.push(`${r.schools.noFeatures} school(s) have no module switches: every module stays ON (nothing changes).`);
  if (r.schools.noLifecycleVersion) f.push(`${r.schools.noLifecycleVersion} school(s) predate lifecycle versions: harmless, the counter starts at their first change.`);
  if (r.schools.noTimezone.length) f.push(`ATTENTION: ${r.schools.noTimezone.length} school(s) have no time zone: subscription dates would use UTC until one is set.`);
  if (r.features.unknownKeys.length) f.push(`ATTENTION: unknown module keys (ignored by the app): ${r.features.unknownKeys.slice(0, 5).join(', ')}.`);
  if (r.features.inconsistent.length) f.push(`${r.features.inconsistent.length} module(s) are on although a dependency is off; they will read as OFF: ${r.features.inconsistent.slice(0, 5).join(', ')}.`);
  if (r.subscriptions.total === 0) f.push('No school has a subscription: subscription enforcement changes nothing for anyone today (legacy schools are allowed).');
  if (r.subscriptions.willBlockOnDeploy.length) f.push(`ATTENTION: ${r.subscriptions.willBlockOnDeploy.length} ACTIVE school(s) have an ended subscription and would be paused within 15 minutes of deploy: ${r.subscriptions.willBlockOnDeploy.join(', ')}.`);
  if (r.subscriptions.notStarted.length) f.push(`ATTENTION: ${r.subscriptions.notStarted.length} school(s) have a subscription that has not started and would be paused until it does: ${r.subscriptions.notStarted.join(', ')}.`);
  if (r.subscriptions.noSchool.length) f.push(`ATTENTION: subscription document(s) without a school: ${r.subscriptions.noSchool.join(', ')}.`);
  if (r.users.platformAdminsWithoutRole) f.push(`${r.users.platformAdminsWithoutRole} platform admin(s) have no platformRole (legacy): treated as OWNER, as before.`);
  if (r.users.mirrorMissing.length) f.push(`ATTENTION: ${r.users.mirrorMissing.length} sampled user(s) of a paused school are not mirrored as paused (the repair action "Re-apply to all users" fixes it): ${r.users.mirrorMissing.slice(0, 5).join(', ')}.`);
  if (r.users.mirrorStale.length) f.push(`ATTENTION: ${r.users.mirrorStale.length} sampled user(s) of an ACTIVE school are still marked paused: ${r.users.mirrorStale.slice(0, 5).join(', ')}.`);
  const attention = f.filter((x) => x.startsWith('ATTENTION')).length;
  f.push(attention ? `RESULT: ${attention} item(s) need a decision before deploying. No data is changed by the deployment itself.` : 'RESULT: nothing needs fixing first. No data is changed by the deployment itself.');
  report.attention = attention;
  return report;
}

function parseArgs(argv) {
  const out = { sample: 50, json: false, readProd: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--json') out.json = true;
    else if (a === '--read-prod') out.readProd = true;
    else if (a === '--project' || a === '--sample') {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) return { error: `${a} needs a value` };
      out[a.slice(2)] = a === '--sample' ? Number(v) : v;
    } else return { error: `unknown option ${a}` };
  }
  if (!out.project) return { error: '--project is required' };
  if (!Number.isInteger(out.sample) || out.sample < 1 || out.sample > 1000) return { error: '--sample must be 1 to 1000' };
  if (/prod/i.test(out.project) && !out.readProd) return { error: `"${out.project}" looks like production: add --read-prod to confirm you may read its data` };
  return out;
}

async function main(argv) {
  const args = parseArgs(argv);
  if (args.error) {
    console.error(`error: ${args.error}`);
    return 2;
  }
  const { initializeApp, applicationDefault } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');
  initializeApp({ projectId: args.project, credential: process.env.FIRESTORE_EMULATOR_HOST ? undefined : applicationDefault() });
  const report = await analyse(getFirestore(), { sample: args.sample });
  if (args.json) console.log(JSON.stringify(report, null, 2));
  else console.log(`Governance dry run for ${args.project} (read-only)\n\n${report.findings.map((x) => `- ${x}`).join('\n')}`);
  return report.attention ? 1 : 0;
}

module.exports = { analyse, readOnly, parseArgs };

if (require.main === module) {
  main(process.argv.slice(2)).then((c) => process.exit(c), (e) => {
    console.error(`failed: ${e.message}`);
    process.exit(3);
  });
}

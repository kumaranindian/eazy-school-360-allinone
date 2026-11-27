'use strict';
// Loading index.js catches wiring mistakes (use-before-define, missing exports) that unit tests of the
// individual modules cannot: a broken index.js fails the WHOLE deploy.
const test = require('node:test');
const assert = require('node:assert');

test('index.js loads and exports the governance callables, scheduler and triggers', () => {
  const m = require('./index.js');
  const want = [
    'transitionSchool', 'requestSchoolRecovery', 'approveSchoolRecovery', 'cancelSchoolRecovery', 'schoolCreated',
    'listMyPlatformNotifications', 'acknowledgeNotification', 'dismissNotification',
    'savePlan', 'listPlans', 'setSubscription', 'extendSubscription', 'renewSubscription', 'cancelSubscription', 'grantTrial', 'getSubscriptionHistory', 'masterScheduler',
    'setSchoolFeatures', 'getFeatureConfig', 'setFeatureDefaults', 'getFeatureHistory',
    'checkUploadedFile',
    'queryAuditEvents', 'exportAuditEvents', 'getAuditSummary', 'getAuditEvent', 'reportClientEvent', 'auditMirrorPlatform', 'auditMirrorAuth',
  ];
  for (const name of want) assert.ok(m[name], `missing export ${name}`);
  const watched = Object.keys(m).filter((k) => k.startsWith('moduleWatch_'));
  const want_ = new Set([...Object.keys(require('./feature_guard').MODULE_COLLECTIONS), ...Object.keys(require('./audit').MODULES)]);
  assert.equal(watched.length, want_.size);
  for (const c of Object.keys(require('./feature_guard').MODULE_COLLECTIONS)) assert.ok(m[`moduleWatch_${c}`], `a guarded collection is not watched: ${c}`);
  for (const c of Object.keys(require('./audit').MODULES)) assert.ok(m[`moduleWatch_${c}`], `an audited collection is not watched: ${c}`);
});

// Cloud Scheduler bills every job beyond three per billing account: prod gets exactly ONE scheduled function,
// dev none (it gets the OWNER-only runScheduledTask instead). Checked in a child process per project id,
// as the Firebase CLI sets GCLOUD_PROJECT when it reads the code at deploy time.
test('one scheduled function in prod, none in dev', () => {
  const { execFileSync } = require('node:child_process');
  const probe = (env) => JSON.parse(execFileSync(process.execPath, ['-e', `
    const m = require('./index.js');
    const sched = Object.keys(m).filter((k) => m[k].__endpoint && m[k].__endpoint.scheduleTrigger);
    process.stdout.write(JSON.stringify({ sched, manual: 'runScheduledTask' in m }));
  `], { cwd: __dirname, env: { ...process.env, GCLOUD_PROJECT: '', FIREBASE_CONFIG: '', SCHEDULED_JOBS: '', ...env } }).toString());
  assert.deepEqual(probe({ GCLOUD_PROJECT: 'eazy-school-360-prod' }), { sched: ['masterScheduler'], manual: false });
  assert.deepEqual(probe({ GCLOUD_PROJECT: 'eazy-school-360-dev' }), { sched: [], manual: true });
  assert.deepEqual(probe({ GCLOUD_PROJECT: 'eazy-school-360-prod', SCHEDULED_JOBS: 'off' }), { sched: [], manual: true });
});

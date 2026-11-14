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
    'savePlan', 'listPlans', 'setSubscription', 'extendSubscription', 'renewSubscription', 'cancelSubscription', 'grantTrial', 'getSubscriptionHistory', 'subscriptionMonitor',
    'setSchoolFeatures', 'getFeatureConfig', 'setFeatureDefaults', 'getFeatureHistory',
    'queryAuditEvents', 'exportAuditEvents', 'getAuditSummary', 'reportClientEvent', 'auditRetention', 'auditMirrorPlatform', 'auditMirrorAuth',
  ];
  for (const name of want) assert.ok(m[name], `missing export ${name}`);
  const watched = Object.keys(m).filter((k) => k.startsWith('moduleWatch_'));
  const want_ = new Set([...Object.keys(require('./feature_guard').MODULE_COLLECTIONS), ...Object.keys(require('./audit').MODULES)]);
  assert.equal(watched.length, want_.size);
  for (const c of Object.keys(require('./feature_guard').MODULE_COLLECTIONS)) assert.ok(m[`moduleWatch_${c}`], `a guarded collection is not watched: ${c}`);
  for (const c of Object.keys(require('./audit').MODULES)) assert.ok(m[`moduleWatch_${c}`], `an audited collection is not watched: ${c}`);
});

'use strict';

// Options shared by every callable. App Check enforcement is opt-in per
// deployment (`ENFORCE_APP_CHECK=true` in functions/.env.<project>): turning
// it on before the apps send tokens would lock every user out, so it is only
// enabled once the clients are configured (docs/app-check-and-monitoring.md).
function appCheckEnforced(env = process.env) {
  return String(env.ENFORCE_APP_CHECK || '').toLowerCase() === 'true';
}

function callOptions(extra = {}, env = process.env) {
  return { ...extra, enforceAppCheck: appCheckEnforced(env) };
}

module.exports = { appCheckEnforced, callOptions };

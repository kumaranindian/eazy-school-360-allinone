#!/usr/bin/env node
'use strict';

// Creates (or recovers access for) an Avail404 platform administrator.
//
//   node tool/create_platform_admin.js --project <firebase-project-id> \
//        --email person@avail404.com --name "Full Name" [--role OWNER] [--dry-run] [--yes]
//
// * Run by a person with project credentials (Application Default Credentials:
//   `gcloud auth application-default login`, or GOOGLE_APPLICATION_CREDENTIALS).
// * The new person's password is never known to anyone: the script prints a
//   one-time link for them to choose it. They must then set up two-step
//   verification at first sign-in (the app does not let a platform admin in
//   without it).
// * Writes an audit record (source SCRIPT) in `platformAuditLog`.
// * Against a project whose id contains "prod" it asks for --yes.
// See docs/platform-admin/PLATFORM_ADMIN_PLAN.md and DEVELOPMENT_GUIDE.md.

const ROLES = ['OWNER', 'SUPPORT', 'COMPLIANCE', 'VIEWER'];

function parseArgs(argv) {
  const out = { role: 'OWNER', dryRun: false, yes: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') out.dryRun = true;
    else if (a === '--yes') out.yes = true;
    else if (['--project', '--email', '--name', '--role'].includes(a)) {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) return { error: `${a} needs a value` };
      out[a.slice(2)] = v;
    } else return { error: `unknown argument ${a}` };
  }
  if (!out.project) return { error: '--project is required' };
  if (!out.email) return { error: '--email is required' };
  if (!out.name) return { error: '--name is required' };
  if (!ROLES.includes(out.role)) return { error: `--role must be one of ${ROLES.join(', ')}` };
  return { args: out };
}

const REASONS = {
  name: 'the name must be 2-100 characters',
  email: 'the email address looks invalid',
  emailDomain: 'the email domain is not allowed (set PLATFORM_ADMIN_EMAIL_DOMAINS, default avail404.com)',
  platformRole: 'unknown role',
};

/**
 * `deps` is injected for tests: { bootstrap, validate, makeCtx, log, operator, env }.
 * Returns the process exit code.
 */
async function run(argv, deps) {
  const log = deps.log;
  const parsed = parseArgs(argv);
  if (parsed.error) {
    log.error(`Error: ${parsed.error}`);
    log.error('Usage: node tool/create_platform_admin.js --project <id> --email <e> --name "<n>" [--role OWNER|SUPPORT|COMPLIANCE|VIEWER] [--dry-run] [--yes]');
    return 2;
  }
  const a = parsed.args;
  const data = { name: a.name, email: a.email, platformRole: a.role };
  const check = deps.validate(data, deps.env);
  if (check.error) {
    log.error(`Refused: ${REASONS[check.reason] || check.reason}`);
    return 2;
  }
  if (/prod/i.test(a.project) && !a.yes && !a.dryRun) {
    log.error(`"${a.project}" looks like production. Re-run with --yes to confirm.`);
    return 2;
  }
  log.info(`Project: ${a.project}`);
  log.info(`Account: ${check.value.email} (${check.value.platformRole})`);
  if (a.dryRun) {
    log.info('Dry run: nothing was created.');
    return 0;
  }
  const out = await deps.bootstrap(deps.makeCtx(a.project), data, deps.env, deps.operator);
  if (out.error === 'EMAIL_IN_USE') {
    log.error('That email already has an account. Platform admins are dedicated accounts: use another address, or manage the existing one from the app.');
    return 1;
  }
  if (out.error) {
    log.error(`Refused: ${REASONS[out.reason] || out.error}`);
    return 1;
  }
  log.info(`Created ${out.email} as ${out.platformRole}.`);
  log.info('');
  log.info('Send this ONE-TIME link to the person (it lets them choose a password; do not post it anywhere shared):');
  log.info(out.resetLink);
  log.info('');
  log.info('Then: they open the app, sign in, and set up two-step verification (a code from an authenticator app).');
  return 0;
}

module.exports = { parseArgs, run, ROLES };

if (require.main === module) {
  (async () => {
    const path = require('node:path');
    const functions = path.join(__dirname, '..', 'functions');
    // firebase-admin lives in functions/node_modules (resolved with its package exports).
    const dep = (name) => require(require.resolve(name, { paths: [functions] }));
    const admin = dep('firebase-admin/app');
    const { getFirestore, FieldValue } = dep('firebase-admin/firestore');
    const { getAuth } = dep('firebase-admin/auth');
    const pa = require(path.join(functions, 'platform_admin.js'));
    const parsed = parseArgs(process.argv.slice(2));
    if (!parsed.error) admin.initializeApp({ projectId: parsed.args.project });
    const code = await run(process.argv.slice(2), {
      validate: (d, env) => {
        const domains = pa.allowedDomains(env);
        const name = typeof d.name === 'string' ? d.name.trim() : '';
        const email = typeof d.email === 'string' ? d.email.trim().toLowerCase() : '';
        if (name.length < 2 || name.length > 100) return { error: true, reason: 'name' };
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return { error: true, reason: 'email' };
        if (!domains.includes(email.split('@')[1])) return { error: true, reason: 'emailDomain' };
        return { value: { email, platformRole: d.platformRole } };
      },
      bootstrap: pa.bootstrapPlatformAdmin,
      makeCtx: () => ({ db: getFirestore(), auth: getAuth(), now: FieldValue.serverTimestamp() }),
      log: { info: (m) => console.log(m), error: (m) => console.error(m) },
      operator: process.env.USER || process.env.USERNAME || 'operator',
      env: process.env,
    });
    process.exit(code);
  })().catch((e) => {
    console.error(`Failed: ${e && e.message ? e.message : e}`);
    process.exit(1);
  });
}

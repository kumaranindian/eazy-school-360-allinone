'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { parseArgs, run } = require('./create_platform_admin');

const logs = () => {
  const out = { info: [], error: [] };
  return { out, log: { info: (m) => out.info.push(m), error: (m) => out.error.push(m) } };
};
const okValidate = (d) => ({ value: { email: d.email.toLowerCase(), platformRole: d.platformRole } });
const base = ['--project', 'eazy-school-360-dev', '--email', 'Admin@Avail404.com', '--name', 'Admin'];

test('parseArgs: required values, role check, unknown flags', () => {
  assert.equal(parseArgs([]).error, '--project is required');
  assert.equal(parseArgs(['--project', 'p']).error, '--email is required');
  assert.equal(parseArgs(['--project', 'p', '--email', 'e']).error, '--name is required');
  assert.match(parseArgs([...base, '--role', 'GOD']).error, /--role must be one of/);
  assert.match(parseArgs([...base, '--nope']).error, /unknown argument/);
  assert.match(parseArgs([...base, '--role']).error, /needs a value/);
  const ok = parseArgs([...base, '--role', 'SUPPORT', '--dry-run']);
  assert.equal(ok.args.role, 'SUPPORT');
  assert.equal(ok.args.dryRun, true);
  assert.equal(parseArgs(base).args.role, 'OWNER');
});

test('dry run creates nothing', async () => {
  const { out, log } = logs();
  let called = 0;
  const code = await run([...base, '--dry-run'], { log, validate: okValidate, bootstrap: async () => void called++, makeCtx: () => ({}), env: {} });
  assert.equal(code, 0);
  assert.equal(called, 0);
  assert.ok(out.info.some((l) => /Dry run/.test(l)));
});

test('a validation refusal is explained and nothing is created', async () => {
  const { out, log } = logs();
  let called = 0;
  const code = await run(base, { log, validate: () => ({ error: true, reason: 'emailDomain' }), bootstrap: async () => void called++, makeCtx: () => ({}), env: {} });
  assert.equal(code, 2);
  assert.equal(called, 0);
  assert.match(out.error.join('\n'), /domain is not allowed/);
});

test('production needs --yes', async () => {
  const { out, log } = logs();
  let called = 0;
  const args = ['--project', 'eazy-school-360-prod', '--email', 'a@avail404.com', '--name', 'Admin'];
  const deps = { log, validate: okValidate, bootstrap: async () => (called++, { email: 'a@avail404.com', platformRole: 'OWNER', resetLink: 'L' }), makeCtx: () => ({}), env: {} };
  assert.equal(await run(args, deps), 2);
  assert.equal(called, 0);
  assert.match(out.error.join('\n'), /production/);
  assert.equal(await run([...args, '--yes'], deps), 0);
  assert.equal(called, 1);
});

test('success prints the one-time link and the next steps, never a password', async () => {
  const { out, log } = logs();
  const code = await run(base, {
    log,
    validate: okValidate,
    bootstrap: async (ctx, data, env, operator) => ({ uid: 'u1', email: 'admin@avail404.com', platformRole: 'OWNER', resetLink: 'https://reset/abc', operator }),
    makeCtx: () => ({}),
    operator: 'ops',
    env: {},
  });
  assert.equal(code, 0);
  const text = out.info.join('\n');
  assert.match(text, /https:\/\/reset\/abc/);
  assert.match(text, /two-step verification/);
  assert.doesNotMatch(text, /password:/i);
});

test('an existing account is refused with guidance', async () => {
  const { out, log } = logs();
  const code = await run(base, { log, validate: okValidate, bootstrap: async () => ({ error: 'EMAIL_IN_USE' }), makeCtx: () => ({}), env: {} });
  assert.equal(code, 1);
  assert.match(out.error.join('\n'), /already has an account/);
});

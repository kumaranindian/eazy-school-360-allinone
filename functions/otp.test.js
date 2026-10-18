'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const otp = require('./otp');
const { createWhatsAppSender, WhatsAppError } = require('./whatsapp');

const PHONE = '+919876543210';
const user = (o = {}) => ({
  schoolId: 's1', role: 'TEACHER', status: 'ACTIVE',
  login: { enabled: true, methods: ['PHONE_OTP'], effective: ['PHONE_OTP'], phone: PHONE },
  ...o,
});
function setup(users = { 'users/u1': user() }, senderOver = {}) {
  const db = fakeDb(users);
  const sent = [];
  let clock = 1_000_000;
  let n = 0;
  const ctx = {
    db,
    pepper: 'pepper',
    nowMs: () => clock,
    newId: () => String(++n).padStart(32, '0'),
    randomInt: () => 424242,
    sender: { configured: true, sendOtp: async (m) => void sent.push(m), ...senderOver },
  };
  return { db, ctx, sent, tick: (ms) => (clock += ms) };
}

test('sends a code to a registered phone and stores only a hash', async () => {
  const { db, ctx, sent } = setup();
  const r = await otp.requestOtp(ctx, { phone: '98765 43210', ip: '1.1.1.1' });
  assert.ok(r.challengeId);
  assert.deepStrictEqual(sent, [{ to: PHONE, code: '424242' }]);
  const stored = JSON.stringify([...db.store.values()]);
  assert.ok(!stored.includes('424242'), 'plain code is never persisted');
});

test('unknown, disabled or ambiguous phones look identical but send nothing', async () => {
  const cases = [
    { 'users/u1': user({ login: { enabled: false, effective: [], phone: PHONE } }) },
    { 'users/u1': user({ login: { enabled: true, effective: ['PASSWORD'], phone: PHONE } }) },
    { 'users/u1': user({ status: 'DISABLED' }) },
    { 'users/u1': user(), 'users/u2': user({ schoolId: 's2' }) },
    {},
  ];
  for (const users of cases) {
    const { ctx, sent } = setup(users);
    const r = await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' });
    assert.ok(r.challengeId && !r.error);
    assert.strictEqual(sent.length, 0);
    assert.strictEqual((await otp.verifyOtp(ctx, { challengeId: r.challengeId, code: '424242' })).error, 'OTP_INVALID');
  }
});

test('verifies the right code once; the code cannot be replayed', async () => {
  const { ctx } = setup();
  const { challengeId } = await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' });
  const ok = await otp.verifyOtp(ctx, { challengeId, code: '424242' });
  assert.strictEqual(ok.uid, 'u1');
  assert.strictEqual((await otp.verifyOtp(ctx, { challengeId, code: '424242' })).error, 'OTP_INVALID');
});

test('wrong code is rejected and the challenge locks after the attempt limit', async () => {
  const { ctx } = setup();
  const { challengeId } = await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' });
  for (let i = 1; i < otp.MAX_ATTEMPTS; i++) {
    const r = await otp.verifyOtp(ctx, { challengeId, code: '000000' });
    assert.strictEqual(r.error, 'OTP_INVALID');
  }
  assert.strictEqual((await otp.verifyOtp(ctx, { challengeId, code: '000000' })).error, 'OTP_LOCKED');
  // even the right code is refused once locked
  assert.strictEqual((await otp.verifyOtp(ctx, { challengeId, code: '424242' })).error, 'OTP_LOCKED');
});

test('expired codes are refused', async () => {
  const { ctx, tick } = setup();
  const { challengeId } = await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' });
  tick(otp.TTL_MS + 1);
  assert.strictEqual((await otp.verifyOtp(ctx, { challengeId, code: '424242' })).error, 'OTP_EXPIRED');
});

test('resend cooldown and hourly limits; a new code supersedes the old one', async () => {
  const { ctx, tick } = setup();
  const first = await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' });
  const again = await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' });
  assert.strictEqual(again.error, 'RESEND_COOLDOWN');
  tick(otp.RESEND_COOLDOWN_MS + 1);
  const second = await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' });
  assert.ok(second.challengeId);
  assert.strictEqual((await otp.verifyOtp(ctx, { challengeId: first.challengeId, code: '424242' })).error, 'OTP_INVALID');
  assert.ok((await otp.verifyOtp(ctx, { challengeId: second.challengeId, code: '424242' })).uid);
  for (let i = 0; i < otp.MAX_PER_PHONE; i++) {
    tick(otp.RESEND_COOLDOWN_MS + 1);
    const r = await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' });
    if (r.error) assert.strictEqual(r.error, 'RATE_LIMITED');
  }
  tick(otp.RESEND_COOLDOWN_MS + 1);
  assert.strictEqual((await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' })).error, 'RATE_LIMITED');
});

test('per-IP limit protects against spraying many numbers', async () => {
  const { ctx } = setup();
  let limited = false;
  for (let i = 0; i < otp.MAX_PER_IP + 2; i++) {
    const r = await otp.requestOtp(ctx, { phone: `+9190000000${String(i).padStart(2, '0')}`, ip: 'same' });
    if (r.error === 'RATE_LIMITED') limited = true;
  }
  assert.ok(limited);
});

test('access revoked or phone re-bound while a code is pending is refused', async () => {
  const a = setup();
  const r = await otp.requestOtp(a.ctx, { phone: PHONE, ip: 'x' });
  await a.db.collection('users').doc('u1').update({ 'login.enabled': false });
  assert.strictEqual((await otp.verifyOtp(a.ctx, { challengeId: r.challengeId, code: '424242' })).error, 'ACCESS_DISABLED');
  const b = setup();
  const r2 = await otp.requestOtp(b.ctx, { phone: PHONE, ip: 'x' });
  await b.db.collection('users').doc('u1').update({ 'login.phone': '+919999999999' });
  assert.strictEqual((await otp.verifyOtp(b.ctx, { challengeId: r2.challengeId, code: '424242' })).error, 'ACCESS_DISABLED');
});

test('provider failure is reported and the challenge is unusable', async () => {
  const { ctx } = setup(undefined, { sendOtp: async () => { throw new WhatsAppError('TIMEOUT', 'x'); } });
  const r = await otp.requestOtp(ctx, { phone: PHONE, ip: 'x' });
  assert.deepStrictEqual([r.error, r.reason], ['DELIVERY_FAILED', 'TIMEOUT']);
  const none = await otp.requestOtp({ ...ctx, sender: { configured: false } }, { phone: PHONE, ip: 'y' });
  assert.strictEqual(none.error, 'OTP_UNAVAILABLE');
  assert.strictEqual((await otp.requestOtp(ctx, { phone: 'abc', ip: 'z' })).error, 'INVALID_PHONE');
});

test('malformed verify input is rejected without touching storage', async () => {
  const { ctx } = setup();
  for (const [challengeId, code] of [[undefined, '123456'], ['zz', '123456'], ['0'.repeat(32), '12'], ['0'.repeat(32), 123456]]) {
    assert.strictEqual((await otp.verifyOtp(ctx, { challengeId, code })).error, 'OTP_INVALID');
  }
});

// ---- WhatsApp sender (HTTP mocked: no real message is ever sent) ----------

const cfg = { accessToken: 'tok', phoneNumberId: '123', templateName: 'tmpl', languageCode: 'en', apiVersion: 'v21.0' };
const resp = (status, body) => ({ ok: status < 300, status, json: async () => body });

test('whatsapp: posts the approved template with the code to the Graph API', async () => {
  let call;
  const s = createWhatsAppSender(cfg, async (url, init) => ((call = { url, init }), resp(200, {})));
  await s.sendOtp({ to: PHONE, code: '123456' });
  assert.strictEqual(call.url, 'https://graph.facebook.com/v21.0/123/messages');
  assert.strictEqual(call.init.headers.Authorization, 'Bearer tok');
  const body = JSON.parse(call.init.body);
  assert.strictEqual(body.to, '919876543210');
  assert.strictEqual(body.template.name, 'tmpl');
  assert.strictEqual(body.template.components[0].parameters[0].text, '123456');
});

test('whatsapp: maps provider failures to actionable codes', async () => {
  const run = async (fetchImpl, c = cfg) => createWhatsAppSender(c, fetchImpl).sendOtp({ to: PHONE, code: '1' }).catch((e) => e.code);
  assert.strictEqual(await run(async () => resp(400, { error: { code: 131026 } })), 'INVALID_RECIPIENT');
  assert.strictEqual(await run(async () => resp(429, { error: { code: 130429 } })), 'PROVIDER_RATE_LIMIT');
  assert.strictEqual(await run(async () => resp(401, { error: { code: 190 } })), 'PROVIDER_AUTH');
  assert.strictEqual(await run(async () => resp(500, null)), 'PROVIDER_ERROR');
  assert.strictEqual(await run(async () => { throw new TypeError('down'); }), 'NETWORK');
  assert.strictEqual(
    await run((u, { signal }) => new Promise((_, rej) => signal.addEventListener('abort', () => rej(Object.assign(new Error(), { name: 'AbortError' })))), { ...cfg, timeoutMs: 5 }),
    'TIMEOUT',
  );
  assert.strictEqual(await createWhatsAppSender({}, async () => resp(200, {})).sendOtp({ to: PHONE, code: '1' }).catch((e) => e.code), 'NOT_CONFIGURED');
});

test('SEC-3: challenges and rate counters carry a TTL date, so they are cleaned up', async () => {
  const { db, ctx } = setup();
  await otp.requestOtp(ctx, { phone: PHONE, ip: '1.1.1.1' });
  const docs = [...db.store.entries()];
  const challenge = docs.find(([k]) => k.startsWith('otpChallenges/'))[1];
  const rates = docs.filter(([k]) => k.startsWith('otpRate/')).map(([, v]) => v);
  assert.ok(challenge.expireAt instanceof Date);
  assert.ok(challenge.expireAt.getTime() > challenge.expiresAt);
  assert.strictEqual(rates.length, 2); // phone + ip
  for (const r of rates) assert.ok(r.expireAt instanceof Date && r.expireAt.getTime() > r.windowStart);
});

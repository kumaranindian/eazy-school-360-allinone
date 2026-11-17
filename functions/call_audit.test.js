'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const audit = require('./audit');
const { makeAuditedCall, eventTypeOf, categoryOf, actionOf } = require('./call_audit');

const NOW = new Date('2026-11-15T10:00:00Z');
const setup = (name, extra = {}) => {
  const db = fakeDb({ 'users/u1': { role: 'SCHOOL_ADMIN', schoolId: 's1', email: 'a@x.test' } });
  const logs = [];
  const wrap = makeAuditedCall({ ctx: () => ({ db, now: 'TS', nowDate: () => NOW }), nameOf: () => name, log: (m, d) => logs.push([m, d]), ...extra });
  const events = () => [...db.store.entries()].filter(([k]) => k.startsWith('auditEvents/')).map(([, v]) => v);
  return { db, wrap, events, logs };
};
const req = (data, uid = 'u1') => ({ data, auth: uid ? { uid, token: {} } : undefined, rawRequest: { ip: '1.2.3.4', headers: { 'user-agent': 'UA', 'x-cloud-trace-context': 'abc123/1;o=1' } } });

test('a successful call records action name, actor, request and response', async () => {
  const { wrap, events } = setup('updateAdmissionEnquiry');
  const out = await wrap(async () => ({ ok: true, id: 'e1' }))(req({ schoolId: 's1', enquiryId: 'e1', parentPhone: '9999999999', password: 'hunter2' }));
  assert.deepEqual(out, { ok: true, id: 'e1' });
  const [e] = events();
  assert.equal(e.actionName, 'updateAdmissionEnquiry');
  assert.equal(e.eventType, 'API_UPDATE_ADMISSION_ENQUIRY');
  assert.equal(e.category, 'ADMISSION');
  assert.equal(e.action, 'UPDATE');
  assert.equal(e.result, 'SUCCESS');
  assert.equal(e.actorUserId, 'u1');
  assert.equal(e.application, 'SCHOOL_ADMIN');
  assert.equal(e.schoolId, 's1');
  assert.equal(e.request.parentPhone, '9999999999', 'personal data is kept');
  assert.equal(e.request.password, '[masked]', 'secrets are masked');
  assert.deepEqual(e.response, { ok: true, id: 'e1' });
  assert.equal(e.client.ip, '1.2.3.4');
  assert.equal(e.correlationId, 'abc123');
  assert.equal(e.source, 'CALLABLE');
  assert.equal(e.trust, 'T1');
});

test('a failing call is recorded with its error and the error still reaches the caller', async () => {
  const { wrap, events } = setup('setSubscription');
  const boom = Object.assign(new Error('bad input'), { code: 'invalid-argument' });
  await assert.rejects(wrap(async () => { throw boom; })(req({ schoolId: 's1' })), (e) => e === boom);
  const [e] = events();
  assert.equal(e.result, 'FAILURE');
  assert.equal(e.error.code, 'invalid-argument');
  assert.equal(e.response, undefined);
});

test('permission and authentication refusals are DENIED', async () => {
  const { wrap, events } = setup('transitionSchool');
  await assert.rejects(wrap(async () => { throw Object.assign(new Error('no'), { code: 'permission-denied' }); })(req({})));
  assert.equal(events()[0].result, 'DENIED');
});

test('an anonymous (public) call has no actor and is a public-portal event', async () => {
  const { wrap, events } = setup('submitPublicAdmissionEnquiry');
  await wrap(async () => ({ ok: 1 }))(req({ name: 'Asha' }, null));
  const [e] = events();
  assert.equal(e.actorUserId, null);
  assert.equal(e.application, 'PUBLIC_PORTAL');
});

test('an audit write failure never changes the call result', async () => {
  const { wrap, db, logs } = setup('listPlans');
  const real = db.collection;
  db.collection = (p) => (p === 'auditEvents' ? { doc: () => ({ collection: () => ({ doc: () => ({ create: async () => { throw new Error('down'); } }) }) }) } : real(p));
  const out = await wrap(async () => 'fine')(req({}));
  assert.equal(out, 'fine');
  assert.ok(logs.length >= 1);
});

test('reading the trail does not copy it back into the trail; the app audit report is not audited twice', async () => {
  let s = setup('queryAuditEvents');
  await s.wrap(async () => ({ events: [{ big: 1 }] }))(req({}));
  assert.equal(s.events()[0].response, undefined);
  s = setup('reportClientEvent');
  await s.wrap(async () => ({ ok: true }))(req({}));
  assert.equal(s.events().length, 0);
});

test('a huge body is truncated with its size, not dropped or stored whole', async () => {
  const { wrap, events } = setup('createStudentImport');
  await wrap(async () => ({ ok: true }))(req({ rows: Array.from({ length: 150 }, (_, i) => ({ n: 'x'.repeat(500), i })) }));
  const r = events()[0].request;
  assert.equal(r.truncated, true);
  assert.ok(r.bytes > audit.PAYLOAD_MAX_BYTES);
  assert.ok(r.preview.length <= audit.PAYLOAD_MAX_BYTES);
});

test('secrets are masked anywhere in the request or response, including reset links and bearer strings', async () => {
  const { wrap, events } = setup('resetLoginPassword');
  await wrap(async () => ({ link: 'https://app/reset?oobCode=abc', header: 'Bearer abc.def', nested: { apiKey: 'k', otpCode: '1' } }))(req({ newPassword: 'p', note: 'ok' }));
  const [e] = events();
  assert.equal(e.request.newPassword, '[masked]');
  assert.equal(e.request.note, 'ok');
  assert.equal(e.response.link, '[masked]');
  assert.equal(e.response.header, '[masked]');
  assert.equal(e.response.nested.apiKey, '[masked]');
  assert.equal(e.response.nested.otpCode, '[masked]');
  assert.ok(!JSON.stringify(e).includes('hunter'));
});

test('names map to event types, categories and actions', () => {
  assert.equal(eventTypeOf('transitionSchool'), 'API_TRANSITION_SCHOOL');
  assert.match(eventTypeOf('a'.repeat(200)), /^API_[A-Z]+$/);
  assert.equal(categoryOf('recordAdmissionFeePayment'), 'ADMISSION');
  assert.equal(categoryOf('requestPhoneOtp'), 'AUTHENTICATION');
  assert.equal(categoryOf('somethingNew'), 'API');
  assert.equal(actionOf('getFeatureConfig'), 'VIEW');
  assert.equal(actionOf('cancelSubscription'), 'DELETE');
  assert.equal(actionOf('weirdName'), 'OTHER');
});

test('getAuditEvent returns the full payload to an owner only, and is itself audited', async () => {
  const db = fakeDb({ 'users/o1': { role: 'PLATFORM_ADMIN', platformRole: 'OWNER', status: 'ACTIVE', email: 'o@x.test' }, 'users/v1': { role: 'PLATFORM_ADMIN', platformRole: 'VIEWER', status: 'ACTIVE', email: 'v@x.test' } });
  const ctx = { db, now: 'TS', nowDate: () => NOW };
  const rec = await audit.record(ctx, { sourceId: 'x1', eventType: 'API_TEST_CALL', category: 'API', source: 'CALLABLE', actionName: 'testCall', request: { a: 1, password: 'z' }, response: { b: 2 } });
  const tok = { mfa: true, firebase: { sign_in_second_factor: 'totp' } };
  const ok = await audit.getAuditEvent(ctx, 'o1', tok, { eventId: rec.eventId, month: rec.month });
  assert.deepEqual(ok.event.request, { a: 1, password: '[masked]' });
  assert.deepEqual(ok.event.response, { b: 2 });
  const no = await audit.getAuditEvent(ctx, 'v1', tok, { eventId: rec.eventId, month: rec.month });
  assert.ok(no.error);
  assert.equal((await audit.getAuditEvent(ctx, 'o1', tok, { eventId: 'nope', month: rec.month })).error, 'INVALID_ARGUMENT');
  const viewed = [...db.store.values()].filter((v) => v.eventType === 'AUDIT_EVENT_VIEWED');
  assert.equal(viewed.length, 1);
});

test('data writes record the full before and after documents', () => {
  const e = audit.fromModuleWrite({ eventId: 'ev1', schoolId: 's1', branchId: 'b1', collection: 'students', docId: 'st1', before: { status: 'ACTIVE', phone: '1', updatedBy: 'u1' }, after: { status: 'INACTIVE', phone: '1', updatedBy: 'u1' } });
  const built = audit.buildEvent(e, NOW).event;
  assert.equal(built.actionName, 'students.update');
  assert.equal(built.before.phone, '1');
  assert.equal(built.after.status, 'INACTIVE');
  const sparse = audit.buildEvent(audit.fromModuleWrite({ eventId: 'ev2', schoolId: 's1', branchId: 'b1', collection: 'students', docId: 'st1', before: null, after: { status: 'ACTIVE' } }), NOW).event;
  assert.equal(sparse.before, undefined);
});

test('payroll: salary reads are not copied into the trail and a saved structure\'s amounts are not recorded', async () => {
  const { wrap, events } = setup('getSalaryStructure');
  await wrap(async () => ({ current: { netMinor: 3900000, lines: [{ amountMinor: 3000000 }] } }))(req({ schoolId: 's1', branchId: 'b1', staffId: 'st1' }));
  let [e] = events();
  assert.equal(e.response, undefined, 'the response (a salary) is not stored');
  assert.equal(e.request.staffId, 'st1', 'who was looked at is');
  assert.equal(e.result, 'SUCCESS');

  const s2 = setup('saveSalaryStructure');
  await s2.wrap(async () => ({ id: 'st1_00002', seq: 2 }))(req({ schoolId: 's1', branchId: 'b1', staffId: 'st1', effectiveFrom: '2026-12-01', reason: 'Annual increment', lines: [{ componentId: 'pc_basic', amountMinor: 3300000 }, { componentId: 'x', amountMinor: 1 }] }));
  [e] = s2.events();
  assert.equal(e.request.lines, '[2 lines; amounts not recorded]');
  assert.equal(JSON.stringify(e).includes('3300000'), false, 'no amount anywhere in the event');
  assert.equal(e.request.reason, 'Annual increment');
  assert.deepEqual(e.response, { id: 'st1_00002', seq: 2 });
  const s3 = setup('listSalaryStructures');
  await s3.wrap(async () => ({ staff: [{ netMinor: 1 }] }))(req({ schoolId: 's1', branchId: 'b1' }));
  assert.equal(s3.events()[0].response, undefined);
  // a malformed body must not break the call or leak
  const s4 = setup('saveSalaryStructure');
  await s4.wrap(async () => ({}))(req('not an object'));
  assert.equal(s4.events().length, 1);
});

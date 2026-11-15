'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const a = require('./admission');
const pub = require('./admission_public');

let clock = new Date('2026-11-07T10:00:00Z');
const now = clock;
const ctx = (db, over = {}) => ({ db, now, wall: () => clock, clientIp: '203.0.113.7', ...over });
const B = 'schools/sA/branches/b1';
const portal = { enabled: true, slug: 'rosewood', branchId: 'b1', introText: 'Welcome', consentText: 'I agree that the school may contact me about this enquiry.', consentVersion: 2 };
const seed = (settings = {}, portalOver = {}) => ({
  'schools/sA': { name: 'Rosewood High', timezone: 'Asia/Kolkata' },
  'schools/sB': { name: 'Other' },
  [B]: { name: 'Main' },
  [`${B}/academicYears/ay1`]: { name: '2026-27', status: 'ACTIVE', endDate: new Date('2027-03-31') },
  [`${B}/academicYears/ay1/classes/c1`]: { name: 'Class 1', status: 'ACTIVE' },
  [`${B}/academicYears/ay1/classes/c2`]: { name: 'Class 2', status: 'ACTIVE' },
  [`${B}/academicYears/old`]: { name: '2024-25', status: 'ARCHIVED' },
  [`${B}/academicYears/old/classes/c1`]: { name: 'Class 1', status: 'ACTIVE' },
  'schools/sA/admissionSettings/config': { ...a.DEFAULT_SETTINGS, enabled: true, version: 1, publicPortal: { ...portal, ...portalOver }, ...settings },
  'admissionPortalSlugs/rosewood': { schoolId: 'sA', branchId: 'b1', enabled: true },
  'users/adminA': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
});
const form = (over = {}) => ({
  slug: 'rosewood',
  requestId: 'req-pub-0001',
  consent: { accepted: true, version: 2 },
  enquiry: {
    student: { firstName: 'Asha', lastName: 'Nair', dateOfBirth: '2020-05-01', gender: 'FEMALE' },
    academicYearId: 'ay1',
    interestedClassId: 'c1',
    guardians: [{ name: 'Meena Nair', phone: '98765 43210', email: 'm@example.com', relationship: 'Mother' }],
  },
  ...over,
});
const enquiries = (db) => [...db.store.keys()].filter((k) => k.startsWith(`${B}/admissionEnquiries/`));

test('the page shows only what the school offers, nothing else', async () => {
  const db = fakeDb(seed());
  const r = await pub.getPublicPortal(ctx(db), null, null, { slug: 'rosewood' });
  assert.equal(r.result.schoolName, 'Rosewood High');
  assert.deepEqual(r.result.academicYears.map((y) => y.id), ['ay1']);
  assert.deepEqual(r.result.academicYears[0].classes.map((c) => c.id), ['c1', 'c2']);
  assert.equal(r.result.consentVersion, 2);
  assert.equal(JSON.stringify(r).includes('sA'), false, 'no internal ids of the school leak');
});

test('the school restricts the offered years and classes', async () => {
  const db = fakeDb(seed({ classIds: ['c2'] }));
  const r = await pub.getPublicPortal(ctx(db), null, null, { slug: 'rosewood' });
  assert.deepEqual(r.result.academicYears[0].classes.map((c) => c.id), ['c2']);
});

test('unknown, disabled and malformed slugs look the same: not found', async () => {
  for (const slug of ['nope', 'ROSE WOOD', '', undefined, '../x', 'a']) {
    assert.equal((await pub.getPublicPortal(ctx(fakeDb(seed())), null, null, { slug })).error, 'NOT_FOUND', String(slug));
  }
  for (const db of [fakeDb(seed({}, { enabled: false })), fakeDb(seed({ enabled: false })), fakeDb({ ...seed(), 'admissionPortalSlugs/rosewood': { schoolId: 'sA', branchId: 'b1', enabled: false } })]) {
    assert.equal((await pub.getPublicPortal(ctx(db), null, null, { slug: 'rosewood' })).error, 'NOT_FOUND');
    assert.equal((await pub.submitPublicEnquiry(ctx(db), null, null, form())).error, 'NOT_FOUND');
  }
});

test('a valid submission creates a NEW website enquiry in the portal branch, with consent recorded', async () => {
  const db = fakeDb(seed());
  const r = await pub.submitPublicEnquiry(ctx(db), null, null, form());
  assert.match(r.result.reference, /^ENQ-2026-\d{5}$/);
  const e = db.store.get(`${B}/admissionEnquiries/pub_req-pub-0001`);
  assert.equal(e.status, 'NEW');
  assert.equal(e.source, 'Website');
  assert.equal(e.channel, 'PUBLIC_PORTAL');
  assert.equal(e.assignedTo, null);
  assert.equal(e.primaryPhone, '9876543210');
  assert.equal(e.consent.accepted, true);
  assert.equal(e.consent.version, 2);
  assert.equal(e.consent.ipHash.length, 32);
  assert.notEqual(e.consent.ipHash, '203.0.113.7');
  assert.equal(e.createdBy, 'public-portal');
  assert.ok(db.store.get(`${B}/admissionStatusHistory/pub_req-pub-0001__1`));
});

test('the school and branch cannot be chosen by the caller', async () => {
  const db = fakeDb(seed());
  await pub.submitPublicEnquiry(ctx(db), null, null, form({ schoolId: 'sB', branchId: 'zz', enquiry: { ...form().enquiry, schoolId: 'sB', branchId: 'zz', status: 'APPROVED', remarks: 'x', assignedTo: 'adminA' } }));
  assert.equal(enquiries(db).length, 1);
  const e = db.store.get(`${B}/admissionEnquiries/pub_req-pub-0001`);
  assert.equal(e.schoolId, 'sA');
  assert.equal(e.branchId, 'b1');
  assert.equal(e.status, 'NEW');
  assert.equal(e.assignedTo, null);
  assert.ok(!e.remarks);
});

test('a retry with the same request id returns the same reference and stores nothing new', async () => {
  const db = fakeDb(seed());
  const one = await pub.submitPublicEnquiry(ctx(db), null, null, form());
  const two = await pub.submitPublicEnquiry(ctx(db), null, null, form());
  assert.equal(two.result.reference, one.result.reference);
  assert.equal(enquiries(db).length, 1);
});

test('consent is required and must be for the current text', async () => {
  const db = fakeDb(seed());
  assert.equal((await pub.submitPublicEnquiry(ctx(db), null, null, form({ consent: { accepted: false, version: 2 } }))).error, 'INVALID_ARGUMENT');
  assert.equal((await pub.submitPublicEnquiry(ctx(db), null, null, form({ consent: undefined }))).error, 'INVALID_ARGUMENT');
  assert.equal((await pub.submitPublicEnquiry(ctx(db), null, null, form({ consent: { accepted: true, version: 1 } }))).error, 'FAILED_PRECONDITION');
  assert.equal(enquiries(db).length, 0);
});

test('validation: bad mobile, missing name, a year or class the school does not offer', async () => {
  const db = fakeDb(seed());
  const bad = (mut) => { const f = form(); mut(f.enquiry); return pub.submitPublicEnquiry(ctx(db), null, null, f); };
  assert.equal((await bad((e) => { e.guardians[0].phone = '123'; })).error, 'INVALID_ARGUMENT');
  assert.equal((await bad((e) => { e.student.firstName = ''; })).error, 'INVALID_ARGUMENT');
  assert.equal((await bad((e) => { e.academicYearId = 'old'; })).error, 'INVALID_ARGUMENT');
  assert.equal((await bad((e) => { e.interestedClassId = 'c9'; })).error, 'INVALID_ARGUMENT');
  assert.equal((await bad((e) => { e.student.dateOfBirth = '2999-01-01'; })).error, 'INVALID_ARGUMENT');
  assert.equal(enquiries(db).length, 0);
  assert.equal((await pub.submitPublicEnquiry(ctx(db), null, null, form({ requestId: 'x' }))).error, 'INVALID_ARGUMENT');
});

test('the honeypot: a filled hidden field gets a quiet success and nothing is stored', async () => {
  const db = fakeDb(seed());
  const r = await pub.submitPublicEnquiry(ctx(db), null, null, form({ website: 'http://spam.example' }));
  assert.equal(r.result.reference, null);
  assert.equal(enquiries(db).length, 0);
});

test('rate limit per address: the 6th request in an hour is refused, an hour later it works', async () => {
  const db = fakeDb(seed());
  const send = (n, over) => pub.submitPublicEnquiry(ctx(db, over), null, null, form({ requestId: `req-rate-000${n}`, enquiry: { ...form().enquiry, guardians: [{ name: 'Meena Nair', phone: `98765432${10 + n}` }] } }));
  for (let n = 1; n <= 5; n++) assert.ok((await send(n)).result, `request ${n}`);
  assert.equal((await send(6)).error, 'RESOURCE_EXHAUSTED');
  assert.equal((await send(7, { clientIp: '198.51.100.9' })).result.reference.startsWith('ENQ'), true, 'another address is not affected');
  clock = new Date(clock.getTime() + 61 * 60 * 1000);
  assert.ok((await send(8)).result);
  clock = new Date('2026-11-07T10:00:00Z');
});

test('rate limit per mobile number: 3 a day', async () => {
  const db = fakeDb(seed());
  const send = (n, ip) => pub.submitPublicEnquiry(ctx(db, { clientIp: ip }), null, null, form({ requestId: `req-phone-000${n}` }));
  for (let n = 1; n <= 3; n++) assert.ok((await send(n, `10.0.0.${n}`)).result);
  assert.equal((await send(4, '10.0.0.9')).error, 'RESOURCE_EXHAUSTED');
});

test('no raw address is stored anywhere', async () => {
  const db = fakeDb(seed());
  await pub.submitPublicEnquiry(ctx(db), null, null, form());
  await pub.getPublicPortal(ctx(db), null, null, { slug: 'rosewood' });
  assert.equal(JSON.stringify([...db.store.entries()]).includes('203.0.113.7'), false);
});

test('captcha: when a secret is configured a valid token is required', async () => {
  const db = fakeDb(seed());
  const c = (verify) => ctx(db, { turnstileSecret: 's', verifyCaptcha: verify });
  assert.equal((await pub.submitPublicEnquiry(c(async () => false), null, null, form({ captchaToken: 'bad' }))).error, 'PERMISSION_DENIED');
  assert.equal(enquiries(db).length, 0);
  assert.ok((await pub.submitPublicEnquiry(c(async (t) => t === 'good'), null, null, form({ captchaToken: 'good' }))).result);
  assert.equal((await pub.getPublicPortal(c(), null, null, { slug: 'rosewood' })).result.captchaRequired, true);
});

test('verifyTurnstile: success, failure, missing token, network error', async () => {
  const ok = { fetchFn: async () => ({ json: async () => ({ success: true }) }), secret: 's' };
  assert.equal(await pub.verifyTurnstile('t', '1.1.1.1', ok), true);
  assert.equal(await pub.verifyTurnstile('t', null, { ...ok, fetchFn: async () => ({ json: async () => ({ success: false }) }) }), false);
  assert.equal(await pub.verifyTurnstile('', null, ok), false);
  assert.equal(await pub.verifyTurnstile('t', null, { ...ok, fetchFn: async () => { throw new Error('down'); } }), false);
});

test('a possible duplicate is flagged for staff but not revealed to the visitor', async () => {
  const db = fakeDb(seed());
  const first = await pub.submitPublicEnquiry(ctx(db, { clientIp: '10.1.1.1' }), null, null, form());
  const second = await pub.submitPublicEnquiry(ctx(db, { clientIp: '10.1.1.2' }), null, null, form({ requestId: 'req-pub-0002' }));
  assert.deepEqual(Object.keys(second.result), ['reference']);
  assert.notEqual(second.result.reference, first.result.reference);
  assert.equal(db.store.get(`${B}/admissionEnquiries/pub_req-pub-0002`).duplicateOf.length, 1);
});

test('settings: the page address is unique across schools, versions the consent, validates the branch', async () => {
  const db = fakeDb({ ...seed(), 'users/adminB': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' }, 'schools/sB/branches/bb': { name: 'B' } });
  const save = (uid, school, publicPortal, base) => a.saveAdmissionSettings(ctx(db), uid, undefined, { schoolId: school, baseVersion: base, settings: { enabled: true, publicPortal } });
  const mine = { enabled: true, slug: 'rosewood', branchId: 'b1', consentText: 'I agree that the school may contact me about this enquiry.' };
  const r1 = await save('adminA', 'sA', { ...mine, consentText: 'I agree that the school may contact me about my enquiry.' });
  assert.ok(r1.result, JSON.stringify(r1));
  assert.equal(db.store.get('schools/sA/admissionSettings/config').publicPortal.consentVersion, 3);
  const same = await save('adminA', 'sA', { ...mine, consentText: 'I agree that the school may contact me about my enquiry.' });
  assert.equal(db.store.get('schools/sA/admissionSettings/config').publicPortal.consentVersion, 3, 'unchanged text keeps the version');
  assert.ok(same.result);
  const clash = await save('adminB', 'sB', { ...mine, branchId: 'bb' });
  assert.equal(clash.error, 'FAILED_PRECONDITION');
  assert.equal((await save('adminA', 'sA', { ...mine, branchId: 'nope' })).error, 'INVALID_ARGUMENT');
  assert.equal((await save('adminA', 'sA', { ...mine, slug: 'Bad Slug' })).error, 'INVALID_ARGUMENT');
  assert.equal((await save('adminA', 'sA', { ...mine, slug: 'admin' })).error, 'INVALID_ARGUMENT');
  assert.equal((await save('adminA', 'sA', { ...mine, consentText: 'short' })).error, 'INVALID_ARGUMENT');
  const moved = await save('adminA', 'sA', { ...mine, slug: 'rosewood-high' });
  assert.ok(moved.result);
  assert.equal(db.store.get('admissionPortalSlugs/rosewood'), undefined, 'the old address is released');
  assert.ok(db.store.get('admissionPortalSlugs/rosewood-high'));
  assert.ok((await save('adminB', 'sB', { ...mine, branchId: 'bb' })).result, 'and can be taken by another school');
});

test('a suspended school, or one the platform switched the module off for, has no public page and takes no enquiries', async () => {
  const variants = [
    { 'schools/sA': { name: 'Rosewood High', timezone: 'Asia/Kolkata', status: 'SUSPENDED' } },
    { 'schools/sA': { name: 'Rosewood High', timezone: 'Asia/Kolkata', features: { admission: false } } },
    { 'schools/sA': { name: 'Rosewood High', timezone: 'Asia/Kolkata', features: { publicAdmission: false } } },
  ];
  for (const v of variants) {
    const db = fakeDb({ ...seed(), ...v });
    assert.equal((await pub.getPublicPortal(ctx(db), null, null, { slug: 'rosewood' })).error, 'NOT_FOUND', JSON.stringify(v));
    assert.equal((await pub.submitPublicEnquiry(ctx(db), null, null, form())).error, 'NOT_FOUND', JSON.stringify(v));
    assert.equal(enquiries(db).length, 0);
  }
  // Untouched or explicitly on: works as before.
  const on = fakeDb({ ...seed(), 'schools/sA': { name: 'Rosewood High', timezone: 'Asia/Kolkata', status: 'ACTIVE', features: { admission: true, publicAdmission: true } } });
  assert.equal((await pub.getPublicPortal(ctx(on), null, null, { slug: 'rosewood' })).result.schoolName, 'Rosewood High');
});

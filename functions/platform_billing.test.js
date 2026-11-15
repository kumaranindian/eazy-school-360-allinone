'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const pb = require('./platform_billing');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const NO_MFA = { firebase: { sign_in_provider: 'password' } };
const T0 = new Date('2026-11-13T10:00:00Z');
const admin = (role) => ({ role: 'PLATFORM_ADMIN', platformRole: role, status: 'ACTIVE', email: `${role}@avail404.com`, schoolId: null, login: { enabled: true, methods: ['PASSWORD'], effective: ['PASSWORD'] } });
const rec = { schoolId: 's1', period: 'Nov 2026', amountMinor: 1500000, currency: 'inr', dueDate: '2026-11-30', reference: 'INV-9', note: 'Annual licence' };

function world() {
  const db = fakeDb({
    'users/owner': admin('OWNER'), 'users/support': admin('SUPPORT'), 'users/viewer': admin('VIEWER'),
    'users/sa1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1' },
    'schools/s1': { name: 'Rosewood' },
  });
  return { db, ctx: { db, now: 'TS', nowDate: () => T0 } };
}
const audits = (db) => [...db.store.entries()].filter(([k]) => k.startsWith('platformAuditLog/')).map(([, v]) => v);
const records = (db) => [...db.store.entries()].filter(([k]) => k.startsWith('platformBilling/'));

test('only an owner with a second factor reads or writes billing', async () => {
  const { db, ctx } = world();
  assert.equal((await pb.saveBillingRecord(ctx, 'owner', NO_MFA, rec)).error, 'MFA_REQUIRED');
  for (const uid of ['support', 'viewer', 'sa1', 'nobody']) {
    assert.equal((await pb.saveBillingRecord(ctx, uid, MFA, rec)).error, 'PERMISSION_DENIED', uid);
    assert.equal((await pb.listBillingRecords(ctx, uid, MFA, {})).error, 'PERMISSION_DENIED', uid);
    assert.equal((await pb.setBillingStatus(ctx, uid, MFA, { id: 'x', status: 'PAID', paidDate: '2026-11-01' })).error, 'PERMISSION_DENIED', uid);
  }
  assert.equal(records(db).length, 0);
});

test('a record is validated: integer minor units, a real currency and due date, an existing school', async () => {
  const { ctx } = world();
  for (const bad of [
    { ...rec, amountMinor: 0 }, { ...rec, amountMinor: -5 }, { ...rec, amountMinor: 12.5 }, { ...rec, amountMinor: '100' }, { ...rec, amountMinor: 2e12 },
    { ...rec, currency: 'rupees' }, { ...rec, currency: '' }, { ...rec, dueDate: '30/11/2026' }, { ...rec, dueDate: '2026-02-31' }, { ...rec, period: 'x' }, { ...rec, schoolId: '' },
  ]) assert.equal((await pb.saveBillingRecord(ctx, 'owner', MFA, bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  assert.equal((await pb.saveBillingRecord(ctx, 'owner', MFA, { ...rec, schoolId: 'ghost' })).error, 'NOT_FOUND');
});

test('saving writes a DUE record with the school name and an audit entry', async () => {
  const { db, ctx } = world();
  const out = await pb.saveBillingRecord(ctx, 'owner', MFA, rec);
  assert.equal(out.ok, true);
  const r = db.store.get(`platformBilling/${out.id}`);
  assert.deepEqual([r.status, r.currency, r.amountMinor, r.schoolName, r.paidDate], ['DUE', 'INR', 1500000, 'Rosewood', null]);
  assert.equal(audits(db)[0].action, 'BILLING_RECORD_CREATED');
  assert.equal(audits(db)[0].schoolId, 's1');
});

test('DUE moves to PAID (needs a real past date), WAIVED or VOID; every end state is final', async () => {
  const { db, ctx } = world();
  const mk = async () => (await pb.saveBillingRecord(ctx, 'owner', MFA, rec)).id;
  const a = await mk();
  for (const bad of [{}, { paidDate: '2026-11-14' }, { paidDate: 'yesterday' }, { paidDate: '2026-13-01' }]) {
    assert.equal((await pb.setBillingStatus(ctx, 'owner', MFA, { id: a, status: 'PAID', ...bad })).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
  assert.equal((await pb.setBillingStatus(ctx, 'owner', MFA, { id: a, status: 'PENDING' })).error, 'INVALID_ARGUMENT');
  assert.equal((await pb.setBillingStatus(ctx, 'owner', MFA, { id: 'ghost', status: 'VOID' })).error, 'NOT_FOUND');
  assert.equal((await pb.setBillingStatus(ctx, 'owner', MFA, { id: a, status: 'PAID', paidDate: '2026-11-13', note: 'Bank transfer' })).ok, true);
  assert.deepEqual([db.store.get(`platformBilling/${a}`).status, db.store.get(`platformBilling/${a}`).paidDate, db.store.get(`platformBilling/${a}`).note], ['PAID', '2026-11-13', 'Bank transfer']);
  for (const next of ['VOID', 'DUE', 'WAIVED', 'PAID']) {
    assert.equal((await pb.setBillingStatus(ctx, 'owner', MFA, { id: a, status: next, paidDate: '2026-11-13' })).reason, 'FINAL', next);
  }
  const b = await mk();
  assert.equal((await pb.setBillingStatus(ctx, 'owner', MFA, { id: b, status: 'WAIVED' })).ok, true);
  const c = await mk();
  assert.equal((await pb.setBillingStatus(ctx, 'owner', MFA, { id: c, status: 'VOID' })).ok, true);
  assert.deepEqual(audits(db).map((x) => x.action).filter((x) => x !== 'BILLING_RECORD_CREATED'), ['BILLING_RECORD_PAID', 'BILLING_RECORD_WAIVED', 'BILLING_RECORD_VOID']);
});

test('the list shows what is still owed per currency, overdue separately, ignoring settled records', async () => {
  const { ctx } = world();
  const due = await pb.saveBillingRecord(ctx, 'owner', MFA, { ...rec, dueDate: '2026-11-30' });
  await pb.saveBillingRecord(ctx, 'owner', MFA, { ...rec, period: 'Oct 2026', dueDate: '2026-10-31', amountMinor: 500000 });
  await pb.saveBillingRecord(ctx, 'owner', MFA, { ...rec, period: 'US plan', currency: 'USD', amountMinor: 20000, dueDate: '2026-12-31' });
  const paid = await pb.saveBillingRecord(ctx, 'owner', MFA, { ...rec, period: 'Sep 2026', dueDate: '2026-09-30' });
  await pb.setBillingStatus(ctx, 'owner', MFA, { id: paid.id, status: 'PAID', paidDate: '2026-10-01' });
  const out = await pb.listBillingRecords(ctx, 'owner', MFA, {});
  assert.equal(out.records.length, 4);
  assert.deepEqual(out.owed.INR, { dueMinor: 2000000, overdueMinor: 500000 });
  assert.deepEqual(out.owed.USD, { dueMinor: 20000, overdueMinor: 0 });
  assert.equal((await pb.listBillingRecords(ctx, 'owner', MFA, { schoolId: 'other' })).records.length, 0);
  assert.ok(due.id);
});

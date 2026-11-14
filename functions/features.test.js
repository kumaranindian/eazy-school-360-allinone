'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const F = require('./features');

const MFA = { firebase: { sign_in_provider: 'password', sign_in_second_factor: 'totp' } };
const ctxOf = (db) => ({ db, now: 'NOW', nowDate: () => new Date('2026-06-15T10:00:00Z') });
function world(extra = {}) {
  return fakeDb({
    'schools/s1': { name: 'S1', status: 'ACTIVE' },
    'schools/s2': { name: 'S2', status: 'ACTIVE', features: { admission: false, publicAdmission: false } },
    'users/owner': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'OWNER', email: 'o@avail404.com' },
    'users/support': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'SUPPORT' },
    'users/viewer': { role: 'PLATFORM_ADMIN', status: 'ACTIVE', platformRole: 'VIEWER' },
    'users/a1': { role: 'SCHOOL_ADMIN', status: 'ACTIVE', schoolId: 's1' },
    'users/t1': { role: 'TEACHER', status: 'ACTIVE', schoolId: 's1' },
    ...extra,
  });
}
const school = async (db, id = 's1') => (await db.collection('schools').doc(id).get()).data();
const history = async (db) => (await db.collection('schoolFeatureHistory').get()).docs.map((d) => d.data());
const set = (db, over) => F.setSchoolFeatures(ctxOf(db), 'owner', MFA, { schoolId: 's1', ...over });

test('catalogue: only real modules, unique keys, every dependency exists, no cycles, existing keys kept', () => {
  assert.equal(new Set(F.KEYS).size, F.KEYS.length);
  for (const f of F.CATALOGUE) {
    assert.ok(f.label.length > 3, f.key);
    for (const d of f.dependsOn) assert.ok(F.BY_KEY[d], `${f.key} -> ${d}`);
    assert.ok(!F.dependantsOf(f.key).includes(f.key), `cycle at ${f.key}`);
  }
  for (const kept of ['admission', 'publicAdmission']) assert.ok(F.BY_KEY[kept], kept);
  for (const absent of ['transport', 'library', 'payments', 'parentApp', 'teacherApp']) assert.equal(F.BY_KEY[absent], undefined, absent);
  assert.equal(F.consistent(F.effective({})), true, 'everything on is consistent');
});

test('dependants are transitive', () => {
  assert.deepEqual(F.dependantsOf('fees').sort(), ['feeReminders']);
  assert.deepEqual(F.dependantsOf('admission'), ['publicAdmission']);
  assert.deepEqual(F.dependantsOf('students').sort(), ['admission', 'attendance', 'exams', 'fees', 'feeReminders', 'messages', 'parents', 'publicAdmission'].sort());
  assert.deepEqual(F.dependantsOf('notifications'), []);
});

test('planChange: enabling needs dependencies; disabling needs confirmation and cascades', () => {
  const on = F.effective({});
  assert.deepEqual(F.planChange(on, { fees: false }, false), { error: 'FAILED_PRECONDITION', reason: 'DEPENDANTS', keys: ['feeReminders'] });
  const ok = F.planChange(on, { fees: false }, true);
  assert.deepEqual(ok.changed, [{ key: 'fees', from: true, to: false, cascade: false }, { key: 'feeReminders', from: true, to: false, cascade: true }]);
  const off = F.effective({ fees: false, feeReminders: false });
  assert.deepEqual(F.planChange(off, { feeReminders: true }, false), { error: 'FAILED_PRECONDITION', reason: 'DEPENDENCY', keys: ['fees'] });
  assert.equal(F.planChange(off, { fees: true, feeReminders: true }, false).changed.length, 2, 'both together is fine');
  assert.equal(F.planChange(on, { fees: true }, false).changed.length, 0, 'no-op');
  assert.equal(F.planChange(on, { payroll: false }, true).reason, 'features');
  assert.equal(F.planChange(on, { fees: 'no' }, true).reason, 'features');
  assert.equal(F.consistent(F.planChange(on, { students: false }, true).next), true, 'the result is always consistent');
});

test('set: owner only; support and viewers refused; nothing written', async () => {
  const db = world();
  for (const uid of ['support', 'viewer', 't1', 'ghost']) {
    const out = await F.setSchoolFeatures(ctxOf(db), uid, MFA, { schoolId: 's1', features: { homework: false }, reason: 'A proper reason here' });
    assert.equal(out.error, 'PERMISSION_DENIED', uid);
  }
  assert.equal((await school(db)).features, undefined);
});

test('set: validation', async () => {
  const db = world();
  for (const bad of [undefined, null, 'x', [], {}, { homework: 'off' }, { transport: false }]) {
    assert.equal((await set(db, { features: bad, reason: 'A proper reason here' })).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
  assert.equal((await set(db, { schoolId: '', features: { homework: false }, reason: 'A proper reason here' })).error, 'INVALID_ARGUMENT');
  assert.equal((await set(db, { schoolId: 'ghost', features: { homework: false }, reason: 'A proper reason here' })).error, 'NOT_FOUND');
  assert.equal((await set(db, { features: { homework: false }, reason: 'short' })).reason, 'reason', 'switching off needs a reason');
  assert.equal((await set(db, { features: { homework: false } })).reason, 'reason');
  assert.equal((await school(db)).features, undefined);
});

test('switching off: school + history + audit + one notice, with the reason on record', async () => {
  const db = world();
  const out = await set(db, { features: { homework: false }, reason: 'Not included in this plan' });
  assert.equal(out.ok, true);
  assert.deepEqual(out.changed, [{ key: 'homework', from: true, to: false, cascade: false }]);
  const s = await school(db);
  assert.equal(s.features.homework, false);
  assert.equal(s.featuresVersion, 1);
  const h = await history(db);
  assert.equal(h.length, 1);
  assert.deepEqual([h[0].feature, h[0].from, h[0].to, h[0].reason, h[0].actorEmail], ['homework', true, false, 'Not included in this plan', 'o@avail404.com']);
  const audit = (await db.collection('platformAuditLog').get()).docs.map((d) => d.data()).find((a) => a.action === 'SCHOOL_FEATURES_CHANGED');
  assert.deepEqual(audit.meta.changed, ['homework:off']);
  const notes = (await db.collection('platformNotifications').get()).docs.map((d) => d.data());
  assert.equal(notes.length, 1);
  assert.equal(notes[0].recipientUserId, 'a1');
  assert.equal(notes[0].type, 'FEATURE_CHANGED');
  assert.ok(notes[0].body.includes('Homework and submissions switched off'));
  assert.ok(!notes[0].body.includes('Not included'), 'the internal reason is not shown to the school');
});

test('switching off a module with dependants needs confirmation, then cascades with a history row each', async () => {
  const db = world();
  const refused = await set(db, { features: { fees: false }, reason: 'Fees are billed elsewhere' });
  assert.deepEqual([refused.error, refused.reason], ['FAILED_PRECONDITION', 'DEPENDANTS']);
  assert.equal((await school(db)).features, undefined, 'nothing changed');
  const out = await set(db, { features: { fees: false }, reason: 'Fees are billed elsewhere', confirmDependants: true });
  assert.deepEqual(out.changed.map((c) => [c.key, c.cascade]), [['fees', false], ['feeReminders', true]]);
  const h = await history(db);
  assert.deepEqual(h.map((e) => [e.feature, e.cascade, e.version]).sort(), [['feeReminders', true, 1], ['fees', false, 1]]);
});

test('enabling needs its dependencies on; the same call can enable both', async () => {
  const db = world({ 'schools/s1': { name: 'S1', status: 'ACTIVE', features: { fees: false, feeReminders: false } } });
  const refused = await set(db, { features: { feeReminders: true } });
  assert.deepEqual([refused.error, refused.reason], ['FAILED_PRECONDITION', 'DEPENDENCY']);
  const out = await set(db, { features: { fees: true, feeReminders: true } });
  assert.equal(out.ok, true);
  assert.equal(F.effective((await school(db)).features).fees, true);
  assert.equal((await school(db)).featuresVersion, 1);
});

test('no change is a no-op: nothing written, nobody notified', async () => {
  const db = world();
  const out = await set(db, { features: { homework: true } });
  assert.equal(out.unchanged, true);
  assert.equal((await history(db)).length, 0);
  assert.equal((await db.collection('platformNotifications').get()).docs.length, 0);
});

test('other schools are never touched', async () => {
  const db = world();
  await set(db, { features: { homework: false }, reason: 'Not included in this plan' });
  assert.deepEqual((await school(db, 's2')).features, { admission: false, publicAdmission: false });
});

test('legacy schools: the old keys keep their meaning and a missing key means on', () => {
  const eff = F.effective({ admission: false });
  assert.equal(eff.admission, false);
  assert.equal(eff.publicAdmission, true, 'stored as it was; the next change makes it consistent');
  assert.equal(eff.homework, true);
});

test('defaults: owner sets them, they must be consistent, new schools get a snapshot, existing ones never change', async () => {
  const db = world();
  const c = ctxOf(db);
  assert.equal((await F.setFeatureDefaults(c, 'support', MFA, { features: { homework: false } })).error, 'PERMISSION_DENIED');
  assert.equal((await F.setFeatureDefaults(c, 'owner', MFA, { features: { homework: 'x' } })).error, 'INVALID_ARGUMENT');
  assert.equal((await F.setFeatureDefaults(c, 'owner', MFA, { features: { fees: false } })).reason, 'DEPENDENCY', 'feeReminders is still on');
  const ok = await F.setFeatureDefaults(c, 'owner', MFA, { features: { fees: false, feeReminders: false, homework: false } });
  assert.equal(ok.defaults.fees, false);
  assert.equal(ok.defaults.homework, false);
  assert.equal(ok.defaults.exams, true);
  const snap = await F.snapshotDefaults(db);
  assert.equal(snap.fees, false);
  assert.deepEqual(Object.keys(snap).sort(), [...F.KEYS].sort(), 'a full explicit snapshot');
  assert.equal((await school(db)).features, undefined, 'an existing school is unchanged');
  const viewer = await F.getFeatureConfig(c, 'viewer', MFA);
  assert.equal(viewer.catalogue.length, F.KEYS.length);
  assert.equal(viewer.defaults.homework, false);
  assert.equal((await F.getFeatureConfig(c, 't1', MFA)).error, 'PERMISSION_DENIED');
  const audit = (await db.collection('platformAuditLog').get()).docs.map((d) => d.data()).find((a) => a.action === 'FEATURE_DEFAULTS_CHANGED');
  assert.equal(audit.meta.before.homework, true);
  assert.equal(audit.meta.after.homework, false);
});

test('a school created by the platform copies today\'s defaults', async () => {
  const L = require('./school_lifecycle');
  const db = world();
  await F.setFeatureDefaults(ctxOf(db), 'owner', MFA, { features: { homework: false } });
  const auth = { users: {}, getUserByEmail: async () => { const e = new Error('nf'); e.code = 'auth/user-not-found'; throw e; }, createUser: async () => ({ uid: 'new1' }), updateUser: async () => {}, revokeRefreshTokens: async () => {}, generatePasswordResetLink: async () => 'x' };
  const out = await L.createSchoolWithAdmin({ ...ctxOf(db), auth }, 'owner', MFA, { schoolName: 'New School', adminName: 'Asha Rao', adminEmail: 'asha@newschool.edu', regional: { countryCode: 'IN', currency: 'INR', timezone: 'Asia/Kolkata', dateFormat: 'dd/MM/yyyy' } });
  assert.equal(out.ok, true, JSON.stringify(out));
  const created = await school(db, out.schoolId);
  assert.equal(created.features.homework, false);
  assert.equal(created.features.exams, true);
  assert.equal(created.featuresVersion, 1);
  await F.setFeatureDefaults(ctxOf(db), 'owner', MFA, { features: { homework: true } });
  assert.equal((await school(db, out.schoolId)).features.homework, false, 'later default changes do not reach it');
});

test('history: platform roles read it newest first; school users cannot', async () => {
  const db = world();
  await set(db, { features: { homework: false }, reason: 'Not included in this plan' });
  await set(db, { features: { homework: true } });
  const r = await F.getFeatureHistory(ctxOf(db), 'viewer', MFA, { schoolId: 's1' });
  assert.equal(r.entries.length, 2);
  assert.deepEqual(r.entries.map((e) => e.version).sort(), [1, 2]);
  assert.equal((await F.getFeatureHistory(ctxOf(db), 't1', MFA, { schoolId: 's1' })).error, 'PERMISSION_DENIED');
  assert.equal((await F.getFeatureHistory(ctxOf(db), 'viewer', MFA, {})).reason, 'schoolId');
});

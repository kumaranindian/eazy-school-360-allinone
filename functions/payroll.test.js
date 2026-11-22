'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const p = require('./payroll');
const features = require('./features');

const now = 'TS';
const at = (db, path) => path.split('/').reduce((r, seg, i) => (i === 0 ? db.collection(seg) : i % 2 ? r.doc(seg) : r.collection(seg)), null);
const T = {};
const seed = (extra = {}) => ({
  'schools/sA': { name: 'A', status: 'ACTIVE', currency: 'INR', timezone: 'Asia/Kolkata' },
  'schools/sB': { name: 'B', status: 'ACTIVE' },
  'users/owner': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/fin': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'FINANCE' },
  'users/finB2': { schoolId: 'sA', branchId: 'b2', status: 'ACTIVE', role: 'FINANCE' },
  'users/ba1': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacher': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/parent': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  'users/otherOwner': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'schools/sA/branches/b1': { name: 'One' },
  'schools/sA/branches/b1/staff/st1': { firstName: 'Asha', lastName: 'Rao', employeeCode: 'E1', status: 'ACTIVE', userId: 'teacher' },
  'schools/sA/branches/b1/staff/st2': { firstName: 'Bala', employeeCode: 'E2', status: 'ACTIVE' },
  'schools/sA/branches/b1/staff/gone': { firstName: 'Left', status: 'RESIGNED' },
  ...extra,
});
const env = (extra) => {
  const db = fakeDb(seed(extra));
  return { db, ctx: { db, now, wall: () => new Date('2026-11-17T06:00:00Z') } };
};
const comp = async (ctx, body) => (await p.savePayComponent(ctx, 'owner', T, { schoolId: 'sA', ...body }));
const basicId = 'pc_basic';
const struct = (extra = {}) => ({ schoolId: 'sA', branchId: 'b1', staffId: 'st1', effectiveFrom: '2026-11-01', lines: [{ componentId: basicId, amountMinor: 3000000 }], ...extra });

test('the capability table: finance reads, only a school admin changes; no branch admin, no teacher', () => {
  assert.deepEqual(p.CAPS.view, ['SCHOOL_ADMIN', 'FINANCE']);
  assert.deepEqual(p.CAPS.editStructure, ['SCHOOL_ADMIN']);
  assert.deepEqual(p.CAPS.manage, ['SCHOOL_ADMIN']);
});

test('authorize: roles, branch scope, school, login state, module switch', async () => {
  const { db } = env();
  const a = (uid, branch, cap, school = 'sA') => p.authorize(db, uid, T, school, branch, cap);
  assert.ok(await a('owner', 'b1', 'editStructure'));
  assert.ok(await a('fin', 'b1', 'view'));
  assert.equal(await a('fin', 'b1', 'editStructure'), null);
  assert.equal(await a('fin', null, 'manage'), null);
  assert.equal(await a('finB2', 'b1', 'view'), null, 'finance only in their own branch');
  for (const u of ['ba1', 'teacher', 'parent', 'otherOwner', 'ghost']) assert.equal(await a(u, 'b1', 'view'), null, u);
  assert.equal(await a('owner', 'b1', 'nope'), null);
  assert.equal(await a('owner', '../x', 'view'), null);
  const off = fakeDb(seed({ 'schools/sA': { name: 'A', status: 'ACTIVE', features: { payroll: false } } }));
  assert.equal(await p.authorize(off, 'owner', T, 'sA', 'b1', 'view'), null, 'module off');
  const noStaff = fakeDb(seed({ 'schools/sA': { name: 'A', status: 'ACTIVE', features: { staff: false } } }));
  assert.equal(await p.authorize(noStaff, 'owner', T, 'sA', 'b1', 'view'), null, 'payroll needs the staff module');
});

test('payroll depends on staff in the catalogue', () => {
  const f = features.CATALOGUE.find((x) => x.key === 'payroll');
  assert.deepEqual(f.dependsOn, ['staff']);
});

test('components: the built-in basic is seeded; add, percent, rename, switch off; immutability of meaning', async () => {
  const { ctx } = env();
  const l = await p.listPayComponents(ctx, 'fin', T, { schoolId: 'sA' });
  assert.deepEqual(l.components.map((c) => c.id), [basicId]);
  assert.equal(l.canManage, false);
  const hra = await comp(ctx, { name: 'HRA', kind: 'EARNING', calc: 'PERCENT', basisComponentId: basicId, percentBp: 4000 });
  assert.ok(hra.result.id);
  const pf = await comp(ctx, { name: 'Provident fund', kind: 'DEDUCTION', calc: 'PERCENT', basisComponentId: basicId, percentBp: 1200 });
  assert.ok(pf.result.id);
  assert.equal((await comp(ctx, { name: ' hra ', kind: 'EARNING', calc: 'FIXED' })).error, 'ALREADY_EXISTS');
  assert.equal((await comp(ctx, { name: 'Chain', kind: 'EARNING', calc: 'PERCENT', basisComponentId: hra.result.id, percentBp: 100 })).error, 'INVALID_ARGUMENT', 'basis must be fixed');
  assert.equal((await comp(ctx, { name: 'Pct', kind: 'EARNING', calc: 'PERCENT', basisComponentId: basicId })).error, 'INVALID_ARGUMENT', 'percentage required');
  assert.equal((await comp(ctx, { componentId: basicId, name: 'Renamed', active: true })).error, 'FAILED_PRECONDITION');
  assert.equal((await comp(ctx, { componentId: basicId, name: 'Basic salary', active: false })).error, 'FAILED_PRECONDITION');
  // rename + change the default percentage; kind/calc/basis are not editable
  assert.ok((await comp(ctx, { componentId: hra.result.id, name: 'House rent allowance', kind: 'DEDUCTION', calc: 'FIXED', percentBp: 3500 })).result);
  const after = (await p.listPayComponents(ctx, 'owner', T, { schoolId: 'sA' })).components.find((c) => c.id === hra.result.id);
  assert.deepEqual([after.name, after.kind, after.calc, after.percentBp, after.basisComponentId], ['House rent allowance', 'EARNING', 'PERCENT', 3500, basicId]);
  assert.ok((await comp(ctx, { componentId: hra.result.id, name: 'House rent allowance', active: false })).result);
  assert.equal((await p.listPayComponents(ctx, 'owner', T, { schoolId: 'sA' })).components.some((c) => c.id === hra.result.id), false);
  assert.equal((await p.listPayComponents(ctx, 'owner', T, { schoolId: 'sA', includeInactive: true })).components.some((c) => c.id === hra.result.id), true);
  assert.equal((await p.listPayComponents(ctx, 'fin', T, { schoolId: 'sA', includeInactive: true })).components.some((c) => c.id === hra.result.id), false, 'finance sees active only');
  // inactive basis cannot be used for a new component
  assert.equal((await comp(ctx, { name: 'Late', kind: 'EARNING', calc: 'PERCENT', basisComponentId: 'pc_missing', percentBp: 100 })).error, 'INVALID_ARGUMENT');
});

test('components: who may write, bad input', async () => {
  const { ctx } = env();
  for (const u of ['fin', 'ba1', 'teacher', 'parent', 'otherOwner', 'ghost']) {
    assert.equal((await p.savePayComponent(ctx, u, T, { schoolId: 'sA', name: 'X1', kind: 'EARNING', calc: 'FIXED' })).error, 'PERMISSION_DENIED', u);
  }
  for (const u of ['ba1', 'teacher', 'parent', 'otherOwner']) assert.equal((await p.listPayComponents(ctx, u, T, { schoolId: 'sA' })).error, 'PERMISSION_DENIED', u);
  for (const bad of [{ name: '' }, { name: 'x' }, { name: 'ok', kind: 'BONUS', calc: 'FIXED' }, { name: 'ok', kind: 'EARNING', calc: 'X' }, { name: 'ok', kind: 'EARNING', calc: 'FIXED', active: 'yes' }, { name: 'ok', kind: 'EARNING', calc: 'FIXED', percentBp: 1.5 }, { name: 5 }]) {
    assert.equal((await comp(ctx, bad)).error, 'INVALID_ARGUMENT', JSON.stringify(bad));
  }
  assert.equal((await comp(ctx, { componentId: '../x', name: 'ok' })).error, 'INVALID_ARGUMENT');
  assert.equal((await comp(ctx, { componentId: 'pc_none', name: 'ok' })).error, 'NOT_FOUND');
});

test('structure: first version, snapshot, totals, currency lock; reads', async () => {
  const { ctx, db } = env();
  await p.listPayComponents(ctx, 'owner', T, { schoolId: 'sA' });
  const hra = (await comp(ctx, { name: 'HRA', kind: 'EARNING', calc: 'PERCENT', basisComponentId: basicId, percentBp: 4000 })).result.id;
  const pf = (await comp(ctx, { name: 'PF', kind: 'DEDUCTION', calc: 'PERCENT', basisComponentId: basicId, percentBp: 1200 })).result.id;
  const out = await p.saveSalaryStructure(ctx, 'owner', T, struct({ lines: [{ componentId: basicId, amountMinor: 3000000 }, { componentId: hra }, { componentId: pf, percentBp: 1000 }] }));
  assert.deepEqual(out.result, { id: 'st1_00001', seq: 1 });
  const doc = (await at(db, 'schools/sA/branches/b1/salaryStructures/st1_00001').get()).data();
  assert.equal(doc.grossMinor, 4200000);
  assert.equal(doc.deductionsMinor, 300000, 'the per-employee percentage overrides the default');
  assert.equal(doc.netMinor, 3900000);
  assert.equal(doc.currency, 'INR');
  assert.equal(doc.latest, true);
  assert.equal(doc.lines[1].nameSnapshot, 'HRA');
  assert.equal((await at(db, 'schools/sA').get()).data().currencyLocked, true);
  const got = await p.getSalaryStructure(ctx, 'fin', T, { schoolId: 'sA', branchId: 'b1', staffId: 'st1' });
  assert.equal(got.result.current.netMinor, 3900000);
  assert.equal(got.result.canEdit, false);
  assert.equal(got.result.currency, 'INR');
  assert.equal(got.result.staff.name, 'Asha Rao');
  const list = await p.listSalaryStructures(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1' });
  assert.deepEqual(list.result.staff.map((s) => [s.staffId, s.hasStructure, s.netMinor]), [['st1', true, 3900000], ['st2', false, null]], 'a staff member who left is not listed');
  assert.equal(list.result.currency, 'INR');
  assert.equal(JSON.stringify(list).includes('nameSnapshot'), false, 'the list carries totals, not lines');
});

test('structure: a revision is a NEW version with a reason; old versions never change; effective dating', async () => {
  const { ctx, db } = env();
  await p.listPayComponents(ctx, 'owner', T, { schoolId: 'sA' });
  assert.ok((await p.saveSalaryStructure(ctx, 'owner', T, struct({ effectiveFrom: '2026-04-01' }))).result);
  assert.equal((await p.saveSalaryStructure(ctx, 'owner', T, struct({ effectiveFrom: '2026-12-01', lines: [{ componentId: basicId, amountMinor: 3300000 }] }))).error, 'INVALID_ARGUMENT', 'a revision needs a reason');
  assert.equal((await p.saveSalaryStructure(ctx, 'owner', T, struct({ effectiveFrom: '2026-12-01', reason: 'short', lines: [{ componentId: basicId, amountMinor: 3300000 }] }))).error, 'INVALID_ARGUMENT');
  const r2 = await p.saveSalaryStructure(ctx, 'owner', T, struct({ effectiveFrom: '2026-12-01', reason: 'Annual increment 10%', lines: [{ componentId: basicId, amountMinor: 3300000 }] }));
  assert.equal(r2.result.seq, 2);
  const v1 = (await at(db, 'schools/sA/branches/b1/salaryStructures/st1_00001').get()).data();
  assert.equal(v1.latest, false);
  assert.equal(v1.grossMinor, 3000000, 'the old version is untouched');
  // in force today (2026-11-17) is still version 1; the December one is future-dated
  const got = (await p.getSalaryStructure(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', staffId: 'st1' })).result;
  assert.equal(got.current.seq, 1);
  assert.deepEqual(got.history.map((h) => h.seq), [2, 1]);
  // history is not rewritten: nothing earlier than the latest
  assert.equal((await p.saveSalaryStructure(ctx, 'owner', T, struct({ effectiveFrom: '2026-06-01', reason: 'Backdated fix attempt' }))).error, 'FAILED_PRECONDITION');
  // the same date again supersedes it (a correction), still as a new version
  const r3 = await p.saveSalaryStructure(ctx, 'owner', T, struct({ effectiveFrom: '2026-12-01', reason: 'Corrected the amount', lines: [{ componentId: basicId, amountMinor: 3400000 }] }));
  assert.equal(r3.result.seq, 3);
  assert.equal(p.inForce((await (async () => { const g = (await p.getSalaryStructure(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', staffId: 'st1' })).result.history; return g.map((h) => ({ id: h.id, data: h })); })()), '2026-12-05').data.seq, 3, 'the later revision of the same date wins');
  // optimistic check
  assert.equal((await p.saveSalaryStructure(ctx, 'owner', T, struct({ effectiveFrom: '2027-01-01', reason: 'Stale screen save', baseSeq: 1 }))).error, 'ABORTED');
});

test('structure: refusals (role, branch, staff, dates, components, lines)', async () => {
  const { ctx, db } = env();
  await p.listPayComponents(ctx, 'owner', T, { schoolId: 'sA' });
  const off = (await comp(ctx, { name: 'Old', kind: 'EARNING', calc: 'FIXED' })).result.id;
  await comp(ctx, { componentId: off, name: 'Old', active: false });
  const rows = [
    ['PERMISSION_DENIED', 'fin', struct()],
    ['PERMISSION_DENIED', 'ba1', struct()],
    ['PERMISSION_DENIED', 'teacher', struct()],
    ['PERMISSION_DENIED', 'otherOwner', struct()],
    ['PERMISSION_DENIED', 'owner', struct({ branchId: '../b' })],
    ['PERMISSION_DENIED', 'owner', struct({ staffId: 5 })],
    ['NOT_FOUND', 'owner', struct({ staffId: 'nobody' })],
    ['FAILED_PRECONDITION', 'owner', struct({ staffId: 'gone' })],
    ['INVALID_ARGUMENT', 'owner', struct({ effectiveFrom: '2026-11-15' })],
    ['INVALID_ARGUMENT', 'owner', struct({ effectiveFrom: '2026-13-01' })],
    ['INVALID_ARGUMENT', 'owner', struct({ effectiveFrom: '2020-01-01' })],
    ['INVALID_ARGUMENT', 'owner', struct({ effectiveFrom: undefined })],
    ['INVALID_ARGUMENT', 'owner', struct({ lines: 'x' })],
    ['INVALID_ARGUMENT', 'owner', struct({ lines: [] })],
    ['INVALID_ARGUMENT', 'owner', struct({ lines: [null] })],
    ['INVALID_ARGUMENT', 'owner', struct({ lines: [{ componentId: 'pc_nope', amountMinor: 5 }] })],
    ['INVALID_ARGUMENT', 'owner', struct({ lines: [{ componentId: off, amountMinor: 5 }] })],
    ['INVALID_ARGUMENT', 'owner', struct({ lines: [{ componentId: basicId, amountMinor: 0 }] })],
    ['INVALID_ARGUMENT', 'owner', struct({ lines: [{ componentId: basicId, amountMinor: '5' }] })],
    ['INVALID_ARGUMENT', 'owner', struct({ lines: [{ componentId: basicId, amountMinor: 5 }, { componentId: basicId, amountMinor: 6 }] })],
    ['INVALID_ARGUMENT', 'owner', struct({ reason: 'x'.repeat(301) })],
  ];
  for (const [code, uid, body] of rows) {
    const r = await p.saveSalaryStructure(ctx, uid, T, body);
    assert.equal(r.error, code, `${uid} ${JSON.stringify(body)} -> ${JSON.stringify(r)}`);
  }
  const written = (await db.collection('schools').doc('sA').collection('branches').doc('b1').collection('salaryStructures').get()).docs;
  assert.equal(written.length, 0, 'nothing was written by a refused call');
  assert.notEqual((await at(db, 'schools/sA').get()).data().currencyLocked, true, 'a refused call does not lock the currency');
});

test('a client cannot plant kind, calc, totals or the basis: they come from the school\'s component', async () => {
  const { ctx, db } = env();
  await p.listPayComponents(ctx, 'owner', T, { schoolId: 'sA' });
  const r = await p.saveSalaryStructure(ctx, 'owner', T, struct({ lines: [{ componentId: basicId, amountMinor: 1000, kind: 'DEDUCTION', calc: 'PERCENT', grossMinor: 9, netMinor: 9, latest: false, basisId: 'x' }], grossMinor: 99, netMinor: 99, currency: 'USD', createdBy: 'x' }));
  assert.ok(r.result);
  const d = (await at(db, 'schools/sA/branches/b1/salaryStructures/st1_00001').get()).data();
  assert.deepEqual([d.lines[0].kind, d.lines[0].calc, d.grossMinor, d.netMinor, d.currency, d.createdBy, d.latest], ['EARNING', 'FIXED', 1000, 1000, 'INR', 'owner', true]);
});

test('reads: who may see salary figures', async () => {
  const { ctx } = env();
  await p.listPayComponents(ctx, 'owner', T, { schoolId: 'sA' });
  await p.saveSalaryStructure(ctx, 'owner', T, struct());
  for (const u of ['ba1', 'teacher', 'parent', 'otherOwner', 'finB2', 'ghost']) {
    assert.equal((await p.getSalaryStructure(ctx, u, T, { schoolId: 'sA', branchId: 'b1', staffId: 'st1' })).error, 'PERMISSION_DENIED', `get ${u}`);
    assert.equal((await p.listSalaryStructures(ctx, u, T, { schoolId: 'sA', branchId: 'b1' })).error, 'PERMISSION_DENIED', `list ${u}`);
  }
  // the staff member whose salary it is cannot read it here either (own payslips arrive with phase P4)
  assert.equal((await p.getSalaryStructure(ctx, 'teacher', T, { schoolId: 'sA', branchId: 'b1', staffId: 'st1' })).error, 'PERMISSION_DENIED');
  assert.equal((await p.getSalaryStructure(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', staffId: 'st1/../x' })).error, 'PERMISSION_DENIED');
  assert.equal((await p.getSalaryStructure(ctx, 'owner', T, { schoolId: 'sA', branchId: 'b1', staffId: 'nobody' })).error, 'NOT_FOUND');
});

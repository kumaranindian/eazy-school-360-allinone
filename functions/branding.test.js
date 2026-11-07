'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { fakeDb } = require('./test_support');
const b = require('./branding');

const now = new Date('2026-11-07T10:00:00Z');
const seed = (extra = {}) => ({
  'schools/sA': { name: 'A' },
  'schools/sB': { name: 'B' },
  'users/adminA': { schoolId: 'sA', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/adminB': { schoolId: 'sB', status: 'ACTIVE', role: 'SCHOOL_ADMIN' },
  'users/branchA': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'BRANCH_ADMIN' },
  'users/teacherA': { schoolId: 'sA', branchId: 'b1', status: 'ACTIVE', role: 'TEACHER' },
  'users/parentA': { schoolId: 'sA', status: 'ACTIVE', role: 'PARENT' },
  'users/plat': { status: 'ACTIVE', role: 'PLATFORM_ADMIN' },
  ...extra,
});
const ctx = (db) => ({ db, now });
const save = (db, uid, data) => b.updateSchoolBranding(ctx(db), uid, undefined, data);
const doc = (db, s = 'sA') => db.store.get(`schools/${s}/branding/config`);

test('every built-in preset passes the readability rules', () => {
  for (const [id, p] of Object.entries(b.BUILT_IN_PRESETS)) {
    assert.deepStrictEqual(b.colorProblems(p.colors), {}, id);
  }
});

test('a school admin saves a preset; the stored colours are complete and version starts at 1', async () => {
  const db = fakeDb(seed());
  const r = await save(db, 'adminA', { schoolId: 'sA', branding: { preset: 'indigo' } });
  assert.deepStrictEqual(r.result, { version: 1, reset: false });
  const d = doc(db);
  assert.strictEqual(d.preset, 'indigo');
  assert.strictEqual(d.appearance, 'system');
  assert.deepStrictEqual(Object.keys(d.colors).sort(), [...b.TOKENS].sort());
  assert.strictEqual(d.schoolId, 'sA');
});

test('custom colours are laid over the preset and upper-cased', async () => {
  const db = fakeDb(seed());
  await save(db, 'adminA', { schoolId: 'sA', branding: { preset: 'emerald', colors: { primary: '#0b5d8a' }, appearance: 'light' } });
  assert.strictEqual(doc(db).colors.primary, '#0B5D8A');
  assert.strictEqual(doc(db).colors.surface, '#FFFFFF');
  assert.strictEqual(doc(db).appearance, 'light');
});

test('unreadable colours are refused (faint text, faint secondary, not a hex)', async () => {
  const db = fakeDb(seed());
  for (const colors of [{ text: '#CCCCCC' }, { secondary: '#EEEEEE' }, { primary: 'red' }]) {
    const r = await save(db, 'adminA', { schoolId: 'sA', branding: { colors } });
    assert.strictEqual(r.error, 'INVALID_ARGUMENT', JSON.stringify(colors));
  }
  assert.strictEqual(doc(db), undefined);
});

test('unknown preset, appearance, colour name and extra fields are refused', async () => {
  const db = fakeDb(seed());
  for (const branding of [{ preset: 'nope' }, { appearance: 'sepia' }, { colors: { error: '#00FF00' } }, { success: '#fff' }, null, 'x']) {
    const r = await save(db, 'adminA', { schoolId: 'sA', branding });
    assert.strictEqual(r.error, 'INVALID_ARGUMENT', JSON.stringify(branding));
  }
});

test('status colours cannot be set by a school', async () => {
  const db = fakeDb(seed());
  const r = await save(db, 'adminA', { schoolId: 'sA', branding: { colors: { error: '#23965B' } } });
  assert.strictEqual(r.error, 'INVALID_ARGUMENT');
});

test('only the school admin of THAT school (or a platform admin) may save', async () => {
  const db = fakeDb(seed());
  const branding = { preset: 'plum' };
  for (const uid of ['adminB', 'branchA', 'teacherA', 'parentA', 'nobody']) {
    const r = await save(db, uid, { schoolId: 'sA', branding });
    assert.strictEqual(r.error, 'PERMISSION_DENIED', uid);
  }
  assert.strictEqual(doc(db), undefined);
  assert.strictEqual((await save(db, 'plat', { schoolId: 'sA', branding })).result.version, 1);
  assert.strictEqual(doc(db, 'sB'), undefined, 'school B untouched');
});

test('a suspended or login-blocked admin is refused', async () => {
  const db = fakeDb(seed({ 'users/adminA': { schoolId: 'sA', status: 'SUSPENDED', role: 'SCHOOL_ADMIN' } }));
  assert.strictEqual((await save(db, 'adminA', { schoolId: 'sA', branding: {} })).error, 'PERMISSION_DENIED');
});

test('an unknown school is not found', async () => {
  const db = fakeDb(seed());
  assert.strictEqual((await save(db, 'plat', { schoolId: 'ghost', branding: {} })).error, 'NOT_FOUND');
});

test('version grows on every save; a stale baseVersion is refused', async () => {
  const db = fakeDb(seed());
  await save(db, 'adminA', { schoolId: 'sA', branding: { preset: 'indigo' } });
  const r2 = await save(db, 'adminA', { schoolId: 'sA', branding: { preset: 'crimson' }, baseVersion: 1 });
  assert.strictEqual(r2.result.version, 2);
  const stale = await save(db, 'adminA', { schoolId: 'sA', branding: { preset: 'plum' }, baseVersion: 1 });
  assert.strictEqual(stale.error, 'ABORTED');
  assert.strictEqual(doc(db).preset, 'crimson');
});

test('reset keeps the document (so the version keeps growing) and clears the colours', async () => {
  const db = fakeDb(seed());
  await save(db, 'adminA', { schoolId: 'sA', branding: { preset: 'indigo' } });
  const r = await save(db, 'adminA', { schoolId: 'sA', reset: true });
  assert.deepStrictEqual(r.result, { version: 2, reset: true });
  assert.strictEqual(doc(db).colors, null);
  assert.strictEqual(doc(db).preset, null);
  assert.strictEqual(doc(db).appearance, 'system');
});

test('schools are independent', async () => {
  const db = fakeDb(seed());
  await save(db, 'adminA', { schoolId: 'sA', branding: { preset: 'indigo' } });
  await save(db, 'adminB', { schoolId: 'sB', branding: { preset: 'crimson' } });
  assert.strictEqual(doc(db, 'sA').preset, 'indigo');
  assert.strictEqual(doc(db, 'sB').preset, 'crimson');
  assert.strictEqual(doc(db, 'sB').version, 1);
});

// ---- platform defaults ------------------------------------------------------

const custom = { teal2: { label: 'Teal', colors: { primary: '#0F6B6B', secondary: '#4F6F6F', accent: '#C98A1B', surface: '#FFFFFF', background: '#F4F8F8', text: '#142222', selectedNav: '#0F6B6B' } } };
const plat = (db, uid, branding) => b.updatePlatformBranding(ctx(db), uid, undefined, { branding });

test('only a platform admin sets the default and custom presets', async () => {
  const db = fakeDb(seed());
  for (const uid of ['adminA', 'teacherA', 'nobody']) {
    assert.strictEqual((await plat(db, uid, { defaultPreset: 'indigo' })).error, 'PERMISSION_DENIED', uid);
  }
  const r = await plat(db, 'plat', { defaultPreset: 'teal2', presets: custom });
  assert.strictEqual(r.result.version, 1);
  assert.strictEqual(db.store.get('platformBranding/default').defaultPreset, 'teal2');
});

test('platform presets: built-in ids are protected, colours must be readable, default must exist', async () => {
  const db = fakeDb(seed());
  assert.strictEqual((await plat(db, 'plat', { presets: { emerald: custom.teal2 } })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await plat(db, 'plat', { presets: { bad1: { label: 'x', colors: { ...custom.teal2.colors, text: '#DDDDDD' } } } })).error, 'INVALID_ARGUMENT');
  assert.strictEqual((await plat(db, 'plat', { defaultPreset: 'missing' })).error, 'INVALID_ARGUMENT');
});

test('a school can pick a custom platform preset once it exists', async () => {
  const db = fakeDb(seed());
  assert.strictEqual((await save(db, 'adminA', { schoolId: 'sA', branding: { preset: 'teal2' } })).error, 'INVALID_ARGUMENT');
  await plat(db, 'plat', { presets: custom });
  assert.strictEqual((await save(db, 'adminA', { schoolId: 'sA', branding: { preset: 'teal2' } })).result.version, 1);
});

test('defaultPresetId falls back to emerald', () => {
  assert.strictEqual(b.defaultPresetId(undefined), 'emerald');
  assert.strictEqual(b.defaultPresetId({ defaultPreset: 'gone' }), 'emerald');
  assert.strictEqual(b.defaultPresetId({ defaultPreset: 'indigo' }), 'indigo');
});

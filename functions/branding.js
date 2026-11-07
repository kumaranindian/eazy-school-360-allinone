'use strict';

// Tenant-wide branding (docs/tenant-theme.md).
//
//   schools/{s}/branding/config = {
//     schoolId, version, preset, colors: { primary, secondary, accent, surface,
//     background, text, selectedNav } | null, appearance, updatedAt, updatedBy
//   }
//   platformBranding/default = { version, defaultPreset, presets: { id: { label, colors } } }
//
// Read by every member of the school (so every role gets the same theme) and
// by platform admins; written ONLY by the callables below (rules deny client
// writes). `version` only ever grows (a reset keeps the document), so a client
// can ignore any snapshot older than the one it already applied.
//
// Status colours (success / warning / error) are not tenant-controlled, so a
// school cannot turn an overdue marker green. Every colour set is checked for
// readability (WCAG contrast) before it is stored.

const TOKENS = ['primary', 'secondary', 'accent', 'surface', 'background', 'text', 'selectedNav'];
const APPEARANCES = ['system', 'light', 'dark'];
const MAX_CUSTOM_PRESETS = 12;
const PRESET_ID = /^[a-z][a-z0-9_]{1,23}$/;
const HEX = /^#[0-9A-Fa-f]{6}$/;

// The default is the approved neutral/green design system (lib/core/theme).
const BUILT_IN_PRESETS = Object.freeze({
  emerald: { label: 'Emerald', colors: { primary: '#16856A', secondary: '#527A69', accent: '#E0A030', surface: '#FFFFFF', background: '#F7F8F7', text: '#17231F', selectedNav: '#16856A' } },
  indigo: { label: 'Indigo', colors: { primary: '#4F46A5', secondary: '#5B6275', accent: '#D08A1E', surface: '#FFFFFF', background: '#F6F6FA', text: '#1B1B2F', selectedNav: '#4F46A5' } },
  crimson: { label: 'Crimson', colors: { primary: '#B23A48', secondary: '#6D5A5E', accent: '#C98A1B', surface: '#FFFFFF', background: '#FAF6F6', text: '#2A1A1D', selectedNav: '#B23A48' } },
  amber: { label: 'Amber', colors: { primary: '#9A5B00', secondary: '#6B5E48', accent: '#2A7F62', surface: '#FFFFFF', background: '#FAF8F3', text: '#2B2214', selectedNav: '#9A5B00' } },
  plum: { label: 'Plum', colors: { primary: '#7A3E8E', secondary: '#665A70', accent: '#C98A1B', surface: '#FFFFFF', background: '#F9F6FA', text: '#241A28', selectedNav: '#7A3E8E' } },
  graphite: { label: 'Graphite', colors: { primary: '#3D4A52', secondary: '#5F6B72', accent: '#C98A1B', surface: '#FFFFFF', background: '#F5F6F7', text: '#171C1F', selectedNav: '#3D4A52' } },
});
const DEFAULT_PRESET = 'emerald';

// ---- colour maths ---------------------------------------------------------

function rgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function luminance(hex) {
  const [r, g, b] = rgb(hex).map((v) => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG contrast ratio, 1..21. */
function contrast(a, b) {
  const la = luminance(a);
  const lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/** Text colour (white or near-black) that reads best on `hex`. */
function onColor(hex) {
  return contrast('#FFFFFF', hex) >= contrast('#111111', hex) ? '#FFFFFF' : '#111111';
}

// [foreground, background, minimum ratio, message]
const CONTRAST_RULES = [
  ['text', 'surface', 4.5, 'text on surface'],
  ['text', 'background', 4.5, 'text on background'],
  ['secondary', 'surface', 3, 'secondary on surface'],
  // The accent is a highlight colour (never the only carrier of text), and the
  // approved default gold is 2.3:1, so it is held to a lower bar than the rest.
  ['accent', 'surface', 2, 'accent on surface'],
  ['selectedNav', 'surface', 3, 'selected navigation on surface'],
];

/** Problems with a COMPLETE colour set, as { token: message }. */
function colorProblems(colors) {
  const errors = {};
  for (const t of TOKENS) {
    if (typeof colors[t] !== 'string' || !HEX.test(colors[t])) errors[t] = 'must be a #RRGGBB colour';
  }
  if (Object.keys(errors).length) return errors;
  // Buttons and highlights carry a computed on-colour; it must stay readable.
  if (contrast(onColor(colors.primary), colors.primary) < 4.5) {
    errors.primary = 'too light or too dark to carry button text (needs 4.5:1)';
  }
  for (const [fg, bg, min, label] of CONTRAST_RULES) {
    const r = contrast(colors[fg], colors[bg]);
    if (r < min) errors[fg] = `${label} is ${r.toFixed(1)}:1, needs ${min}:1`;
  }
  return errors;
}

const normHex = (h) => h.toUpperCase();

// ---- presets --------------------------------------------------------------

/** Built-in presets plus the platform's custom ones (a built-in id cannot be replaced). */
function presetsOf(platformDoc) {
  const out = { ...BUILT_IN_PRESETS };
  const custom = (platformDoc && platformDoc.presets) || {};
  for (const [id, p] of Object.entries(custom)) {
    if (!BUILT_IN_PRESETS[id] && p && p.colors) out[id] = p;
  }
  return out;
}

function defaultPresetId(platformDoc) {
  const presets = presetsOf(platformDoc);
  const id = platformDoc && platformDoc.defaultPreset;
  return id && presets[id] ? id : DEFAULT_PRESET;
}

// ---- validation -----------------------------------------------------------

/**
 * A school's branding from a client: { preset?, colors?, appearance? }.
 * `colors` may be partial; it is laid over the preset's colours. Returns
 * { value: { preset, colors, appearance } } (colors complete, upper-case hex)
 * or { errors }.
 */
function validateSchoolBranding(input, presets) {
  const errors = {};
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { errors: { branding: 'is required' } };
  const unknown = Object.keys(input).filter((k) => !['preset', 'colors', 'appearance'].includes(k));
  if (unknown.length) errors.branding = `unknown field ${unknown[0]}`;
  const presetId = input.preset === undefined || input.preset === null ? DEFAULT_PRESET : input.preset;
  if (typeof presetId !== 'string' || !presets[presetId]) errors.preset = 'is not an available preset';
  const appearance = input.appearance === undefined ? 'system' : input.appearance;
  if (!APPEARANCES.includes(appearance)) errors.appearance = `must be one of ${APPEARANCES.join(', ')}`;
  const overrides = input.colors === undefined || input.colors === null ? {} : input.colors;
  if (typeof overrides !== 'object' || Array.isArray(overrides)) errors.colors = 'must be an object';
  else {
    for (const k of Object.keys(overrides)) if (!TOKENS.includes(k)) errors.colors = `unknown colour ${k}`;
  }
  if (Object.keys(errors).length) return { errors };
  const colors = { ...presets[presetId].colors, ...overrides };
  const bad = colorProblems(colors);
  if (Object.keys(bad).length) return { errors: Object.fromEntries(Object.entries(bad).map(([k, v]) => [`colors.${k}`, v])) };
  const full = Object.fromEntries(TOKENS.map((t) => [t, normHex(colors[t])]));
  return { value: { preset: presetId, colors: full, appearance } };
}

/** The platform default document from a platform admin: { defaultPreset, presets }. */
function validatePlatformBranding(input) {
  const errors = {};
  if (!input || typeof input !== 'object' || Array.isArray(input)) return { errors: { branding: 'is required' } };
  const custom = input.presets === undefined ? {} : input.presets;
  if (typeof custom !== 'object' || custom === null || Array.isArray(custom)) return { errors: { presets: 'must be an object' } };
  const ids = Object.keys(custom);
  if (ids.length > MAX_CUSTOM_PRESETS) errors.presets = `at most ${MAX_CUSTOM_PRESETS} custom presets`;
  const clean = {};
  for (const id of ids) {
    const p = custom[id];
    if (!PRESET_ID.test(id) || BUILT_IN_PRESETS[id]) {
      errors[`presets.${id}`] = 'id must be 2-24 lower-case letters, digits or _, and not a built-in id';
      continue;
    }
    if (!p || typeof p.label !== 'string' || !p.label.trim() || p.label.length > 30) {
      errors[`presets.${id}.label`] = 'is required (up to 30 characters)';
      continue;
    }
    const bad = colorProblems(p.colors || {});
    if (Object.keys(bad).length) {
      for (const [k, v] of Object.entries(bad)) errors[`presets.${id}.${k}`] = v;
      continue;
    }
    clean[id] = { label: p.label.trim(), colors: Object.fromEntries(TOKENS.map((t) => [t, normHex(p.colors[t])])) };
  }
  const all = { ...BUILT_IN_PRESETS, ...clean };
  const def = input.defaultPreset === undefined ? DEFAULT_PRESET : input.defaultPreset;
  if (typeof def !== 'string' || !all[def]) errors.defaultPreset = 'is not an available preset';
  if (Object.keys(errors).length) return { errors };
  return { value: { defaultPreset: def, presets: clean } };
}

// ---- callables ------------------------------------------------------------

const brandingDoc = (db, schoolId) => db.collection('schools').doc(schoolId).collection('branding').doc('config');
const platformDoc = (db) => db.collection('platformBranding').doc('default');
const reasonOf = (errors) => Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join('; ');

/** The caller as an ACTIVE, sign-in-allowed platform admin, or null. */
async function platformAdmin(db, uid, token) {
  const u = (await db.collection('users').doc(uid).get()).data();
  if (!u || u.role !== 'PLATFORM_ADMIN' || u.status !== 'ACTIVE') return null;
  return require('./access').loginAllowed(u, token) ? u : null;
}

/**
 * Saves (or, with `reset: true`, clears) one school's branding. School admins
 * of THAT school and platform admins only. `baseVersion` (optional) makes a
 * save fail with ABORTED when someone else saved first.
 */
async function updateSchoolBranding(ctx, callerUid, token, data) {
  const { db, now } = ctx;
  const schoolId = data && data.schoolId;
  if (typeof schoolId !== 'string' || !schoolId) return { error: 'INVALID_ARGUMENT' };
  let caller = await require('./access').assertAdmin(db, callerUid, schoolId, null, token);
  if (caller && caller.role !== 'SCHOOL_ADMIN') caller = null;
  if (!caller) caller = await platformAdmin(db, callerUid, token);
  if (!caller) return { error: 'PERMISSION_DENIED' };
  if (!(await db.collection('schools').doc(schoolId).get()).exists) return { error: 'NOT_FOUND' };

  const reset = data.reset === true;
  let value;
  if (!reset) {
    const platform = (await platformDoc(db).get()).data();
    const parsed = validateSchoolBranding(data.branding, presetsOf(platform));
    if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
    value = parsed.value;
  }
  const ref = brandingDoc(db, schoolId);
  const result = await db.runTransaction(async (tx) => {
    const prev = (await tx.get(ref)).data();
    const current = prev && Number.isInteger(prev.version) ? prev.version : 0;
    if (data.baseVersion !== undefined && data.baseVersion !== current) return { error: 'ABORTED', reason: 'branding changed by someone else; reload' };
    const doc = reset
      ? { schoolId, version: current + 1, preset: null, colors: null, appearance: 'system', updatedAt: now, updatedBy: callerUid }
      : { schoolId, version: current + 1, ...value, updatedAt: now, updatedBy: callerUid };
    tx.set(ref, doc);
    return { result: { version: doc.version, reset } };
  });
  return result;
}

/** Platform admins only: the default preset for schools without their own, and the custom presets. */
async function updatePlatformBranding(ctx, callerUid, token, data) {
  const { db, now } = ctx;
  if (!(await platformAdmin(db, callerUid, token))) return { error: 'PERMISSION_DENIED' };
  const parsed = validatePlatformBranding(data && data.branding);
  if (parsed.errors) return { error: 'INVALID_ARGUMENT', reason: reasonOf(parsed.errors) };
  const ref = platformDoc(db);
  return db.runTransaction(async (tx) => {
    const prev = (await tx.get(ref)).data();
    const current = prev && Number.isInteger(prev.version) ? prev.version : 0;
    tx.set(ref, { version: current + 1, ...parsed.value, updatedAt: now, updatedBy: callerUid });
    return { result: { version: current + 1 } };
  });
}

module.exports = {
  TOKENS,
  APPEARANCES,
  BUILT_IN_PRESETS,
  DEFAULT_PRESET,
  contrast,
  onColor,
  colorProblems,
  presetsOf,
  defaultPresetId,
  validateSchoolBranding,
  validatePlatformBranding,
  brandingDoc,
  platformDoc,
  updateSchoolBranding,
  updatePlatformBranding,
};

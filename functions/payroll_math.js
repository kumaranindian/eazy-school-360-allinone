'use strict';

// Payroll arithmetic (docs/expense-management/IMPLEMENTATION_PLAN.md, section 6). PURE: no database, no
// clock. Money is integer minor units of the school's one currency. The rounding rule is fixed and
// documented: a percentage line is `base * basisPoints / 10000`, rounded HALF UP to a whole minor unit,
// per line (never on a running total). Net pay = earnings - deductions and may never be negative.
//
// A structure line is { componentId, kind: EARNING|DEDUCTION, calc: FIXED|PERCENT, amountMinor?, percentBp?, basisId? }.
// A PERCENT line's basis is a FIXED EARNING line of the SAME structure (so there are no chains or cycles).

const KINDS = Object.freeze(['EARNING', 'DEDUCTION']);
const CALCS = Object.freeze(['FIXED', 'PERCENT']);
const MAX_MINOR = 1e12; // per line; keeps every product exact in BigInt and every sum a safe integer
const MAX_BP = 10000; // 100.00%
const MAX_LINES = 40;

/** round-half-up of base * bp / 10000, exactly (BigInt), for non-negative integers. */
function percentOf(base, bp) {
  const n = BigInt(base) * BigInt(bp);
  return Number((n + 5000n) / 10000n);
}

/**
 * Validates a structure's lines and works out each amount, the gross, the deductions and the net.
 * Returns { errors } (field -> message) or { lines, grossMinor, deductionsMinor, netMinor }; each returned
 * line carries its computed `amountMinor`.
 */
function evaluate(input) {
  const errors = {};
  if (!Array.isArray(input) || input.length === 0) return { errors: { lines: 'add at least one earning' } };
  if (input.length > MAX_LINES) return { errors: { lines: `at most ${MAX_LINES} lines` } };
  const seen = new Set();
  const byId = new Map();
  const lines = [];
  input.forEach((l, i) => {
    const at = `lines[${i}]`;
    if (!l || typeof l !== 'object') {
      errors[at] = 'not a line';
      return;
    }
    if (typeof l.componentId !== 'string' || !l.componentId) errors[`${at}.componentId`] = 'missing';
    else if (seen.has(l.componentId)) errors[`${at}.componentId`] = 'used twice';
    seen.add(l.componentId);
    if (!KINDS.includes(l.kind)) errors[`${at}.kind`] = `one of ${KINDS.join(', ')}`;
    if (!CALCS.includes(l.calc)) errors[`${at}.calc`] = `one of ${CALCS.join(', ')}`;
    if (l.calc === 'FIXED') {
      if (!Number.isSafeInteger(l.amountMinor) || l.amountMinor < 1 || l.amountMinor > MAX_MINOR) errors[`${at}.amountMinor`] = 'a whole amount in minor units, above 0';
    } else if (l.calc === 'PERCENT') {
      if (!Number.isSafeInteger(l.percentBp) || l.percentBp < 1 || l.percentBp > MAX_BP) errors[`${at}.percentBp`] = 'between 0.01% and 100% (in hundredths of a percent)';
      if (typeof l.basisId !== 'string' || !l.basisId) errors[`${at}.basisId`] = 'choose what the percentage is of';
    }
    const line = { componentId: l.componentId, kind: l.kind, calc: l.calc, amountMinor: l.amountMinor, percentBp: l.percentBp, basisId: l.basisId };
    if (typeof l.componentId === 'string') byId.set(l.componentId, line);
    lines.push(line);
  });
  if (Object.keys(errors).length) return { errors };
  if (!lines.some((l) => l.kind === 'EARNING')) return { errors: { lines: 'add at least one earning' } };

  // Percent lines first need their basis: a FIXED EARNING line of this structure.
  for (const l of lines) {
    if (l.calc !== 'PERCENT') continue;
    const basis = byId.get(l.basisId);
    if (!basis || basis.kind !== 'EARNING' || basis.calc !== 'FIXED') errors[`${l.componentId}.basisId`] = 'must be a fixed earning in this structure';
  }
  if (Object.keys(errors).length) return { errors };

  const out = lines.map((l) => {
    if (l.calc === 'FIXED') return { componentId: l.componentId, kind: l.kind, calc: 'FIXED', amountMinor: l.amountMinor };
    return { componentId: l.componentId, kind: l.kind, calc: 'PERCENT', percentBp: l.percentBp, basisId: l.basisId, amountMinor: percentOf(byId.get(l.basisId).amountMinor, l.percentBp) };
  });
  const sum = (kind) => out.filter((l) => l.kind === kind).reduce((s, l) => s + l.amountMinor, 0);
  const grossMinor = sum('EARNING');
  const deductionsMinor = sum('DEDUCTION');
  if (!Number.isSafeInteger(grossMinor) || !Number.isSafeInteger(deductionsMinor)) return { errors: { lines: 'the total is too large' } };
  if (deductionsMinor > grossMinor) return { errors: { lines: 'deductions are more than the earnings' } };
  return { lines: out, grossMinor, deductionsMinor, netMinor: grossMinor - deductionsMinor };
}

module.exports = { KINDS, CALCS, MAX_MINOR, MAX_BP, MAX_LINES, percentOf, evaluate };

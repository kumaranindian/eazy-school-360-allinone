'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const p = require('./deletion_processor');

// A new collection cannot be forgotten: every collection named in
// firestore.rules must be scanned by the deletion processor, retained on
// purpose, or exempted here with a reason. (Same idea as ROUTE-1.)
const rules = fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8');
const named = new Set(
  [...rules.matchAll(/match \/(?!\{)([A-Za-z][A-Za-z0-9]*)\/\{/g)].map((m) => m[1]),
);

const EXEMPT = {
  users: 'handled by the PROFILE step and USER_DATA step (own document and subcollections)',
  schools: 'the school itself is never deleted by an individual request',
  branches: 'the structure of the school; iterated, not scanned',
  databases: 'rules scaffolding',
  accountDeletionRequests: 'the request records; kept as proof the request was handled (matrix E5)',
  accountDeletionLocks: 'bookkeeping, no personal data',
  accountDeletionRate: 'hashed counters with a TTL',
  otpChallenges: 'hashes only, expire on a TTL (matrix A5)',
  otpRate: 'hashes only, expire on a TTL (matrix A5)',
  pushDeliveries: 'delivery bookkeeping keyed by event; carries no user id (matrix A6)',
  notifications: 'deleted by the NOTIFICATIONS step',
};

test('every collection in firestore.rules is scanned, retained on purpose, or exempted with a reason', () => {
  const covered = new Set([
    ...p.BRANCH_COLLECTIONS,
    ...p.SCHOOL_COLLECTIONS,
    ...Object.keys(p.NESTED_GROUPS),
    ...p.FINANCIAL,
    ...Object.keys(EXEMPT),
  ]);
  const missing = [...named].filter((c) => !covered.has(c)).sort();
  assert.deepStrictEqual(missing, [], `collections with no deletion decision: ${missing.join(', ')}`);
});

test('the lists do not name collections that no longer exist', () => {
  const listed = [
    ...p.BRANCH_COLLECTIONS,
    ...p.SCHOOL_COLLECTIONS,
    ...Object.keys(p.NESTED_GROUPS),
    ...p.FINANCIAL,
  ];
  const stale = listed.filter((c) => !named.has(c) && !/^(feeCounters|invoiceNumbers|receiptNumbers)$/.test(c));
  assert.deepStrictEqual(stale, []);
});

test('financial records are never in the scan lists', () => {
  const scanned = new Set([...p.BRANCH_COLLECTIONS, ...p.SCHOOL_COLLECTIONS, ...Object.keys(p.NESTED_GROUPS)]);
  for (const c of p.FINANCIAL) assert.ok(!scanned.has(c), `${c} must be retained unchanged`);
});

test('nested collection groups have single-field indexes declared', () => {
  const idx = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'firestore.indexes.json'), 'utf8'));
  const overrides = idx.fieldOverrides || [];
  for (const [group, fields] of Object.entries(p.NESTED_GROUPS)) {
    for (const f of fields) {
      const hit = overrides.find(
        (o) => o.collectionGroup === group && o.fieldPath === f && (o.indexes || []).some((i) => i.queryScope === 'COLLECTION_GROUP'),
      );
      assert.ok(hit, `missing collection-group index override for ${group}.${f}`);
    }
  }
});

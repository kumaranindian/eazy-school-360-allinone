#!/usr/bin/env node
'use strict';
// One-off for multi-country setup: marks every school that already holds money
// (a fee structure, invoice or payment in any branch) as `currencyLocked`, so
// its currency (implicitly INR for schools created before Regional settings)
// cannot be changed from under existing amounts. Schools with no money yet
// stay open. New schools are locked automatically by the `lockCurrencyOn*`
// functions.
//
//   node tool/lock_currencies.js                 # DRY RUN
//   node tool/lock_currencies.js --apply         # writes
//   --school <id> limits to one school; --project <id> picks the project
//
// Safe to re-run. Needs Application Default Credentials or FIRESTORE_EMULATOR_HOST.
const path = require('path');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : fallback;
}

async function main() {
  const apply = process.argv.includes('--apply');
  const only = arg('school', null);
  const { initializeApp } = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin', 'lib', 'app'));
  const { getFirestore } = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin', 'lib', 'firestore'));
  initializeApp({ projectId: arg('project', process.env.GCLOUD_PROJECT || undefined) });
  const db = getFirestore();
  const { lockCurrency } = require(path.join(__dirname, '..', 'functions', 'currency_lock'));

  const schools = only ? [db.collection('schools').doc(only)] : (await db.collection('schools').get()).docs.map((d) => d.ref);
  let toLock = 0;
  for (const school of schools) {
    const snap = await school.get();
    if (!snap.exists || snap.data().currencyLocked === true) continue;
    let has = null;
    for (const branch of (await school.collection('branches').get()).docs) {
      for (const c of ['feeStructures', 'invoices', 'payments']) {
        const q = await branch.ref.collection(c).limit(1).get();
        if (!q.empty) { has = `${branch.id}/${c}`; break; }
      }
      if (has) break;
    }
    if (!has) continue;
    toLock++;
    console.log(`${apply ? 'LOCK' : 'would lock'} ${school.id} (${snap.data().currency || 'INR, implicit'}) - has ${has}`);
    if (apply) await lockCurrency(db, school.id);
  }
  console.log(`${apply ? 'locked' : 'dry run'}: ${toLock} school(s)`);
  if (!apply && toLock) console.log('Re-run with --apply to write.');
}

main().catch((e) => { console.error(e); process.exit(1); });

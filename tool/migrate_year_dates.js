#!/usr/bin/env node
'use strict';
// One-off migration for ACAD-1: rewrites legacy academic-year boundaries
// (local-midnight instants) as civil dates — UTC-midnight timestamps plus
// startDateKey/endDateKey — in every branch of every school.
//
//   node tool/migrate_year_dates.js --zone Asia/Kolkata                 # DRY RUN: prints the plan
//   node tool/migrate_year_dates.js --zone Asia/Kolkata --apply         # writes
//   add --school <id> to limit to one school; --project <id> to choose the project
//
// Safe to re-run (already-normalised documents are skipped). Back up first
// (PITR/clone) and run on staging before production. Needs Application Default
// Credentials (or the Firestore emulator via FIRESTORE_EMULATOR_HOST).
const path = require('path');
const { planYearUpdate } = require('./year_dates');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : fallback;
}

async function main() {
  const zone = arg('zone', null);
  if (!zone) {
    console.error('--zone <IANA zone the dates were entered in, e.g. Asia/Kolkata> is required');
    process.exit(1);
  }
  new Intl.DateTimeFormat('en', { timeZone: zone }); // throws on an unknown zone
  const apply = process.argv.includes('--apply');
  const only = arg('school', null);
  const { initializeApp } = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin', 'lib', 'app'));
  const { getFirestore } = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin', 'lib', 'firestore'));
  initializeApp({ projectId: arg('project', process.env.GCLOUD_PROJECT || undefined) });
  const db = getFirestore();

  let seen = 0, changed = 0, failed = 0;
  const schools = only ? [db.collection('schools').doc(only)] : (await db.collection('schools').get()).docs.map((d) => d.ref);
  for (const school of schools) {
    const branches = await school.collection('branches').get();
    for (const branch of branches.docs) {
      const years = await branch.ref.collection('academicYears').get();
      for (const y of years.docs) {
        seen++;
        try {
          const plan = planYearUpdate(y.data(), zone);
          if (!plan) continue;
          changed++;
          console.log(`${apply ? 'UPDATE' : 'would update'} ${y.ref.path}: ${plan.startDateKey} .. ${plan.endDateKey}`);
          if (apply) await y.ref.update(plan);
        } catch (e) {
          failed++;
          console.error(`SKIP ${y.ref.path}: ${e.message}`);
        }
      }
    }
  }
  console.log(`${apply ? 'applied' : 'dry run'}: ${seen} years seen, ${changed} ${apply ? 'updated' : 'to update'}, ${failed} skipped`);
  if (!apply && changed) console.log('Re-run with --apply to write.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

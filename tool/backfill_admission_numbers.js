#!/usr/bin/env node
'use strict';
// One-off for ACAD-2: creates the `admissionNumbers/{key}` reservation for every
// student admitted before reservations existed, in every branch.
//
//   node tool/backfill_admission_numbers.js                 # DRY RUN: prints the plan
//   node tool/backfill_admission_numbers.js --apply         # writes
//   add --school <id> to limit to one school; --project <id> to choose the project
//
// Duplicates (two students with the same number in one branch) are reported and
// left alone - decide who keeps the number, change the other, then re-run. Safe
// to re-run. Needs Application Default Credentials or FIRESTORE_EMULATOR_HOST.
const path = require('path');
const { planBackfill } = require('./admission_backfill');

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith('--') ? process.argv[i + 1] : fallback;
}

async function main() {
  const apply = process.argv.includes('--apply');
  const only = arg('school', null);
  const { initializeApp } = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin', 'lib', 'app'));
  const { getFirestore, FieldValue } = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin', 'lib', 'firestore'));
  initializeApp({ projectId: arg('project', process.env.GCLOUD_PROJECT || undefined) });
  const db = getFirestore();

  let created = 0, dupes = 0, invalid = 0;
  const schools = only ? [db.collection('schools').doc(only)] : (await db.collection('schools').get()).docs.map((d) => d.ref);
  for (const school of schools) {
    for (const branch of (await school.collection('branches').get()).docs) {
      const students = (await branch.ref.collection('students').get()).docs.map((d) => ({ id: d.id, admissionNumber: d.get('admissionNumber') }));
      const reserved = new Set((await branch.ref.collection('admissionNumbers').get()).docs.map((d) => d.id));
      const plan = planBackfill(students, reserved);
      for (const d of plan.duplicates) {
        dupes++;
        console.error(`DUPLICATE ${branch.ref.path}: "${d.key}" held by ${d.studentIds.join(', ')}`);
      }
      for (const i of plan.invalid) {
        invalid++;
        console.error(`INVALID ${branch.ref.path}/students/${i.studentId}: "${i.number}"`);
      }
      for (const c of plan.create) {
        console.log(`${apply ? 'RESERVE' : 'would reserve'} ${branch.ref.path}/admissionNumbers/${c.key} -> ${c.studentId}`);
        if (!apply) continue;
        try {
          await branch.ref.collection('admissionNumbers').doc(c.key).create({
            schoolId: school.id,
            branchId: branch.id,
            studentId: c.studentId,
            admissionNumber: c.number,
            createdAt: FieldValue.serverTimestamp(),
            createdBy: 'backfill',
          });
          created++;
        } catch (e) {
          console.error(`SKIP ${c.key}: ${e.message}`);
        }
      }
    }
  }
  console.log(`${apply ? 'applied' : 'dry run'}: ${created} reserved, ${dupes} duplicate numbers, ${invalid} invalid numbers`);
  if (!apply) console.log('Re-run with --apply to write.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

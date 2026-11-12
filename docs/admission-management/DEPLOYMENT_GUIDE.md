# Deployment guide

**Nothing here has been deployed.** Deploys to `eazy-school-360-prod` need explicit approval; use
`--dry-run` first and **dev first**.

## Order (backward compatible; the module is off until a school enables it)
1. App build containing the Admissions screens (hidden for every role until step 5 grants access;
   routes already guarded by `manageAdmissions`).
2. Indexes: `firebase deploy --only firestore:indexes --project <dev>` — wait until the new
   `admissionEnquiries` / `admissionStatusHistory` indexes are READY.
3. Functions: `cd functions && npm test`, then deploy the five `*Admission*` callables:
   `saveAdmissionSettings, createAdmissionEnquiry, updateAdmissionEnquiry, assignAdmissionEnquiry,
   changeAdmissionEnquiryStatus`.
4. Rules: **never** `firebase deploy --only firestore:rules` with the default config. Build and deploy the
   stripped artifact: `node tool/build_rules.js --check` then `tool/deploy_rules.sh <project> --dry-run`
   (current build is ~148 KB of 256 KB).
5. As a school admin of a **test school on dev**: Admissions → Admission settings → switch on → create
   an enquiry → exercise search, every filter, status changes, assign, edit, duplicate warning.
6. Repeat on prod only after approval.

## Rollback
- Switch the module off per school (Admission settings) — existing data stays, new enquiries stop.
- Functions/rules/indexes are additive: remove the five callables or redeploy the previous rules;
  nothing else reads these collections. Data is not deleted by rollback.

## Prerequisites / config
No new secrets or environment variables. Cloud Functions region is the existing `FUNCTIONS_REGION`.
`ENFORCE_APP_CHECK` behaves as for every other callable.

## Smoke checklist (dev)
School admin and branch admin see Admissions; teacher/finance/parent do not; a branch admin cannot
create in another branch; two simultaneous "New enquiry" saves give two different numbers; a repeat of the
same child shows the duplicate warning; rejecting without a reason is refused; closed enquiries cannot be edited.

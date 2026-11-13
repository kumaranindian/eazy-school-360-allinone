# RBAC matrix

Decision (product owner): **no separate "Admission Staff" role.** Admissions are run by school and branch
administrators; Finance collects admission fees and sees nothing else of an enquiry.

Legend: ✅ allowed · – refused · *(setting)* needs a school setting.

## Admissions (enquiries, follow-ups, applications, documents)
| Capability | Platform admin | School admin | Branch admin | Teacher | Finance | Parent |
|---|---|---|---|---|---|---|
| See Admissions in the app (`manageAdmissions`) | ✅ (holds every permission; with no school the page says "No branch found") | ✅ | ✅ | – | – | – |
| Read enquiries, history, activities, applications, documents, conversions (rules) | ✅ support | ✅ | ✅ own branch | – | – | – |
| Create / edit / assign / change status (callables) | – | ✅ any branch | ✅ own branch | – | – | – |
| Schedule, reschedule, reassign, complete, cancel follow-ups and visits | – | ✅ | ✅ own branch | – | – | – |
| Start / edit / submit applications; upload, verify, remove documents; review; comment | – | ✅ | ✅ own branch | – | – | – |
| Approve or reject an application | – | ✅ | *(setting `branchAdminsMayApprove`)* own branch | – | – | – |
| Convert an approved application to a student | – | ✅ | *(same setting)* own branch | – | – | – |
| Admission settings (open / save) | – | ✅ | – (read only) | – | – | – |
| Reports of one branch | – | ✅ | ✅ own branch | – | – | – |
| Reports of **all** branches | – | ✅ | – | – | – | – |
| Public enquiry page | anyone, no sign-in; sees only what the school offers, can only add a NEW enquiry |
| Follow-up reminders and new-enquiry / assignment / decision notices | – | ✅ | ✅ | – | – | confirmation notice only, if the parent already has a login |

## Admission fees
| Capability | Platform admin | School admin | Branch admin | Teacher | Finance (branch) | Parent |
|---|---|---|---|---|---|---|
| Read fee records and payments (rules) | ✅ | ✅ | ✅ own branch | – | ✅ own branch | – |
| Set an amount / cancel a fee | – | ✅ | ✅ own branch | – | – | – |
| **Record a payment** (issues the receipt number) | – | ✅ | ✅ own branch | – | ✅ own branch | – |
| Waive a balance / refund | – | ✅ | – | – | – | – |
| Admission-fee list page (`/admissions/fees`, `collectPayments`) | ✅ | ✅ | ✅ | – | ✅ | – |
Finance sees the **enquiry number**, the fee category and the money, nothing about the applicant, guardians or remarks
(the fee record carries only `enquiryNumber`; Finance cannot read the enquiry, application, documents or settings: rules-tested).

## Where it is enforced (all must agree)
1. `RolePermissions` / `AppRoutes.requiredPermissions` (what the UI offers; a UX guard only).
2. `firestore.rules` (reads; **no client writes** to any admission collection).
3. The callables in `functions/` (every write) and `functions/admission_reports.js` (aggregates).

## Proofs
- `functions/admission_rbac.test.js`: one row per callable × nine callers (school admin, branch admin of the branch, branch admin of another branch, inactive branch admin,
  teacher, Finance, parent, another school's admin, unknown user) + signed-out callers + malformed tenant ids + the branch-admin setting + a **coverage check that fails when a new
  admission callable has no row**.
- `functions/admission_fees.test.js`: Finance records payments but cannot set, waive, refund or cancel; Finance of another branch / inactive / teacher / parent refused; the fee record holds no enquiry detail.
- `firestore-tests/admission-rules.test.mjs`: read scope per collection and role, denied writes for every role, Finance cannot read enquiries/applications/documents/activities/settings/conversions, public bookkeeping server-only.
- Dart: role matrix (`manageAdmissions`, `decideAdmissions`, Finance, teacher, parent), route permissions, Finance fee-list widget tests.

## Known gaps
- The platform admin is not a callable caller (callables use `assertAdmin`: school admin or branch admin of the branch); the platform admin reads through the rules only.
- Storage rules for document access are written but their allow-cases could not be run in the build sandbox.

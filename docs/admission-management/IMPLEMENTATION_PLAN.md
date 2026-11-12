# Plan

Done: Phases 0–4 (see IMPLEMENTATION_STATUS). Remaining, in order — each ends with tests and a
status update, and none is deployed without approval.

4. ~~Follow-ups~~ **done** (activities, history, dashboard, reminders).
5. **Visits** — build on the activity model: a visit activity that, when scheduled/completed, drives VISIT_SCHEDULED / VISIT_COMPLETED through `applyStatus`; purpose, completion notes, parent feedback, reschedule/cancel reasons (the activity fields already carry most of this).
6. **Applications and documents** — `admissionApplications`, `admissionDocuments`, Storage rules
   (tenant path, MIME/size/signature checks, no public download), verification workflow, APPLICATION_SUBMITTED /
   UNDER_REVIEW / APPROVED through `applyStatus`.
7. **Admission fees** — reuse the fee module (invoice + payment + receipt); no parallel ledger.
8. **Conversion** — Cloud Function state machine with idempotency key, resumable steps, reconciliation;
   reuse student/parent services; reuse the `ADM-` numbering at this point.
9. **Public enquiry form** — verified school identifier (slug document), server-side validation,
   rate limit, CAPTCHA / App Check, consent text and policy version. Needs a business decision on
   the spam-protection vendor.
10. **Notifications**, 11. **Reports + export**, 12. remaining UI tabs (Activities, Application, Documents, Fees).
13. **Per-user admission permission** ("Admission staff") — needs a design review of
    `branchRoles`/rules before any role change.
14. **Settings UI for open years/classes** — needs a school-wide mapping of per-branch ids.

Open business questions: retention period for lost enquiries; whether branch admins may approve
(the prompt says "only if configured"); the spam-protection choice for the public form.

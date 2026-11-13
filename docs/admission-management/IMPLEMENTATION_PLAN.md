# Plan

Done: Phases 0–6 (see IMPLEMENTATION_STATUS). Remaining, in order — each ends with tests and a
status update, and none is deployed without approval.

4. ~~Follow-ups~~ **done** (activities, history, dashboard, reminders).
5. ~~Visits~~ **done** (visit activities with purpose; drive VISIT_SCHEDULED / VISIT_COMPLETED; merged timeline).
6. ~~Applications and documents~~ **done** (applications, documents, Storage rules, verification, approval). The server also checks each file's real format (PDF/PNG/JPEG/WebP signature), not just the declared type.
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

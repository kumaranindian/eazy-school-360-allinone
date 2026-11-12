# Admission management

Enquiry → follow-up → visit → application → documents → approval → fee → conversion
to a student, built into the existing EazySchool 360 app (same tenants, roles, theme).

**Status: Phases 0–4 of the master prompt are implemented** (assessment, admission
foundation, enquiry management, enquiry lifecycle, follow-up management). Phases 5–16 are **not started**.
See [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) for the honest list and
[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for what comes next.

| Document | What it holds |
|---|---|
| [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md) | What the repository actually looks like, and the conflicts with the master prompt |
| [REQUIREMENTS.md](REQUIREMENTS.md) | Requirements by phase, with their state |
| [ENTERPRISE_PRD.md](ENTERPRISE_PRD.md) | Scope, users, success measures, non-goals |
| [DATABASE_DESIGN.md](DATABASE_DESIGN.md) | Collections, fields, indexes |
| [API_DESIGN.md](API_DESIGN.md) | The Cloud Function callables |
| [SECURITY_DESIGN.md](SECURITY_DESIGN.md) | Threat model, rules, server checks |
| [RBAC_MATRIX.md](RBAC_MATRIX.md) | Who can do what |
| [WORKFLOWS.md](WORKFLOWS.md) | The status state machine |
| [TEST_PLAN.md](TEST_PLAN.md) | What is tested, and what is not yet |
| [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) | Rollout, rollback, prerequisites |

Code: `lib/features/admission/`, `functions/admission.js`, rules in `firestore.rules`
(search "Admission enquiries"), tests in `test/admission`, `test/widget/admission_ui_test.dart`,
`functions/admission.test.js`, `firestore-tests/admission-rules.test.mjs`.

The module is **off by default** for every school; a school administrator switches it on
in Admissions → Admission settings. Nothing existing changes until then.

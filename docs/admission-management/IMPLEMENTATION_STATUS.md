# Implementation status

Branch `feature/admission-management`. **Not deployed anywhere.** Last verified 2026-11-12.

## Completed (Phases 0–3)
- Phase 0: this documentation set.
- Phase 1: admission settings (module switch, prefixes, sources, follow-up days) and transactional
  number generation.
- Phase 2: enquiry create / edit / assign / list (search + filters + paging) / details, duplicate flagging.
- Phase 3: status state machine for the lead stages, reasons, ON_HOLD/RESUME, immutable history.
- Responsive UI for: Admission dashboard, Enquiry list, New/Edit enquiry, Enquiry detail
  (Overview, Timeline, Internal notes), Admission settings.

## Not started
Phases 4–16 of the master prompt: follow-ups, visits, applications, documents, admission fees,
student conversion, public portal, notifications, reports/export, the Activities/Application/Documents/Fees
tabs, an "Admission staff" role, settings UI for open years/classes. See IMPLEMENTATION_PLAN.

## Files
- Created: `lib/features/admission/**` (domain 5, data 1, presentation: 5 pages, widgets, providers, routes),
  `functions/admission.js`, `functions/admission.test.js`, `firestore-tests/admission-rules.test.mjs`,
  `test/admission/admission_domain_test.dart`, `test/widget/admission_ui_test.dart`,
  `test/support/admission_fakes.dart`, `docs/admission-management/*`.
- Modified: `functions/index.js` (5 callables), `functions/deletion_processor.js` (+ matrix D8/D9),
  `firestore.rules` (3 read-only matches), `firestore.indexes.json` (6 indexes),
  `lib/core/permissions/{permission,role_permissions}.dart`, `lib/core/routing/{app_routes,app_router,app_shell,route_titles}.dart`,
  `lib/features/students/presentation/widgets/parents/parents_ui.dart` (added a `danger` badge tone).

## Collections / indexes / functions / security
See DATABASE_DESIGN, API_DESIGN, SECURITY_DESIGN. New collections: `admissionSettings`,
`admissionEnquiries`, `admissionStatusHistory`, `admissionSequences`. Rules are read-only; all writes are callables.

## Verification (this branch)
| Check | Result |
|---|---|
| `flutter analyze` | clean |
| `dart format --set-exit-if-changed` | clean |
| `flutter test` (full) | 1,946 tests; the only failure was `platformAdmin has every permission` (the new permission was not granted to the platform admin) — **fixed and re-run green**. The full suite was not re-run end to end after that one-line fix |
| `functions` `npm test` | 321 / 321 pass (23 admission) |
| Firestore rules (emulator, full suite) | all Firestore-rules tests pass incl. 6 admission tests; 22 **Storage**-rules tests fail in this sandbox and the same Storage tests also fail on a clean `develop` checkout here (`staff-storage-rules`: 3 of 4) — `storage.rules` is unchanged by this work |
| `tool/*.test.js`, `build_rules.js --check` | pass; built rules 148 KB of 256 KB |
| `flutter build web` | **not run** for this branch |

## Known limitations
- The repository's Firestore queries and index set are untested against a real/emulated query run
  (see TEST_PLAN). Verify on dev first.
- Enquiries are read by the school admin and the branch admin; the platform admin sees the screens but,
  with no school, the page says "No branch found".
- Assignment lists staff of the branch that have a login (first 100 active).
- The list shows newest first only; filter by assigned staff has no UI.
- Admission settings cannot restrict academic years/classes from the UI.

## Deployment prerequisites
DEPLOYMENT_GUIDE: indexes → functions → built rules → app, dev first, explicit approval for prod.

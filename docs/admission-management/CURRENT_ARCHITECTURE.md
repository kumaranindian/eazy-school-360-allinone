# Current architecture (as inspected)

Facts taken from the repository, not from the master prompt.

- **Stack:** Flutter (Riverpod, GoRouter `StatefulShellRoute.indexedStack`), Firebase Auth,
  Firestore, Storage, Cloud Functions (Node 22, `functions/`, region `asia-south1`).
- **Tenancy:** `schools/{schoolId}/branches/{branchId}/...`. Rules (`firestore.rules`,
  4,100+ lines) authorise through a lookup of `/users/{uid}` (role, schoolId, branchId,
  `branchRoles`). The UI mirrors this in `lib/core/permissions`.
- **Write pattern for sensitive data:** callable functions using the Admin SDK, with the
  rules denying client writes. Examples: `updateSchoolBranding`, `updateFeeReminderSettings`,
  `provisionLogins`. Admission follows this pattern.
- **Rules size:** `firestore.rules` is close to the release-size limit (built artifact
  ~148 KB of 256 KB after stripping comments, source ~229 KB). Admission adds three tiny
  read-only matches because writes are server-side.
- **Student numbering today:** `ADM-0001` per branch, derived from the highest existing number
  (`FirebaseAdmissionNumberSource`). It is *not* a transactional counter.
- **Theme:** tenant theme (`schools/{s}/branding/config`) feeds `AppTheme`; screens use
  `AdminDashboardPalette.of(context)` / `colorScheme`, never raw colours.
- **Account deletion:** every new collection needs a decision in
  `functions/deletion_processor.js` and the data matrix (`deletion_coverage.test.js`).
- **Existing building blocks reused:** `FilterBar`/`FilterField`, `ParentsCard`/`ParentsBadge`/
  `ParentsPageBar` (generic atoms from the Parents revamp), `AsyncValueWidget`, `EmptyView`,
  `PagedResult`, `academicYearsProvider`/`classesProvider`, `staffRepositoryProvider`,
  `assertAdmin` in `functions/access.js`, the in-memory Firestore fake in `functions/test_support.js`.

## Conflicts with the master prompt, and how they are resolved

| Master prompt says | Repository reality | Resolution |
|---|---|---|
| Roles include "Admission Staff" | No such role; adding one touches rules, `UserRole`, provisioning, every role test | **Not added.** Only school admin and branch admin manage admissions for now. A per-user admission permission is the proposed future route (IMPLEMENTATION_PLAN) |
| "Reuse the existing student admission-number mechanism" | It is non-transactional (max+1). Enquiry/application numbers must be concurrency-safe | Enquiry/application numbers use their own transactional counters (`admissionSequences`). The student `ADM-` number is untouched and will be reused at conversion (Phase 8) |
| Admission settings per branch for Branch Admin | Classes and academic years are **per branch** documents, so a school-wide list of ids cannot name them | Settings are school-wide and school-admin only. The server supports `academicYearIds`/`classIds` restrictions but the UI does not expose them yet |
| Finance sees fee info without enquiry details | Fee integration is Phase 7 | Finance has no admission access now |
| Public enquiry page `/admission/{slug}` | The app has no public (signed-out) pages or school slug | Phase 9; needs a verified public identifier and abuse controls (see IMPLEMENTATION_PLAN) |
| Platform admin: cross-tenant support | `assertAdmin` is school-scoped; a platform admin has no school | Platform admin can **read** (rules); cannot write through the callables |

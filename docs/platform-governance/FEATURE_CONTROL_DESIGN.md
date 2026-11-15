# Feature control design

## Catalogue (only modules that exist in the repository)
| Key | Module | Depends on | Write path today |
|---|---|---|---|
| `dashboard` | Dashboard | | read-only |
| `students` | Student management | `academic` | client |
| `parents` | Parents and family links | `students` | client |
| `staff` | Staff, teachers, departments, designations | | client |
| `academic` | Years, classes, sections, subjects, calendar | | client |
| `attendance` | Student and staff attendance | `students`, `academic` | client |
| `leave` | Leave management | `staff` | client |
| `fees` | Fee structures, assignment, invoices, payments, reports | `students` | client |
| `feeReminders` | Fee reminders | `fees` | callable |
| `admission` | Enquiries, applications, documents, fees, conversion, reports | `students` | callable |
| `publicAdmission` | Public enquiry page | `admission` | callable |
| `exams` | Exams, marks, results, report cards | `students`, `academic` | client |
| `timetable` | Timetable and substitutions | `academic`, `staff` | client |
| `homework` | Homework and submissions | `academic` | client |
| `announcements` | Announcements and attachments | | client |
| `messages` | Parent-teacher messaging | `parents` | client |
| `notifications` | Push and in-app notifications | | trigger |
Not in the repository and therefore **not shown**: transport, library, online payments. "Parent app" and "teacher app" are roles, not modules.

## Configuration
`platformFeatureDefaults/default` (global defaults for new schools) and `schoolFeatures/{schoolId}` (explicit overrides: key -> {enabled, source, reason, version, updatedAt/By}).
Effective = override if present, else the default **as it was when the school was created** (snapshotted at creation), so changing a default never changes an existing school.
`schoolFeatureHistory` is append-only. Dependencies: enabling needs every dependency enabled; disabling lists dependants and requires confirmation; no data is touched.

## Enforcement layers (and their honest limits)
1. **UI and routes**: nav hidden, direct route redirected, "feature unavailable" screen (`TenantContext.can` / a feature gate).
2. **Callables** (admission, fee reminders, provisioning, platform, future): the access engine returns `FEATURE_DISABLED`.
3. **Firestore rules**: only through the existing profile mirror and only for a very small number of modules; per-module clauses do not fit the rules size limit.
4. **Triggers (D6)**: a write to a disabled module's collection is audited as `FEATURE_ACCESS_DENIED` and reverted/flagged. This is detective, not preventive.
Per-module migration to callables is the only way to get fully preventive enforcement for a direct-write module; it is out of scope until D6 is decided.

## As built
See `IMPLEMENTATION_STATUS.md` (Phases 7-8). The effective switches are `schools.features` (not a separate `schoolFeatures` collection), so every existing reader keeps working; history is `schoolFeatureHistory`; defaults are `platformFeatureDefaults/default` and are copied into a school at creation. The trigger in layer 4 records but does not revert.

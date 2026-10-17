# Production gap register

Consolidated release blockers and unresolved risks. "Blocker" = must be closed (or formally accepted by the owner) before any real school goes live. IDs → BUG_REGISTER.md.

## Release blockers
| # | Gap | Source | Close when |
|---|---|---|---|
| B1 | Rules may be undeployable/at the size edge; live rules in dev/prod unknown | SEC-1 | `firebase deploy --only firestore:rules --dry-run` passes on dev and prod, CI size gate added, suite green |
| B2 | Academic-year dates off by one day in UTC+ zones (also in the new school-year registry) | ACAD-1 | UTC-midnight writes + date-key fields + data migration; tests pass under `TZ=Asia/Kolkata` and `America/Los_Angeles` |
| B3 | Push goes to the wrong person after common sign-out paths; failed pushes are lost | NOTIF-1, NOTIF-3 | central unregister, device expiry, redrive; tests per the register |
| B4 | Android release can be debug-signed | CFG-1 | build fails without the key; one signed AAB verified with `apksigner` |
| B5 | No backup/PITR/restore evidence | OPS-1 | PITR on, scheduled backups on, one restore into a scratch DB rehearsed and recorded |
| B6 | No working crash reporting / alerts on mobile | OPS-2, OPS-3 | Gradle plugin + iOS symbols, test crash seen in console, alert policies created |
| B7 | No staging environment and no repeatable deploy | config audit | staging project + documented/automated deploy with dry-run |
| B8 | Critical E2E journeys never run against a real project | E2E audit | smoke checklist executed on staging (DEPLOYMENT_CHECKLIST.md) |
| B9 | App Check off while unauthenticated OTP callables are exposed (only if phone login is enabled) | SEC-2 | App Check enforced, or phone login left off |

## High-risk defects (fix before pilot)
ACAD-2 admission-number duplicates · ACAD-3/4/7 non-atomic exam/transfer flows · UI-1/UI-2 misleading success & silent data loss · STATE-1/2 roster races · LOG-1 PII to Crashlytics · NOTIF-2/4 · ROUTE-2 · SEC-4 · CFG-6 missing indexes · DEP-1.

## Accepted-for-pilot candidates (owner decision needed)
Rules-only finance (no gateway; separate cashier/approver, daily reconciliation) · counters ceiling (OPS-4) · scheduled-announcement semantics (ACAD-6) · attendance/leave client-only checks (ACAD-9/10) while users are trusted staff.

## Unknowns that cannot be closed from the repository
Live rules/indexes/TTL state · secrets & function config · App Check registration · API-key restrictions · OAuth/domains · APNs/VAPID · signing assets · billing/quotas · backups · branch protection · production data quality (legacy years, missing `teacherAccess`/`parentAccess`).

# Platform admin: production plan

Status: **Phase 0 and Phase 1 are implemented** (see `PLATFORM_ADMIN_RUNBOOK.md`): creation script, platform roles,
mandatory second factor (rules, storage, callables, app), platform home and administrators screen, audit-log
collection and writer, removal of the client-writable `/users` platform-admin clause. Phases 2-5 are still plan.

Decisions (2026-11-13): first account `admin@avail404.com`; password plus two-step verification; schools get **on/off
status only** (no plans or limits, so 4.3 shrinks to a status flag and manual billing records); **manual billing**;
schools **are told** when support accesses their data.
Audience: Avail404 (the operator of EazySchool 360). Not a school-facing role.

## 1. What exists today (verified in code, 2026-11-13)

| Area | Fact | Evidence |
|---|---|---|
| Creation | No in-app path. Rules never let a client write `role: PLATFORM_ADMIN`. Only a hand-made `/users/{uid}` doc in the Firebase console. | `firestore.rules` `/users` create (a)(b)(c); `docs/account-deletion.md` step 4 |
| Sign-in | A platform admin has `schoolId: null`, so the app loads no school or branch. Staff screens say "No school found for your account." | `tenant_context_provider.dart`, `staff_branch_scope.dart` |
| Screens | Only **Settings → Platform branding**. No school list, no support tools. | `settings_overview_page.dart`, `app_routes.dart` |
| Deletion review | Callable `reviewAccountDeletion` exists; **no screen calls it**. | `grep reviewAccountDeletion lib` is empty |
| Data access | Rules treat the platform admin as a school admin of **every** school (read and write, including finance). Audit finding **H1 (High)**, unfixed. | `docs/security/rbac-audit.md` |
| Suspension | `SchoolStatus` has `suspended` / `inactive`, and the rules let a platform admin change it, but **nothing enforces it**: users of a suspended school keep working. | `school_status.dart`; no `SUSPENDED` check in `firestore.rules` or `lib` |
| Audit | No platform audit log. | no `auditLog` / `supportGrant` anywhere |
| MFA | Not required for any role. | no MFA code |

The role is a placeholder: powerful in the rules, unusable in the app, and not audited.

## 2. Principles

1. **Least privilege.** A platform admin sees school *metadata and counts* by default, never student, staff or finance records.
2. **Break-glass, not blanket.** Access to a school's data needs a reason, is time-boxed, read-only unless stated, visible to the school, and logged.
3. **Every platform action is a server action** (callable) that checks the caller, validates input, writes an audit record, and is idempotent. The client never writes platform state directly.
4. **Hard to create, easy to revoke.** Only a script run by an owner creates platform admins; MFA is required; revocation is immediate.
5. **No impersonation.** Nobody signs in as another user. "View as" is read-only through the grant.
6. **Dev and prod separate.** Nothing is promoted without a rules test, an emulator test and a dev rehearsal.

## 3. Platform roles

Add `platformRole` on the `/users/{uid}` profile (only with `role: PLATFORM_ADMIN`). All values are server-written.

| platformRole | Who | Can |
|---|---|---|
| `OWNER` | 1-2 named people | Everything below, including managing other platform admins and approving deletions. |
| `SUPPORT` | Support staff | School directory, school detail, support access (with reason), reset a school admin's login, send platform notices. Cannot suspend, delete, change plans or manage platform admins. |
| `COMPLIANCE` | Reviewer | Deletion-request queue, audit log (read), data-export requests. |
| `VIEWER` | Read-only (e.g. leadership) | Dashboard, directory, usage. No actions. |

A permission table lives in code beside `RolePermissions` (`PlatformPermission`), mirrored in rules and callables, with a generated matrix like `docs/security/role-permission-matrix.md`.

## 4. Feature set

### 4.1 Identity, access and security (Phase 1)
- **Create/revoke platform admins** with `tool/create_platform_admin.js --project <id> --email <e> --role OWNER|SUPPORT|COMPLIANCE|VIEWER`: creates the Auth user, writes the profile with all required audit fields, refuses duplicates, writes an audit record. Revoke: `status: INACTIVE` plus session revoke (`revokeRefreshTokens`).
- **Platform admins screen** (OWNER only): list, add, change role, deactivate, last sign-in.
- **MFA required** for every platform admin (Firebase Auth TOTP or phone). The rules and callables reject a platform admin token without a second factor (`firebase.sign_in_second_factor`).
- **Allowed sign-in methods**: Google (company account) or password plus MFA. No phone OTP, no shared accounts.
- **Short sessions and recent-login** for sensitive actions (suspend, delete, grant changes): re-authenticate within 5 minutes.
- **Two-person rule** (configurable) for the most destructive actions: school deletion/offboarding needs a second OWNER's approval.
- **Break-glass account**: one sealed OWNER account, credentials in a vault, alerts on any use.

### 4.2 Tenant (school) management (Phase 2)
- **Schools directory**: search, filter (status, plan, country), sort; columns: name, status, plan, branches, students, staff, last activity, created.
- **School detail**: profile, owner admin(s), branches, counts, regional settings (currency lock visible), enabled modules, storage and message usage, recent platform actions on that school. Counts come from aggregate queries, never by downloading records.
- **Create school and first admin** (onboarding wizard, sales-led) without self-signup: school, `main` branch, owner admin with a chosen password option (the existing `passwordSetup` options), welcome email. Idempotent.
- **Suspend / reactivate / deactivate** with a required reason, effective immediately, **actually enforced** (see 5.2), and a notice shown to the school's users ("Your school's access is paused. Contact support.").
- **Replace or add owner admin**; reset a school admin's login (existing `resetLoginPassword` semantics, platform-callable).
- **Branch overview** and branch limits.
- **Offboarding**: export (all data as JSON/CSV to a signed, expiring link), grace period, then deletion by the processor with the legal hold and retention rules in `docs/account-deletion-data-matrix.md`. Never automatic.

### 4.3 Plans, limits and feature flags (Phase 3)
- **Plan per school** (`plan`, `planLimits`: students, staff, branches, storage; `planStatus`: trial / active / past_due / cancelled; `trialEndsAt`).
- **Feature flags per school** (e.g. admission module, public admission portal, WhatsApp OTP, report cards PDF). Enforced in rules and callables for server-side features; hidden in the UI.
- **Limit enforcement** on create paths (admit student, add branch) with a clear message, and warnings at 80% / 100%.
- **Manual billing record** for each school (amount, period, paid/unpaid, notes, invoice reference). Payment collection stays outside the app until you decide on a gateway.

### 4.4 Support access (fixes audit finding H1) (Phase 2-3)
- **Remove the blanket access** (see 5.1).
- **`requestSupportAccess(schoolId, reason, scope, minutes)`**: SUPPORT/OWNER only, reason mandatory (min 15 characters), scope `READ` (default) or `READ_FINANCE`, duration 15-240 minutes, ticket reference optional.
- Creates `supportGrants/{id}`; rules honour it only for that admin, that school, until `expiresAt`. A separate, rarer `WRITE` scope needs OWNER approval.
- **The school sees it**: Settings → Security shows "Avail404 support accessed your data" with who, why, when. Optional email to the school admin.
- **Grant revoke** at any time by the platform OWNER or the school admin.
- A support session opens the normal app screens for that school, in a visible read-only banner.

### 4.5 Operations and monitoring (Phase 3-4)
- **Platform dashboard**: schools by status, new schools (30 days), active users (DAU/WAU), students and staff totals, trials ending, past-due, storage, messages sent.
- **Health and cost**: function error rates and latency, push delivery failures with redrive, WhatsApp/OTP volume and spend by school (usage counters written by the functions), Firestore and Storage growth.
- **Alerts**: error-rate and quota alerts to a monitored channel (Cloud Monitoring), plus alerts for any support grant, any platform-admin sign-in from a new device, and any failed MFA.
- **Platform notices**: broadcast to all school admins or a chosen set (maintenance, new release, policy), with scheduling and read receipts.
- **Maintenance mode and force-update**: `platformSettings/app` with `minAppVersion` per platform, `maintenanceMessage`, `maintenanceUntil`; the app checks at start and shows a blocking screen when needed.

### 4.6 Compliance (Phase 2)
- **Deletion review queue** (the missing screen): list by state, SLA timers, approve / reject / request action / reopen, with the existing server rules; shows the held/blocked reasons. Processor stays off until enabled per environment.
- **Audit log viewer**: filter by actor, school, action, date; immutable; CSV export.
- **Data-export requests** from a school or parent, tracked to completion.
- **Retention policy** document and automated TTL on logs where permitted.

### 4.7 Platform configuration (Phase 3-4)
- **Platform branding** (exists).
- **Defaults** for new schools: regional presets, grading templates, notification templates.
- **Legal links** and support contact shown in the app.
- **Integrations settings** (WhatsApp sender, App Check state) shown read-only with status; secrets never displayed.

## 5. Design decisions

### 5.1 Removing blanket access (H1)
- Stop using `isPlatformAdmin()` inside `isSchoolAdminOrAbove` / `staffScope`. Keep it only for `/users` (read), `/schools` (read, metadata) and platform collections.
- New helper `hasSupportGrant(schoolId, scope)` reads `supportGrants/{adminUid}__{schoolId}`: a **single get** keyed by id, so no query cost. Rules then treat a granted platform admin like a school admin of that school only, read-only unless scope allows.
- **Rules budget**: `firestore.rules` is near the source-operation limit (see `docs/` rules budget note and `tool/build_rules.js --check`). The change must be a net reduction; verify with the budget check and mutation-check the new helper.

### 5.2 Enforcing suspension
- Do **not** add a school `get()` to every rule evaluation (cost and 10-document access limit).
- Instead a Firestore trigger `schoolStatusChanged` fans the status out onto each user profile (`schoolAccess: 'SUSPENDED'|'ACTIVE'`), the same pattern as `parentAccess`. `activeAndAllowed()` already reads the profile, so it gains one field check with no extra read.
- Callables check the school status through a shared `assertSchoolActive()`.
- Reactivation fans out the reverse. Large schools are processed in batches with a resumable cursor; a repair callable (`refreshSchoolAccess`) fixes drift.
- The app shows a clear "paused" screen instead of errors.

### 5.3 Data model (all server-written)
```
users/{uid}                    role: PLATFORM_ADMIN, platformRole, schoolId: null, mfaEnrolled
schools/{id}                   status, plan, planLimits, planStatus, trialEndsAt, features{...}
platformSettings/app           minAppVersion{android,ios,web}, maintenance{...}
platformAuditLog/{id}          actor, action, schoolId?, target?, reason?, at, ip?, result   (create-only)
supportGrants/{adminUid__schoolId}  scope, reason, ticket, grantedAt, expiresAt, revokedAt?
platformNotices/{id}           audience, title, body, schedule, createdBy
schoolUsage/{schoolId__yyyymm} students, staff, messages, otp, storageBytes
```
Every new collection needs a `firestore.rules` entry, a `firestore-tests` allow and deny case, and a decision in the deletion matrix (`functions/deletion_coverage.test.js` fails otherwise).

### 5.4 Callables (all audited, all idempotent)
`createPlatformAdmin` (script-backed), `setPlatformRole`, `deactivatePlatformAdmin`, `listSchools`, `getSchoolOverview`, `createSchoolWithAdmin`, `setSchoolStatus`, `setSchoolPlan`, `setSchoolFeatures`, `requestSupportAccess`, `revokeSupportAccess`, `resetSchoolAdminLogin`, `publishPlatformNotice`, `setAppRequirements`, `reviewAccountDeletion` (exists), `exportSchoolData`.

## 6. Phases

| Phase | Contents | Exit criteria |
|---|---|---|
| **0. Safety net** (1-2 days) | Rules test that no client can create or promote a platform admin; audit-log collection and writer helper; decision sign-off. | Tests green; audit helper used by one callable. |
| **1. Identity** (S) | Creation script, platform roles, MFA enforcement, platform admins screen. | A platform admin can sign in only with MFA; revoke takes effect at once. |
| **2. Console + compliance + H1** (L) | Shell for platform roles (no school needed); schools directory and detail; deletion review queue; audit viewer; support grants; remove blanket access. | A platform admin cannot read a school's students without a grant; every action is in the audit log. |
| **3. Lifecycle + plans** (L) | Create school and admin, suspend/reactivate **enforced**, plans, limits, feature flags, manual billing, offboarding export. | Suspended school users are blocked within a minute; limits enforced. |
| **4. Operations** (M) | Dashboard, usage metering, health, alerts, platform notices, maintenance and force-update, defaults. | Alert fires on a test failure; force-update blocks an old build. |
| **5. Hardening and launch** (M) | Full rules/functions/emulator suites; mutation checks; load check on directory queries; runbooks; dev rehearsal; prod roll-out with `--dry-run` first; backup/PITR confirmed. | Checklist in section 8 signed off. |

Deploy order for each phase, matching `docs/production-audit/DEPLOYMENT_CHECKLIST.md`: app and functions, then backfills, then rules last; dev before prod.

## 7. Testing and quality bar
- Domain rules as pure Dart classes with unit tests (platform permissions, plan limits, grant windows).
- `firestore-tests`: allow **and** deny for each new collection; mutation-check every new rules helper; cross-school isolation (a granted admin of school A cannot touch school B; expired and revoked grants deny).
- Functions: unit tests for each callable (caller roles, idempotency, audit written, no secrets logged) plus emulator tests for the fan-out and deletion interplay.
- Widget tests at phone, tablet and desktop sizes and text scale 1.5 (project convention) for every platform screen.
- Contract fixtures where a screen writes through a "write plan".

## 8. Production readiness checklist
- [ ] MFA enforced for all platform admins; break-glass account sealed.
- [ ] No platform admin can read school data without a grant (rules test proves it).
- [ ] Every platform action writes an audit record; log is create-only.
- [ ] Suspension enforced in rules, callables and UI, with repair callable.
- [ ] Rules size and operation budget pass (`node tool/build_rules.js --check`); suite green against the **built** rules.
- [ ] New collections have deletion-matrix decisions.
- [ ] Alerts wired to a monitored channel; runbook for each alert.
- [ ] Backups/PITR confirmed on dev and prod; restore rehearsed once.
- [ ] Privacy: support-access notice visible to schools; policy text updated.
- [ ] Dev rehearsal signed off, then prod with explicit approval.

## 9. Risks
| Risk | Mitigation |
|---|---|
| Rules budget overrun when adding helpers | Remove the blanket helper first (net reduction); run the budget check on every change. |
| Locking out the only platform admin | Two OWNERs plus the sealed break-glass account; script can recreate access from a trusted machine. |
| Suspension fan-out on a large school is slow or partial | Batched, resumable trigger plus `refreshSchoolAccess` repair; UI treats an unreadable school as paused. |
| Support grants abused | Reason required, short window, read-only default, visible to the school, alerts on every grant. |
| Behaviour change for existing schools | Phase 3 flags default to "everything on" for existing schools; limits default to unlimited until set. |

## 10. Decisions needed before Phase 1
1. Who are the first platform admins, and which roles?
2. Sign-in method for them: Google company accounts or password plus MFA?
3. Do schools get a plan and limits now, or only a status (on/off)?
4. Is billing record-keeping enough for now, or do you want an online payment gateway for school subscriptions?
5. Should schools be told when support accesses their data (recommended: yes)?

# Multi-Tenant Guide

This is the reference for Milestone 1 — the multi-tenant core and
authentication foundation every future business feature (Students, Fees,
Attendance, Leave, Homework, Announcements, Holiday Calendar, ...) is built
on top of. If you're adding a new role, a new tenant-aware collection, or
just trying to understand how a request ends up authorized, start here.

## Tenant model

- **Platform** — the whole product. [`UserRole.platformAdmin`](lib/core/permissions/user_role.dart)
  is the only role not scoped to a school.
- **School** (`/schools/{schoolId}`) — the tenant root. Everything else
  traces back to a `schoolId`.
- **Branch** (`/schools/{schoolId}/branches/{branchId}`) — a school may have
  many branches. Never assume one school equals one branch.
- **User** (`/users/{uid}`) — scoped to a school (and, for most roles, a
  branch) via its `schoolId`/`branchId` fields.

```
Platform
 └── School (schoolId)
      └── Branch (branchId)
           └── Users (TEACHER / FINANCE / PARENT / BRANCH_ADMIN)
      └── SCHOOL_ADMIN (schoolId set; branchId = home branch, but authority spans all branches)
PLATFORM_ADMIN (schoolId null — not scoped to any one school)
```

## User model

`lib/features/users/domain/user_profile.dart` — the `/users/{uid}` document:

| Field | Type | Notes |
|---|---|---|
| `userId` | `String` | = the Firebase Auth `uid`; also the document id |
| `schoolId` | `String?` | null only for `PLATFORM_ADMIN` |
| `branchId` | `String?` | null for `PLATFORM_ADMIN`; for `SCHOOL_ADMIN` it is a home branch only (self-signup sets `main`) — their authority is school-wide, see `UserRole.isBranchScoped` |
| `name`, `email`, `phone`, `photoUrl` | `String?` | profile fields |
| `role` | `UserRole` | see below |
| `status` | `UserStatus` | `active` / `invited` / `disabled` |
| `createdAt`/`updatedAt`/`createdBy`/`updatedBy` | audit fields | `createdAt`/`updatedAt` are `FieldValue.serverTimestamp()` — never client-supplied |

## Roles

`lib/core/permissions/user_role.dart`:

| Role | Scope | Wire value |
|---|---|---|
| `platformAdmin` | Platform-wide | `PLATFORM_ADMIN` |
| `schoolAdmin` | One school, all its branches | `SCHOOL_ADMIN` |
| `branchAdmin` | One branch | `BRANCH_ADMIN` |
| `teacher` | One branch | `TEACHER` |
| `finance` | One branch | `FINANCE` |
| `parent` | One branch (their child's) | `PARENT` |

## Permissions — the centralized authorization mechanism

`lib/core/permissions/permission.dart` defines the fine-grained
capabilities (`managePlatform`, `manageSchool`, `manageBranches`,
`manageUsers`, `viewUsers`, `manageOwnProfile`). `role_permissions.dart`'s
`RolePermissions.grants` is the **single map** from role → permissions.

Nothing else should branch on `role == UserRole.x`. Instead:

```dart
if (tenantContext.can(Permission.manageUsers)) { ... }
```

`AppShell` (`core/routing/app_shell.dart`) uses exactly this to decide which
navigation destinations to show — a role gaining/losing a destination is a
one-line change to `RolePermissions.grants`, not a hunt through widgets.

**This is a UX-layer mirror of what `firestore.rules` independently
enforces.** Changing `RolePermissions` changes what the UI *offers*: it
does not change what Firestore *allows*. Keep both in sync deliberately —
see "How to add a new role" below.

## Authentication flow

```
Splash (/)
  │
  ├─ Firebase Auth state unresolved ──────────────► stay at Splash
  │
  ├─ Not authenticated ────────────────────────────► /login
  │                                                     │
  │                                      /forgot-password (email link)
  │
  └─ Authenticated
       │
       ├─ Load /users/{uid} profile
       │
       ├─ No profile yet (brand-new account) ───────► /create-school
       │                                                 │
       │                                    one atomic batch (see below)  
       │                                                 │
       │                                        tenant context re-resolves
       │
       ├─ status != ACTIVE (INVITED/DISABLED) ───────► /account-inactive
       │                                                 (sign-out only)
       │
       └─ status == ACTIVE ──────────────────────────► load school + branch
                                                           │
                                                           ▼
                                                      /dashboard
                                              (nav filtered by permissions)
```

Implemented in `lib/features/authentication/` (email/password, Google
Sign-In, forgot/reset password, sign-out) and
`lib/core/tenant/tenant_context_provider.dart` (profile → school → branch →
`TenantContext`). `lib/core/routing/app_router.dart`'s `redirect` is the
state machine above, made concrete.

**Password reset**: "forgot password" sends Firebase's standard reset
email; clicking it lands on Firebase's own hosted action-handler page. This
app does not implement a custom in-app "choose new password" screen for
Milestone 1 — see `DEVELOPMENT_GUIDE.md` for the one-line config needed if
a branded in-app reset screen is wanted later.

**Google Sign-In**: implemented for both Web (`signInWithPopup`) and
mobile (the `google_sign_in` plugin's token exchanged via
`signInWithCredential`). Mobile requires SHA-1/SHA-256 fingerprints and an
OAuth client registered against each real Firebase project before it
actually works — see `SECURITY_ARCHITECTURE.md` → "Google Sign-In" for what
that setup involves. Nothing about *this app's code* is Google-specific
beyond `FirebaseAuthRepository.signInWithGoogle()`.

## Firestore structure

```
/users/{uid}
/schools/{schoolId}
/schools/{schoolId}/branches/{branchId}
```

### Why `/users` is flat, not nested under `/schools/{schoolId}`

A client has to be able to answer "what school/branch/role am I?" the
moment it signs in — before it knows any `schoolId` to even construct a
nested path. A flat `/users/{uid}` collection, readable by the signed-in
user for their own document, solves that bootstrapping problem directly.
Nesting under `/schools/{schoolId}/users/{uid}` (which Milestone 0's
FIRESTORE_ARCHITECTURE.md sketched as an *illustrative, not-yet-built*
example) would require already knowing the `schoolId` to even form the
query — a chicken-and-egg problem for a brand-new sign-in.

### School creation — one atomic batch

`FirebaseSchoolRepository.createSchoolForCurrentUser` writes the school, the
caller's `SCHOOL_ADMIN` profile, and the default `main` branch in a single
`WriteBatch` — all three or none. The rules for each of those writes use
`getAfter()`/`existsAfter()` to confirm the other two are in the same batch,
the school did not exist beforehand, and the caller authored it (helper
`isSelfSignupBatchFor` in `firestore.rules`). That is what stops a brand-new
account from naming an existing school in its own profile.

If an older account has a profile but no branch (left by the previous
two-phase implementation), calling the method again creates only the
missing branch.

## Security rules

`firestore.rules` enforces tenant isolation with a **lookup-table
pattern**: every rule that needs to know "who is this caller, really"
reads the caller's *own* `/users/{request.auth.uid}` document via `get()`
— never trusting anything about the document being accessed, and never
trusting a client-supplied role/schoolId on the request itself for
*authorization* purposes (only for what's being *written*, which is then
separately validated).

```
callerProfile() = get(/databases/$(database)/documents/users/$(request.auth.uid)).data
isActiveCaller() = that profile exists AND status == 'ACTIVE'
isSchoolAdminOf(schoolId) = isActiveCaller() AND role == 'SCHOOL_ADMIN' AND schoolId matches
```

**Decision: lookup rules, not custom claims.** Firebase Auth custom claims
(`request.auth.token.role`, etc.) would need a trusted server-side writer
— a Cloud Function — to issue them, and none exist in this project.
Lookup rules need no Cloud Functions deployment and are fully testable
right now against the Firestore emulator (see "Testing the rules" below).
This supersedes what Milestone 0's `SECURITY_ARCHITECTURE.md` anticipated;
see that file's "Custom claims vs. lookup rules" for the full tradeoff and
when to revisit it.

What the rules guarantee (see `firestore-tests/rules.test.mjs` for the
executable proof):
- A user can never read or write another school's data, full stop —
  including by guessing a document ID.
- An account that isn't `ACTIVE` (`INVITED` or `DISABLED`) is denied everywhere except
  reading its own profile (so the client can tell the user *why*).
- A user can never change their own `role`/`schoolId`/`branchId`/`status`.
- An admin can never grant `PLATFORM_ADMIN` or `SCHOOL_ADMIN` through a
  client write, and can never act outside their own school. A
  `BRANCH_ADMIN` can only create/manage `TEACHER`/`FINANCE`/`PARENT` users
  in their own branch.
- A new account can only become `SCHOOL_ADMIN` of a school it creates in
  the same batch — never an existing one.
- A `SCHOOL_ADMIN` can't change their school's `status` (suspension is a
  platform decision).
- Audit fields are enforced: `createdAt`/`updatedAt` must be the server
  time, `createdBy`/`updatedBy` must be the caller, and the `created*`
  fields are immutable.
- Nothing is `allow read, write: if true` anywhere; anything not
  explicitly matched is denied by the final fallback rule.

### Testing the rules

```
cd firestore-tests
npm install
firebase emulators:exec --only firestore "npm test"
```

See `DEVELOPMENT_GUIDE.md` → "Firestore security rules" for the full
command and what's covered (School A vs. School B, parent-vs-parent,
disabled accounts, role-escalation attempts, the self-signup flow, ...).

## How to add a new role

1. Add the enum value to `UserRole` (`lib/core/permissions/user_role.dart`)
   and its `.wireValue` — the exact string that will be stored in
   Firestore and compared in rules.
2. Add its entry to `RolePermissions.grants`
   (`lib/core/permissions/role_permissions.dart`).
3. If the role needs different rule treatment (not just UI visibility),
   update `firestore.rules`' helper functions and the relevant `match`
   blocks — e.g. a new admin-tier role likely needs its own
   `isXAdminOf(...)` helper alongside `isSchoolAdminOf`/`isBranchAdminOf`.
4. Add a rules test in `firestore-tests/rules.test.mjs` proving the new
   role can/can't do what's intended — don't rely on the Dart-side
   `RolePermissions` test alone, since that only proves what the *UI*
   offers, not what Firestore *enforces*.
5. Update the role table above.

## How to add a new tenant-aware feature/collection

1. Decide whether it's school-scoped (most things) or also branch-scoped,
   and add `schoolId` (and `branchId`, if applicable) fields using
   `FirestoreFields.schoolId`/`.branchId` — never a raw string literal.
2. Add the four audit fields (`createdAt`/`updatedAt`/`createdBy`/`updatedBy`),
   writing timestamps via `FieldValue.serverTimestamp()`, never a
   client-computed `DateTime.now()`.
3. Add a `match` block in `firestore.rules` for the new collection,
   re-using `isSameSchool`/`isSchoolAdminOf`/`isBranchAdminOf` — don't
   invent a parallel authorization scheme.
4. Follow the layering from `PROJECT_ARCHITECTURE.md`: a domain model +
   repository interface in `features/<feature>/domain/`, a Firestore
   implementation in `features/<feature>/data/`, Riverpod providers in
   `features/<feature>/presentation/providers/`. Never call
   `FirebaseFirestore.instance` directly from a widget.
5. Add rules tests for the new collection's tenant isolation, following
   the pattern in `firestore-tests/rules.test.mjs`.
6. If the feature introduces a new permission (e.g. `manageFees`), add it
   to `Permission` and to each role's entry in `RolePermissions.grants` —
   see "How to add a new role" above for the same two-sided (UI +
   rules) requirement.

## Multi-branch (staff in several branches, school-wide years, student moves)

A login can hold a role in more than one branch (`users.branchRoles`, server-written), academic years are defined once per
school and *opened* by each branch, and a school admin can move a student to another branch. The role-in-branch helper
(`branchRoleOf` in `firestore.rules`, `roleIn` in `storage.rules`) must be used instead of comparing `callerBranchId()`
when adding rules. See `docs/multi-branch.md`.

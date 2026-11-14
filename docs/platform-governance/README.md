# Platform governance: school lifecycle, subscriptions, feature control, central audit

Status: **Phase 0 (assessment and design) complete; implementation not started.** See `IMPLEMENTATION_STATUS.md`.

This folder extends the existing platform-admin work (`docs/platform-admin/`) rather than replacing it. A large part of the
requested scope already exists in the repository; `REQUIREMENTS.md` maps every requested item to *built / partial / not built /
conflict*, so nothing is rebuilt and nothing is claimed that is not there.

## Read in this order
1. `CURRENT_ARCHITECTURE.md`: what the system actually is today, including the constraints that shape the design.
2. `REQUIREMENTS.md`: the request versus the repository.
3. `IMPLEMENTATION_PLAN.md`: **decisions needed before Phase 1**, and the revised phased plan.
4. Design documents: `SCHOOL_LIFECYCLE_DESIGN.md`, `SUBSCRIPTION_DESIGN.md`, `FEATURE_CONTROL_DESIGN.md`, `AUDIT_ARCHITECTURE.md`,
   `AUDIT_EVENT_CATALOG.md`, `DATABASE_DESIGN.md`, `SECURITY_DESIGN.md`, `RBAC_MATRIX.md`, `API_DESIGN.md`.
5. `TEST_PLAN.md`, `DEPLOYMENT_GUIDE.md`, `AUDIT_EVENT_COVERAGE.md`, `ENTERPRISE_PRD.md`.

## Three findings that change the design (details in CURRENT_ARCHITECTURE.md)
1. **Most business writes bypass the server.** Attendance, fees, students, homework and most other modules are written by the
   apps straight to Firestore under security rules; only admission, provisioning, branding, fee reminders and the platform
   features go through Cloud Functions. So "one trusted audit service wrapped around business operations" cannot cover them without
   either Firestore triggers (observed, after the fact) or migrating writes to callables.
2. **The Firestore rules are at the platform's release-size limit** (256,000 compiled bytes; a release above it is refused). New per-module
   feature checks and per-collection audit rules cannot be added to the rules. Enforcement must use the existing pattern: a flag mirrored onto the
   user profile that the rules already read, plus callables and triggers.
3. **A failed login or a permission-denied request never reaches our code.** Firebase Auth rejects a wrong password, and Firestore rules
   reject a denied read before any function runs. Those events can only be reported by the client (untrusted) or inferred. The audit design
   labels trust levels per event instead of pretending all events are equally trustworthy.

## Policy decisions requested
`IMPLEMENTATION_PLAN.md` section 1 lists the business policies the request leaves open (default state of self-registered schools, what
happens to existing schools with no subscription, expiry boundary, consistency window, audit retention and cost). They are answered with a
recommendation each; Phase 1 starts once items 1-4 and 10 are confirmed.

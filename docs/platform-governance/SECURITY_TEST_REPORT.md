# Security and regression report (Phase 12)

Scope: everything added by the governance programme (lifecycle, central access engine, notifications, subscriptions, feature control, audit trail).
Method: automated tests only; nothing was deployed and no real Firebase project was touched.

## What was tested
| Area | Test | What it proves |
|---|---|---|
| Cross-role matrix | `functions/governance_security.test.js` | 22 callables x 15 kinds of caller (4 platform roles, owner without a second factor, disabled owner, school admin, branch admin, teacher, finance, parent, another school's admin, a school admin whose profile merely CONTAINS `platformRole`, unknown user). Only the intended roles pass the permission check; every other caller is refused AND the store is byte-for-byte unchanged. |
| Second factor | same | every platform callable refuses an owner signed in without MFA |
| Hostile payloads | same | every write callable survives 30 hostile values (wrong types, NaN, 1e308, 100,000-character strings, NoSQL-style objects, path traversal, `__proto__`, `constructor`, control characters, nested pollution) as the whole request and in each of 31 fields: none throws, none creates an odd document, the global object is never polluted |
| Tenant isolation | same | notifications: nobody reads/acknowledges/dismisses another person's (same school or other); changes to one school never touch another school's documents or users; the access engine refuses every cross-school call for every role |
| Audit integrity | same, `audit.test.js` | secrets smuggled into a client report (token in a route, a Bearer string as the app version, password/idToken fields) never reach the store; a client cannot choose its actor, school, trust level, result, category or action |
| Rules | `firestore-tests/governance-rules.test.mjs` | all 12 governance collections (including the nested audit partitions) deny get, list, create, update and delete to every caller (8 roles, an owner without MFA, an unknown user, signed-out), platform owner and compliance included; a school admin cannot write any server-owned school field (status, lifecycle, features, subscription, mirror); no one but the school's own admin can edit its profile; self-registration is INACTIVE only; every mirrored state (including SUBSCRIPTION_NOT_STARTED) pauses the user; a user cannot lift their own pause, pause someone else, or promote a profile to a platform role. **Mutation-checked**: adding a read rule for one collection makes the suite fail. |
| Full regression | all suites | Flutter 2,471, functions 684 (1 skipped), tools 30, Firestore rules 564 of 565 on the source AND the built artifact |

## Defects found and fixed in this phase
1. **Prototype keys passed as modules.** `BY_KEY['constructor']` / `['__proto__']` are truthy, so a feature map such as `{"constructor": true}` passed validation and then crashed (`dependsOn` of a function). Same pattern in the client-event allowlist, the module table and the lifecycle notice table. Fixed with own-property lookups (`ids.own`); tests added.
2. **Identifiers became Firestore paths unchecked.** A `schoolId`/`planId`/notification id containing `/`, `..` or shaped `__x__` made the callable throw (an INTERNAL error) instead of refusing. All governance entry points now validate ids (`ids.idOf`); the audit cursor too. An optional plan id that is present but invalid is refused rather than silently ignored.
3. **Secrets could be stored through a free-text field.** A client report's `appVersion` or a metadata string could carry a Bearer header or JWT. Strings that look like one are now redacted wherever they appear, and `appVersion`, `route` and `correlationId` must match strict shapes.
4. **Self-registered schools could pre-set server-owned fields.** The rules allow a client to create a school document with extra fields, so a client could create it with all modules switched on (defeating a platform default that switches a module off), a made-up activation remark/approver, `subscriptionStatus`, `accessMirror` or inflated lifecycle counters. The creation trigger now resets all of these (defaults for modules, counters to 1, server-owned fields removed). **Residual:** for a moment after creation the planted values exist (the school is INACTIVE and its users are paused, so nobody can use it). A rules-level key allowlist would close the window but the rules are close to the size limit, so it is deferred until it can be measured with a real dev release.
5. The test Firestore now behaves like Firestore for invalid document ids, so this class of defect cannot hide again.

## Known limitations (not fixed, by decision or constraint)
- **A paused user can still edit their OWN name/phone/photo** (the self-edit rule does not look at the pause). No school data and no way to lift the pause. A rules change would add size; documented and tested as a limitation.
- **Direct writes to a disabled module** are recorded, not blocked (D6); see Phase 8.
- **Admission storage "create-only" test (`admission-storage-rules.test.mjs` #36)** fails in the emulator: a second upload to the same path succeeds, although `storage.rules` has no update/overwrite rule. It comes from the merged `develop` work and predates this programme. It may be an emulator behaviour; verify with a real second upload on the dev project before relying on "create-only".
- Failed sign-ins cannot be audited server-side; the app does not yet send T4 reports (see AUDIT_EVENT_COVERAGE.md).
- No penetration test, load test or review of the deployed configuration (IAM, App Check enforcement, Identity Platform) was done: those need the real environment.

## Not covered by this phase
The Cloud Functions were exercised through their exported functions against an in-memory Firestore, not through the deployed HTTP layer (callable auth wrapping, App Check, CORS, quotas). `index_exports.test.js` proves the wiring loads; a dev deployment smoke test belongs to Phase 13.

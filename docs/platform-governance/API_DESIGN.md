# API design (callables, `asia-south1`)

All callables: authenticate, authorise (role + MFA for platform), validate input, return `{error, reason}` mapped to HttpsError details like the existing ones.

| Callable | Caller | Purpose |
|---|---|---|
| `transitionSchool` | owner | validated lifecycle transition (replaces the status part of `setSchoolStatus`); idempotency key |
| `requestSchoolRecovery`, `approveSchoolRecovery`, `cancelSchoolRecovery` | owner (approver must differ from requester) | recovery of a CLOSED school -> INACTIVE |
| `listSchools` / `getSchoolGovernance` | platform | search by name/id/owner/registration date/status; detail incl. lifecycle, subscription, features, recent audit |
| `savePlan`, `listPlans` | owner / platform | plan catalogue |
| `setSubscription`, `extendSubscription`, `renewSubscription`, `cancelSubscription`, `grantTrial` | owner | validated subscription operations + history |
| `getSubscriptionHistory` | platform; school admin (own) | |
| `setFeature`, `setFeatureDefaults`, `listFeatures` | owner / platform | with dependency validation and history |
| `evaluateAccess` | server-internal (module) | `evaluateSchoolAccess(schoolId, userId, feature, action)` -> reason code |
| `getMyGovernanceState` | any school user | effective access and enabled features for the app (a hint for UI; never trusted for security) |
| `listMyPlatformNotifications`, `acknowledgeNotification`, `dismissNotification` | school admins | inbox and popup state |
| `queryAuditEvents`, `getAuditSummary`, `exportAuditEvents` | owner/compliance (support read-limited) | bounded, paginated, redacted |
| `reportClientEvent` | any signed-in user | T4 events, allowlisted and rate limited |
Scheduled: `subscriptionMonitor` (15 min), `auditRetention` (daily), `notificationDelivery` retry. Triggers: `schoolStatusChanged` (exists), module audit triggers (Phase 10), feature-violation trigger (Phase 8).

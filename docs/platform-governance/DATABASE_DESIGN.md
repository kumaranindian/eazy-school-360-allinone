# Database design (additive, backward compatible)

Existing fields are reused; absent = today's behaviour.

## Reused / extended
`schools/{id}`: `status` (ACTIVE|INACTIVE|SUSPENDED + new EXPIRED|CLOSED), `statusReason`, `statusChangedAt/By` (exist) + `activatedAt/By`, `suspendedAt/By`, `closedAt/By`,
`lifecycleUpdatedAt/By`, `lifecycleVersion`. `schools.features` is migrated, then superseded by `schoolFeatures`.
`users/{uid}`: `schoolAccess` (exists; value becomes a reason code: SCHOOL_INACTIVE|SCHOOL_SUSPENDED|SCHOOL_EXPIRED|SCHOOL_CLOSED|SUBSCRIPTION_NOT_STARTED|SUBSCRIPTION_EXPIRED, absent = allowed),
`blockedFeatures` (array of disabled keys, only for the few rules-enforced modules).
`platformSettings/app`: + `supportEmail`.

## New collections (all server-written; clients have no rules; reads through callables)
| Collection | Key | Purpose |
|---|---|---|
| `schoolRecovery/{schoolId}` | | recovery request for a CLOSED school (state REQUESTED/APPROVED/CANCELLED, reason, requester, approver) |
| `schoolLifecycleHistory/{id}` | schoolId, at | one entry per transition (from, to, actor, reason, remarks, correlationId) |
| `platformPlans/{planId}` | | plan catalogue (no prices in code) |
| `schoolSubscriptions/{schoolId}` | | current subscription |
| `schoolSubscriptionHistory/{id}` | schoolId, at | append-only |
| `platformFeatureDefaults/default` | | global defaults (versioned) |
| `schoolFeatures/{schoolId}` | | explicit overrides |
| `schoolFeatureHistory/{id}` | schoolId, at | append-only |
| `platformNotifications/{id}` | recipientUserId, schoolId | created / delivered / acknowledged / dismissed + `sourceEventId`; deterministic id per (event, recipient) |
| `auditEvents/{yyyyMM}/events/{eventId}` | | partitioned audit |
| `auditOutbox/{id}` | | transactional outbox for fan-out where needed |

## Indexes (collection-group where noted)
auditEvents (collection group `events`): (schoolId, timestamp desc), (actorUserId, timestamp desc), (category, timestamp desc), (eventType, timestamp desc),
(schoolId, category, timestamp desc), (targetEntityId, timestamp desc), (result, timestamp desc). `schoolLifecycleHistory`: (schoolId, at desc). `platformNotifications`: (recipientUserId, status, createdAt desc).
Cursor pagination only; every audit query has a required bounded time range.

## Rules impact
New collections have **no client rules** (default deny), so the rules file does not grow. The only rules change planned is the self-registration status default (D1) and
reading the new `schoolAccess` reason values (the check `!('schoolAccess' in p)` is unchanged).

## Added in Phase 9
`auditEvents/{yyyyMM}/events/{eventId}` (append-only), `auditArchives/{yyyyMM}` (archive marker: count, bytes, sha256, state ARCHIVED|PURGED), `auditClientRate/{uid}` (T4 rate window). No client rules for any of them. Composite indexes on collection `events`: (schoolId | actorUserId | category | eventType | result | source) ascending + `timestampMs` descending.

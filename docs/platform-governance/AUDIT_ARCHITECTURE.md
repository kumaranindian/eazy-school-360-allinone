# Audit architecture

## Principles
One schema, one writer, append-only, tenant-scoped, bounded queries. Clients never write audit documents. Every event carries a **trust level**
because the platform cannot observe everything the same way.

## Trust levels
| Level | Meaning | Sources |
|---|---|---|
| T1 transactional | written in the same batch as the business change | callables: admission, provisioning, platform, lifecycle, feature, subscription |
| T2 observed | written by a Firestore trigger after the change, actor taken from the rules-enforced `createdBy/updatedBy` | client-written modules (students, attendance, fees, ...) |
| T3 system | scheduled jobs and triggers acting as the system | expiry job, rollups |
| T4 client-reported | reported by the app through a rate-limited, allowlisted callable; **not proof**, shown with a "client-reported" label | failed login, permission denied, logout, session expiry |
Never claimed: reads of individual records (direct reads are invisible), or notification "read" before acknowledgement.

## Write path
```
callable -> authorise -> validate -> transaction { business write + audit event + outbox } -> mirror/fan-out
client write -> rules -> Firestore -> trigger -> audit event (T2)
scheduler -> idempotent job -> audit event (T3)
app -> reportClientEvent (allowlist, rate limit, correlation id) -> audit event (T4)
```
The audit writer (`audit.js`) is the only code that writes `auditEvents`; it validates the schema, applies the per-event field allowlist and
redaction, sets `timestamp` from the server and a deterministic `eventId` (hash of source event id + type) so retries never duplicate.
If the downstream write fails the surrounding transaction fails (T1) or the trigger is retried (T2); events are not silently dropped.

## Storage (D9)
`auditEvents/{yyyyMM}/events/{eventId}`: monthly partitions keep collections small and make archival a bounded operation. Indexed fields:
schoolId, branchId, actorUserId, category, eventType, result, timestamp, targetEntityId (composite indexes listed in DATABASE_DESIGN).
Reads only through callables (platform owner/compliance, cursor pagination, bounded date range) because the Firestore rules cannot take another collection.
Nothing is updated or deleted by application code; retention and archival run as a scheduled, audited job.

## Schema (v1)
eventId, eventType, category, schoolId, branchId, actorUserId, actorRole, actorNameSnapshot, application (PLATFORM_ADMIN|SCHOOL_ADMIN|BRANCH_ADMIN|TEACHER|PARENT|FINANCE|WEB|PUBLIC_PORTAL|FUNCTION|SCHEDULER),
platform (ANDROID|IOS|WEB|SERVER), targetEntity, targetEntityId, action (CREATE|UPDATE|DELETE|ACTIVATE|...), result (SUCCESS|FAILURE|DENIED),
timestamp (server), correlationId, source (CALLABLE|TRIGGER|SCHEDULER|CLIENT_REPORTED), trust (T1..T4), changeSummary {description, changes:[{field, from, to}]}, metadata, schemaVersion.
Forbidden everywhere: passwords, OTPs, tokens, secrets, document download URLs, full document copies. Change summaries use an allowlist per entity; sensitive fields
(phone, email, address, DOB, Aadhaar-type ids, medical) are recorded as "changed" without values unless the catalogue marks them safe.

## Exports
Callable, owner/compliance, current filters, hard cap (10,000 rows), CSV with time zone, no sensitive payloads, and the export itself is audited.

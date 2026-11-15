# Subscription design

## Model
`platformPlans/{planId}`: name, periodType (MONTHLY|QUARTERLY|HALF_YEARLY|ANNUAL|CUSTOM), optional default feature set, active flag. **No price or currency in code.**
`schoolSubscriptions/{schoolId}`: the current subscription (planId, classification TRIAL|PAID, startDate, endDate (both `yyyy-MM-dd` in the school's zone), status,
gracePeriodDays, renewalDate, remarks, internalNotes, cancellationReason, version).
`schoolSubscriptionHistory/{id}`: one append-only entry per change (who, when, before, after, reason). History is never overwritten.

## Statuses and the access matrix
NOT_STARTED, TRIAL, ACTIVE, GRACE_PERIOD, EXPIRED, CANCELLED.
| School | Subscription | Access |
|---|---|---|
| INACTIVE / SUSPENDED / CLOSED | any | blocked |
| ACTIVE | none (legacy, D2) | allowed |
| ACTIVE | NOT_STARTED | blocked ("not active yet") |
| ACTIVE | TRIAL / ACTIVE, within dates | allowed |
| ACTIVE | GRACE_PERIOD | allowed with a warning (only if `gracePeriodDays > 0`) |
| ACTIVE | EXPIRED / CANCELLED | blocked |

## Time rules (D3)
Dates are plain calendar dates in the **school's time zone** (`schools.timezone`). `endDate` is inclusive through its last millisecond local time.
Status is a pure function `statusAt(subscription, now, zone)`; the same function runs in the scheduler, the callables and the tests.
Validation: end >= start; dates must be real calendar dates; extensions only forward; renewal creates a new history entry and recomputes status.

## Enforcement
1. Admin changes apply immediately (fan-out).
2. A 15-minute idempotent scheduler recomputes `statusAt` for subscriptions whose boundary has passed, updates status, mirrors access, writes the history entry and a
   single notification (a deterministic notification id prevents duplicates on retry).
3. Callables evaluate live; the scheduler is never the only control. Rules-level checks read the mirror (maximum staleness 15 minutes for pure time-based expiry, D5).

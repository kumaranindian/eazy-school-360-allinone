# Requirements versus repository

Legend: **Built** (exists and tested), **Partial**, **Not built**, **Conflict** (cannot be done as written; see the note).

| # | Requested | Status | Note |
|---|---|---|---|
| 3.1 | New schools default INACTIVE (every registration path) | Not built | Server-created and self-registered schools are ACTIVE today. Self-registration needs a rules change (`nd().status == 'ACTIVE'` on create) and an app release. Needs approval, see PLAN D1 |
| 3.2 | Statuses INACTIVE/ACTIVE/SUSPENDED/EXPIRED/CLOSED, transition table | Partial | ACTIVE/INACTIVE/SUSPENDED exist; EXPIRED, CLOSED and a validated transition table do not |
| 3.3 | Inactive school blocks every role, branded message with support email | Partial | Paused screen exists for all school roles; wording and the support email are generic |
| 3.4 | Activation management UI (filters, search, detail, remarks, confirm) | Partial | Directory, overview, suspend/reactivate with reason exist; no remarks/internal notes/activation message, no registration-date or owner search |
| 3.5 | Suspend, reactivate, close, history | Partial | Suspend/reactivate built; close and lifecycle history missing |
| 4 | Notify school admins of lifecycle/feature changes; popup with acknowledge, inbox, delivery state | Partial | Banner exists, session-dismiss only; no per-recipient record, acknowledgement or delivery state |
| 5 | Subscription plans, dates, statuses, grace, extend/renew/cancel, history | Not built | Only manual billing records exist |
| 5.3 | Access matrix from lifecycle + subscription | Not built | |
| 5.4 | Scheduled expiry job, idempotent, no duplicate notices | Not built | Pattern exists (`platformStatsRollup`) |
| 6.1-6.2 | Feature catalogue, per-school toggles with history | Partial | Two flags, no catalogue or history |
| 6.3 | Enforcement in UI, routes, backend, rules | **Conflict (partly)** | UI, routes and callables: yes. Direct Firestore writes for most modules cannot get a per-module rule clause (size limit). See FEATURE_CONTROL_DESIGN |
| 6.4 | Dependencies | Not built | |
| 6.5 | Global defaults, overrides, history | Not built | |
| 7.1-7.4 | Central schema, all apps/categories A-M | Partial | Platform events only. Categories E-J (client-written modules) need trigger-based capture; K (admission) is callable-based and easy |
| 7.1 | Failed logins / unauthorized attempts / permission denied | **Conflict** | Never reaches our code. Only client-reported (untrusted) or inferred. See AUDIT_ARCHITECTURE |
| 7.3 | Read/access auditing (profile viewed, etc.) | **Conflict (partly)** | Direct Firestore reads are invisible to the server. Only reads through callables (exports, documents via signed URLs) can be audited |
| 7.5 | Before/after summaries with allowlists and redaction | Not built | |
| 7.6 | Append-only, trusted ingestion, transactional with business write | Partial | Platform events are written in the same batch as the change. Direct-write modules: after-the-fact via triggers (not transactional) |
| 7.7 | Scalable storage, partitioning, retention | Not built | |
| 7.8-7.9 | Audit dashboard, school/user history, exports | Partial | Newest-200 viewer for platform actions only |
| 9 | One access-evaluation service | Partial | `access.js` (`methodAllowed`, `loginAllowed`) + profile mirror; no feature/subscription decisions or reason codes |
| 10 | RBAC | Built (for existing features) | Owner/support/compliance/viewer roles; extend per RBAC_MATRIX |

Items in the request that this repository does not have as modules: **Transport, Library, Online Payments, "Parent App"/"Teacher App" as modules**
(the apps are roles of one codebase), Staff Attendance is a sub-feature of Attendance. These will not be shown in the catalogue.

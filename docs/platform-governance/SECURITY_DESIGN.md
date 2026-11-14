# Security design

Trust boundaries: the client is untrusted; Firestore rules authorise direct writes; Cloud Functions authorise everything else; the Admin SDK bypasses rules, so every
function re-checks caller identity, role, second factor (platform) and school eligibility.

Controls: platform owner role + MFA for lifecycle/subscription/feature/audit actions (`platformCaller`); idempotency keys on lifecycle operations; transitions validated by a table;
server-set timestamps; immutable history/audit (no client rules, no update/delete code path, retention job is the only deleter and is itself audited); redaction allowlists;
no secrets in events or logs; export caps; rate limits on `reportClientEvent`; deterministic ids against duplicates; tenant isolation tests on every new callable.

Threats considered: school admin activating own school (no client write path to `status`); direct Firestore request forging audit/features/subscription (default deny); replay of lifecycle
calls (idempotency); stale mirrors after expiry (15-minute bound, live checks in callables); feature bypass by modified client (layers + trigger, residual risk accepted under D6);
audit forgery through `reportClientEvent` (allowlisted types, labelled T4, never counted as proof); cross-tenant reads through audit queries (callable scopes by role); support-access sessions
(read-only grants already exist and see only what the profile mirror and rules allow).

Rules budget: any change to `firestore.rules` must be released to dev first (`--debug` shows the compiled size) and keep at least 1 KB of headroom (currently thin).

# Platform monitoring and alerts

What the app does by itself, and what has to be set up in Google Cloud. **Nothing in the
second half is applied by the repo**: create it once per project (dev and prod) and check
it fires. Written 2026-11-13; the alert definitions below were NOT created or tested from here.

## Built into the app
- **Platform dashboard** (Platform home): schools by status, new schools, students/staff/parents,
  sign-in activity (today / week / month) and a "needs attention" list (deletion requests
  waiting, open support sessions, offboardings, overdue bills). Numbers come from
  `platformStats/current`, recomputed nightly by `platformStatsRollup` (02:00 Asia/Kolkata) and on demand
  by the refresh button (not more than once every 5 minutes).
- **Stale numbers warning**: the dashboard turns red when the numbers are older than 36 hours, which means the
  nightly job did not run. Check Cloud Scheduler and the function logs.
- **Per-school usage** in `schoolUsage/{schoolId}` (students, staff, parents, branches, users), same job.
- **Audit log** (`platformAuditLog`) for every platform action; **support access log** per school.

## Cloud Monitoring alerts to create (per project)
Send all of them to a monitored channel (email group, Slack, or on-call).

| Alert | Condition (Logs-based or metric) | Why |
|---|---|---|
| Functions error rate | `cloudfunctions.googleapis.com/function/execution_count` with `status != ok`, > 5% over 10 minutes for any function | Broken release or outage |
| Nightly rollup failed | Log: `resource.type="cloud_function" AND textPayload:"platform stats rollup failed"` (or severity ERROR from `platformStatsRollup`) | Dashboard goes stale |
| Suspension fan-out not finished | Log: `"school access applied"` with `done=false`, or the function `schoolStatusChanged` retrying more than 3 times in an hour | Users of a suspended school are not yet paused |
| Deletion processor failing | Log: `"deletion sweep failed"` | Google Play deletion requirement |
| Support access granted | Log: `jsonPayload.message="requestSupportAccess"` (any occurrence) | Someone looked into a school; send to the security channel |
| Platform admin sign-in from a new device | Firebase Auth (Identity Platform) sign-in events for `role=PLATFORM_ADMIN` accounts | Account takeover |
| App Check / auth failure spike | Callable `permission-denied` or `unauthenticated` > 50 in 10 minutes | Attack or broken client |
| Firestore / Storage quota | Built-in quota alerts at 80% | Cost and outages |

Suggested creation: Console -> Monitoring -> Alerting -> Create policy, or
`gcloud alpha monitoring policies create --policy-from-file=<file>` once you have exported one you trust.

## Runbook for each alert
1. **Functions error rate**: Logs Explorer, filter by the function; roll back the last functions deploy if it started right after one.
2. **Rollup failed / stale dashboard**: run *Recompute now* on the platform home. If it fails, read the `platform stats rollup failed` log; usual cause is the function timing out as the platform grows (raise `timeoutSeconds`/memory, or shard per school).
3. **Suspension not finished**: run *Re-apply to all users* on the school (calls `refreshSchoolAccess`). Safe to repeat.
4. **Support access granted**: confirm there is a ticket for it; review the school's *Support access* page.

## Maintenance mode and forced update (operational use)
- *App availability* (owner): switch maintenance on with a message (and an automatic end time). School users see the message;
  platform admins are never blocked and the sign-in screen stays usable, so you can switch it off from the app.
- Set a **minimum build** to retire a broken Android/iOS release. The number is the build in brackets in the app footer (for
  example `v1.1.0 (13)` is build 13). The web app is always current.
- If you lock yourself out: Firebase console -> Firestore -> `platformSettings/app` -> set `maintenance.enabled` to `false`
  (or `minBuild` to 0).

# Scheduled jobs

Cloud Scheduler bills **every job** at about $0.10 (~₹9) a month, whether it runs, is paused or idle, beyond
the first **three per billing account**. That allowance is shared by every project on the account
(eazy-school-360-dev, eazy-school-360-prod, eazy-gold-dev). In November 2026 the 10 scheduled functions
deployed to both projects made up about 99% of the Firebase bill. So all scheduled work now runs in **one**
job, in prod only.

## How it works

`masterScheduler` (`functions/index.js`) runs every 15 minutes in Asia/Kolkata, with 512 MiB, a 540 s
timeout and at most one instance. It only dispatches. Each task's body stays in `index.js` and its module.
The plan and the rules are in `functions/scheduled_jobs.js`:

| Task | Cadence | Notes |
|---|---|---|
| `pushRedrive` | every tick | Retries push deliveries that failed. First delivery is done by the Firestore triggers. |
| `subscriptionMonitor` | every tick | Subscription start, end and grace. |
| `feeDueReminders` | hourly (UTC hour) | Each school's own delivery time. The 180-minute window tolerates a late run. |
| `admissionFollowUpReminders` | hourly | Same window. |
| `processDeletionRequests` | hourly | Exits at once while `ACCOUNT_DELETION_PROCESSING_ENABLED` is off. Its 8-minute budget is capped to the tick's deadline. |
| `expireDeletionRequests`, `admissionDocumentCleanup`, `expenseReceiptCleanup`, `platformStatsRollup`, `auditRetention` | daily | First tick at or after 02:00 IST. Catches up later the same IST day if that tick was missed. |

* **Once per window.** Hourly and daily tasks claim their window in `schedulerState/{task}` inside a
  transaction. A document holds `window`, `status` (`RUNNING`/`DONE`/`FAILED`), `attempts`, `startedAtMs`,
  `finishedAtMs`, `error` and `lastDoneWindow`. A repeated, late or overlapping tick never runs a task twice in
  a window. A `RUNNING` claim older than 10 minutes belongs to a tick that died and is taken over.
* **Failures.** A task body throws on failure after logging its own message. It is marked `FAILED` and
  retried on the next tick, at most 3 times per window.
* **Independent tasks.** Due tasks run together (`Promise.allSettled`) and share the tick's deadline. One
  failing task never stops the others. Each failure is logged as `scheduled task failed` with `task`.
* **State is server-only.** `schedulerState` has no client rules (deny by default; tested in
  `firestore-tests/platform-ops-rules.test.mjs`) and holds no personal data (deletion matrix D4c).
* **Adding a task.** Add a `jobs.<name>` body plus an entry in `PLAN`. Never add a new `onSchedule` export:
  `deploy_manifest.test.js` fails on a second scheduled function, and `index.js` refuses to load if the
  bodies and the plan disagree.

## Dev

`masterScheduler` is **not exported** to a project whose id ends in `-dev`. The Firebase CLI sets
`GCLOUD_PROJECT` while it reads the code at deploy time. `SCHEDULED_JOBS=off` in `functions/.env.<project>`
also leaves it out. Those projects get the callable `runScheduledTask({ task, force? })` instead:

* Only a platform admin with the OWNER role and a second factor can call it.
* It takes task names on the list only, and it is audited like every callable.
* By default it runs the task now, without a window. `force: false` makes it follow the window rules.

In the emulator, call `masterScheduler()` from `firebase functions:shell`. The demo project id is not a
`-dev` id, so the scheduler is exported there.

## One-time cleanup and deploy (2026-11)

The old functions each own a Cloud Scheduler job. Deleting a function deletes its job.

```
OLD="pushRedrive subscriptionMonitor feeDueReminders admissionFollowUpReminders processDeletionRequests expireDeletionRequests admissionDocumentCleanup expenseReceiptCleanup platformStatsRollup auditRetention"

# Dev: no scheduler at all. No deploy needed, and no .env file needed.
firebase functions:delete $OLD --region asia-south1 --project eazy-school-360-dev --force

# Prod: the new job first, so no task is skipped, then the old ones.
firebase deploy --only functions:masterScheduler --project eazy-school-360-prod
firebase functions:delete $OLD --region asia-south1 --project eazy-school-360-prod --force
```

* Deploy with `functions/.env.eazy-school-360-prod` in place. The tasks only need settings that have safe
  defaults, but the file keeps the deployed values the same.
* For a later full `firebase deploy --only functions`, the `.env` file **must** be present. A full deploy
  without it wipes the WhatsApp and portal settings of every function.
* The dev callable goes out with the next dev functions deploy:
  `firebase deploy --only functions:runScheduledTask --project eazy-school-360-dev`.
* Old and new jobs running side by side for a few minutes is harmless: every task is safe to repeat.

## Verify

```
gcloud scheduler jobs list --location asia-south1 --project eazy-school-360-prod   # 1: firebase-schedule-masterScheduler-asia-south1
gcloud scheduler jobs list --location asia-south1 --project eazy-school-360-dev    # 0
gcloud scheduler jobs list --location asia-south1 --project eazy-gold-dev          # counts against the same 3 free jobs
```

* `schedulerState` documents appear in prod within the first hour. Daily tasks show `lastDoneWindow` set
  to the IST date after 02:00 IST.
* The logs show `scheduler tick` when an hourly or daily task ran, and `scheduled task failed` for any
  failure.
* Billing → Reports → SKU "Cloud Scheduler Jobs" drops to about 0 from the next billing day.

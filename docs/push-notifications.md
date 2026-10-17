# Push notifications (Android, iOS, Web)

Push tells people something happened while the app is closed. The **in-app
notification centre is the record**; push is a best-effort alert on top of it.
Nothing here guarantees that a device shows or sounds a notification — the
server can only know that FCM *accepted* a message.

## How it works

```
event (leave, payment, register finalised, holiday, announcement…)
  → a `notifications/{id}` (one person) or `broadcastNotices/{id}` (an audience)
    document is created, by the app or by a trusted Cloud Function
  → onDocumentCreated trigger (functions/index.js `deliver`)
      1. claims `pushDeliveries/{eventId}` (idempotency, see below)
      2. resolves recipients (functions/recipients.js)
      3. functions/push.js: keep only ACTIVE users of the same school, drop the
         sender, honour push-off / muted categories, find device tokens,
         de-duplicate tokens, send in batches of 500 with bounded retry,
         delete tokens FCM reports as dead
      4. records counts on the claim (never text or tokens)
```

### Events that notify

| Event | Trigger | Recipients | Text |
|---|---|---|---|
| Leave submitted / approved / rejected / returned… | app writes `notifications` | applicant / reviewers | existing |
| Announcement, homework, result | app writes `broadcastNotices` | audience | existing |
| Fee payment recorded | `notifyPaymentRecorded` (payments `onCreate`, status ACTIVE) | linked parents with portal access | "A fee payment was recorded." (no amount) |
| Student absent | `notifyRegisterFinalized` (register becomes FINALIZED) | that student's linked parents | "Your child was marked absent on 3 Aug 2026." |
| Holiday added / changed / cancelled | `notifyHolidayWritten` | whole branch | name and dates |
| Fee due soon / today | `feeDueReminders` (daily 08:00 Asia/Kolkata) | linked parents of open invoices due in 3 days / today | "A fee invoice is due on …" (no amount) |

Payloads and notification text never contain amounts, marks, or other private
data. Event handlers (`functions/notify_events.js`) write deterministic
document ids with `create()`, so a retry or a re-run creates nothing new.

### Idempotency and retries

* Cloud Functions events are delivered at least once. `claimDelivery` creates
  `pushDeliveries/{event.id}` atomically; a second arrival does nothing. A
  claim stuck in `PROCESSING` for >10 min (a crash) can be taken over.
* Transient FCM errors (`internal-error`, `server-unavailable`, rate limits)
  are retried up to 3 times with backoff, only for the tokens that failed.
* Permanent errors are not retried. `invalid-argument` never deletes a token.
* Only `registration-token-not-registered` / `invalid-registration-token`
  delete a device document.
* `pushDeliveries` documents carry `expireAt` (30 days). **Enable a Firestore
  TTL policy on `pushDeliveries.expireAt`** — `firestore.indexes.json` declares
  it, and `firebase deploy --only firestore:indexes` applies it.

## Device registration

Clients never write `users/{uid}/devices/*` (rules: `create, update: false`).
They call the `registerDevice` / `unregisterDevice` callables, which:

* require an ACTIVE signed-in user with a school;
* store the token under the **caller's** account and school (never from the
  request), with a hashed document id, platform, status, timestamps;
* move a token off any other account that held it (shared devices);
* keep at most 10 devices per user (least recently seen dropped);
* let a user remove only their own registration.

Collection-group queries on `devices.token` and `invoices.dueDateKey` need the
field overrides in `firestore.indexes.json`.

## Platforms

**Android** — channel `eazyschool_general` (high importance, lock-screen
visible) is created in `MainActivity.kt`; the FCM payload targets it, so
background messages use the channel's sound. Android 13+ asks for
`POST_NOTIFICATIONS` at registration. While the app is open the in-app feed
shows a snackbar.

**iOS** — `ios/Runner/Runner.entitlements` (`aps-environment`) is wired into the
Runner target; `UIBackgroundModes: remote-notification` is in `Info.plist`;
foreground presentation (banner + sound) is enabled in the gateway; payload
uses `sound: default`.

**Web** — `web/firebase-messaging-sw.js` is a small service worker with **no
SDK, no keys, no config**; it shows the push and opens `/#/notifications` on
click. Browsers only honour a permission prompt from a click, so the app never
asks by itself: *Notification settings → This browser → Enable*. Web push is
only active in builds that set the VAPID key:

```
flutter build web --release -t lib/main_prod.dart \
  --dart-define=APP_ENV=prod --dart-define=FCM_VAPID_KEY=<public key>
```

Tapping any push opens the notification centre (`PushRoute` allowlist); the
list there applies the role-aware navigator and the router's permission checks.

## Manual configuration (not done by code — verify yourself)

1. **Firebase Console → Cloud Messaging → Web Push certificates**: generate a
   key pair per project; pass the public key as `FCM_VAPID_KEY`.
2. **Apple Developer**: enable Push Notifications on the App ID
   (`com.avail404.eazyschool.eazyschool360`); create an APNs auth key (.p8) and
   upload it in **Firebase Console → Project settings → Cloud Messaging → Apple
   app configuration** (dev and prod projects).
3. In Xcode confirm *Signing & Capabilities → Push Notifications* shows for
   Runner and *Background Modes → Remote notifications* is on.
4. Firestore: enable the TTL policy on `pushDeliveries.expireAt`.
5. Blaze plan (Cloud Functions + Scheduler).
6. Hosting must serve `firebase-messaging-sw.js` over HTTPS with `no-cache`
   (already in `firebase.json`).
7. Optionally set the schedule's time zone / offsets for fee reminders (code
   defaults: Asia/Kolkata, 3 days and same day).

## Testing

* `cd functions && npm test` — payloads, eligibility, preferences, dedupe,
  retry, stale tokens, idempotency, device registration, event handlers.
* `flutter test test/communication` — registration lifecycle, permission
  handling, route allowlist, categories.
* Rules: `firebase emulators:exec --only firestore,storage --project demo-eazy-school-360 "cd firestore-tests && node --test communication-rules.test.mjs"`.
* Real delivery (physical Android/iOS device, a browser, sound, lock screen)
  can't be automated here and must be checked by hand after the manual steps.

## Troubleshooting

* No push, in-app works: check the user's *Notification settings*, device
  permission, and `pushDeliveries/{eventId}` (`status`, `accepted`, `devices`,
  `muted`, `ineligible`).
* iOS silent: APNs key missing/wrong environment, or capability not enabled.
* Web silent: VAPID key not passed to the build, permission blocked in browser
  site settings, or OS "do not disturb". Sound follows the OS/browser settings.
* A user stops receiving after sign-in on another account: the token was moved
  to the other account on purpose (shared device); sign in again to re-register.

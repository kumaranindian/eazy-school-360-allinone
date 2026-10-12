# Push notifications

## How it works
1. The app registers this device's FCM token at `users/{uid}/devices/{id}` once the user is signed in
   and push is on (Settings → Notification settings → Push notifications; on by default).
2. When a document is created in `schools/{s}/branches/{b}/broadcastNotices` (announcements, homework,
   results) or `.../notifications` (leave, messages, timetable…), the Cloud Functions in `functions/`
   resolve the recipients with the same audience rules as the app, skip users who turned push off or
   muted that category (administrative notices cannot be muted), skip the sender, and send via FCM.
3. Dead tokens are deleted. Sign-out removes this device's token.
4. The in-app bell and snackbar alert are still the record of truth; push is a nudge.

## One-time setup
- Firebase project on the **Blaze** plan; `cd functions && npm install`; `firebase deploy --only functions,firestore:rules`.
- Set `FUNCTIONS_REGION` to the Firestore database region if it is not `us-central1`.
- Android: nothing more (POST_NOTIFICATIONS is declared; Android 13+ prompts at first sign-in).
- iOS: in Xcode enable the **Push Notifications** capability and **Background Modes → Remote notifications**,
  and upload an APNs auth key in Firebase console → Project settings → Cloud Messaging.
- Web is not supported yet (needs a service worker and VAPID key).

## Known limits
- A recipient set is capped at 2000 users per event.
- Leave-reviewer notices go to school admins and that branch's admins.
- If the user denies the OS permission, the setting stays on but nothing is delivered.

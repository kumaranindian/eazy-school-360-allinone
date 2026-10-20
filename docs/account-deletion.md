# Account deletion (Google Play policy)

Status: **Phases 2 (backend), 3 (public page), 4 (in-app screen) and 5 (deletion processor) implemented.**
The processor is **off** (`ACCOUNT_DELETION_PROCESSING_ENABLED` unset) and has never run against production data.
Phase 6 (deployment and launch checks) is documented below; see its open items.

## Decisions (confirmed by Avail404)

| # | Decision |
|---|---|
| 1 | Every request is reviewed by Avail404 before anything is deleted. No automatic deletion. |
| 2 | Public-form identity is verified with a Firebase Auth e-mail link. |
| 3 | Avail404 reviews and completes a request within **7 days** (service target, not a retention period). Retention periods for fee, invoice, payment and audit records are **not decided**; those records are retained until they are. |
| 4 | A parent's request affects the parent's own data only. Student records belong to the school and are never touched by it. |
| 5 | References to a deleted user's id in audit fields (`createdBy`, ...) are replaced with a non-identifying value (Phase 5). |
| 6 | A privacy policy page will be added in the app (text to be supplied/approved by Avail404). |
| 7 | Public URL: `https://eazyschool.avail404.com/delete-account` (to be verified live before it is given to Play). |

## Lifecycle (functions/account_deletion.js)

`PENDING_VERIFICATION` (public form, awaiting e-mail link; lapses after 24 h)
-> `UNDER_REVIEW` -> `APPROVED` -> `PROCESSING` -> `COMPLETED` (last two: Phase 5).
Side states: `ACTION_REQUIRED` (e.g. the only active school admin), `FAILED_RETRYABLE`,
and terminal `REJECTED` / `CANCELLED` / `EXPIRED`. Transitions are a closed table;
no path leads from review straight to a destructive state.

## Callables

| Callable | Who | Purpose |
|---|---|---|
| `requestAccountDeletion` | signed in, re-authenticated within 5 min | own request; `{confirm: true}` required |
| `getMyDeletionRequests` / `cancelAccountDeletion` | signed in | own requests only; cancel until approved |
| `requestAccountDeletionPublic` | anyone | web form; same answer for any address; rate limited |
| `confirmAccountDeletionRequest` | signed in via the e-mail link | proves the address, opens the request |
| `getDeletionRequestStatus` | anyone with the reference | status category only |
| `reviewAccountDeletion` | ACTIVE `PLATFORM_ADMIN` profile | approve / reject / request action / reopen |
| `expireDeletionRequests` | scheduled daily | lapses unverified requests |

Identity always comes from the verified token; school and role from the server's
`/users/{uid}`. A platform administrator cannot use self-service and cannot review
their own request. A school is never deleted by an administrator's request, and a
sole admin is held in `ACTION_REQUIRED` (re-checked again at approval).

## Collections (server-only; firestore.rules default-deny, covered by `account-deletion-rules.test.mjs`)

`accountDeletionRequests/{reference}`, `accountDeletionLocks/{uid}`, `accountDeletionRate/{key}`.
The reference is 80 random bits (`DEL-XXXXXXXXXXXXXXXX`), not an account id. A request
holds ids and a role snapshot, plus the submitted e-mail only while unverified.

## Manual configuration needed before this can go live

- Enable **Email link (passwordless) sign-in** in Firebase Auth for `eazy-school-360-prod`
  (Phase 3 uses it to verify web requests) and add `eazyschool.avail404.com` to Auth
  **Authorized domains**.
- Add a Firestore **TTL policy** on `accountDeletionRate.expireAt` (same as `otpRate`).
- Create at least one `PLATFORM_ADMIN` profile for Avail404 reviewers.

## Tests

`cd functions && npm test` (42 account-deletion tests) and
`firebase emulators:exec --only firestore,storage --project demo-eazy-school-360 "cd firestore-tests && node --test account-deletion-rules.test.mjs"`.

## Phase 3: public pages (separate repo: `avail404-website`, branch `feature/eazyschool-account-deletion`)

Next.js 14 on Vercel. Pages: `/eazyschool/delete-account` (form + explanations),
`/eazyschool/delete-account/verify` (e-mail link landing), `/eazyschool/delete-account/status`,
`/eazyschool/privacy`. `middleware.ts` also serves them at the root of
`eazyschool.avail404.com` (`/delete-account`, `/privacy`). The form calls the prod
callables with the Firebase JS SDK (`firebase@11.10.0`, region `asia-south1`); the e-mail
link uses Firebase Auth e-mail-link sign-in with in-memory persistence and signs out as
soon as the request is confirmed.

Flow: form -> `requestAccountDeletionPublic` -> `sendSignInLinkToEmail` (same message for
any address) -> link -> `signInWithEmailLink` -> `confirmAccountDeletionRequest` -> status
UNDER_REVIEW. The page says "nothing has been deleted yet" until COMPLETED.

### Needed before the URL is live
1. Vercel: add domain `eazyschool.avail404.com` to the website project; DNS CNAME as Vercel instructs.
2. Firebase Auth (`eazy-school-360-prod`): enable **Email link (passwordless sign-in)**; add `eazyschool.avail404.com` to **Authorized domains**.
3. Optional: edit the Auth **Email link** template (Authentication -> Templates) so the message names EazySchool 360 / Avail404 and the sender is recognisable.
4. Deploy the Phase 2 functions to prod (`firebase deploy --only functions`) - the page calls them.
5. Deploy the Phase 4 app screen first or together: the page tells people to use *profile menu -> Delete account*.
6. Avail404 to review/approve the text of `/eazyschool/privacy` (it states retention only in general terms; no periods are published because none are decided).
7. Verify: open `https://eazyschool.avail404.com/delete-account` in a signed-out browser, submit a real test address of your own, follow the link, and confirm the request appears as UNDER_REVIEW.

### Known limits
- Accounts that have only a phone number (no e-mail) cannot use the web form; the page sends them to the app or `hi@avail404.com`.
- No CAPTCHA or App Check on the public form yet; protection is the server rate limits (3/hour per address, 10/hour per network address), the honeypot, and Firebase's own e-mail limits. `ENFORCE_APP_CHECK` is still off.
- The verification link is sent by Firebase Auth's standard e-mail; deliverability and wording are Firebase's.

## Phase 4: in-app screen (`lib/features/account_deletion/`)

Path: **Dashboard -> Account -> Delete account** (route `/delete-account`, open to every
signed-in role; it is a dashboard shortcut, not an app-bar button, because an extra app-bar
action shifts the centred school header on phones). The screen explains what is deleted and
kept and the school-admin rule, shows the latest request with its reference, and offers
**Request account deletion** only when no request is open.

Flow: tick "I understand" -> "Confirm it is you" (password, Google, or a WhatsApp code,
matching how the person signs in; the server accepts a request only from a sign-in made in
the last 5 minutes) -> `requestAccountDeletion` -> status card (UNDER_REVIEW: "has not been
deleted yet"). A request can be cancelled until Avail404 approves it. The client never sends a
user id, school or role, and never reports a deletion as done until the server says COMPLETED.

Tests: `flutter test test/account_deletion` (37: domain, copy, error mapping, flows for each
sign-in method, double tap, refusals, cancel, and layout at 320-1920 px and text x1-2).

## Phase 5: the deletion processor (`functions/deletion_processor.js`)

Carries out an `APPROVED` request: disable the login -> delete the user's devices, preferences and
read state -> delete their personal notifications -> parent/staff records (data matrix B1, B2) ->
replace the person's uid (and paired names) across every non-financial collection -> delete leave
documents -> turn the profile into a stub -> delete the Firebase Auth user **last**. Then
`COMPLETED` (the only state the app and website describe as "deleted").

Safety properties, each covered by tests:
- Disabled unless `ACCOUNT_DELETION_PROCESSING_ENABLED=true`; only `APPROVED`/`PROCESSING`/`FAILED_RETRYABLE` requests run.
- Acts only on the account stored on the request; matches only documents carrying that uid, so other
  people's data and the school are untouched. Students and financial collections are never changed.
- The only school admin, and platform admins, are held (`ACTION_REQUIRED`), re-checked at run time.
- Idempotent, batched (200), checkpointed, time-boxed (8 min): a failure or timeout leaves
  `FAILED_RETRYABLE` and the hourly sweep resumes. Files are deleted before the document that names them.
- A coverage test (`deletion_coverage.test.js`) fails if any collection in `firestore.rules` has no
  deletion decision, so new features cannot silently skip deletion.

Callables/schedules: `processDeletionRequests` (hourly sweep), `processAccountDeletion` (platform admin,
runs one request now). Tests: `cd functions && npm test` (35 processor/adapter tests) plus
`firebase emulators:exec --only firestore,auth --project demo-eazy-school-360 "cd functions && node --test deletion_processor.emulator.test.js"`
(real Firestore/Auth emulators).

### Before enabling it on a project
1. Deploy `firestore.indexes.json` (collection-group indexes for the nested lookups) and wait until they are **Enabled**.
2. Deploy the functions, then set `ACCOUNT_DELETION_PROCESSING_ENABLED=true` in `functions/.env.<project>` and redeploy.
3. Rehearse on **dev** with a throwaway account: request, approve, run, check the result; then prod.
4. Create the Avail404 `PLATFORM_ADMIN` reviewer profile.
5. Take a backup/clone first (the deployment checklist, section A) - deletion cannot be undone.

## Phase 6: deployment state and launch checklist (as of 2026-10-19)

### Deployed (processor flag OFF everywhere)
| Piece | dev | prod |
|---|---|---|
| Request/review/status functions (8) | deployed | deployed |
| `processDeletionRequests` (hourly) / `processAccountDeletion` | deployed, idle (flag off) | deployed, idle (flag off) |
| Collection-group index overrides for nested lookups | deployed | deployed |
| Cleanup policy for function images (3 days) | n/a | set |
| Website `eazyschool.avail404.com` (`/delete-account`, `/status`, `/verify`, `/privacy`) | - | **live**, public without sign-in, HTTP 200 |
| Android bundle/APK with the in-app screen | - | built (version code 4), **not yet uploaded to Play** |

Checked live: the callables answer correctly signed out; the page text matches the app path
(Dashboard -> Account -> Delete account); status/verify pages are `noindex`.

### Blockers before the public form can work (Firebase console, `eazy-school-360-prod`)
1. **Authentication -> Settings -> Authorized domains: add `eazyschool.avail404.com`.**
   Today the list is only `localhost`, `eazy-school-360-prod.firebaseapp.com`, `eazy-school-360-prod.web.app`.
   Without it the confirmation e-mail cannot be sent (`auth/unauthorized-continue-uri`).
2. **Authentication -> Sign-in method -> Email/Password -> enable "Email link (passwordless sign-in)".**
3. Optional: Authentication -> Templates -> "Email link sign-in": edit the sender name/subject to name EazySchool 360 / Avail404.
4. Create the Avail404 reviewer: a `/users/{uid}` document with `role: PLATFORM_ADMIN`, `status: ACTIVE` for the person who will review.

### Test the public form once (after 1-2), with an address you own
Open `https://eazyschool.avail404.com/delete-account`, submit, open the e-mail on the same device, and confirm the
page says "under review ... has not been deleted yet" with a reference. Then use the status page. An address with no
account should end as "No EazySchool 360 account found" (and the login the link created is removed). This leaves one
real request record; reject or cancel it afterwards.

### Rehearse deletion on dev (only then consider prod)
1. Create a throwaway school + one parent/teacher login in **dev** (not a real school).
2. In dev: file the request from the app, approve it as the reviewer (`reviewAccountDeletion`), set
   `ACCOUNT_DELETION_PROCESSING_ENABLED=true` in `functions/.env.eazy-school-360-dev`, redeploy functions.
3. Run `processAccountDeletion` (or wait for the hourly sweep). Check the result against the data matrix, then set the flag back.
4. Prod: only after a backup/clone is taken, with your explicit go-ahead.

### Google Play Console (Avail404 account holder)
1. **Policy and programs -> App content -> Privacy policy:** `https://eazyschool.avail404.com/privacy`.
2. **App content -> Data safety:** answer from the real data inventory (account: name, email, phone, role; school
   records entered by schools; photos; messages; device/push token; crash reports). State "data is encrypted in
   transit", "users can request that data is deleted: Yes".
3. **Data safety -> Data deletion:** "Add a link ... to request data deletion":
   `https://eazyschool.avail404.com/delete-account`. The page shows the app name and developer (Avail404) as Play requires.
4. Upload `app-release.aab` (version code 4 or higher) to Internal testing, add testers, install, and confirm
   Dashboard -> Account -> Delete account works on a real device before promoting.
5. Keep the in-app path, the web URL and the privacy policy consistent; if any changes, update all three.

### What this is, honestly
The request lifecycle, in-app screen, public page and review flow are live and tested. **Actual deletion has never
run on real data** and is switched off. Until it is rehearsed on dev and enabled, an approved request is queued, not
carried out - do not describe the process to Play or to users as complete before that.

### Rollback
- Page: revert the website commit (`git revert e059817 5cec0af` in `avail404-website`) or remove the footer links.
- Functions: `firebase deploy --only functions` from the previous commit; the processor is already off.
- Data: a completed deletion is irreversible (Auth user removed). Restore only from a backup into a new database.

# CORS audit and fix (production)

Date: 2026-10-31 · Project `eazy-school-360-prod` · Region `asia-south1`
Frontend: `https://eazyschool-360.avail404.com`

## Summary

The browser's "CORS" error on `provisionLogins` / `getLoginAccess` is **not a CORS
configuration bug in the code**. The request is rejected by Google's front end
(HTTP 403, HTML body, no CORS headers) *before* the function runs, because the
Cloud Run service behind each affected function does not allow unauthenticated
invocation (`allUsers` has no `roles/run.invoker`). A browser preflight (OPTIONS)
never carries a token, so it is refused, and the browser reports that as CORS.

No application code change is needed or made. The fix is an IAM change (below),
which requires approval.

## 1. HTTP functions identified

`functions/` is plain JavaScript (no TypeScript, no lint script, no `onRequest`).

| Trigger | Count |
|---|---|
| `onCall` (callable, Gen 2) | 24 |
| `onDocument*` (Firestore) | 12 |
| `onSchedule` | 4 |
| `onRequest` | **0** |

There is no custom CORS middleware and no Express/`cors` package. Every callable
is created with `onCall(callOptions(), …)` (`functions/call_options.js`), which
only sets `enforceAppCheck`. Callables use the firebase-functions default
`cors: true`, handled by the SDK itself: it answers OPTIONS before any auth code,
and the handler verifies the Firebase ID token (`request.auth`) on POST.

The functions named in the brief that are not on this list under that name
(e.g. "refreshTeacherAccess", "registerDevice") are all callables and covered by
the same table.

## 2. Observed state (preflight with `Origin: https://eazyschool-360.avail404.com`)

| Result | Functions |
|---|---|
| 204 with CORS headers (working) | requestPhoneOtp, verifyPhoneOtp, refreshParentAccess, requestAccountDeletion, requestAccountDeletionPublic, getMyDeletionRequests, cancelAccountDeletion, getDeletionRequestStatus, confirmAccountDeletionRequest, reviewAccountDeletion, processAccountDeletion |
| **403 from Google front end (broken)** | provisionLogins, resetLoginPassword, changeInitialPassword, getLoginAccess, setLoginAccess, diagnoseAccess, getSchoolAuthSettings, updateSchoolAuthSettings, registerDevice, unregisterDevice, refreshTeacherAccess, refreshMyParentAccess, setBranchAccess |

Identical code and options; only the Cloud Run invoker IAM differs. These
functions were (re)created by the deploy of commit `e4b9016` and their public
invoker binding was not applied (the deploy output was cut off, so the exact
warning was not captured).

## 3. Changes made

None to code, IAM, or deployed resources by this audit.

Deliberately **not** done: adding `cors`/`onRequest` middleware. It does not
apply to callables and would not help, since the 403 happens before any code runs.

## 4. Fix (needs approval — IAM change)

Grant public invoke on the 13 services:

```
for f in registerdevice unregisterdevice provisionlogins changeinitialpassword \
  resetloginpassword getloginaccess diagnoseaccess setloginaccess \
  getschoolauthsettings updateschoolauthsettings refreshteacheraccess \
  refreshmyparentaccess setbranchaccess; do
  gcloud run services add-iam-policy-binding $f --region=asia-south1 \
    --project=eazy-school-360-prod --member=allUsers --role=roles/run.invoker
done
```

Verify (expect 204 for each):

```
curl -s -o /dev/null -w '%{http_code}\n' -X OPTIONS \
  https://asia-south1-eazy-school-360-prod.cloudfunctions.net/provisionLogins \
  -H 'Origin: https://eazyschool-360.avail404.com' -H 'Access-Control-Request-Method: POST'
```

### Security implications

- `allUsers` invoker only lets anyone *reach* the function. It is the normal state
  for Firebase callables (the 11 working ones already have it). Authorisation is
  inside the handler: Firebase ID token required, role/permission and tenant
  checks (`provisionLogins`, `setLoginAccess`, … reject non-admins and
  cross-tenant callers). The first thing an unauthenticated POST gets is
  `unauthenticated`.
- Anyone can send unauthenticated requests that are cheaply rejected; they still
  count toward invocations. `maxInstances: 10` bounds cost; enabling App Check
  (`ENFORCE_APP_CHECK=true` once clients send tokens) further limits abuse.
- Not changing IAM leaves the admin features (create logins, reset passwords,
  access settings, push device registration) unusable in production.
- If the command fails with a policy violation, an organisation policy
  (`iam.allowedPolicyMemberDomains`) blocks public access and needs a project
  exception; do not work around it by other means.

## 5. Tests

- `cd functions && npm test`: 251 tests, 250 pass, 0 fail, 1 skipped.
- Existing unit tests cover handler-level auth, admin permissions and tenant
  isolation per module (`access`, `provision`, `branch_access`, `devices`, …).
- Live preflight checks (working function `requestPhoneOtp`):
  - Allowed origin → 204, `access-control-allow-origin: https://eazyschool-360.avail404.com`, methods `POST`, headers echoed.
  - Unapproved origin `https://evil.example` → 204 and the origin is **reflected**
    (see risks).
  - OPTIONS carries no token and succeeds, as required.
- Not run: POST with valid token against prod (needs a real user; do as part of
  the smoke test after the IAM fix: sign in as admin → Students → create login).
- TypeScript compile and lint: not applicable (no TS, no lint script).

## 6. Remaining risks

1. **Origin reflection.** Callables default to `cors: true`, so any origin gets
   CORS headers. Impact is limited because calls need a Firebase ID token the
   attacker site cannot obtain (no cookies/ambient credentials), but an explicit
   allowlist is tighter. Option: `callOptions` adds
   `cors: ['https://eazyschool-360.avail404.com', 'https://eazy-school-360-prod.web.app', 'https://eazy-school-360-prod.firebaseapp.com']`.
   Not applied: it is a behaviour change that would break local dev and any
   unlisted host, so it needs the full list of production origins and a deploy.
2. Deploys can leave new functions without the public binding (as happened here).
   After every functions deploy re-run the preflight loop above.
3. `ENFORCE_APP_CHECK` is still off.

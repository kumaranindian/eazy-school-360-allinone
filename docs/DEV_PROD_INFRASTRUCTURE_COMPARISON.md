# DEV vs PROD infrastructure comparison (read-only)

Date: 2026-10-31 · DEV `eazy-school-360-dev` · PROD `eazy-school-360-prod` · Region `asia-south1`
Method: `gcloud run services list/describe/get-iam-policy`, `gcloud functions list`,
Cloud Audit Logs (read). Nothing was modified.

## Root cause

PROD callables fail CORS because **13 of 24 callable Cloud Run services have no
`allUsers` / `roles/run.invoker` binding**; in DEV all 24 have it. Google's front
end answers the (token-less) browser preflight with a 403 that has no CORS
headers, which the browser reports as a CORS error.

Why those 13 lack it (from the audit log):

1. On 2026-10-19 the first prod deploy of Functions created services in batches.
   `provisionLogins` (and the other 12) had a `CreateFunction` at 11:13:16 that
   ended with **code 13 "Build failed … unexpected error"** (11:13:40).
2. The deploy was retried. By then the function existed, so the Firebase CLI
   took the **update** path (`UpdateFunction`, 11:19:54), not create.
3. The Firebase CLI grants the public invoker role **only when it creates a
   function**. Audit log: `SetIamPolicy` was called for 14 services on 10-19
   (the OTP, deletion, scheduler ones) and **never** for the 13. Today's deploy
   (10-31) only issued `UpdateFunction`, which never touches IAM.
4. Services the CLI created in that retry ended up with `client-name:
   cloudfunctions` (vs `cli-firebase`), the fingerprint of the half-created ones.

DEV never hit a failed first create, so every service got its binding at creation.

Not the cause: org policy (none: both projects are standalone, no organisation,
`iam.allowedPolicyMemberDomains` = ALLOW all), ingress, runtime, deployment
scripts (`tool/deploy_rules.sh` only touches rules; nothing in the repo edits
IAM), or service recreation (creation times are 10-15 DEV / 10-19 PROD; today's
deploy did not recreate anything).

## Side-by-side

| Item | DEV | PROD | Differs? |
|---|---|---|---|
| Functions (Gen 2, ACTIVE) | 43 | 43 | no |
| Cloud Run ingress | all | all | no |
| Deployed by | cli-firebase / gcf-admin-robot | same, but 13 services `client-name: cloudfunctions` | **yes** |
| Callable services with `allUsers` invoker | **24 of 24** | **11 of 24** | **yes** |
| Scheduled services (4) | invoker = compute SA | invoker = compute SA | no |
| Firestore-trigger services (15) | no bindings (event-driven) | no bindings | no |
| Runtime service account | `894913996276-compute@developer` (default) | `97832195228-compute@developer` (default) | project number only |
| Memory | 256Mi | 256Mi | no |
| Org / folder policies | none (standalone) | none (standalone) | no |
| Org policy `allowedPolicyMemberDomains` | allow all | allow all | no |
| APIs: cloudfunctions, run, identitytoolkit | enabled | enabled | no |
| `ENFORCE_APP_CHECK` | not checked in this pass | local `functions/.env` has no value (off) | unverified |
| Auth providers / authorised domains | not compared | not compared | unverified |

PROD callables missing the binding: registerDevice, unregisterDevice,
provisionLogins, changeInitialPassword, resetLoginPassword, getLoginAccess,
diagnoseAccess, setLoginAccess, getSchoolAuthSettings, updateSchoolAuthSettings,
refreshTeacherAccess, refreshMyParentAccess, setBranchAccess.

Limits of this comparison: runtime version column and App Check / Auth provider
configuration were not read per project; only the IAM and deployment
differences above are established.

## Recommended permanent fix

1. **Repair now (needs approval):** add the binding to the 13 services (command in
   `docs/CORS_AUDIT_AND_FIX.md` §4). This is what the CLI would have done on create.
2. **Prevent recurrence:**
   - After every `firebase deploy --only functions`, run a verification loop that
     sends an OPTIONS preflight to every callable and fails on any non-204
     (script in the deploy checklist; read-only, no credentials).
   - When a deploy reports "Build failed" for any function, finish by re-running
     the verification (a retry after a failed create skips the IAM step, as here).
   - Optionally declare the invoker explicitly in `functions/call_options.js`
     (`invoker: 'public'`) so the deploy tool manages it. I have not tested
     whether the CLI re-applies it on update; verify in DEV first rather than
     rely on it.
3. Add the preflight check to `docs/production-audit/DEPLOYMENT_CHECKLIST.md`
   (section B/C) so it is a release gate.

## Security implications

- The binding only allows requests to reach the function; each handler requires a
  Firebase ID token and checks role/tenant (see the verification report). It is
  already the state in DEV and for the 11 working PROD callables.
- Leaving PROD as-is is safe but non-functional for admin features. Fixing it adds
  no data exposure; it adds reachability for unauthenticated calls that are
  rejected cheaply (bounded by `maxInstances: 10`; App Check still off).
- Never grant `allUsers` on the 4 scheduler services or the Firestore-trigger services.

## Deployment recommendations

- Deploy order stays: indexes → functions → verify preflight → rules → hosting.
- Treat any function-build failure as a partial deploy.
- Keep Functions deploys to PROD to approved changes only; none were needed for the
  UI-only commit range other than the functions already changed since 10-19.

# Test results

Environment: Linux sandbox, Flutter 3.32.8 / Dart 3.8 (`/opt/sdk/flutter`), Node 22, Firebase CLI with the Firestore (1.22.0) and Storage emulators, **no Android SDK, no Xcode, no browser, no Firebase credentials, outbound access limited by a proxy**. Commit `f36c35f` (`develop`), run 2026-10-17. Emulators were run with proxy variables unset (otherwise Storage→Firestore lookups are blocked by the sandbox proxy).

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Format | `dart format --output=none --set-exit-if-changed .` | **PASS** — 592 files, 0 changed |
| 2 | Static analysis | `flutter analyze` | **PASS** — No issues found |
| 3 | Dart unit/widget tests | `flutter test` | **PASS** — 1,432 passed, 0 failed (≈5 min) |
| 4 | Dart coverage | `flutter test --coverage` | **60.9 %** line coverage of `lib/` (23,506 / 38,625). Lowest: `students` 37.0 %, `school_setup` 39.3 %, `announcements` 47.3 %, `authentication` 51.4 %, `staff` 53.4 %, `academic_setup` 57.2 %, `leave` 57.8 %, `fees` 58.2 %; highest: `shared` 95.7 %, `core` 86.7 %, `exams` 73.1 %. (Line coverage says nothing about branch/interleaving coverage.) |
| 5 | Cloud Functions tests | `cd functions && npm test` | **PASS** — 132 / 132 |
| 6 | Firestore + Storage rules (emulator, serial) | `firebase emulators:exec --only firestore,storage --project demo-eazy-school-360 "cd firestore-tests && npm test"` | **PASS** — 437 / 437 (0 fail, 0 skipped); includes Dart-generated contract replays (exam, homework, leave, timetable, communication, branch transfer) |
| 7 | Web release build (prod entry) | `flutter build web --release -t lib/main_prod.dart --dart-define=APP_ENV=prod` | **PASS** — `main.dart.js` 5.90 MB, `canvaskit.wasm` 7.0 MB, build 70 s |
| 8 | Dependency advisories — Dart | `python3 tool/osv_scan_pub.py` | **NOT RUN** — "Tunnel connection failed: 403" (sandbox). Last known result (2026-10-10, M12A): 0 advisories / 125 packages; lockfile has since changed |
| 9 | `npm audit --omit=dev` (functions) | same | **9 vulnerabilities** (2 high `node-forge`, 7 moderate incl. `uuid`) — all via `firebase-admin@12`; fix is a breaking upgrade (DEP-1) |
| 10 | `npm audit --audit-level=critical` (firestore-tests) | same | exit 0 (5 high in the dev-only emulator test harness, nothing critical) |
| 11 | Secret scan | regex scan of tree (sub-audit) | no private keys/tokens/service accounts found; dedicated tool (gitleaks/trufflehog) **NOT RUN** (not installed); git history **NOT scanned** |
| 12 | Android release build / signing | `flutter build appbundle` | **NOT RUN** — no Android SDK |
| 13 | iOS build / archive | `flutter build ipa` | **NOT RUN** — no macOS/Xcode |
| 14 | CI workflow | read only | **NOT RUN** on a real runner; structure reviewed (CFG-7/8) |
| 15 | Rules deploy dry-run | `firebase deploy --only firestore:rules --dry-run` | **NOT RUN** — no credentials; rules size 223,727 B (SEC-1) |
| 16 | End-to-end journeys against Firebase / devices / deployed web | — | **NOT RUN** |
| 17 | Load / performance profiling | — | **NOT RUN** |
| 18 | Time-zone matrix (`TZ=Asia/Kolkata`, `America/Los_Angeles`) | — | **NOT RUN** (and no test sets a TZ; CI runs UTC) — this is why ACAD-1 is not caught |
| 19 | Push on real devices (Android channel, iOS APNs, web VAPID) | — | **NOT RUN** |
| 20 | Backup restore drill | — | **NOT RUN** |

## What the passing suites do and do not prove
* They prove tenant isolation, role/ownership rules, field immutability and state machines **for the repository's rule text in the emulator**. They do not prove those rules are live, nor that the 256 KiB release limit and the production evaluation quotas are respected.
* Dart tests use fakes for repositories — transactions, index requirements and the real SDK's retry behaviour are only exercised through the rules-contract fixtures.
* Gaps worth adding (tests do not exist today): attendance write-plan contract; `TZ` matrix; two-writer races (ACAD-3/4/7, admission-number); out-of-order list tests (STATE-1); sign-out cleanup per path (NOTIF-1); `errorSink` PII test (LOG-1); route-map completeness (ROUTE-1); push redrive/truncation (NOTIF-3/4).

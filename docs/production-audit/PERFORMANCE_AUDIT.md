# Performance & scalability audit

Measured values are marked **M**; estimates **E**; nothing was load-tested.

## Measured
| Item | Value | Notes |
|---|---|---|
| Web release build (prod entry) | **M:** `main.dart.js` 5.90 MB (uncompressed), `canvaskit.wasm` 7.0 MB, `skwasm.wasm` 3.4 MB, `build/web` 28 MB; build 70 s | gzip/brotli transfer size NOT measured (Firebase Hosting compresses); CanvasKit adds a large first-load cost on slow links |
| Static analysis cost | `flutter analyze` 34 s, 480 files | — |
| Unit/widget suite | **M:** 1,432 tests ≈ 5 min | — |
| Rules emulator suite | 437 tests | — |
| Startup / login / dashboard latency | **NOT MEASURED** | needs device/web profiling against a real project |

## Estimated hot spots (code reading; scale assumptions explicit)
| ID | Hotspot | Scale assumption → effect |
|---|---|---|
| PERF-1 | Finalise results reads attendance per student sequentially (`exam_results_page.dart:105-130`, `maxRangeRows 4000`) | E: 120 students → 120 round-trips, ~25 k doc reads per finalise; a 1,000-student exam cycle ≈ 200 k reads |
| PERF-2 | *Refresh parent access* per parent: CG query + per-child `get` + `set` | E: 3 k parents → 10 k sequential round-trips, minutes with no progress UI |
| SEC-4 | `feeDueReminders` collection-group scan limited to 2,000 and sequential reads | E: with many schools, tenants after the cap never get reminders |
| NOTIF-4 | Push fan-out capped at 2,000 recipients/notice | `ALL` in a >2,000-user school drops the rest |
| PERF-3 | Bulk student import: 2 queries + 1 commit per row | E: 1,000 rows → thousands of round-trips (idempotent, progress shown) |
| OPS-4 | Invoice/receipt counters: one doc per year | ≈ 1 sequential write/s → 1,000 invoices ≈ minutes; contention retries under concurrent cashiers |
| — | Marks entry chunk size 5 | many commits for a 60-student sheet (ACAD-3 also) |
| STATE-1 | Rosters: client re-fetch races | functional rather than raw speed |

## Good patterns observed
Dashboards/fee reports use server `count()`/`sum()` aggregates (no document downloads); list pages paginate with `limit` and cursors (shared `PagedListController`); attendance reads are scoped to a section/day or `limit(4000)` with a `truncated` flag; notifications are `limit`-ed and read-ids capped at 500.

## Priorities
1. Fix NOTIF-4/SEC-4 truncation (correctness at scale), 2. PERF-1/2 (admin-visible stalls), 3. CSP + compression/caching headers for the 6–7 MB first load, 4. measure startup & dashboard on a mid-range Android and a throttled web session before launch.

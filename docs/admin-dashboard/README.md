# School Admin dashboard (light design)

The School Admin's home (`/dashboard`) follows the light dashboard design.
Only the School Admin experience changed: Branch Admin, Teacher, Finance,
Parent and Platform Admin keep their existing homes (`StaffHome`,
`ParentHome`).

## Where it lives
* `lib/features/dashboard/presentation/widgets/admin/` - `AdminHome` (layout
  and wiring), `admin_dashboard_widgets.dart` (card, overview card, ring, stat
  line, activity row, action tile, insights banner, footer),
  `admin_summary_cards.dart` (attendance and fee cards).
* `lib/core/theme/admin_dashboard_palette.dart` - the design colours in one
  place (light palette; dark mode falls back to the app's colour scheme).
* `lib/features/dashboard/domain/dashboard_summaries.dart` - pure rules for
  the attendance and fee cards (unit tested).
* `lib/features/dashboard/presentation/providers/admin_dashboard_providers.dart`
  - the data, reusing existing providers.
* `DashboardPage` picks `AdminHome` for `UserRole.schoolAdmin` only.

## Landing page
No routing change was needed: the router already sends every signed-in user
from `/`, `/login` etc. to `/dashboard` (or the page they asked for before
signing in), and a refresh restores the same location. The School Admin is
never routed to the School module first. `test/dashboard/admin_dashboard_ui_test.dart`
asserts the landing path.

## Data sources (no new collections, schemas or rules)
| Block | Source |
|---|---|
| Students | `studentCountsProvider` (server-side `count()`), ACTIVE |
| Parents | server-side `count()` of ACTIVE parent records of the branch (`FirebaseParentCounter`; read-only, same collection the Parents screen lists) |
| Staff | `staffCountsProvider` (ACTIVE) |
| Today's attendance | the section registers (`attendanceSessions`) for today in **school time**: their stored tallies, one query. Expected = active students; not marked = expected - marked (never "absent"); late/half-day count as present |
| Fee collection | existing fee reports: `loadCollections` for this month (ACTIVE payments, reversals excluded) and `loadSummary` for the academic year (outstanding, collection rate); school currency |
| Leave requests | `leavePendingCountProvider` (student + staff), shown only to roles that may review leave |
| Footer | `appVersionLabel` from `lib/core/config/app_version.dart` |

The fee card's percentage is the academic year's collection rate (existing
definition), labelled as such; "collected this month" is a separate amount.

## Responsive behaviour
Breakpoints (`AdminDashboardBreakpoints`): phone < 600, tablet 600-1023,
desktop >= 1024 with content capped at 1200 px.
* Phone: single column, three overview cards in a row, attendance / fee /
  today stacked, quick actions 4 across from 400 px (2 below).
* Tablet: attendance, fee and today two-up; actions 4 across.
* Desktop: attendance, fee and today three-up; actions 8 across.
* Layout tests render phone portrait/landscape, tablet and desktop at text
  scale 1.0 and 1.5 and fail on any overflow.

## Not available / limits
* **Trend indicators** on the overview cards are omitted: no historical counts
  are stored.
* **School Insights** opens the existing attendance reports; there is no
  analytics module yet, so no metrics are shown on the banner.
* Reports shortcut = attendance reports (the only report screen reachable by
  the same permission).
* Parents counts parent *records* of the selected branch.

Screenshots: `dashboard-mobile-390.png`, `dashboard-desktop-1440.png`
(rendered in a widget test with test data).

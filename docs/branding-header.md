# Global school branding header

## Existing header architecture (before)

* Every authenticated route is a child of **one** `StatefulShellRoute` (`app_router.dart` → `AppShell` → `AdaptiveScaffold`), including nested pages and the Platform Admin, School Admin, Teacher, Finance and Parent roles. Only `/login`, `/register`, `/forgot-password`, splash, `/account-inactive` and `/create-school` sit outside it.
* `AdaptiveScaffold` drew the shell bar: `[school logo + EazySchool mark side by side] [school name]` left-aligned, actions on the right. The dashboard hero repeated the same two logos side by side.
* Inner screens (62 files) bring their own navy page `AppBar` (back button, page title, page actions, tabs) *below* the shell bar. Top-level roots instead show a `PageHero`.
* Tenant branding already comes from `schoolBrandingProvider` (derived from `tenantContextProvider`; no extra Firestore read).

## What changed

| Component | Role |
|---|---|
| `lib/shared/branding/school_branding_header.dart` — `SchoolBrandingHeader` | The three-slot layout: school logo (left) · title (centre) · app mark + actions (right). `CustomMultiChildLayout` centres the title on the **bar**; if the side groups leave too little room it is centred in the free space between them (never overlaps). Ellipsis, text scaling, semantics (`header`). |
| same file — `SchoolBrandingAppBar` | A standard `AppBar` hosting the header, fed from `schoolBrandingProvider`. Same height (`kToolbarHeight`), status-bar and safe-area handling as before. Logo sizes follow width (32 / 36 dp). |
| `lib/core/routing/route_titles.dart` — `screenTitleForPath` | Pure longest-prefix map from location to centre text (`/fees/invoices/1` → "Fees Management"). Null for the dashboard ⇒ school name. |
| `AdaptiveScaffold` (modified) | Uses `SchoolBrandingAppBar`; new optional `screenTitle`; `_BrandTitle` removed. |
| `AppShell` (modified) | Passes `screenTitleForPath(path)`. |
| `SchoolEmblem` (new, `school_brand_logo.dart`) + dashboard hero (modified) | The hero now shows the school logo (or initial) only; the product mark lives in the header's right corner and the footer. |

Hierarchy: **dashboard** → school name; **every other screen** → the module title; the school name is never shown next to a title. Inner page `AppBar`s keep their back/title/actions (functional, preserved) beneath the branding bar.

## Branding data, caching, tenancy

* `schoolBrandingProvider` → `tenantContextProvider.select(school)`; the school document is read **once per sign-in** (not per navigation) and re-derived when a logo/profile write invalidates the tenant context.
* The tenant is resolved from the signed-in user's own profile, so one school's logo cannot appear in another's session; sign-out/sign-in as someone else replaces it (covered by `test/branding/school_branding_test.dart`).
* Logos use `Image.network` with `gaplessPlayback` and a URL key (Flutter's image cache) inside a fixed square, so there is no layout jump; a missing/dead/invalid URL falls back to the school **initial** badge (never a second EazySchool mark). Before a school is known the left slot is reserved empty and the title falls back to the product name.
* No new collection, field, provider-level network request or global state.

## Screens covered

All authenticated screens get the header through the shell: dashboard, School profile, Settings (+ all sub-pages incl. Authentication), Students/Parents/Staff/Teachers (lists, profiles, forms, imports), Attendance (+reports), Timetable (hub, editor, substitutions, periods), Homework, Exams (marks, results, report cards, grading), Fees (+structures, invoices, payments, receipts, reports), My Fees, Leave (+reports) / My Leave, Announcements, Messages, Notifications (+preferences), My Profile/Timetable/Homework/Results, User Management — for Platform Admin, School Admin, Branch Admin, Finance, Teacher and Parent.

Not given the header, deliberately:
* `/login`, `/register`, `/forgot-password`, splash, `/account-inactive` — no tenant exists yet; they keep the EazySchool lockup.
* `/create-school` — signed in but the school does not exist yet; keeps its product `AppBar`.
* Dialogs, bottom sheets and compact panels (per the brief).
* The 62 inner page `AppBar`s were **not** replaced: they are page toolbars (back, page title, tabs, actions) that sit under the branding bar; adding logos there would show them three times.

## Validation actually run

`flutter analyze` (clean); `dart format`; new tests `test/branding/school_branding_header_test.dart` (layout, centring with asymmetric sides, long names, text scale 1.0/1.5 at 320×568, 390×844, 844×390, 820×1180, 1440×900, semantics, missing/dead logo, tenant switch, `screenTitleForPath`) and `test/widget/branding_shell_test.dart` (the real shell for all six roles, different tenant names, navigation changing the title, five sizes × two text scales). A visual check of the real shell at 390, 320 and 1280 px was made with throw-away golden images (test fonts render as blocks). Not tested: real devices, real remote logo loading, RTL (the header assumes left-to-right).

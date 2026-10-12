# UI rebrand — EazySchool 360 logo colours

Source artwork (repo root): `EazySchool360_Logo (1).png`, `EazySchool360_App_Icon (1).png`,
`a_clean_high_resolution_logo_branding_presentatio (1).png`.

## Palette (sampled from the logo)
| Token | Value | Use |
|---|---|---|
| `brandBlue` | `#0182F1` | gradients, illustrations, accents (3.9:1 on white — not for text buttons) |
| `primary` | `#0A6BD9` | buttons, links, focus (≥4.5:1 with white) |
| `brandBlueDeep` | `#00459F` | gradient end, icon tint |
| `navy` / `navyDeep` | `#05224E` / `#031636` | text, dark surfaces, snack bars, hero gradient |
| `gold` | `#FEAF06` | tassel accent: role pill, FAB-adjacent highlights, snack action |
| `orange` | `#FE8B03` | fee/warning accents |
| `success` / `warning` / `error` | `#1E8E3E` / `#D97706` / `#D32F2F` | status colours (replaces raw `Colors.green/orange`) |
| Light surfaces | `#F4F8FD` bg, `#FFFFFF` cards, `#DDE6F2` borders | |
| Dark surfaces | `#06142C` bg, `#0C2244` cards, `#213B63` borders | |

## Plan and status
1. **Assets** — optimised brand PNGs in `assets/brand/` (720px lockups, 256px marks; originals were 1.2 MB);
   launcher icons regenerated for Android (mipmaps), iOS (App Icon set, alpha removed), web (favicon, 192/512, maskable).
   Manifest/theme colour updated. ✅
2. **Foundation** — explicit light/dark `ColorScheme` (not seed-generated), component themes for app bar, cards, buttons,
   inputs, chips, tabs, nav bar/rail, FAB, dialogs, sheets, data tables, snack bars, progress, switches. ✅
3. **Brand widgets** — `BrandLogo` / `BrandMark` (decode at display size, gapless, light/dark artwork), one-time precache. ✅
4. **Screens**
   - Sign in / register / reset password / account inactive → shared `AuthScaffold` (two-pane brand panel on wide
     screens, logo over card on phones). ✅
   - Splash → brand mark + progress. ✅
   - App shell → brand mark + title in the app bar; themed nav bar/rail. ✅
   - Dashboard → hero (gradient, role + school pills) and permission-filtered quick-access grid (lazy `SliverGrid`). ✅
   - Shared empty state, metric cards, status colours → tokens. ✅
   - All other screens inherit the theme (cards, buttons, inputs, tables, chips) — no per-screen colour literals remain
     outside `lib/core/theme` except PDF generation (print output, intentionally neutral).
5. **Performance** — no new packages / network fonts; system font; images pre-sized and decoded at display size;
   dashboard grid is lazy; theme objects are built once; no gradients/blur in scrolling lists.

## Applied to every screen (shared layers)
All routed pages sit inside the shell, so these apply app-wide without per-page edits:
- **Content frame** — pages are bounded to 1360px and top-centred on wide windows (full width on phones/tablets).
- **Data tables** (`ResponsiveDataList`, 13 screens) — bordered rounded surface, tinted header, row hover.
- **Empty / error states** (170 + 79 uses) — tinted-circle icon treatment.
- **Dialogs / sheets / menus / tooltips / segmented buttons / checkboxes / scrollbars** — themed.
- **Status colours** — success / warning / error tokens, no raw `Colors.*` outside PDFs.
- Verified by rendering login (desktop + dark mobile) and a table/empty/error screen to images during development.

## Not done
- Per-screen layout redesigns of the data-heavy lists/forms (they pick up colours/shape from the theme only).
- Android adaptive-icon layers and iOS dark/tinted icon variants (single opaque icon used).
- Branded PDFs (receipts, report cards) — still neutral greys.

# Milestone 8 — Timetable & Teacher Substitution

Status: implemented and verified as far as this environment allows. §13 lists what was **not** verified and the design limits — read §8 (what rules can and cannot enforce) before relying on this for safety.

## 1. What was assessed first (source is the truth)
| Area | Finding | How M8 uses it |
|---|---|---|
| Timetable / schedule | Nothing existed. No period, bell, room or schedule entity. | Built new, branch- and year-scoped. |
| Teacher ↔ class/subject | M4 `teacherAssignments` + `assignmentSlots/{year}__{class}__{section}__{subject}` (one ACTIVE teacher per section+subject, enforced atomically). | A timetable cell's teacher must be that slot's teacher — enforced in rules via the slot document. |
| Subjects, classes, sections | M2, year-scoped. | Cell subject choices = subjects with an ACTIVE assignment in the section. |
| Working days / holidays | M2 `WorkingDays` + holidays via `AttendanceCalendar`. | Days of a timetable must be working days; substitution periods skip holidays. |
| Staff leave | M7 `leaveCalendar` (approved only, minimal fields). | Read-only: affected periods, eligibility, re-validation. Leave records are never touched. |
| Rooms | **No room entity exists.** | Room is an optional free-text label with conflict detection on its normalised text (see §13). |
| Notifications | M7 in-app `notifications` collection. | Reused with four new event types. |
| RBAC | admins = `canManageStaff`; teachers; parents (linked children). | New permissions below. |

## 2. Features
Bell schedules (period sets) · versioned class/section timetables (DRAFT → PUBLISHED → ARCHIVED) · cell editor with copy-a-day and copy-to-another-section · validation with actionable messages · publication under a branch lock with replace/shorten of the version in force · withdraw/discard · date-specific teacher substitutions with eligibility explanation, change, cancel, reinstate and history · leave-aware affected periods and re-validation · class, teacher and personal timetables · conflict report · publication history · in-app notices.

## 3. Data model (all under `schools/{s}/branches/{b}/`)
| Collection | Id | Purpose |
|---|---|---|
| `periodSets` | `{yearId}__{slug}` | A named bell schedule: slots with **stable ids** (`s1`, `p2`…), kind (TEACHING / BREAK / LUNCH / ASSEMBLY / OTHER), label, start/end in **minutes since local midnight**. |
| `timetables` | `{yearId}__{classId}__{sectionId}__v{n}` | One version of one section's weekly schedule: weekday → period-set id, effective range, status, revision, publisher. |
| `timetableEntries` | `{timetableId}__{WEEKDAY}__{slotId}` | One teaching cell. Copies the slot's times, subject name and the teacher's **display name** so other classes' conflicts and teachers/parents (who cannot read staff documents) need no further reads. `live` mirrors "parent is PUBLISHED". |
| `timetableCounters` | `{yearId}__{classId}__{sectionId}` | Per-section version counter. |
| `timetableLocks/branch` | — | Publication lock: `publishSeq` bumped by every publish/withdraw. |
| `timetableHistory` | `{timetableId}__{revision}` | Append-only: who published / withdrew / replaced / shortened what. |
| `substitutions` | `{dateKey}__{timetableId}__{slotId}` | A date-specific cover. The id **is** (date, timetable, slot): one cover per slot per date by construction, retries idempotent. |
| `substitutionDays/{dateKey}` | — | Per-date sequence, bumped by every assign/change/cancel. |
| `substitutionHistory` | `{substitutionId}__{revision}` | Append-only. |
| `notifications` | `{timetableId|substitutionId}__{EVENT}__{rev}__{userId}` | Shared with M7. |

Relationships: `timetable 1—n entries`; `substitution → (timetable, entry)` by id; `entry → slot of a period set` by `slotId`; leave is referenced only by `leaveApplicationId` (never copied or modified).

**Times** are school-local wall-clock minutes: no timezone is attached, so a 09:00 period is at 09:00 for everyone and cannot shift with a device's timezone. **Dates** are civil `yyyy-MM-dd` keys plus UTC-midnight timestamps (same convention as attendance and leave).

## 4. Period configuration rules (`PeriodSet.validate`)
Name 2–40 chars · 1–20 slots · at least one teaching slot · stable unique slot ids · `0 ≤ start < end ≤ 24:00` · **no overlapping slots** (named in the message; back-to-back is fine) · teaching slots numbered 1..n in time order (the editor renumbers) · non-teaching slots need a label but **no subject or teacher**. A timetable maps each working weekday to a period set, so different days can follow different schedules. A published timetable is unaffected by later edits to a period set (cells hold their own times); a draft whose cells no longer match is flagged `STALE_PERIODS` until re-saved.

## 5. Versioning and publication
```
 createDraft (counter+1)                publish (lock bump)                 withdraw (lock bump)
 ───────────────► DRAFT ───────────────────────────────► PUBLISHED ───────────────────────► ARCHIVED
                    │  discard (no lock)                      │ ▲ shortened (TRUNCATED) by a later-starting version
                    └────────────────────────────► ARCHIVED   │ └ replaced outright (SUPERSEDED → ARCHIVED) by an earlier-starting one
```
- A **published or archived version is never edited** (rules refuse any cell/metadata change). A change is a new version, created with "New version from this" (copies cells to the same or another section).
- **What a new version does to the one in force** (computed by `TimetablePublication.planSupersession`, applied in the same transaction):
  - an older published version that **started earlier** keeps its cells and has only its **end date** set to the day before the new one starts (history `TRUNCATED`);
  - a version that **starts on or after** the new start is **replaced**: archived, its cells hidden (`SUPERSEDED`).
  Historical content is therefore never rewritten; "which version applies on date D" is `TimetableResolver` (the newest version whose range covers D).
- **Publication is atomic**: one transaction writes the lock bump, the new status, the cells' `live` flags, the history, any replaced/shortened versions and the notices. A failure leaves nothing partially published.
- **Withdrawing** a published version archives it and hides its cells; substitutions already made against it are flagged "timetable no longer in force" for review (they are not deleted).

## 6. Conflict detection (`TimetableValidator`)
| Check | Severity |
|---|---|
| Empty timetable | error |
| Weekday not a working day / not covered by the timetable / period set missing | error |
| Slot unknown, non-teaching, or times differ from the schedule | error |
| Teacher is not the ACTIVE assigned teacher for the subject in this section (or not active) | error |
| **Teacher double-booked**: same weekday, overlapping times, overlapping effective dates — inside the timetable and against every other published timetable. Message names teacher, day, period, time and the other class | error |
| **Room double-booked** (same normalised label) | error |
| Another published version of the *same* section overlaps (will be replaced/shortened) | warning |
| Teacher has approved leave on dates this timetable covers | warning ("those periods will need a substitute") |

The class/section can never have two simultaneous teaching periods: a cell is one document per (weekday, slot) and slots of one schedule cannot overlap. Different versions of the same section are not conflicts: publishing resolves them (above).

The editor runs the validator on every "Validate" and again inside "Publish"; `/timetable/conflicts` re-checks every draft and published version of the year against each other and against leave.

## 7. Substitutions
- **Affected periods**: `SubstitutionPlanner.affected` — a teacher's periods in a date range under the version in force on each date, school days only (holidays / non-working days dropped), with any existing cover attached.
- **Eligibility** (`candidates`): an ACTIVE teacher, not the person being replaced, *qualified* (teaches this subject in some section **or** teaches in this class), **no regular period overlapping that slot on that date** (a period already covered by someone else counts as free), no overlapping cover of their own, and no approved leave that date (half-day leave blocks the whole day). Ineligible people are listed with the reason. Results are ranked (teaches the subject → teaches the class → other) — **suggestions only: nothing is assigned until an administrator chooses and confirms**.
- **Writes**: one transaction per period under the date's sequence: day sequence bump, the substitution (create or reinstate), append-only history, notices to the substitute and the original teacher. The original timetable is never changed.
- **Eligibility is re-checked immediately before commit** against the date as it is then; a cover made by someone else meanwhile makes the commit fail (sequence mismatch) rather than double-book.
- **Change / cancel / reinstate** each need their history record and a day-sequence bump; cancel needs a reason; a cancelled cover can be reinstated (same id) with a new substitute.
- **Re-validation** (`SubstitutionHealth`, shown on the list, never auto-applied): leave no longer approved, substitute now on leave, timetable no longer in force, regular teacher changed.

## 8. What rules enforce — and what they cannot
Enforced by `firestore.rules` (21 emulator tests + a Dart-written-document contract test, mutation-checked):
- tenant/branch isolation; only managers create/edit/publish; parents/teachers read PUBLISHED data only; drafts, history, locks, counters, bell schedules are manager-only;
- the version comes from the section counter in the same commit (unique, increasing, no gaps skipped);
- the state machine and its history record on **every** change; revision +1;
- **every change to what is published bumps the branch lock by exactly one** in the same commit, so a validation done against an older published set cannot be committed after a newer publish — two concurrent publishes: exactly one commits (tested);
- cells only while the timetable is a DRAFT, and **each cell's teacher must be the section's ACTIVE assignment-slot holder for that subject**; `live` flips only with the parent's status change;
- replacing/shortening only by a newer PUBLISHED version of the **same section**;
- a substitution: live cell of a PUBLISHED timetable that covers the date, matching teacher/subject/class/section/times, substitute ≠ original and an ACTIVE teacher, one per slot per date (document id), day-sequence bump, history, notices tied to the event and writer.

**Not enforceable in rules (honest limits):**
1. **Teacher/room double-booking across timetables.** Rules cannot query the other timetables. It is verified by the client under the publication lock; the lock guarantees the verification was against the *current* published set, but an administrator using a modified client could skip validation and publish a conflicting timetable. Preventing that needs trusted backend execution (a Cloud Function that validates on publish), which this project does not have. `/timetable/conflicts` detects it after the fact.
2. **Substitute qualification, overlap and leave** are checked by the client under the day sequence, not by rules.
3. **That a date's weekday matches the cell's weekday** cannot be computed in rules.
4. **Parents**: rules cannot tie a parent to their child's section (that needs a lookup by child). Any ACTIVE parent of the school can read PUBLISHED schedule data (subject, times, teacher display name, active covers). The app shows only the linked child's section; the rules give parents no access to drafts, staff documents, leave, or anything private.
5. Client transactions do not protect against a malicious privileged client; the rules above are the real guard.

## 9. Leave integration (read-only)
Reads `leaveCalendar` staff entries. Shows "approved leave" beside teachers when arranging cover, excludes those on leave from candidates, warns during timetable validation, and re-validates existing covers when leave is cancelled or the substitute goes on leave. Leave approval and substitution are separate operations: nothing here edits a leave application, its history, or its balance, and covers are never created automatically.

## 10. Notifications
Reuses the M7 collection. `TIMETABLE_PUBLISHED` (to each affected teacher, written with the publish), `SUBSTITUTION_ASSIGNED` (also for a reinstated cover), `SUBSTITUTION_CHANGED`, `SUBSTITUTION_CANCELLED` (to the substitute and the original teacher). Notices carry class, subject, period, time and date — **never the leave reason**. Written in the same transaction as the event: a retry fails its precondition and writes none (no duplicates); rules tie type to the event, the writer to the manager, and the recipient to a user. In-app only; nothing is sent by email/SMS/WhatsApp. Teachers read them under the bell on "My timetable".

## 11. Indexes (5 new, 61 total)
`substitutions`: (substituteTeacherId, dateKey), (originalTeacherId, dateKey), (classId, sectionId, status, dateKey); `timetableHistory`: (academicYearId, at↓); `substitutionHistory`: (substitutionId, revision). All other queries are equality-only (merged automatically). **Not exercised by the emulator** — deploy and watch for "index required".

## 12. Screens (13 required, all present)
Timetable list · bell schedules · editor (day-by-day on phones, one column per day on desktop; copy day; validate; preview; publish with confirmation; discard/withdraw) · validation results (inline + conflict report) · publication confirmation (what it replaces, who is notified) · teacher timetable (admin) · class/section timetable · substitution list (health warnings, change, cancel, history dialog) · arrange cover (affected periods, candidates with reasons, preview, confirm) · my timetable (teacher: periods, covers, who covers theirs; parent: linked child's section with substitutes) · conflict report · publication history.

## 13. Tests and results
- Unit (`test/timetable/`, 55): period/time validation, effective dates and overlap, validator (assignment, double-booking incl. partial overlap/back-to-back/other weekday/disjoint dates, rooms, same-section versions, leave warnings), resolver and supersession (truncate vs replace, month/year ends), planner (affected periods, holidays, version in force, eligibility reasons, covered periods free their teacher, leave), health re-validation, copy-day / copy-to-section, Dart→rules contract export.
- Widget (`test/widget/timetable_ui_test.dart`, 39): route/permission matrix per role, list, draft creation validation, editor (offered subjects, save writes one cell, validate names the conflict, publish refused with errors, publish with confirmation, **concurrent publish refused**, published read-only), bell schedule validation, arrange-cover flow incl. suggestions-not-applied, ineligibility reasons, duplicate, concurrent date change, health flags, cancel with reason, teacher/parent views, 360/800/1400 px.
- Rules (`timetable-rules.test.mjs` 21, `timetable-contract.test.mjs` 1): see §8; **10 mutants all killed**.
- Bugs found by tests while building: a draft's cells could be made live by an "edit"; a new version could skip the counter; reading an auto-dispose provider imperatively could fail mid-load; a text controller was disposed while its dialog animated out; a busy bar animated behind a confirmation dialog; the phone "More" menu overflowed with the extra destinations (now scrolls); week navigation overflowed on narrow screens.
- Full: 669 Flutter tests, 193 rules tests (serial).

## 14. Deploy
`firebase deploy --only firestore:rules,firestore:indexes` (wait for indexes) → create bell schedules → create/publish timetables (teacher assignments must exist first) → substitutions. Run the rules suite with project id `demo-eazy-school-360`; regenerate `fixtures/timetable-write-plans.json` with `flutter test test/timetable/timetable_write_contract_test.dart` after changing what the Dart code writes.

## 15. Known limitations / not verified
1. No end-to-end run against a real Firebase project; the 5 indexes are unexercised.
2. §8 items 1–5: cross-timetable conflict-freeness and substitute checks are client-verified (under locks), not rules-enforced; parents are school-wide readers of published schedules.
3. **Room is a free-text label**, not an entity: no room master, no capacity, conflicts compare normalised text only.
4. No teacher *availability* configuration beyond approved leave, timetable and covers.
5. A cover is one whole period; no partial-period cover. Half-day leave blocks a candidate for the whole day.
6. A failed multi-step save/copy may leave a **draft** partially written (cells before metadata); published data is never affected.
7. A new timetable cannot be created for a section that is inactive; a timetable cannot span academic years.
8. Notices have no per-user "mark all read"; they appear under the "My timetable" bell and the leave notices screen.
9. iOS cannot be built here (iOS 26.5 platform not installed).
10. Disclosed: `dart format lib` also rewrapped three pre-existing files this milestone (`app_failure.dart`, `student.dart`, `firebase_parent_repository.dart`) — whitespace only — and M4's earlier format churn.

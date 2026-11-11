# Extra classes (a student in two classes)

For schools where a child attends one class in the morning (pre-school) and a
second in the afternoon (day care). The **main class is unchanged**; a student
can additionally belong to up to 3 **extra classes**, each in the same academic
year as the main class.

## Data
- `students/{id}.extraPlacements`: array of `{recordId, academicYearId, classId, sectionId, label, rollNumber}`
  and `extraPlacementKeys`: `["{year}|{class}", "{year}|{class}|{section}"]` per extra class — a **cache**,
  like `currentClassId`, so class lists can find extras (`array-contains`, no composite index).
- Source of truth: an ACTIVE `students/{id}/academicRecords/{recordId}` with `kind: "EXTRA"` and `label`.
  Attendance registers read these records, so an extra class has a register with no further change.
- Written by `StudentRepository.addExtraPlacement` / `removeExtraPlacement` (one transaction each);
  `ExtraPlacement.checkAdd` holds the rules (not the main class, one section per class, max 3, ≤30-char label).
  Removing closes the record (COMPLETED) and keeps it in the history.

## Behaviour
- **UI:** student profile → Academic tab → "Extra classes" (add / remove; needs `manageStudentData`).
- **Class lists:** `fetchStudentsByPlacement` appends the extra-class children after the main-class ones.
- **Fees:** `loadPlacementStudents` includes extra-class children, so billing a class bills them that class's
  fees on **their own invoice** (suffix key `…~2` when the main-class invoice for the period exists), carrying
  the extra class's name.
- **Main-class transfer / promotion:** leaves extras alone, except extras of a *different* academic year, which end.
- **Branch transfer:** refused while the student has extra classes (remove them first).
- **Rules:** only `extraPlacements` / `extraPlacementKeys` were added to the student update allow-list; extra
  records use the existing `academicRecords` rules. Tests: `firestore-tests/extra-classes-rules.test.mjs`.

## Phase 2 — access and parent screens
- **Student cache:** also `extraSectionKeys` (`classId__sectionId` per extra class), written with the other two fields.
- **Rules** (`firestore.rules`): `teacherOfStudent` and the student read rule also accept `extraSectionKeys`
  (helper `teacherHasAnyOf`), so the teacher of the day-care section can read the child and the guardian links.
  `studentInSection(student, classId, sectionId)` replaces the four "student is placed in this section" checks
  (homework submission create/change, marks entry, parent→teacher conversation), so a child can hand in the
  extra class's homework, have marks entered there, and message its teachers. Attendance and teacher scope
  were already judged on the record's own class/section.
- **Parent access index** (`parentAccess/{parentId}`): built from the main class **and** extras by
  `functions/provision.js` (`refreshParentAccess`), `ParentAccessKeys.forChildren` (app) and `diagnose.js`.
  `parent_access.js` treats an extras change as a placement change, so the trigger refreshes the family.
  This is what lets the rules show the extra class's homework, announcements, exams, results and timetable.
- **Parent screens:** homework (both classes' work together), announcements (viewer includes extra classes),
  results (exams of every class), timetable and new message (chips to pick the class: "Morning"/"Afternoon" label,
  else "Main class" / "Extra class n"). Exam rosters and results use the child's section and roll number **in
  the exam's class** (`Student.placementInClass`).
- **Unchanged on purpose:** leave requests stay with the main class; attendance reports, fee reports and the
  dashboard are not split by extra class.
- **Deploy order:** functions (index builder) → rules → app → then "Refresh parent access" (Parents) for families
  whose child already has an extra class, so their index is rebuilt.

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

## Not in this phase (Phase 2)
Teacher access in rules for the extra class's teachers, the parent-access index (Cloud Functions
`parent_access.js` / `provision.js`) and the parent screens (homework, results, timetable, announcements,
leave, messages) still use the main class only.

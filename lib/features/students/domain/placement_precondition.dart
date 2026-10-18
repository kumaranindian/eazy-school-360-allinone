/// What a placement change was based on (ACAD-7).
///
/// Moving a student to another class/section closes the active academic
/// record and opens a new one. Two admins doing it at once would each close the
/// record they saw and each open a new one: two ACTIVE records. The change runs
/// in a transaction that re-reads the student and refuses to go on when the
/// placement it was planned from is no longer the current one.
class PlacementPrecondition {
  final String? academicYearId;
  final String? classId;
  final String? sectionId;
  final Object? updatedAt;

  const PlacementPrecondition({
    this.academicYearId,
    this.classId,
    this.sectionId,
    this.updatedAt,
  });

  factory PlacementPrecondition.of(Map<String, dynamic>? student) =>
      PlacementPrecondition(
        academicYearId: student?['currentAcademicYearId'] as String?,
        classId: student?['currentClassId'] as String?,
        sectionId: student?['currentSectionId'] as String?,
        updatedAt: student?['updatedAt'],
      );

  /// True when [current] is still the state this change was planned from.
  bool holdsFor(PlacementPrecondition current) =>
      academicYearId == current.academicYearId &&
      classId == current.classId &&
      sectionId == current.sectionId &&
      updatedAt == current.updatedAt;
}

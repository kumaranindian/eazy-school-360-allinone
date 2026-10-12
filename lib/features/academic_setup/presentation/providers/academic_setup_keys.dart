/// Shared `family` key shapes for this feature's providers. Dart records
/// have structural equality/hashCode for free, which is exactly what
/// Riverpod's `.family` needs — these typedefs just name the shapes
/// consistently instead of each provider file inventing its own.
typedef BranchKey = ({String schoolId, String branchId});
typedef AcademicYearKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
});
typedef ClassKey = ({
  String schoolId,
  String branchId,
  String academicYearId,
  String classId,
});

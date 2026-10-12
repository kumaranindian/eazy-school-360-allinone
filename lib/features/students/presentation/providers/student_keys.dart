/// `.family` keys — Dart records give structural equality/hashCode for
/// free, same pattern as `academic_setup`'s `BranchKey`/`AcademicYearKey`.
typedef BranchKey = ({String schoolId, String branchId});
typedef StudentKey = ({String schoolId, String branchId, String studentId});
typedef ParentKey = ({String schoolId, String branchId, String parentId});

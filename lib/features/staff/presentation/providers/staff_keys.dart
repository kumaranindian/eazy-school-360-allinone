/// `.family` keys for the staff providers — Dart records give structural
/// equality/hashCode for free (same pattern as the other features).
/// `BranchKey` is reused from `academic_setup_keys.dart`.
typedef StaffKey = ({String schoolId, String branchId, String staffId});
typedef OwnStaffKey = ({String schoolId, String branchId, String userId});

/// Key for the directory headcounts: the branch, and whether to count only
/// staff flagged as teachers (the Teachers view) or everyone.
typedef StaffCountsKey = ({
  String schoolId,
  String branchId,
  bool teachersOnly,
});

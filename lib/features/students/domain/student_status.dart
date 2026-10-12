/// A student's lifecycle status. Students are never hard-deleted as a
/// normal business operation — fees, attendance, and reports depend on
/// historical student records remaining readable — so this status is the
/// only way a student leaves the "active roster" view.
enum StudentStatus {
  active,
  inactive,
  transferred,
  graduated,
  left;

  static const Map<StudentStatus, String> _wireValues = {
    StudentStatus.active: 'ACTIVE',
    StudentStatus.inactive: 'INACTIVE',
    StudentStatus.transferred: 'TRANSFERRED',
    StudentStatus.graduated: 'GRADUATED',
    StudentStatus.left: 'LEFT',
  };

  String get wireValue => _wireValues[this]!;

  static StudentStatus fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case StudentStatus.active:
        return 'Active';
      case StudentStatus.inactive:
        return 'Inactive';
      case StudentStatus.transferred:
        return 'Transferred';
      case StudentStatus.graduated:
        return 'Graduated';
      case StudentStatus.left:
        return 'Left';
    }
  }

  /// Whether this status still represents a student actively enrolled at
  /// the school — used to default list views to the "current roster".
  bool get isCurrentlyEnrolled => this == StudentStatus.active;
}

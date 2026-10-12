/// A single [StudentAcademicRecord]'s status. Exactly one record per
/// student should normally be [active] at a time — see
/// `docs/milestone-3-student-parent-management.md` → "Academic history
/// rule" for how a placement change keeps the old record instead of
/// overwriting it.
enum AcademicRecordStatus {
  active,
  completed,
  transferred,
  withdrawn;

  static const Map<AcademicRecordStatus, String> _wireValues = {
    AcademicRecordStatus.active: 'ACTIVE',
    AcademicRecordStatus.completed: 'COMPLETED',
    AcademicRecordStatus.transferred: 'TRANSFERRED',
    AcademicRecordStatus.withdrawn: 'WITHDRAWN',
  };

  String get wireValue => _wireValues[this]!;

  static AcademicRecordStatus fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case AcademicRecordStatus.active:
        return 'Active';
      case AcademicRecordStatus.completed:
        return 'Completed';
      case AcademicRecordStatus.transferred:
        return 'Transferred';
      case AcademicRecordStatus.withdrawn:
        return 'Withdrawn';
    }
  }
}

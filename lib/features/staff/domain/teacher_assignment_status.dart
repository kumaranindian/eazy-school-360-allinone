/// An assignment is ACTIVE while the teacher holds it, ENDED afterwards.
/// Ended assignments are kept forever as history — see
/// `docs/milestone-4-staff-teacher-management.md`.
enum TeacherAssignmentStatus {
  active,
  ended;

  static const Map<TeacherAssignmentStatus, String> _wireValues = {
    TeacherAssignmentStatus.active: 'ACTIVE',
    TeacherAssignmentStatus.ended: 'ENDED',
  };

  String get wireValue => _wireValues[this]!;

  static TeacherAssignmentStatus fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName =>
      this == TeacherAssignmentStatus.active ? 'Active' : 'Ended';
}

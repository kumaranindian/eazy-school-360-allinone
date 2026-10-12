/// Shared ACTIVE/INACTIVE status for simple configuration entities
/// (classes, sections, subjects, holidays) that don't need a richer
/// status model of their own — unlike [SchoolStatus] (ACTIVE/INACTIVE/
/// SUSPENDED) or `AcademicYearStatus` (DRAFT/ACTIVE/CLOSED), which carry
/// extra states and stay as their own types.
///
/// Soft-delete only: these entities are deactivated, never hard-deleted,
/// so historical records that reference them (sections referencing a
/// class, future attendance/marks referencing a subject) never orphan.
enum ActivationStatus {
  active,
  inactive;

  static const Map<ActivationStatus, String> _wireValues = {
    ActivationStatus.active: 'ACTIVE',
    ActivationStatus.inactive: 'INACTIVE',
  };

  String get wireValue => _wireValues[this]!;

  static ActivationStatus fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }
}

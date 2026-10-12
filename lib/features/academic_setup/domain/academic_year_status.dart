/// An academic year's lifecycle — distinct from [ActivationStatus] because
/// it has a third, meaningful state: a year can be prepared ahead of time
/// (`DRAFT`), become the operating year (`ACTIVE`), and later be sealed
/// against further changes once it's over (`CLOSED`) — history stays
/// readable, just not editable.
enum AcademicYearStatus {
  draft,
  active,
  closed;

  static const Map<AcademicYearStatus, String> _wireValues = {
    AcademicYearStatus.draft: 'DRAFT',
    AcademicYearStatus.active: 'ACTIVE',
    AcademicYearStatus.closed: 'CLOSED',
  };

  String get wireValue => _wireValues[this]!;

  static AcademicYearStatus fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case AcademicYearStatus.draft:
        return 'Draft';
      case AcademicYearStatus.active:
        return 'Active';
      case AcademicYearStatus.closed:
        return 'Closed';
    }
  }
}

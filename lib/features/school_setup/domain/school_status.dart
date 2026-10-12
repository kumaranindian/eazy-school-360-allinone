enum SchoolStatus {
  active,
  inactive,
  suspended;

  static const Map<SchoolStatus, String> _wireValues = {
    SchoolStatus.active: 'ACTIVE',
    SchoolStatus.inactive: 'INACTIVE',
    SchoolStatus.suspended: 'SUSPENDED',
  };

  String get wireValue => _wireValues[this]!;

  static SchoolStatus fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }
}

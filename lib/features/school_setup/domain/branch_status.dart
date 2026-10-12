enum BranchStatus {
  active,
  inactive;

  static const Map<BranchStatus, String> _wireValues = {
    BranchStatus.active: 'ACTIVE',
    BranchStatus.inactive: 'INACTIVE',
  };

  String get wireValue => _wireValues[this]!;

  static BranchStatus fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }
}

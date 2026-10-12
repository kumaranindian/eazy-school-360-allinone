/// How a staff member is employed. Informational for now — no payroll or
/// leave rule keys off it yet (those are future milestones).
enum EmploymentType {
  fullTime,
  partTime,
  contract,
  temporary,
  intern,
  other;

  static const Map<EmploymentType, String> _wireValues = {
    EmploymentType.fullTime: 'FULL_TIME',
    EmploymentType.partTime: 'PART_TIME',
    EmploymentType.contract: 'CONTRACT',
    EmploymentType.temporary: 'TEMPORARY',
    EmploymentType.intern: 'INTERN',
    EmploymentType.other: 'OTHER',
  };

  static const Map<EmploymentType, String> _displayNames = {
    EmploymentType.fullTime: 'Full time',
    EmploymentType.partTime: 'Part time',
    EmploymentType.contract: 'Contract',
    EmploymentType.temporary: 'Temporary',
    EmploymentType.intern: 'Intern',
    EmploymentType.other: 'Other',
  };

  String get wireValue => _wireValues[this]!;

  String get displayName => _displayNames[this]!;

  static EmploymentType fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }
}

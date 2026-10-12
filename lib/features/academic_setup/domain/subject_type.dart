enum SubjectType {
  core,
  elective,
  language,
  activity,
  other;

  static const Map<SubjectType, String> _wireValues = {
    SubjectType.core: 'CORE',
    SubjectType.elective: 'ELECTIVE',
    SubjectType.language: 'LANGUAGE',
    SubjectType.activity: 'ACTIVITY',
    SubjectType.other: 'OTHER',
  };

  String get wireValue => _wireValues[this]!;

  static SubjectType fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case SubjectType.core:
        return 'Core';
      case SubjectType.elective:
        return 'Elective';
      case SubjectType.language:
        return 'Language';
      case SubjectType.activity:
        return 'Activity';
      case SubjectType.other:
        return 'Other';
    }
  }
}

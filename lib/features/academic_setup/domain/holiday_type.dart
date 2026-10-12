enum HolidayType {
  public,
  school,
  local,
  special,

  /// Not a holiday: marks a normally non-working date (e.g. a Saturday) as
  /// a working day for this branch — the "special working day" attendance
  /// needs. Added in Milestone 5; see docs/milestone-5-attendance-management.md.
  specialWorkingDay;

  static const Map<HolidayType, String> _wireValues = {
    HolidayType.public: 'PUBLIC',
    HolidayType.school: 'SCHOOL',
    HolidayType.local: 'LOCAL',
    HolidayType.special: 'SPECIAL',
    HolidayType.specialWorkingDay: 'SPECIAL_WORKING_DAY',
  };

  String get wireValue => _wireValues[this]!;

  static HolidayType fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case HolidayType.public:
        return 'Public';
      case HolidayType.school:
        return 'School';
      case HolidayType.local:
        return 'Local';
      case HolidayType.special:
        return 'Special';
      case HolidayType.specialWorkingDay:
        return 'Special working day';
    }
  }
}

enum HolidayType {
  public,
  festival,
  school,
  vacation,
  other,

  /// Older entries; still read and shown, kept so existing calendars load.
  local,
  special,

  /// Not a holiday: marks a normally non-working date (e.g. a Saturday) as
  /// a working day for this branch — the "special working day" attendance
  /// needs. Added in Milestone 5; see docs/milestone-5-attendance-management.md.
  specialWorkingDay;

  static const Map<HolidayType, String> _wireValues = {
    HolidayType.public: 'PUBLIC',
    HolidayType.festival: 'FESTIVAL',
    HolidayType.school: 'SCHOOL',
    HolidayType.vacation: 'VACATION',
    HolidayType.other: 'OTHER',
    HolidayType.local: 'LOCAL',
    HolidayType.special: 'SPECIAL',
    HolidayType.specialWorkingDay: 'SPECIAL_WORKING_DAY',
  };

  String get wireValue => _wireValues[this]!;

  static HolidayType fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  /// Whether the type closes the school (everything but a special working day).
  bool get closesSchool => this != HolidayType.specialWorkingDay;

  /// Which label wins when several holidays cover one date: the lowest first.
  int get precedence => switch (this) {
    HolidayType.public => 0,
    HolidayType.festival => 1,
    HolidayType.school => 2,
    HolidayType.vacation => 3,
    HolidayType.local => 4,
    HolidayType.special => 5,
    HolidayType.other => 6,
    HolidayType.specialWorkingDay => 7,
  };

  String get displayName {
    switch (this) {
      case HolidayType.public:
        return 'Public holiday';
      case HolidayType.festival:
        return 'Festival';
      case HolidayType.school:
        return 'School holiday';
      case HolidayType.vacation:
        return 'Vacation';
      case HolidayType.other:
        return 'Other';
      case HolidayType.local:
        return 'Local';
      case HolidayType.special:
        return 'Special';
      case HolidayType.specialWorkingDay:
        return 'Special working day';
    }
  }
}

/// A week has seven days regardless of which ones a given branch treats
/// as working days — this enum is the full set; [WorkingDays] decides
/// which are on.
enum Weekday {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday;

  static const Map<Weekday, String> _wireValues = {
    Weekday.monday: 'MONDAY',
    Weekday.tuesday: 'TUESDAY',
    Weekday.wednesday: 'WEDNESDAY',
    Weekday.thursday: 'THURSDAY',
    Weekday.friday: 'FRIDAY',
    Weekday.saturday: 'SATURDAY',
    Weekday.sunday: 'SUNDAY',
  };

  String get wireValue => _wireValues[this]!;

  static Weekday fromWireValue(String value) {
    return _wireValues.entries.firstWhere((e) => e.value == value).key;
  }

  String get displayName {
    switch (this) {
      case Weekday.monday:
        return 'Monday';
      case Weekday.tuesday:
        return 'Tuesday';
      case Weekday.wednesday:
        return 'Wednesday';
      case Weekday.thursday:
        return 'Thursday';
      case Weekday.friday:
        return 'Friday';
      case Weekday.saturday:
        return 'Saturday';
      case Weekday.sunday:
        return 'Sunday';
    }
  }

  /// Maps from `DateTime.weekday` (1 = Monday ... 7 = Sunday).
  static Weekday fromDateTimeWeekday(int dateTimeWeekday) =>
      Weekday.values[dateTimeWeekday - 1];
}

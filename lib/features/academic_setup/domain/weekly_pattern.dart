import 'weekday.dart';

/// How a branch treats Saturdays. Always *derived* from a [WeeklyPattern]
/// (the Saturday flag plus its off-weeks) so it can never contradict the data.
enum SaturdayPolicy {
  /// Every Saturday is a working day.
  allWorking,

  /// Every Saturday is a holiday.
  allOff,

  /// The 1st, 3rd and 5th Saturdays are holidays.
  alternateOdd,

  /// The 2nd and 4th Saturdays are holidays.
  alternateEven,

  /// Any other combination of the 1st-5th Saturdays.
  selected;

  String get displayName => switch (this) {
    SaturdayPolicy.allWorking => 'No Saturday holidays',
    SaturdayPolicy.allOff => 'Every Saturday is a holiday',
    SaturdayPolicy.alternateOdd => 'Alternate Saturdays (1st, 3rd, 5th)',
    SaturdayPolicy.alternateEven => 'Alternate Saturdays (2nd, 4th)',
    SaturdayPolicy.selected => 'Selected Saturdays',
  };
}

/// The weekly rhythm of a branch at one point in time: which weekdays are
/// working days and, when Saturday is a working day, which Saturdays of the
/// month are still holidays.
///
/// Pure value type. It works on **civil dates** (the year/month/day fields of
/// the [DateTime] it is given) and never converts time zones, so a Saturday
/// can not shift to Friday or Sunday because of UTC.
class WeeklyPattern {
  /// A day is stored for every [Weekday].
  final Map<Weekday, bool> isWorkingDay;

  /// 1..5. Only meaningful while Saturday is a working day; ignored when every
  /// Saturday is already a holiday.
  final Set<int> saturdayOffWeeks;

  /// `yyyy-MM-dd`: the first date this pattern applies from. Null means
  /// "since always" (the pattern that existed before dating was introduced).
  final String? effectiveFrom;

  const WeeklyPattern({
    required this.isWorkingDay,
    this.saturdayOffWeeks = const {},
    this.effectiveFrom,
  });

  /// The occurrence of a weekday in its month, from the **day of month**:
  /// 1-7 -> 1st, 8-14 -> 2nd, 15-21 -> 3rd, 22-28 -> 4th, 29-31 -> 5th.
  static int occurrenceInMonth(DateTime date) => ((date.day - 1) ~/ 7) + 1;

  static String ordinal(int n) => switch (n) {
    1 => '1st',
    2 => '2nd',
    3 => '3rd',
    _ => '${n}th',
  };

  SaturdayPolicy get saturdayPolicy {
    if (!(isWorkingDay[Weekday.saturday] ?? true)) return SaturdayPolicy.allOff;
    final weeks = saturdayOffWeeks;
    if (weeks.isEmpty) return SaturdayPolicy.allWorking;
    if (weeks.length == 3 && weeks.containsAll(const [1, 3, 5])) {
      return SaturdayPolicy.alternateOdd;
    }
    if (weeks.length == 2 && weeks.containsAll(const [2, 4])) {
      return SaturdayPolicy.alternateEven;
    }
    return SaturdayPolicy.selected;
  }

  /// Why [date] is a weekly off, or null when the pattern makes it a working
  /// day. A 5th-Saturday rule only fires in months that have one, because the
  /// occurrence comes from the real day of month.
  String? weeklyOffLabel(DateTime date) {
    final weekday = Weekday.fromDateTimeWeekday(date.weekday);
    if (!(isWorkingDay[weekday] ?? true)) {
      return weekday == Weekday.saturday ? 'Saturday' : weekday.displayName;
    }
    if (weekday == Weekday.saturday) {
      final n = occurrenceInMonth(date);
      if (saturdayOffWeeks.contains(n)) return '${ordinal(n)} Saturday';
    }
    return null;
  }

  bool isWeeklyOff(DateTime date) => weeklyOffLabel(date) != null;

  /// "Sunday, 2nd & 4th Saturday" — the rule in words, for the settings page.
  String get summary {
    final parts = <String>[];
    for (final d in Weekday.values) {
      if (d == Weekday.saturday) continue;
      if (!(isWorkingDay[d] ?? true)) parts.add(d.displayName);
    }
    switch (saturdayPolicy) {
      case SaturdayPolicy.allWorking:
        break;
      case SaturdayPolicy.allOff:
        parts.add('Every Saturday');
      case SaturdayPolicy.alternateOdd:
      case SaturdayPolicy.alternateEven:
      case SaturdayPolicy.selected:
        final weeks = (saturdayOffWeeks.toList()..sort());
        parts.add('${weeks.map(ordinal).join(', ')} Saturday');
    }
    return parts.isEmpty ? 'No weekly offs' : parts.join(' · ');
  }

  WeeklyPattern copyWith({
    Map<Weekday, bool>? isWorkingDay,
    Set<int>? saturdayOffWeeks,
    String? effectiveFrom,
    bool clearEffectiveFrom = false,
  }) => WeeklyPattern(
    isWorkingDay: isWorkingDay ?? this.isWorkingDay,
    saturdayOffWeeks: saturdayOffWeeks ?? this.saturdayOffWeeks,
    effectiveFrom: clearEffectiveFrom
        ? null
        : (effectiveFrom ?? this.effectiveFrom),
  );

  /// Same weekly rhythm, ignoring the effective date.
  bool sameRhythmAs(WeeklyPattern other) {
    for (final d in Weekday.values) {
      if ((isWorkingDay[d] ?? true) != (other.isWorkingDay[d] ?? true)) {
        return false;
      }
    }
    return saturdayOffWeeks.length == other.saturdayOffWeeks.length &&
        saturdayOffWeeks.containsAll(other.saturdayOffWeeks);
  }

  Map<String, dynamic> toMap() => {
    'effectiveFrom': effectiveFrom,
    'isWorkingDay': {
      for (final d in Weekday.values) d.wireValue: isWorkingDay[d] ?? true,
    },
    'saturdayOffWeeks': (saturdayOffWeeks.toList()..sort()),
  };

  factory WeeklyPattern.fromMap(
    Map<String, dynamic> data, {
    required Map<Weekday, bool> fallback,
  }) {
    final raw = (data['isWorkingDay'] as Map?)?.cast<String, dynamic>() ?? {};
    final weeks = <int>{
      for (final w in (data['saturdayOffWeeks'] as List? ?? const []))
        if (w is num && w >= 1 && w <= 5) w.toInt(),
    };
    return WeeklyPattern(
      isWorkingDay: {
        for (final d in Weekday.values)
          d: raw[d.wireValue] as bool? ?? fallback[d]!,
      },
      saturdayOffWeeks: weeks,
      effectiveFrom: data['effectiveFrom'] as String?,
    );
  }
}

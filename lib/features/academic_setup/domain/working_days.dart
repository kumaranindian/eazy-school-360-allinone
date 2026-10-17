import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_fields.dart';
import 'weekday.dart';
import 'weekly_pattern.dart';

/// The `.../branches/{branchId}/settings/workingDays` singleton document.
/// One document per branch (not per academic year — a branch's weekly
/// pattern rarely changes year to year), holding a working/holiday flag per
/// [Weekday] so every day is represented explicitly — never an assumed
/// Mon-Fri default.
///
/// **Saturday patterns.** [saturdayOffWeeks] lists which Saturdays of the month
/// (1st-5th) are holidays while Saturday is otherwise a working day; "every
/// Saturday" is simply Saturday switched off.
///
/// **Effective dating.** The top-level fields are the *current* pattern and
/// apply from [effectiveFrom] (`yyyy-MM-dd`, null = always). Earlier patterns
/// are kept in [history], so changing the weekly offs never rewrites how an
/// earlier date is judged (attendance, leave counting). [patternFor] picks the
/// pattern in force on a date.
class WorkingDays {
  /// Versions kept in [history]; the oldest are dropped past this.
  static const int maxHistory = 12;

  final String schoolId;
  final String branchId;
  final Map<Weekday, bool> isWorkingDay;
  final Set<int> saturdayOffWeeks;
  final String? effectiveFrom;

  /// Patterns that applied before the current one, oldest first.
  final List<WeeklyPattern> history;
  final DateTime? updatedAt;
  final String? updatedBy;

  const WorkingDays({
    required this.schoolId,
    required this.branchId,
    required this.isWorkingDay,
    this.saturdayOffWeeks = const {},
    this.effectiveFrom,
    this.history = const [],
    this.updatedAt,
    this.updatedBy,
  });

  static Map<Weekday, bool> defaultPattern() => {
    for (final day in Weekday.values)
      day: day != Weekday.saturday && day != Weekday.sunday,
  };

  factory WorkingDays.defaults({
    required String schoolId,
    required String branchId,
  }) {
    return WorkingDays(
      schoolId: schoolId,
      branchId: branchId,
      isWorkingDay: defaultPattern(),
    );
  }

  /// The current pattern as a value.
  WeeklyPattern get current => WeeklyPattern(
    isWorkingDay: isWorkingDay,
    saturdayOffWeeks: saturdayOffWeeks,
    effectiveFrom: effectiveFrom,
  );

  SaturdayPolicy get saturdayPolicy => current.saturdayPolicy;

  /// `yyyy-MM-dd` of a civil date (its own fields, no time-zone conversion).
  static String keyOf(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// The pattern in force on [date]: the latest one whose effective date is on
  /// or before it. A date before every recorded pattern uses the oldest one.
  WeeklyPattern patternFor(DateTime date) {
    final key = keyOf(date);
    final from = effectiveFrom;
    if (from == null || key.compareTo(from) >= 0) return current;
    WeeklyPattern? best;
    for (final p in history) {
      final f = p.effectiveFrom;
      if (f == null || key.compareTo(f) >= 0) {
        if (best == null ||
            best.effectiveFrom == null ||
            (f != null && f.compareTo(best.effectiveFrom!) >= 0)) {
          best = p;
        }
      }
    }
    return best ?? (history.isNotEmpty ? history.first : current);
  }

  /// Why [date] is a weekly off under the pattern then in force, or null.
  String? weeklyOffLabel(DateTime date) =>
      patternFor(date).weeklyOffLabel(date);

  /// Changes one weekday's flag in the current pattern (settings-page edit).
  WorkingDays copyWith(Weekday day, bool isWorking) =>
      _with(isWorkingDay: {...isWorkingDay, day: isWorking});

  /// Replaces the Saturday off-weeks of the current pattern.
  WorkingDays withSaturdayOffWeeks(Set<int> weeks) =>
      _with(saturdayOffWeeks: {...weeks});

  WorkingDays _with({
    Map<Weekday, bool>? isWorkingDay,
    Set<int>? saturdayOffWeeks,
    String? effectiveFrom,
    bool clearEffectiveFrom = false,
    List<WeeklyPattern>? history,
  }) => WorkingDays(
    schoolId: schoolId,
    branchId: branchId,
    isWorkingDay: isWorkingDay ?? this.isWorkingDay,
    saturdayOffWeeks: saturdayOffWeeks ?? this.saturdayOffWeeks,
    effectiveFrom: clearEffectiveFrom
        ? null
        : (effectiveFrom ?? this.effectiveFrom),
    history: history ?? this.history,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
  );

  /// Why [candidate] (an `effectiveFrom`, or null for "always") cannot be
  /// used for a new pattern, or null if it can. A new pattern may not start
  /// before the current one: that would silently re-date days that are
  /// already judged by it.
  String? checkEffectiveFrom(String? candidate) {
    if (candidate == null) {
      return effectiveFrom == null && history.isEmpty
          ? null
          : 'Choose the date the new weekly offs start from.';
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(candidate)) {
      return 'Choose a valid start date.';
    }
    final from = effectiveFrom;
    if (from != null && candidate.compareTo(from) < 0) {
      return 'The new weekly offs cannot start before the current ones '
          '($from). Earlier dates keep the pattern they already had.';
    }
    return null;
  }

  /// The configuration after the admin saves [pattern] (its flags and
  /// off-weeks) with the given start date. Earlier dates keep the pattern
  /// they had: the current one moves to [history] — unless the dates are the
  /// same, in which case it is a correction and replaces it in place.
  ///
  /// The first save of a branch that has never been configured applies from
  /// the start of time, as today's behaviour always has.
  WorkingDays scheduleChange({
    required Map<Weekday, bool> pattern,
    required Set<int> saturdayOffWeeks,
    required String? startsOn,
    required bool configuredBefore,
  }) {
    final next = WeeklyPattern(
      isWorkingDay: {...pattern},
      saturdayOffWeeks: {...saturdayOffWeeks},
      effectiveFrom: configuredBefore ? startsOn : null,
    );
    final sameStart = next.effectiveFrom == effectiveFrom;
    final kept = <WeeklyPattern>[
      ...history,
      if (configuredBefore && !sameStart) current,
    ];
    final trimmed = kept.length > maxHistory
        ? kept.sublist(kept.length - maxHistory)
        : kept;
    return WorkingDays(
      schoolId: schoolId,
      branchId: branchId,
      isWorkingDay: next.isWorkingDay,
      saturdayOffWeeks: next.saturdayOffWeeks,
      effectiveFrom: next.effectiveFrom,
      history: trimmed,
      updatedAt: updatedAt,
      updatedBy: updatedBy,
    );
  }

  factory WorkingDays.fromFirestore(
    String schoolId,
    String branchId,
    Map<String, dynamic> data,
  ) {
    final raw = (data['isWorkingDay'] as Map<String, dynamic>?) ?? const {};
    final defaults = defaultPattern();
    return WorkingDays(
      schoolId: schoolId,
      branchId: branchId,
      isWorkingDay: {
        for (final day in Weekday.values)
          day: raw[day.wireValue] as bool? ?? defaults[day]!,
      },
      saturdayOffWeeks: {
        for (final w in (data['saturdayOffWeeks'] as List? ?? const []))
          if (w is num && w >= 1 && w <= 5) w.toInt(),
      },
      effectiveFrom: data['effectiveFrom'] as String?,
      history: [
        for (final h in (data['history'] as List? ?? const []))
          if (h is Map)
            WeeklyPattern.fromMap(
              h.cast<String, dynamic>(),
              fallback: defaults,
            ),
      ],
      updatedAt: (data[FirestoreFields.updatedAt] as Timestamp?)?.toDate(),
      updatedBy: data[FirestoreFields.updatedBy] as String?,
    );
  }

  Map<String, dynamic> toFirestore({required String updatedBy}) {
    return {
      FirestoreFields.schoolId: schoolId,
      FirestoreFields.branchId: branchId,
      'isWorkingDay': {
        for (final entry in isWorkingDay.entries)
          entry.key.wireValue: entry.value,
      },
      'saturdayOffWeeks': (saturdayOffWeeks.toList()..sort()),
      'effectiveFrom': effectiveFrom,
      'history': [for (final p in history) p.toMap()],
      FirestoreFields.updatedAt: FieldValue.serverTimestamp(),
      FirestoreFields.updatedBy: updatedBy,
    };
  }
}

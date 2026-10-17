import '../../../core/constants/activation_status.dart';
import 'holiday.dart';

/// Pure checks for the holiday calendar, so the dialog, the page and the tests
/// agree on what counts as a duplicate, an overlap or a bad range.
abstract final class HolidayRules {
  /// The longest vacation one entry may cover (a year, plus a leap day).
  static const int maxDays = 366;

  /// Why the range is not acceptable, or null.
  static String? checkRange(DateTime start, DateTime? end) {
    if (end == null) return null;
    final s = DateTime.utc(start.year, start.month, start.day);
    final e = DateTime.utc(end.year, end.month, end.day);
    if (e.isBefore(s)) return 'The last day cannot be before the first day.';
    if (e.difference(s).inDays + 1 > maxDays) {
      return 'A holiday can cover at most $maxDays days.';
    }
    return null;
  }

  static String normalizeName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// An accidental duplicate: the same name starting on the same day. The
  /// record being edited ([candidate]'s own id) is never its own duplicate.
  static Holiday? duplicateOf(Holiday candidate, Iterable<Holiday> existing) {
    for (final h in existing) {
      if (h.holidayId == candidate.holidayId) continue;
      if (normalizeName(h.name) == normalizeName(candidate.name) &&
          h.date.toUtc().year == candidate.date.year &&
          h.date.toUtc().month == candidate.date.month &&
          h.date.toUtc().day == candidate.date.day) {
        return h;
      }
    }
    return null;
  }

  /// Other ACTIVE entries whose days overlap [candidate]. Overlap is allowed
  /// (a festival inside a vacation is real) but must be shown, never silent.
  static List<Holiday> overlapping(
    Holiday candidate,
    Iterable<Holiday> existing,
  ) => [
    for (final h in existing)
      if (h.holidayId != candidate.holidayId &&
          h.status == ActivationStatus.active &&
          h.overlaps(candidate))
        h,
  ];

  /// The deterministic order labels are chosen in when several entries cover a
  /// date: by type precedence, then the earlier start, then name. The records
  /// themselves are never merged or dropped.
  static int compareForLabel(Holiday a, Holiday b) {
    final byType = a.type.precedence.compareTo(b.type.precedence);
    if (byType != 0) return byType;
    final byStart = a.date.compareTo(b.date);
    if (byStart != 0) return byStart;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Attendance dates are *civil dates*, not instants, so they are stored two
/// ways: a `yyyy-MM-dd` string ([key]) that queries, document ids and range
/// filters use (lexicographic order == chronological order, no timezone
/// involved), and a UTC-midnight [Timestamp] for display/interop — the same
/// normalisation `Holiday.normalizeDate` uses.
abstract final class AttendanceDate {
  static String _two(int n) => n.toString().padLeft(2, '0');

  /// The date key for the civil date of [date] (its own year/month/day
  /// fields, no timezone conversion).
  static String key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

  static final RegExp keyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Midnight UTC of the key's date.
  static DateTime parse(String key) {
    final parts = key.split('-');
    return DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static Timestamp timestampFor(String key) => Timestamp.fromDate(parse(key));

  /// A plain local-midnight date with no time part.
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String firstOfMonthKey(int year, int month) =>
      key(DateTime(year, month, 1));

  static String lastOfMonthKey(int year, int month) =>
      key(DateTime(year, month + 1, 0));

  /// Every date key from [fromKey] to [toKey] inclusive.
  static List<String> keysBetween(String fromKey, String toKey) {
    final result = <String>[];
    var day = parse(fromKey);
    final end = parse(toKey);
    while (!day.isAfter(end)) {
      result.add(key(day));
      day = DateTime.utc(day.year, day.month, day.day + 1);
    }
    return result;
  }

  static int compareKeys(String a, String b) => a.compareTo(b);
}

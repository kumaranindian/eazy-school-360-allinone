import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import 'regional_settings.dart';
import 'time_zones.dart';

/// The school's time zone and date format, available to plain functions and
/// domain code that have no `ref`.
///
/// It is set from the signed-in school's regional settings (see `app.dart`)
/// and cleared at sign-out. Until then (tests, the login screen) everything
/// behaves exactly as before: the device's own zone and `dd/MM/yyyy`.
///
/// Three kinds of time are kept apart:
/// * **civil dates** (`yyyy-MM-dd` keys, UTC-midnight stamps): which school
///   day something belongs to - [todayKey], [today];
/// * **instants** (deadlines, publish times, audit stamps): a real moment,
///   compared with `DateTime.now()` as usual, but *shown* and *entered* in the
///   school's zone - [formatInstant], [instantFromWall];
/// * **wall clock** ([wallNow]): the school's current date and time as
///   year/month/day/hour fields in a plain `DateTime`, so existing code that
///   reads `.year`, `.month`, `.day` keeps working.
abstract final class SchoolTime {
  static RegionalSettings? _settings;
  static tz.Location? _location;

  /// Replaced in tests to freeze time.
  static DateTime Function() utcNow = () => DateTime.now().toUtc();

  static void use(RegionalSettings settings) {
    _settings = settings;
    _location = TimeZones.location(settings.timezone);
  }

  static void reset() {
    _settings = null;
    _location = null;
    utcNow = () => DateTime.now().toUtc();
  }

  static bool get isActive => _settings != null;
  static String? get timezone => _settings?.timezone;
  static String get dateFormat => _settings?.dateFormat ?? 'dd/MM/yyyy';

  /// The school's current wall-clock time as a plain `DateTime`.
  static DateTime wallNow() {
    final loc = _location;
    if (loc == null) return DateTime.now();
    final t = tz.TZDateTime.from(utcNow(), loc);
    return DateTime(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute,
      t.second,
      t.millisecond,
    );
  }

  /// Today's date (no time part) in the school's zone.
  static DateTime today() {
    final n = wallNow();
    return DateTime(n.year, n.month, n.day);
  }

  /// Today's `yyyy-MM-dd` in the school's zone.
  static String todayKey() => keyOf(today());

  static String keyOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// The wall-clock fields of [instant] in the school's zone.
  static DateTime wallOf(DateTime instant) {
    final loc = _location;
    if (loc == null) return instant.toLocal();
    final t = tz.TZDateTime.from(instant.toUtc(), loc);
    return DateTime(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute,
      t.second,
      t.millisecond,
    );
  }

  /// The real moment a school wall-clock time (as picked on screen) denotes.
  static DateTime instantFromWall(DateTime wall) {
    final loc = _location;
    if (loc == null) return wall;
    return tz.TZDateTime(
      loc,
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
      wall.millisecond,
    ).toUtc();
  }

  /// A civil date as the school writes it (its date-format setting).
  static String formatDate(DateTime date) =>
      DateFormat(dateFormat).format(date);

  /// A `yyyy-MM-dd` key as the school writes it.
  static String formatKey(String key) {
    final p = key.split('-');
    if (p.length != 3) return key;
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return key;
    return formatDate(DateTime(y, m, d));
  }

  /// An instant as "3 Aug 2026, 4:05 PM" in the school's zone.
  static String formatInstant(DateTime at) =>
      DateFormat('d MMM y, h:mm a').format(wallOf(at));
}

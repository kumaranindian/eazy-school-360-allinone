import 'package:timezone/timezone.dart' as tz;

import 'time_zones.dart';

/// "Now" and "today" as the school lives them (ADR: school time, not the
/// device's). A parent travelling abroad, or an admin whose laptop is set to
/// another zone, still sees the school's day: attendance for "today", a fee
/// due "today", a homework deadline that has "passed".
///
/// Civil dates (`yyyy-MM-dd`) stay the app's currency for days; this class
/// only decides *which* civil date an instant belongs to.
class SchoolClock {
  final String timezone;
  final tz.Location location;
  final DateTime Function() _utcNow;

  SchoolClock(this.timezone, {DateTime Function()? utcNow})
    : location = TimeZones.location(timezone),
      _utcNow = utcNow ?? (() => DateTime.now().toUtc());

  /// The current wall-clock time in the school's zone.
  tz.TZDateTime now() => tz.TZDateTime.from(_utcNow().toUtc(), location);

  /// An instant as wall-clock time in the school's zone.
  tz.TZDateTime inSchoolZone(DateTime instant) =>
      tz.TZDateTime.from(instant.toUtc(), location);

  /// Today's civil date key.
  String todayKey() => keyOf(_utcNow());

  /// The civil date key of [instant] in the school's zone.
  String keyOf(DateTime instant) {
    final t = inSchoolZone(instant);
    return '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  /// Today's civil date as UTC midnight (the app's stored form for a date).
  DateTime today() {
    final t = now();
    return DateTime.utc(t.year, t.month, t.day);
  }

  /// The instant a civil day starts in the school's zone.
  DateTime startOfDay(String key) {
    final p = key.split('-').map(int.parse).toList();
    return tz.TZDateTime(location, p[0], p[1], p[2]).toUtc();
  }

  /// Whether the school's local date has reached [key] (e.g. a due date).
  bool isOnOrAfter(String key) => todayKey().compareTo(key) >= 0;
}

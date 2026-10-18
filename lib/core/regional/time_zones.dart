import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The IANA time zone database, loaded once. All school-time arithmetic goes
/// through here so it is identical on every device whatever its own zone is.
abstract final class TimeZones {
  static bool _ready = false;

  static void ensureInitialized() {
    if (_ready) return;
    tzdata.initializeTimeZones();
    _ready = true;
  }

  static bool isKnown(String name) {
    ensureInitialized();
    try {
      tz.getLocation(name);
      return true;
    } catch (_) {
      return false;
    }
  }

  static tz.Location location(String name) {
    ensureInitialized();
    try {
      return tz.getLocation(name);
    } catch (_) {
      return tz.getLocation('UTC');
    }
  }

  /// "UTC+05:30" for [name] at [at] (now by default), for pickers.
  static String offsetLabel(String name, [DateTime? at]) {
    final t = tz.TZDateTime.from(at ?? DateTime.now().toUtc(), location(name));
    final o = t.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final abs = o.abs();
    final h = abs.inHours.toString().padLeft(2, '0');
    final m = (abs.inMinutes % 60).toString().padLeft(2, '0');
    return 'UTC$sign$h:$m';
  }
}

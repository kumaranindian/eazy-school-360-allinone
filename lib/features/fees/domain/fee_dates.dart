import '../../../core/regional/school_time.dart';
import '../../attendance/domain/attendance_date.dart';

/// Civil dates as `yyyy-MM-dd` keys (the same convention attendance uses), so
/// due-date comparisons and ranges involve no timezone arithmetic.
abstract final class FeeDates {
  /// Today in the **school's** time zone (Regional settings).
  static String todayKey([DateTime? now]) =>
      AttendanceDate.key(now ?? SchoolTime.wallNow());

  static String addDays(String key, int days) {
    final d = AttendanceDate.parse(key);
    return AttendanceDate.key(DateTime.utc(d.year, d.month, d.day + days));
  }

  /// A date key in the school's date format ("10/06/2026" by default).
  static String display(String key) {
    if (!AttendanceDate.keyPattern.hasMatch(key)) return key;
    return SchoolTime.formatKey(key);
  }
}

/// Invoice and receipt numbers: `INV-2026-000123`, `RCT-2026-000045` — the
/// prefix, the academic year's starting year, and a zero-padded sequence per
/// branch per year. Sequences come from `feeCounters` and each number is
/// reserved by a unique document; see the milestone doc for the guarantees
/// (unique and increasing, but gaps are possible).
abstract final class FeeNumbers {
  static String invoice(int startYear, int seq) =>
      'INV-$startYear-${seq.toString().padLeft(6, '0')}';

  static String receipt(int startYear, int seq) =>
      'RCT-$startYear-${seq.toString().padLeft(6, '0')}';

  static String counterId(String kind, String academicYearId) =>
      '${kind}_$academicYearId';
}

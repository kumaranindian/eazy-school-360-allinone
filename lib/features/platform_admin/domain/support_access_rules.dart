/// Limits of a support session. Mirrored on the server
/// (`functions/support_access.js`), which is what enforces them.
abstract final class SupportAccessRules {
  static const List<int> minutes = [15, 30, 60, 120, 240];
  static const int defaultMinutes = 60;
  static const int reasonMin = 15;
  static const int reasonMax = 500;
  static const int ticketMax = 60;

  static String? validateReason(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Say why you need access';
    if (v.length < reasonMin) {
      return 'Give a little more detail (at least $reasonMin characters)';
    }
    if (v.length > reasonMax) return 'Keep it under $reasonMax characters';
    return null;
  }

  static String durationLabel(int minutes) => minutes < 60
      ? '$minutes minutes'
      : '${minutes ~/ 60} hour${minutes == 60 ? '' : 's'}';
}

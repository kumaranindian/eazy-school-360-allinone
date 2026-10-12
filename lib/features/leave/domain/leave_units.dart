/// Leave is counted in **half-day units** (2 units = 1 day) so half days are
/// exact integers; no leave quantity is ever a double.
abstract final class LeaveUnits {
  static const int perDay = 2;

  static int fromDays(num days) => (days * perDay).round();

  /// "1", "1.5", "0.5", "-2" — whole numbers without a trailing ".0".
  static String format(int units) {
    final negative = units < 0;
    final abs = units.abs();
    final whole = abs ~/ perDay;
    final half = abs.isOdd;
    final text = half ? '$whole.5' : '$whole';
    return negative ? '-$text' : text;
  }

  static String formatDays(int units) {
    final text = format(units);
    return text == '1' ? '1 day' : '$text days';
  }

  /// Parses "2", "1.5", ".5"; null when it is not a multiple of 0.5.
  static int? parse(String input) {
    final t = input.trim();
    if (!RegExp(r'^-?\d*\.?\d+$').hasMatch(t)) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    final doubled = v * perDay;
    if ((doubled - doubled.roundToDouble()).abs() > 1e-9) return null;
    return doubled.round();
  }
}

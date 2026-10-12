/// All money in this module is an **integer number of minor units** (paise,
/// cents) — never a double. Sums, balances and comparisons are exact, and
/// `firestore.rules` can check the arithmetic because it is integer
/// arithmetic.
abstract final class Money {
  static const _symbols = {'INR': '₹', 'USD': r'$', 'EUR': '€', 'GBP': '£'};

  /// "₹1,234.50". Unknown currencies are shown as their code.
  static String format(int minor, {String currency = 'INR'}) {
    final negative = minor < 0;
    final abs = minor.abs();
    final major = _group('${abs ~/ 100}', indian: currency == 'INR');
    final text =
        '${_symbols[currency] ?? '$currency '}$major.${(abs % 100).toString().padLeft(2, '0')}';
    return negative ? '-$text' : text;
  }

  /// Digit grouping done by hand so it is identical on every platform and
  /// needs no locale data: Indian (12,34,567) for INR, otherwise thousands
  /// (1,234,567).
  static String _group(String digits, {required bool indian}) {
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final size = indian ? 2 : 3;
    final parts = <String>[];
    while (rest.length > size) {
      parts.insert(0, rest.substring(rest.length - size));
      rest = rest.substring(0, rest.length - size);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }

  /// Parses what a person types ("1500", "1,500.5", "1500.50") into minor
  /// units. Returns null for anything that is not a non-negative amount with
  /// at most two decimals — it never rounds silently.
  static int? parseMinor(String input) {
    final cleaned = input.trim().replaceAll(',', '');
    final match = RegExp(r'^(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final major = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    return major * 100 + int.parse(fraction.isEmpty ? '0' : fraction);
  }

  /// A plain "1500.00" for editing fields.
  static String plain(int minor) =>
      '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';

  /// **Rounding rule for percentage concessions:** `amount × basisPoints ÷
  /// 10,000`, rounded **half up** to the nearest minor unit, computed in
  /// integers. 10% (1000 bp) of ₹1,000.05 is ₹100.01 (100.005 rounds up);
  /// 33.33% (3333 bp) of ₹100.00 is ₹33.33.
  static int percentOf(int amountMinor, int basisPoints) =>
      (amountMinor * basisPoints + 5000) ~/ 10000;
}

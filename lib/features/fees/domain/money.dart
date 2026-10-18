import '../../../core/regional/currency.dart';

/// All money in this module is an **integer number of minor units** (paise,
/// cents) — never a double. Sums, balances and comparisons are exact, and
/// `firestore.rules` can check the arithmetic because it is integer
/// arithmetic.
abstract final class Money {
  /// "₹1,234.50", "¥1,234", "KWD 1,234.500". Digits after the point follow the
  /// currency (0, 2 or 3). The currency is always explicit: a default here
  /// would silently show another country's money as rupees.
  static String format(int minor, {required String currency}) {
    final c = Currencies.of(currency);
    final negative = minor < 0;
    final abs = minor.abs();
    final unit = _pow10(c.decimals);
    final major = _group('${abs ~/ unit}', indian: c.indianGrouping);
    final fraction = c.decimals == 0
        ? ''
        : '.${(abs % unit).toString().padLeft(c.decimals, '0')}';
    final text = '${c.symbol}$major$fraction';
    return negative ? '-$text' : text;
  }

  static int _pow10(int n) {
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }

  /// Digit grouping done by hand so it is identical on every platform and
  /// needs no locale data: Indian (12,34,567) where the currency uses it,
  /// otherwise thousands (1,234,567).
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
  /// units of [currency]. Returns null for anything that is not a
  /// non-negative amount with at most the currency's decimals (no decimals at
  /// all for yen, three for dinars) — it never rounds silently.
  static int? parseMinor(String input, {required String currency}) {
    final decimals = Currencies.of(currency).decimals;
    final cleaned = input.trim().replaceAll(',', '');
    final pattern = decimals == 0
        ? RegExp(r'^(\d{1,12})$')
        : RegExp('^(\\d{1,12})(?:\\.(\\d{1,$decimals}))?\$');
    final match = pattern.firstMatch(cleaned);
    if (match == null) return null;
    final major = int.parse(match.group(1)!);
    if (decimals == 0) return major;
    final fraction = (match.group(2) ?? '').padRight(decimals, '0');
    return major * _pow10(decimals) + int.parse(fraction);
  }

  /// What to tell a person whose amount did not parse.
  static String invalidAmountMessage(String currency) {
    final d = Currencies.of(currency).decimals;
    return d == 0
        ? 'Enter a whole amount (no decimals).'
        : 'Enter a valid amount, up to $d decimals.';
  }

  /// A plain "1500.00" for editing fields ("1500" for yen).
  static String plain(int minor, {required String currency}) {
    final decimals = Currencies.of(currency).decimals;
    if (decimals == 0) return '$minor';
    final unit = _pow10(decimals);
    return '${minor ~/ unit}.${(minor % unit).toString().padLeft(decimals, '0')}';
  }

  /// **Rounding rule for percentage concessions:** `amount × basisPoints ÷
  /// 10,000`, rounded **half up** to the nearest minor unit, computed in
  /// integers. 10% (1000 bp) of ₹1,000.05 is ₹100.01 (100.005 rounds up);
  /// 33.33% (3333 bp) of ₹100.00 is ₹33.33.
  static int percentOf(int amountMinor, int basisPoints) =>
      (amountMinor * basisPoints + 5000) ~/ 10000;
}

/// A currency as the app needs it: how many decimal places a minor unit has,
/// how it is written and how digits are grouped.
///
/// Money is stored everywhere as an integer count of **minor units** (paise,
/// cents, fils, ...). [decimals] says how many digits of that integer are the
/// fraction: 2 for INR/USD, 0 for JPY/KRW, 3 for KWD/BHD. The Firestore rules
/// only ever do integer arithmetic on those counts, so they are unaffected.
class Currency {
  final String code;
  final String name;
  final String symbol;
  final int decimals;

  /// Lakh/crore grouping (12,34,567) instead of thousands (1,234,567).
  final bool indianGrouping;

  const Currency(
    this.code,
    this.name,
    this.symbol,
    this.decimals, {
    this.indianGrouping = false,
  });
}

abstract final class Currencies {
  /// ISO 4217 codes the app offers. Decimals follow the standard
  /// (ISO 4217 minor-unit exponents).
  static const List<Currency> all = [
    Currency('INR', 'Indian rupee', '₹', 2, indianGrouping: true),
    Currency('USD', 'US dollar', r'$', 2),
    Currency('EUR', 'Euro', '€', 2),
    Currency('GBP', 'Pound sterling', '£', 2),
    Currency('AED', 'UAE dirham', 'AED ', 2),
    Currency('SAR', 'Saudi riyal', 'SAR ', 2),
    Currency('QAR', 'Qatari riyal', 'QAR ', 2),
    Currency('KWD', 'Kuwaiti dinar', 'KWD ', 3),
    Currency('BHD', 'Bahraini dinar', 'BHD ', 3),
    Currency('OMR', 'Omani rial', 'OMR ', 3),
    Currency('JOD', 'Jordanian dinar', 'JOD ', 3),
    Currency('EGP', 'Egyptian pound', 'E£', 2),
    Currency('SGD', 'Singapore dollar', r'S$', 2),
    Currency('MYR', 'Malaysian ringgit', 'RM', 2),
    Currency('IDR', 'Indonesian rupiah', 'Rp', 2),
    Currency('PHP', 'Philippine peso', '₱', 2),
    Currency('THB', 'Thai baht', '฿', 2),
    Currency('VND', 'Vietnamese dong', '₫', 0),
    Currency('BDT', 'Bangladeshi taka', '৳', 2, indianGrouping: true),
    Currency('LKR', 'Sri Lankan rupee', 'Rs ', 2, indianGrouping: true),
    Currency('NPR', 'Nepalese rupee', 'Rs ', 2, indianGrouping: true),
    Currency('PKR', 'Pakistani rupee', 'Rs ', 2, indianGrouping: true),
    Currency('JPY', 'Japanese yen', '¥', 0),
    Currency('KRW', 'South Korean won', '₩', 0),
    Currency('CNY', 'Chinese yuan', 'CN¥', 2),
    Currency('AUD', 'Australian dollar', r'A$', 2),
    Currency('NZD', 'New Zealand dollar', r'NZ$', 2),
    Currency('CAD', 'Canadian dollar', r'CA$', 2),
    Currency('MXN', 'Mexican peso', r'MX$', 2),
    Currency('BRL', 'Brazilian real', r'R$', 2),
    Currency('ZAR', 'South African rand', 'R', 2),
    Currency('NGN', 'Nigerian naira', '₦', 2),
    Currency('KES', 'Kenyan shilling', 'KSh ', 2),
    Currency('GHS', 'Ghanaian cedi', 'GH₵', 2),
    Currency('UGX', 'Ugandan shilling', 'USh ', 0),
    Currency('TZS', 'Tanzanian shilling', 'TSh ', 2),
    Currency('RWF', 'Rwandan franc', 'RF ', 0),
    Currency('XOF', 'West African CFA franc', 'CFA ', 0),
    Currency('CHF', 'Swiss franc', 'CHF ', 2),
  ];

  static final Map<String, Currency> _byCode = {for (final c in all) c.code: c};

  static bool isSupported(String? code) => _byCode.containsKey(code);

  /// The currency for [code]. An unknown code (older data, a code added
  /// later) is treated as a plain 2-decimal currency shown by its code, so
  /// nothing throws and nothing is misread by a factor of 10 or 1000 for the
  /// common case.
  static Currency of(String code) =>
      _byCode[code] ?? Currency(code, code, '$code ', 2);
}

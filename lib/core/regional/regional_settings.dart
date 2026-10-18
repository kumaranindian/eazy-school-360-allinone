import 'country.dart';
import 'currency.dart';

/// How a school is set up regionally: where it is, what it bills in, which
/// time zone its days run in and how dates are written. Set by the school
/// admin once; every branch and every screen follows it.
///
/// Stored on the school document (`countryCode`, `currency`, `timezone`,
/// `dateFormat`). A school created before this existed has none of them and
/// is treated as an Indian school ([legacy]) - exactly what the app assumed
/// before - until an admin saves its settings.
class RegionalSettings {
  final String countryCode;
  final String currency;
  final String timezone;
  final String dateFormat;

  const RegionalSettings({
    required this.countryCode,
    required this.currency,
    required this.timezone,
    required this.dateFormat,
  });

  static const RegionalSettings legacy = RegionalSettings(
    countryCode: 'IN',
    currency: 'INR',
    timezone: 'Asia/Kolkata',
    dateFormat: 'dd/MM/yyyy',
  );

  /// The defaults for a newly chosen [country].
  factory RegionalSettings.forCountry(Country country) => RegionalSettings(
    countryCode: country.code,
    currency: country.currency,
    timezone: country.timezones.first,
    dateFormat: country.dateFormat,
  );

  factory RegionalSettings.fromSchoolMap(Map<String, dynamic>? data) {
    if (data == null) return legacy;
    return RegionalSettings(
      countryCode: data['countryCode'] as String? ?? legacy.countryCode,
      currency: data['currency'] as String? ?? legacy.currency,
      timezone: data['timezone'] as String? ?? legacy.timezone,
      dateFormat: data['dateFormat'] as String? ?? legacy.dateFormat,
    );
  }

  Map<String, dynamic> toMap() => {
    'countryCode': countryCode,
    'currency': currency,
    'timezone': timezone,
    'dateFormat': dateFormat,
  };

  RegionalSettings copyWith({
    String? countryCode,
    String? currency,
    String? timezone,
    String? dateFormat,
  }) => RegionalSettings(
    countryCode: countryCode ?? this.countryCode,
    currency: currency ?? this.currency,
    timezone: timezone ?? this.timezone,
    dateFormat: dateFormat ?? this.dateFormat,
  );

  /// A problem with these settings, or null. [isKnownZone] is the time zone
  /// database check (kept out of here so this class stays plain Dart).
  String? validate({required bool Function(String) isKnownZone}) {
    if (Countries.byCode(countryCode) == null) return 'Choose a country.';
    if (!Currencies.isSupported(currency)) return 'Choose a currency.';
    if (!isKnownZone(timezone)) return 'Choose a time zone.';
    if (!DateFormats.all.contains(dateFormat)) return 'Choose a date format.';
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is RegionalSettings &&
      other.countryCode == countryCode &&
      other.currency == currency &&
      other.timezone == timezone &&
      other.dateFormat == dateFormat;

  @override
  int get hashCode => Object.hash(countryCode, currency, timezone, dateFormat);
}

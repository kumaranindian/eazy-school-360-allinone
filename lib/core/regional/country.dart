/// A country with its sensible regional defaults. The admin picks a country,
/// and currency, time zone and date format are pre-filled (each can still be
/// changed: a school in one country may bill in another currency).
class Country {
  final String code; // ISO 3166-1 alpha-2
  final String name;
  final String currency;

  /// IANA zones in this country, the first being the default.
  final List<String> timezones;
  final String dateFormat;

  const Country(
    this.code,
    this.name,
    this.currency,
    this.timezones, {
    this.dateFormat = 'dd/MM/yyyy',
  });
}

abstract final class Countries {
  static const List<Country> all = [
    Country('IN', 'India', 'INR', ['Asia/Kolkata']),
    Country('US', 'United States', 'USD', [
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Los_Angeles',
      'America/Anchorage',
      'Pacific/Honolulu',
    ], dateFormat: 'MM/dd/yyyy'),
    Country('GB', 'United Kingdom', 'GBP', ['Europe/London']),
    Country('IE', 'Ireland', 'EUR', ['Europe/Dublin']),
    Country('AE', 'United Arab Emirates', 'AED', ['Asia/Dubai']),
    Country('SA', 'Saudi Arabia', 'SAR', ['Asia/Riyadh']),
    Country('QA', 'Qatar', 'QAR', ['Asia/Qatar']),
    Country('KW', 'Kuwait', 'KWD', ['Asia/Kuwait']),
    Country('BH', 'Bahrain', 'BHD', ['Asia/Bahrain']),
    Country('OM', 'Oman', 'OMR', ['Asia/Muscat']),
    Country('JO', 'Jordan', 'JOD', ['Asia/Amman']),
    Country('EG', 'Egypt', 'EGP', ['Africa/Cairo']),
    Country('SG', 'Singapore', 'SGD', ['Asia/Singapore']),
    Country('MY', 'Malaysia', 'MYR', ['Asia/Kuala_Lumpur']),
    Country('ID', 'Indonesia', 'IDR', [
      'Asia/Jakarta',
      'Asia/Makassar',
      'Asia/Jayapura',
    ]),
    Country('PH', 'Philippines', 'PHP', ['Asia/Manila']),
    Country('TH', 'Thailand', 'THB', ['Asia/Bangkok']),
    Country('VN', 'Vietnam', 'VND', ['Asia/Ho_Chi_Minh']),
    Country('BD', 'Bangladesh', 'BDT', ['Asia/Dhaka']),
    Country('LK', 'Sri Lanka', 'LKR', ['Asia/Colombo']),
    Country('NP', 'Nepal', 'NPR', ['Asia/Kathmandu']),
    Country('PK', 'Pakistan', 'PKR', ['Asia/Karachi']),
    Country('JP', 'Japan', 'JPY', ['Asia/Tokyo'], dateFormat: 'yyyy/MM/dd'),
    Country('KR', 'South Korea', 'KRW', [
      'Asia/Seoul',
    ], dateFormat: 'yyyy.MM.dd'),
    Country('CN', 'China', 'CNY', ['Asia/Shanghai'], dateFormat: 'yyyy/MM/dd'),
    Country('AU', 'Australia', 'AUD', [
      'Australia/Sydney',
      'Australia/Melbourne',
      'Australia/Brisbane',
      'Australia/Adelaide',
      'Australia/Perth',
      'Australia/Darwin',
      'Australia/Hobart',
    ]),
    Country('NZ', 'New Zealand', 'NZD', ['Pacific/Auckland']),
    Country('CA', 'Canada', 'CAD', [
      'America/Toronto',
      'America/Vancouver',
      'America/Edmonton',
      'America/Winnipeg',
      'America/Halifax',
      'America/St_Johns',
    ]),
    Country('MX', 'Mexico', 'MXN', ['America/Mexico_City']),
    Country('BR', 'Brazil', 'BRL', ['America/Sao_Paulo', 'America/Manaus']),
    Country('ZA', 'South Africa', 'ZAR', ['Africa/Johannesburg']),
    Country('NG', 'Nigeria', 'NGN', ['Africa/Lagos']),
    Country('KE', 'Kenya', 'KES', ['Africa/Nairobi']),
    Country('GH', 'Ghana', 'GHS', ['Africa/Accra']),
    Country('UG', 'Uganda', 'UGX', ['Africa/Kampala']),
    Country('TZ', 'Tanzania', 'TZS', ['Africa/Dar_es_Salaam']),
    Country('RW', 'Rwanda', 'RWF', ['Africa/Kigali']),
    Country('SN', 'Senegal', 'XOF', ['Africa/Dakar']),
    Country('DE', 'Germany', 'EUR', [
      'Europe/Berlin',
    ], dateFormat: 'dd.MM.yyyy'),
    Country('FR', 'France', 'EUR', ['Europe/Paris']),
    Country('ES', 'Spain', 'EUR', ['Europe/Madrid']),
    Country('IT', 'Italy', 'EUR', ['Europe/Rome']),
    Country('NL', 'Netherlands', 'EUR', ['Europe/Amsterdam']),
    Country('CH', 'Switzerland', 'CHF', [
      'Europe/Zurich',
    ], dateFormat: 'dd.MM.yyyy'),
  ];

  static Country? byCode(String? code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// Display formats a school can choose (all are `intl` patterns).
abstract final class DateFormats {
  static const List<String> all = [
    'dd/MM/yyyy',
    'MM/dd/yyyy',
    'yyyy-MM-dd',
    'dd.MM.yyyy',
    'yyyy/MM/dd',
    'yyyy.MM.dd',
    'dd-MM-yyyy',
  ];
}

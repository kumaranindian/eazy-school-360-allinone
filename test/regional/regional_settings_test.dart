import 'package:eazy_school_360/core/regional/country.dart';
import 'package:eazy_school_360/core/regional/currency.dart';
import 'package:eazy_school_360/core/regional/regional_settings.dart';
import 'package:eazy_school_360/core/regional/school_clock.dart';
import 'package:eazy_school_360/core/regional/time_zones.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RegionalSettings', () {
    test('a school with nothing stored behaves as it always did (India)', () {
      expect(RegionalSettings.fromSchoolMap(null), RegionalSettings.legacy);
      expect(RegionalSettings.fromSchoolMap({'name': 'x'}).currency, 'INR');
      expect(
        RegionalSettings.fromSchoolMap({'name': 'x'}).timezone,
        'Asia/Kolkata',
      );
    });

    test('round-trips through its map', () {
      const s = RegionalSettings(
        countryCode: 'AE',
        currency: 'AED',
        timezone: 'Asia/Dubai',
        dateFormat: 'dd/MM/yyyy',
      );
      expect(RegionalSettings.fromSchoolMap(s.toMap()), s);
    });

    test('every country default is itself valid', () {
      for (final c in Countries.all) {
        final s = RegionalSettings.forCountry(c);
        expect(
          s.validate(isKnownZone: TimeZones.isKnown),
          isNull,
          reason: c.code,
        );
        expect(Currencies.isSupported(c.currency), isTrue, reason: c.code);
        for (final z in c.timezones) {
          expect(TimeZones.isKnown(z), isTrue, reason: '${c.code} $z');
        }
      }
    });

    test('invalid choices are named', () {
      bool zone(String z) => TimeZones.isKnown(z);
      const ok = RegionalSettings.legacy;
      expect(
        ok.copyWith(countryCode: 'XX').validate(isKnownZone: zone),
        isNotNull,
      );
      expect(
        ok.copyWith(currency: 'XXX').validate(isKnownZone: zone),
        isNotNull,
      );
      expect(
        ok.copyWith(timezone: 'Mars/Base').validate(isKnownZone: zone),
        isNotNull,
      );
      expect(
        ok.copyWith(dateFormat: 'yy').validate(isKnownZone: zone),
        isNotNull,
      );
    });
  });

  group('SchoolClock', () {
    // 2026-08-03 20:00 UTC: already Tuesday 4th in Kolkata/Auckland, still
    // Monday 3rd in New York and Los Angeles.
    final instant = DateTime.utc(2026, 8, 3, 20);
    String today(String zone) =>
        SchoolClock(zone, utcNow: () => instant).todayKey();

    test('the same instant is a different school day in different zones', () {
      expect(today('Asia/Kolkata'), '2026-08-04');
      expect(today('Pacific/Auckland'), '2026-08-04');
      expect(today('UTC'), '2026-08-03');
      expect(today('America/New_York'), '2026-08-03');
      expect(today('America/Los_Angeles'), '2026-08-03');
      expect(today('Asia/Kolkata'), isNot(today('America/New_York')));
    });

    test('is independent of the device zone', () {
      // Nothing here reads DateTime.now() or the machine zone: the result is
      // fixed by the injected instant and the school zone alone.
      expect(today('Asia/Dubai'), '2026-08-04');
    });

    test('day boundaries follow daylight saving', () {
      // 2026-03-08 07:30 UTC: New York has just switched to daylight time
      // (UTC-4), so it is 03:30 on the 8th; one hour earlier is 01:30 EST.
      final c = SchoolClock(
        'America/New_York',
        utcNow: () => DateTime.utc(2026, 3, 8, 7, 30),
      );
      expect(c.now().hour, 3);
      expect(c.todayKey(), '2026-03-08');
      expect(c.startOfDay('2026-03-08'), DateTime.utc(2026, 3, 8, 5));
      expect(
        c.startOfDay('2026-03-09'),
        DateTime.utc(2026, 3, 9, 4),
      ); // 23h day
    });

    test('keyOf and today() agree, and isOnOrAfter compares civil dates', () {
      final c = SchoolClock('Asia/Kolkata', utcNow: () => instant);
      expect(c.today(), DateTime.utc(2026, 8, 4));
      expect(c.keyOf(DateTime.utc(2026, 8, 3, 18, 29)), '2026-08-03');
      expect(c.keyOf(DateTime.utc(2026, 8, 3, 18, 30)), '2026-08-04');
      expect(c.isOnOrAfter('2026-08-04'), isTrue);
      expect(c.isOnOrAfter('2026-08-05'), isFalse);
    });

    test('an unknown zone falls back to UTC instead of throwing', () {
      expect(
        SchoolClock('Mars/Base', utcNow: () => instant).todayKey(),
        '2026-08-03',
      );
    });
  });
}

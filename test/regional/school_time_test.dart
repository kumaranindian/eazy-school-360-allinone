import 'package:eazy_school_360/core/regional/regional_settings.dart';
import 'package:eazy_school_360/core/regional/school_time.dart';
import 'package:eazy_school_360/core/utils/date_formatting.dart';
import 'package:eazy_school_360/features/fees/domain/fee_dates.dart';
import 'package:eazy_school_360/features/homework/domain/homework.dart';
import 'package:flutter_test/flutter_test.dart';

const _dubai = RegionalSettings(
  countryCode: 'AE',
  currency: 'AED',
  timezone: 'Asia/Dubai',
  dateFormat: 'dd/MM/yyyy',
);
const _newYork = RegionalSettings(
  countryCode: 'US',
  currency: 'USD',
  timezone: 'America/New_York',
  dateFormat: 'MM/dd/yyyy',
);

void main() {
  // 2026-08-03 22:30 UTC: 02:30 on the 4th in Dubai, 18:30 on the 3rd in New York.
  final instant = DateTime.utc(2026, 8, 3, 22, 30);

  test('not signed in: the device zone and dd/MM/yyyy, as before', () {
    expect(SchoolTime.isActive, isFalse);
    expect(formatDisplayDate(DateTime(2026, 8, 3)), '03/08/2026');
    final n = DateTime.now();
    expect(SchoolTime.wallNow().difference(n).inSeconds.abs(), lessThan(2));
  });

  test('"today" is the school day, not the device day', () {
    SchoolTime.utcNow = () => instant;
    SchoolTime.use(_dubai);
    expect(SchoolTime.todayKey(), '2026-08-04');
    expect(FeeDates.todayKey(), '2026-08-04');
    SchoolTime.use(_newYork);
    expect(SchoolTime.todayKey(), '2026-08-03');
    expect(FeeDates.todayKey(), '2026-08-03');
  });

  test('the date format follows the school', () {
    SchoolTime.use(_dubai);
    expect(formatDisplayDate(DateTime(2026, 8, 3)), '03/08/2026');
    expect(FeeDates.display('2026-08-03'), '03/08/2026');
    SchoolTime.use(_newYork);
    expect(formatDisplayDate(DateTime(2026, 8, 3)), '08/03/2026');
    expect(FeeDates.display('2026-08-03'), '08/03/2026');
    expect(FeeDates.display('nonsense'), 'nonsense');
  });

  test('instants are shown in the school zone on any device', () {
    SchoolTime.use(_dubai);
    expect(formatInstant(instant), '4 Aug 2026, 2:30 AM');
    SchoolTime.use(_newYork);
    expect(formatInstant(instant), '3 Aug 2026, 6:30 PM');
    expect(formatInstant(null), '—');
  });

  test('a homework deadline is a moment in the school zone', () {
    SchoolTime.use(_dubai); // UTC+4
    // 17:00 in Dubai is 13:00 UTC.
    expect(
      Homework.dueInstant('2026-08-10', 17 * 60),
      DateTime.utc(2026, 8, 10, 13),
    );
    SchoolTime.use(_newYork); // UTC-4 in August
    expect(
      Homework.dueInstant('2026-08-10', 17 * 60),
      DateTime.utc(2026, 8, 10, 21),
    );
    // no time chosen: the end of the school day
    expect(
      Homework.dueInstant('2026-08-10', null),
      DateTime.utc(2026, 8, 11, 3, 59),
    );
  });

  test(
    'wall clock <-> instant round trip, including a daylight-saving day',
    () {
      SchoolTime.use(_newYork);
      for (final wall in [
        DateTime(2026, 8, 3, 9, 15),
        DateTime(2026, 12, 3, 9, 15), // standard time
        DateTime(2026, 3, 8, 12), // the day clocks went forward
      ]) {
        expect(SchoolTime.wallOf(SchoolTime.instantFromWall(wall)), wall);
      }
    },
  );

  test('the 3-decimal and 0-decimal currencies keep their day logic too', () {
    // Day logic does not depend on the currency: guards a mix-up of the two
    // settings in one object.
    SchoolTime.utcNow = () => instant;
    SchoolTime.use(_dubai.copyWith(currency: 'KWD'));
    expect(SchoolTime.todayKey(), '2026-08-04');
  });
}

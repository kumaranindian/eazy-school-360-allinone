import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday_rules.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday_type.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_calendar.dart';
import 'package:eazy_school_360/features/academic_setup/domain/weekday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/weekly_pattern.dart';
import 'package:eazy_school_360/features/academic_setup/domain/working_days.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_calendar.dart';
import 'package:eazy_school_360/features/leave/domain/leave_days.dart';
import 'package:eazy_school_360/features/leave/domain/leave_enums.dart';
import 'package:eazy_school_360/features/leave/domain/leave_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every weekday works except [off]; [saturdayOffWeeks] are the Saturdays of
/// the month that are holidays while Saturday is otherwise a working day.
WorkingDays week({
  Set<Weekday> off = const {Weekday.sunday},
  Set<int> saturdayOffWeeks = const {},
}) => WorkingDays(
  schoolId: 's',
  branchId: 'b',
  isWorkingDay: {for (final d in Weekday.values) d: !off.contains(d)},
  saturdayOffWeeks: saturdayOffWeeks,
);

Holiday holiday(
  String name,
  DateTime start, {
  DateTime? end,
  HolidayType type = HolidayType.school,
  ActivationStatus status = ActivationStatus.active,
  String id = '',
}) => Holiday(
  holidayId: id.isEmpty ? name : id,
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y',
  date: DateTime.utc(start.year, start.month, start.day),
  endDate: end == null ? null : DateTime.utc(end.year, end.month, end.day),
  name: name,
  type: type,
  status: status,
);

SchoolDayInfo on(
  WorkingDays w,
  int y,
  int m,
  int d, [
  List<Holiday> holidays = const [],
]) => SchoolCalendar.evaluate(
  date: DateTime(y, m, d),
  workingDays: w,
  holidays: holidays,
);

/// A written document as it reads back: the server stamps are filled in by
/// Firestore, so the placeholders are dropped here.
Map<String, dynamic> stored(Map<String, dynamic> written) => Map.of(written)
  ..remove('createdAt')
  ..remove('updatedAt');

void main() {
  group('weekly offs', () {
    test('Sunday only: every Sunday is off, Saturdays work', () {
      final w = week();
      expect(on(w, 2026, 8, 2).isWeeklyOff, isTrue); // Sunday
      expect(on(w, 2026, 8, 9).isWeeklyOff, isTrue);
      expect(on(w, 2026, 8, 8).isWorkingDay, isTrue); // Saturday
      expect(on(w, 2026, 8, 3).isWorkingDay, isTrue); // Monday
      expect(w.saturdayPolicy, SaturdayPolicy.allWorking);
    });

    test('Saturday and Sunday: every Saturday and Sunday is off', () {
      final w = week(off: {Weekday.saturday, Weekday.sunday});
      for (final d in [1, 8, 15, 22, 29]) {
        expect(on(w, 2026, 8, d).isWeeklyOff, isTrue, reason: 'Saturday $d');
      }
      expect(on(w, 2026, 8, 7).isWorkingDay, isTrue); // Friday
      expect(w.saturdayPolicy, SaturdayPolicy.allOff);
    });

    test('2nd and 4th Saturdays are off, the others work', () {
      final w = week(saturdayOffWeeks: {2, 4});
      expect(on(w, 2026, 8, 1).isWorkingDay, isTrue); // 1st
      expect(on(w, 2026, 8, 8).isWeeklyOff, isTrue); // 2nd
      expect(on(w, 2026, 8, 15).isWorkingDay, isTrue); // 3rd
      expect(on(w, 2026, 8, 22).isWeeklyOff, isTrue); // 4th
      expect(on(w, 2026, 8, 29).isWorkingDay, isTrue); // 5th
      expect(on(w, 2026, 8, 8).weeklyOffLabel, '2nd Saturday');
      expect(w.saturdayPolicy, SaturdayPolicy.alternateEven);
    });

    test('1st and 3rd Saturdays are off', () {
      final w = week(saturdayOffWeeks: {1, 3});
      expect(on(w, 2026, 8, 1).isWeeklyOff, isTrue);
      expect(on(w, 2026, 8, 8).isWorkingDay, isTrue);
      expect(on(w, 2026, 8, 15).isWeeklyOff, isTrue);
      expect(on(w, 2026, 8, 22).isWorkingDay, isTrue);
      expect(w.saturdayPolicy, SaturdayPolicy.selected);
    });

    test('1st, 3rd and 5th is the "alternate" odd policy', () {
      expect(
        week(saturdayOffWeeks: {1, 3, 5}).saturdayPolicy,
        SaturdayPolicy.alternateOdd,
      );
    });

    test('custom weekday combinations', () {
      final w = week(off: {Weekday.wednesday, Weekday.friday});
      expect(on(w, 2026, 8, 5).isWeeklyOff, isTrue); // Wednesday
      expect(on(w, 2026, 8, 7).isWeeklyOff, isTrue); // Friday
      expect(on(w, 2026, 8, 2).isWorkingDay, isTrue); // Sunday works here
      expect(on(w, 2026, 8, 5).weeklyOffLabel, 'Wednesday');
    });

    test('a 5th-Saturday rule fires only in months that have one', () {
      final w = week(saturdayOffWeeks: {5});
      // August 2026 has five Saturdays (1, 8, 15, 22, 29).
      expect(on(w, 2026, 8, 29).isWeeklyOff, isTrue);
      expect(on(w, 2026, 8, 29).weeklyOffLabel, '5th Saturday');
      // September 2026 has four (5, 12, 19, 26): none is a 5th.
      for (final d in [5, 12, 19, 26]) {
        expect(on(w, 2026, 9, d).isWorkingDay, isTrue, reason: 'Sep $d');
      }
    });

    test('Saturday occurrence comes from the day of month', () {
      DateTime d(int day) => DateTime(2026, 8, day);
      expect(WeeklyPattern.occurrenceInMonth(d(1)), 1);
      expect(WeeklyPattern.occurrenceInMonth(d(7)), 1);
      expect(WeeklyPattern.occurrenceInMonth(d(8)), 2);
      expect(WeeklyPattern.occurrenceInMonth(d(14)), 2);
      expect(WeeklyPattern.occurrenceInMonth(d(15)), 3);
      expect(WeeklyPattern.occurrenceInMonth(d(21)), 3);
      expect(WeeklyPattern.occurrenceInMonth(d(22)), 4);
      expect(WeeklyPattern.occurrenceInMonth(d(28)), 4);
      expect(WeeklyPattern.occurrenceInMonth(d(29)), 5);
      expect(WeeklyPattern.occurrenceInMonth(d(31)), 5);
    });

    test('a Saturday rule never touches another weekday', () {
      final w = week(saturdayOffWeeks: {1, 2, 3, 4, 5});
      // Friday the 7th has day-of-month 1-7 but is not a Saturday.
      expect(on(w, 2026, 8, 7).isWorkingDay, isTrue);
      expect(on(w, 2026, 8, 3).isWorkingDay, isTrue);
    });

    test('a month with exactly four Saturdays (Feb 2026)', () {
      final w = week(saturdayOffWeeks: {2, 4});
      // Feb 2026 Saturdays: 7, 14, 21, 28.
      expect(on(w, 2026, 2, 7).isWorkingDay, isTrue);
      expect(on(w, 2026, 2, 14).isWeeklyOff, isTrue);
      expect(on(w, 2026, 2, 21).isWorkingDay, isTrue);
      expect(on(w, 2026, 2, 28).isWeeklyOff, isTrue);
    });

    test('leap day and month/year boundaries', () {
      final w = week(saturdayOffWeeks: {1, 5});
      // Feb 29 2024 is a Thursday: a leap day is an ordinary working day.
      expect(DateTime(2024, 2, 29).weekday, DateTime.thursday);
      expect(on(w, 2024, 2, 29).isWorkingDay, isTrue);
      // Mar 30 2024 is a Saturday with day 30 -> the 5th.
      expect(DateTime(2024, 3, 30).weekday, DateTime.saturday);
      expect(on(w, 2024, 3, 30).weeklyOffLabel, '5th Saturday');
      // Dec 30 2023 (a 5th Saturday) and Jan 6 2024 (the next 1st Saturday)
      // sit either side of a year boundary.
      expect(DateTime(2023, 12, 30).weekday, DateTime.saturday);
      expect(on(w, 2023, 12, 30).weeklyOffLabel, '5th Saturday');
      expect(DateTime(2024, 1, 6).weekday, DateTime.saturday);
      expect(on(w, 2024, 1, 6).weeklyOffLabel, '1st Saturday');
      // A new year does not carry the month count over.
      expect(on(w, 2024, 1, 13).isWorkingDay, isTrue); // 2nd
    });

    test('the rule in words', () {
      expect(week().current.summary, 'Sunday');
      expect(
        week(off: {Weekday.sunday}, saturdayOffWeeks: {2, 4}).current.summary,
        'Sunday · 2nd, 4th Saturday',
      );
      expect(
        week(off: {Weekday.saturday, Weekday.sunday}).current.summary,
        'Sunday · Every Saturday',
      );
      expect(week(off: {}).current.summary, 'No weekly offs');
    });
  });

  group('holidays', () {
    final w = week();

    test('a single-day holiday closes only that day', () {
      final h = holiday('Founders day', DateTime(2026, 8, 12));
      final info = on(w, 2026, 8, 12, [h]);
      expect(info.isHoliday, isTrue);
      expect(info.holidayName, 'Founders day');
      expect(info.holidayType, HolidayType.school);
      expect(info.isWorkingDay, isFalse);
      expect(on(w, 2026, 8, 11, [h]).isWorkingDay, isTrue);
      expect(on(w, 2026, 8, 13, [h]).isWorkingDay, isTrue);
    });

    test('a multi-day vacation covers every day, inclusive', () {
      final v = holiday(
        'Summer vacation',
        DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 14),
        type: HolidayType.vacation,
      );
      expect(v.dayCount, 5);
      expect(v.isRange, isTrue);
      for (final d in [10, 11, 12, 13, 14]) {
        expect(on(w, 2026, 8, d, [v]).isHoliday, isTrue, reason: 'day $d');
      }
      expect(on(w, 2026, 8, 9, [v]).isHoliday, isFalse);
      expect(on(w, 2026, 8, 15, [v]).isHoliday, isFalse);
    });

    test('a vacation can span a month, a year and a leap day', () {
      final v = holiday(
        'Winter break',
        DateTime(2023, 12, 28),
        end: DateTime(2024, 1, 3),
      );
      expect(v.dayCount, 7);
      expect(v.covers(DateTime(2023, 12, 31)), isTrue);
      expect(v.covers(DateTime(2024, 1, 1)), isTrue);
      final feb = holiday(
        'Break',
        DateTime(2024, 2, 28),
        end: DateTime(2024, 3, 1),
      );
      expect(feb.dayCount, 3); // 28, 29 (leap day), 1
      expect(feb.covers(DateTime(2024, 2, 29)), isTrue);
    });

    test('an inactive holiday closes nothing', () {
      final h = holiday(
        'Cancelled',
        DateTime(2026, 8, 12),
        status: ActivationStatus.inactive,
      );
      expect(on(w, 2026, 8, 12, [h]).isWorkingDay, isTrue);
      expect(on(w, 2026, 8, 12, [h]).holidays, isEmpty);
    });

    test('a holiday on a weekly off is a holiday and still a weekly off', () {
      final h = holiday('Diwali', DateTime(2026, 8, 2)); // a Sunday
      final info = on(w, 2026, 8, 2, [h]);
      expect(info.isHoliday, isTrue);
      expect(info.weeklyOffLabel, 'Sunday');
    });

    test('overlapping holidays keep every record and pick one label', () {
      final vacation = holiday(
        'Summer vacation',
        DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 14),
        type: HolidayType.vacation,
      );
      final festival = holiday(
        'Raksha Bandhan',
        DateTime(2026, 8, 12),
        type: HolidayType.festival,
      );
      final public = holiday(
        'Independence Day',
        DateTime(2026, 8, 12),
        type: HolidayType.public,
      );
      final info = on(w, 2026, 8, 12, [vacation, festival, public]);
      expect(info.holidays, hasLength(3));
      // Public beats festival beats vacation, whatever the input order.
      expect(info.holidayName, 'Independence Day');
      final reversed = on(w, 2026, 8, 12, [public, festival, vacation]);
      expect(reversed.holidayName, 'Independence Day');
      expect(reversed.holidays.map((h) => h.name).toList(), [
        'Independence Day',
        'Raksha Bandhan',
        'Summer vacation',
      ]);
    });

    test('equal types are ordered by start, then name', () {
      final a = holiday('B-camp', DateTime(2026, 8, 12));
      final b = holiday('A-camp', DateTime(2026, 8, 12));
      final earlier = holiday(
        'Zed',
        DateTime(2026, 8, 11),
        end: DateTime(2026, 8, 12),
      );
      expect(on(w, 2026, 8, 12, [a, b]).holidayName, 'A-camp');
      expect(on(w, 2026, 8, 12, [a, b, earlier]).holidayName, 'Zed');
    });

    test('a special working day opens a weekly off but never a holiday', () {
      final swd = holiday(
        'Make-up day',
        DateTime(2026, 8, 2),
        type: HolidayType.specialWorkingDay,
      );
      final open = on(w, 2026, 8, 2, [swd]); // a Sunday
      expect(open.kind, SchoolDayKind.specialWorkingDay);
      expect(open.isWorkingDay, isTrue);
      final closed = on(w, 2026, 8, 2, [
        swd,
        holiday('Closure', DateTime(2026, 8, 2)),
      ]);
      expect(closed.isHoliday, isTrue);
    });

    test('the attendance adapter agrees with the central calendar', () {
      final h = holiday('Founders day', DateTime(2026, 8, 12));
      final info = AttendanceCalendar.evaluate(
        date: DateTime(2026, 8, 12),
        workingDays: w,
        calendarEntries: [h],
      );
      expect(info.kind, CalendarDayKind.holiday);
      expect(info.needsOverride, isTrue);
      expect(info.description, 'Holiday: Founders day');
      final off = AttendanceCalendar.evaluate(
        date: DateTime(2026, 8, 2),
        workingDays: w,
        calendarEntries: const [],
      );
      expect(off.kind, CalendarDayKind.nonWorkingDay);
      expect(off.description, 'Weekly off (Sunday)');
      expect(
        AttendanceCalendar.evaluate(
          date: DateTime(2026, 8, 3),
          workingDays: w,
          calendarEntries: const [],
        ).isSchoolDay,
        isTrue,
      );
    });
  });

  group('civil dates, never time zones', () {
    test('local, UTC and stored-midnight dates give the same answer', () {
      final w = week(saturdayOffWeeks: {2});
      final h = holiday('Founders day', DateTime(2026, 8, 12));
      for (final date in [
        DateTime(2026, 8, 12),
        DateTime.utc(2026, 8, 12),
        DateTime(2026, 8, 12, 23, 59),
        DateTime.utc(2026, 8, 12, 23, 59),
      ]) {
        final info = SchoolCalendar.evaluate(
          date: date,
          workingDays: w,
          holidays: [h],
        );
        expect(info.isHoliday, isTrue, reason: '$date');
      }
      // A Saturday keeps its occurrence whichever way the date is built.
      for (final date in [DateTime(2026, 8, 8), DateTime.utc(2026, 8, 8)]) {
        expect(w.weeklyOffLabel(date), '2nd Saturday', reason: '$date');
      }
    });

    test('a stored holiday round-trips through Firestore as the same day', () {
      final h = holiday(
        'Break',
        DateTime(2026, 12, 24),
        end: DateTime(2026, 12, 26),
      );
      final data = h.toFirestoreCreate(createdBy: 'u');
      expect(
        (data['date'] as Timestamp).toDate().toUtc(),
        DateTime.utc(2026, 12, 24),
      );
      expect(
        (data['endDate'] as Timestamp).toDate().toUtc(),
        DateTime.utc(2026, 12, 26),
      );
      final back = Holiday.fromFirestore('s', 'b', 'y', 'id', stored(data));
      expect(back.isRange, isTrue);
      expect(back.covers(DateTime(2026, 12, 25)), isTrue);
      expect(back.covers(DateTime(2026, 12, 27)), isFalse);
    });

    test('a single day stores no end date and reads back as one day', () {
      final h = holiday('Day', DateTime(2026, 8, 12));
      final data = h.toFirestoreCreate(createdBy: 'u');
      expect(data['endDate'], isNull);
      final back = Holiday.fromFirestore('s', 'b', 'y', 'id', stored(data));
      expect(back.isRange, isFalse);
      expect(back.dayCount, 1);
      // An older document without the field reads the same way.
      final legacy = stored(data)..remove('endDate');
      expect(Holiday.fromFirestore('s', 'b', 'y', 'id', legacy).dayCount, 1);
    });
  });

  group('effective dating', () {
    final base = week().scheduleChange(
      pattern: week().isWorkingDay,
      saturdayOffWeeks: const {},
      startsOn: null,
      configuredBefore: false,
    );

    WorkingDays change(
      WorkingDays from, {
      required Set<int> weeks,
      required String startsOn,
    }) => from.scheduleChange(
      pattern: from.isWorkingDay,
      saturdayOffWeeks: weeks,
      startsOn: startsOn,
      configuredBefore: true,
    );

    test('the first save applies from the beginning', () {
      expect(base.effectiveFrom, isNull);
      expect(base.history, isEmpty);
    });

    test('a later change leaves earlier dates under the old pattern', () {
      final next = change(base, weeks: {2, 4}, startsOn: '2026-09-01');
      expect(next.effectiveFrom, '2026-09-01');
      expect(next.history, hasLength(1));
      // August's 2nd Saturday was a working day and still is.
      expect(next.weeklyOffLabel(DateTime(2026, 8, 8)), isNull);
      // From September the 2nd and 4th are off.
      expect(next.weeklyOffLabel(DateTime(2026, 9, 12)), '2nd Saturday');
      expect(next.weeklyOffLabel(DateTime(2026, 9, 26)), '4th Saturday');
      // The day before and the day of the change.
      expect(next.weeklyOffLabel(DateTime(2026, 8, 29)), isNull);
      expect(next.patternFor(DateTime(2026, 9, 1)).effectiveFrom, '2026-09-01');
    });

    test('several changes keep every period right', () {
      final one = change(base, weeks: {2, 4}, startsOn: '2026-09-01');
      final two = change(one, weeks: {1, 2, 3, 4, 5}, startsOn: '2027-01-01');
      expect(two.history, hasLength(2));
      expect(two.weeklyOffLabel(DateTime(2026, 8, 8)), isNull); // before
      expect(two.weeklyOffLabel(DateTime(2026, 9, 12)), '2nd Saturday');
      expect(
        two.weeklyOffLabel(DateTime(2026, 9, 5)),
        isNull,
      ); // 1st, middle era
      expect(two.weeklyOffLabel(DateTime(2027, 1, 2)), '1st Saturday'); // after
    });

    test('saving on the same start date corrects it in place', () {
      final one = change(base, weeks: {2, 4}, startsOn: '2026-09-01');
      final fixed = change(one, weeks: {1, 3}, startsOn: '2026-09-01');
      expect(fixed.history, hasLength(1));
      expect(fixed.weeklyOffLabel(DateTime(2026, 9, 5)), '1st Saturday');
      expect(fixed.weeklyOffLabel(DateTime(2026, 9, 12)), isNull);
    });

    test('a new pattern may not start before the current one', () {
      final one = change(base, weeks: {2, 4}, startsOn: '2026-09-01');
      expect(
        one.checkEffectiveFrom('2026-08-01'),
        contains('cannot start before'),
      );
      expect(one.checkEffectiveFrom('2026-09-01'), isNull);
      expect(one.checkEffectiveFrom('2026-10-01'), isNull);
      expect(one.checkEffectiveFrom('not a date'), isNotNull);
      expect(one.checkEffectiveFrom(null), isNotNull);
      expect(base.checkEffectiveFrom(null), isNull);
    });

    test('history survives a Firestore round trip', () {
      final one = change(base, weeks: {2, 4}, startsOn: '2026-09-01');
      final data = one.toFirestore(updatedBy: 'u');
      final back = WorkingDays.fromFirestore('s', 'b', stored(data));
      expect(back.effectiveFrom, '2026-09-01');
      expect(back.saturdayOffWeeks, {2, 4});
      expect(back.history, hasLength(1));
      expect(back.weeklyOffLabel(DateTime(2026, 8, 8)), isNull);
      expect(back.weeklyOffLabel(DateTime(2026, 9, 12)), '2nd Saturday');
    });

    test('documents saved before Saturday patterns still read correctly', () {
      final old = WorkingDays.fromFirestore('s', 'b', {
        'isWorkingDay': {
          'MONDAY': true,
          'TUESDAY': true,
          'WEDNESDAY': true,
          'THURSDAY': true,
          'FRIDAY': true,
          'SATURDAY': false,
          'SUNDAY': false,
        },
      });
      expect(old.saturdayOffWeeks, isEmpty);
      expect(old.effectiveFrom, isNull);
      expect(old.history, isEmpty);
      expect(old.saturdayPolicy, SaturdayPolicy.allOff);
      expect(old.weeklyOffLabel(DateTime(2026, 8, 8)), 'Saturday');
    });

    test('only the most recent versions are kept', () {
      var w = base;
      for (var i = 1; i <= WorkingDays.maxHistory + 4; i++) {
        final month = ((i - 1) % 12) + 1;
        final year = 2026 + (i - 1) ~/ 12;
        w = change(
          w,
          weeks: {(i % 5) + 1},
          startsOn: '$year-${month.toString().padLeft(2, '0')}-01',
        );
      }
      expect(w.history.length, WorkingDays.maxHistory);
    });
  });

  group('holiday rules', () {
    test('a range must end on or after it starts, and stay within a year', () {
      final start = DateTime(2026, 8, 10);
      expect(HolidayRules.checkRange(start, null), isNull);
      expect(HolidayRules.checkRange(start, DateTime(2026, 8, 10)), isNull);
      expect(
        HolidayRules.checkRange(start, DateTime(2026, 8, 9)),
        contains('cannot be before'),
      );
      expect(
        HolidayRules.checkRange(start, DateTime(2027, 8, 11)),
        contains('at most'),
      );
      // 366 days (a leap year, or Aug 10 to Aug 10 next year) is the limit.
      expect(HolidayRules.checkRange(start, DateTime(2027, 8, 10)), isNull);
      expect(
        HolidayRules.checkRange(DateTime(2024, 1, 1), DateTime(2024, 12, 31)),
        isNull,
      );
    });

    test('a duplicate is the same name on the same first day', () {
      final existing = [holiday('Diwali', DateTime(2026, 11, 8), id: 'a')];
      expect(
        HolidayRules.duplicateOf(
          holiday('  diwali ', DateTime(2026, 11, 8), id: 'new'),
          existing,
        ),
        isNotNull,
      );
      // another name on the same day, or the same name another day: fine
      expect(
        HolidayRules.duplicateOf(
          holiday('Govardhan', DateTime(2026, 11, 8), id: 'new'),
          existing,
        ),
        isNull,
      );
      expect(
        HolidayRules.duplicateOf(
          holiday('Diwali', DateTime(2026, 11, 9), id: 'new'),
          existing,
        ),
        isNull,
      );
      // editing a record never collides with itself
      expect(
        HolidayRules.duplicateOf(
          holiday('Diwali', DateTime(2026, 11, 8), id: 'a'),
          existing,
        ),
        isNull,
      );
    });

    test('overlap finds active ranges that share a day, and only those', () {
      final vacation = holiday(
        'Vacation',
        DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 14),
        id: 'v',
      );
      final inactive = holiday(
        'Old',
        DateTime(2026, 8, 12),
        status: ActivationStatus.inactive,
        id: 'o',
      );
      final elsewhere = holiday('Later', DateTime(2026, 9, 1), id: 'l');
      final touching = holiday(
        'Edge',
        DateTime(2026, 8, 14),
        end: DateTime(2026, 8, 16),
        id: 'e',
      );
      final candidate = holiday('Fest', DateTime(2026, 8, 12), id: 'new');
      final found = HolidayRules.overlapping(candidate, [
        vacation,
        inactive,
        elsewhere,
        touching,
      ]);
      expect(found.map((h) => h.holidayId), ['v']);
      expect(vacation.overlaps(touching), isTrue); // share the 14th
      expect(vacation.overlaps(elsewhere), isFalse);
    });

    test('new types are read and written', () {
      for (final t in [
        HolidayType.public,
        HolidayType.festival,
        HolidayType.school,
        HolidayType.vacation,
        HolidayType.other,
      ]) {
        expect(HolidayType.fromWireValue(t.wireValue), t);
        expect(t.closesSchool, isTrue);
      }
      expect(HolidayType.specialWorkingDay.closesSchool, isFalse);
    });
  });

  group('leave counting follows the same calendar', () {
    final type = LeaveType(
      typeId: LeaveType.idFor(LeaveKind.student, 'sick'),
      schoolId: 's',
      branchId: 'b',
      kind: LeaveKind.student,
      code: 'sick',
      name: 'Sick leave',
      payType: LeavePayType.notApplicable,
      allowHalfDay: true,
      status: ActivationStatus.active,
    );

    LeaveDaySpan span(
      WorkingDays w,
      String from,
      String to, [
      List<Holiday> holidays = const [],
    ]) => LeaveDayCalculator.compute(
      startKey: from,
      endKey: to,
      halfDay: HalfDay.none,
      type: type,
      workingDays: w,
      calendarEntries: holidays,
      yearStartKey: '2026-06-01',
      yearEndKey: '2027-03-31',
    );

    test('weekly offs and Saturday patterns are not leave days', () {
      // Mon 3 Aug .. Sun 16 Aug 2026; 2nd Saturday (the 8th) and Sundays off.
      final w = week(saturdayOffWeeks: {2, 4});
      final s = span(w, '2026-08-03', '2026-08-16');
      // 14 days, minus Sun 9th, Sun 16th and the 2nd Saturday (the 8th); the
      // 3rd Saturday (the 15th) is a working day.
      expect(s.countedDateKeys, hasLength(11));
      expect(
        s.skipped.keys,
        containsAll(['2026-08-08', '2026-08-09', '2026-08-16']),
      );
      expect(s.skipped['2026-08-08'], 'Weekly off (2nd Saturday)');
    });

    test(
      'a holiday inside the range is skipped, with its name, not refused',
      () {
        final w = week(off: {Weekday.saturday, Weekday.sunday});
        final h = holiday('Independence Day', DateTime(2026, 8, 12));
        final s = span(w, '2026-08-10', '2026-08-14', [h]);
        expect(s.error, isNull);
        expect(s.countedDateKeys, hasLength(4));
        expect(s.skipped['2026-08-12'], 'Holiday: Independence Day');
      },
    );

    test(
      'leave wholly inside a vacation has nothing to count, said plainly',
      () {
        final w = week();
        final v = holiday(
          'Summer vacation',
          DateTime(2026, 8, 10),
          end: DateTime(2026, 8, 14),
          type: HolidayType.vacation,
        );
        final s = span(w, '2026-08-11', '2026-08-13', [v]);
        expect(s.countedDateKeys, isEmpty);
        expect(s.error, contains('No school day'));
        expect(s.skipped, hasLength(3));
      },
    );

    test(
      'a type that counts non-working days is unaffected by the calendar',
      () {
        final every = LeaveType(
          typeId: LeaveType.idFor(LeaveKind.student, 'any'),
          schoolId: 's',
          branchId: 'b',
          kind: LeaveKind.student,
          code: 'any',
          name: 'Any',
          payType: LeavePayType.notApplicable,
          countNonWorkingDays: true,
          status: ActivationStatus.active,
        );
        final s = LeaveDayCalculator.compute(
          startKey: '2026-08-03',
          endKey: '2026-08-09',
          halfDay: HalfDay.none,
          type: every,
          workingDays: week(off: {Weekday.saturday, Weekday.sunday}),
          calendarEntries: const [],
          yearStartKey: '2026-06-01',
          yearEndKey: '2027-03-31',
        );
        expect(s.countedDateKeys, hasLength(7));
      },
    );
  });
}

import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday_type.dart';
import 'package:eazy_school_360/features/academic_setup/domain/weekday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/working_days.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_calendar.dart';
import 'package:eazy_school_360/features/attendance/domain/enrollment_eligibility.dart';
import 'package:eazy_school_360/features/attendance/domain/staff_eligibility.dart';
import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:eazy_school_360/features/students/domain/academic_record_status.dart';
import 'package:eazy_school_360/features/students/domain/student_academic_record.dart';
import 'package:eazy_school_360/features/students/domain/student_status.dart';
import 'package:flutter_test/flutter_test.dart';

// 2026-06-10 is a Wednesday; 2026-06-13 a Saturday; 2026-06-14 a Sunday.
final _wed = DateTime(2026, 6, 10);
final _sat = DateTime(2026, 6, 13);
final _sun = DateTime(2026, 6, 14);

WorkingDays _days({Map<Weekday, bool>? override}) => WorkingDays(
  schoolId: 's',
  branchId: 'b',
  isWorkingDay: {...WorkingDays.defaultPattern(), ...?override},
);

Holiday _entry(
  DateTime date,
  HolidayType type, {
  String name = 'Entry',
  ActivationStatus status = ActivationStatus.active,
}) => Holiday(
  holidayId: 'h',
  schoolId: 's',
  branchId: 'b',
  academicYearId: 'y',
  // stored the way the app stores it: UTC midnight of the civil date
  date: Holiday.normalizeDate(date),
  name: name,
  type: type,
  status: status,
);

CalendarDayInfo _eval(
  DateTime date, {
  WorkingDays? days,
  List<Holiday> entries = const [],
}) => AttendanceCalendar.evaluate(
  date: date,
  workingDays: days ?? _days(),
  calendarEntries: entries,
);

void main() {
  group('AttendanceCalendar', () {
    test('a normal working weekday allows ordinary marking', () {
      final info = _eval(_wed);
      expect(info.kind, CalendarDayKind.workingDay);
      expect(info.isSchoolDay, isTrue);
      expect(info.needsOverride, isFalse);
    });

    test(
      'a configured non-working day (Saturday/Sunday by default) needs an override',
      () {
        for (final d in [_sat, _sun]) {
          final info = _eval(d);
          expect(info.kind, CalendarDayKind.nonWorkingDay);
          expect(info.needsOverride, isTrue);
        }
      },
    );

    test(
      'weekends are NOT hard-coded: a school that works Saturdays gets a working Saturday',
      () {
        final info = _eval(
          _sat,
          days: _days(override: {Weekday.saturday: true}),
        );
        expect(info.kind, CalendarDayKind.workingDay);
      },
    );

    test(
      'and a school that is closed on a Wednesday gets a non-working Wednesday',
      () {
        expect(
          _eval(_wed, days: _days(override: {Weekday.wednesday: false})).kind,
          CalendarDayKind.nonWorkingDay,
        );
      },
    );

    test(
      'public, school, local and special holidays all block ordinary marking and name the holiday',
      () {
        for (final type in [
          HolidayType.public,
          HolidayType.school,
          HolidayType.local,
          HolidayType.special,
        ]) {
          final info = _eval(
            _wed,
            entries: [_entry(_wed, type, name: 'Founders Day')],
          );
          expect(info.kind, CalendarDayKind.holiday, reason: type.name);
          expect(info.needsOverride, isTrue);
          expect(info.description, 'Holiday: Founders Day');
        }
      },
    );

    test('a special working day makes a Saturday a school day', () {
      final info = _eval(
        _sat,
        entries: [
          _entry(_sat, HolidayType.specialWorkingDay, name: 'Make-up day'),
        ],
      );
      expect(info.kind, CalendarDayKind.specialWorkingDay);
      expect(info.isSchoolDay, isTrue);
      expect(info.needsOverride, isFalse);
    });

    test('an inactive calendar entry is ignored', () {
      expect(
        _eval(
          _wed,
          entries: [
            _entry(_wed, HolidayType.public, status: ActivationStatus.inactive),
          ],
        ).kind,
        CalendarDayKind.workingDay,
      );
      expect(
        _eval(
          _sat,
          entries: [
            _entry(
              _sat,
              HolidayType.specialWorkingDay,
              status: ActivationStatus.inactive,
            ),
          ],
        ).kind,
        CalendarDayKind.nonWorkingDay,
      );
    });

    test('a holiday on another date does not affect this one', () {
      expect(
        _eval(
          _wed,
          entries: [_entry(DateTime(2026, 6, 11), HolidayType.public)],
        ).kind,
        CalendarDayKind.workingDay,
      );
    });

    test(
      'if a date is both a holiday and a special working day, the holiday wins (safer)',
      () {
        final info = _eval(
          _sat,
          entries: [
            _entry(_sat, HolidayType.specialWorkingDay),
            _entry(_sat, HolidayType.public, name: 'Festival'),
          ],
        );
        expect(info.kind, CalendarDayKind.holiday);
      },
    );

    test(
      'different branches can have different calendars (same date, different result)',
      () {
        final mainBranch = _eval(_sat);
        final saturdayBranch = _eval(
          _sat,
          days: _days(override: {Weekday.saturday: true}),
        );
        expect(mainBranch.needsOverride, isTrue);
        expect(saturdayBranch.needsOverride, isFalse);
      },
    );

    test(
      'holiday dates are matched by civil date even though stored as UTC midnight',
      () {
        // The device is in a UTC+/- zone; the stored instant must still match the local calendar day.
        expect(
          _eval(
            DateTime(2026, 1, 1),
            entries: [_entry(DateTime(2026, 1, 1), HolidayType.public)],
          ).kind,
          CalendarDayKind.holiday,
        );
        expect(
          _eval(
            DateTime(2026, 12, 31),
            entries: [_entry(DateTime(2026, 12, 31), HolidayType.public)],
          ).kind,
          CalendarDayKind.holiday,
        );
      },
    );

    test('the new calendar type round-trips and is labelled', () {
      expect(
        HolidayType.fromWireValue('SPECIAL_WORKING_DAY'),
        HolidayType.specialWorkingDay,
      );
      expect(HolidayType.specialWorkingDay.displayName, 'Special working day');
      for (final t in HolidayType.values) {
        expect(HolidayType.fromWireValue(t.wireValue), t);
      }
    });
  });

  group(
    'EnrollmentEligibility — class registers use academic history, not the current-placement cache',
    () {
      StudentAcademicRecord record(
        DateTime start, {
        DateTime? end,
        AcademicRecordStatus status = AcademicRecordStatus.active,
      }) => StudentAcademicRecord(
        recordId: 'r',
        studentId: 's',
        schoolId: 'sc',
        branchId: 'b',
        academicYearId: 'y',
        classId: 'c',
        sectionId: 'a',
        startDate: start,
        endDate: end,
        status: status,
      );

      test('an open placement covers every date from its start', () {
        final r = record(DateTime(2026, 6, 1));
        expect(
          EnrollmentEligibility.recordCovers(r, DateTime(2026, 6, 1)),
          isTrue,
        );
        expect(
          EnrollmentEligibility.recordCovers(r, DateTime(2026, 9, 1)),
          isTrue,
        );
        expect(
          EnrollmentEligibility.recordCovers(r, DateTime(2026, 5, 31)),
          isFalse,
        );
      });

      test(
        'a student who joined mid-year is not on the register before they joined',
        () {
          final joined = record(DateTime(2026, 8, 15, 10, 30));
          expect(
            EnrollmentEligibility.recordCovers(joined, DateTime(2026, 8, 14)),
            isFalse,
          );
          expect(
            EnrollmentEligibility.recordCovers(joined, DateTime(2026, 8, 15)),
            isTrue,
          );
        },
      );

      test(
        'after a transfer the old section keeps the dates before it, the new one from the transfer day — never both',
        () {
          final transferDay = DateTime(2026, 7, 10, 14, 0);
          final old = record(
            DateTime(2026, 6, 1),
            end: transferDay,
            status: AcademicRecordStatus.transferred,
          );
          final current = record(transferDay);

          expect(
            EnrollmentEligibility.recordCovers(old, DateTime(2026, 7, 9)),
            isTrue,
          );
          expect(
            EnrollmentEligibility.recordCovers(current, DateTime(2026, 7, 9)),
            isFalse,
          );

          // on the transfer day exactly one section claims the student
          expect(
            EnrollmentEligibility.recordCovers(old, DateTime(2026, 7, 10)),
            isFalse,
          );
          expect(
            EnrollmentEligibility.recordCovers(current, DateTime(2026, 7, 10)),
            isTrue,
          );
          expect(
            EnrollmentEligibility.recordCovers(old, DateTime(2026, 7, 11)),
            isFalse,
          );
        },
      );

      test(
        'an active student is always enrolled; a withdrawn one stops at the status-change date',
        () {
          expect(
            EnrollmentEligibility.studentStillEnrolled(
              status: StudentStatus.active,
              statusChangeDate: null,
              date: DateTime(2026, 9, 1),
            ),
            isTrue,
          );
          final left = DateTime(2026, 8, 1);
          for (final status in [
            StudentStatus.left,
            StudentStatus.transferred,
            StudentStatus.graduated,
            StudentStatus.inactive,
          ]) {
            expect(
              EnrollmentEligibility.studentStillEnrolled(
                status: status,
                statusChangeDate: left,
                date: DateTime(2026, 7, 31),
              ),
              isTrue,
              reason: '${status.name} before',
            );
            expect(
              EnrollmentEligibility.studentStillEnrolled(
                status: status,
                statusChangeDate: left,
                date: DateTime(2026, 8, 1),
              ),
              isFalse,
              reason: '${status.name} on',
            );
          }
          expect(
            EnrollmentEligibility.studentStillEnrolled(
              status: StudentStatus.left,
              statusChangeDate: null,
              date: DateTime(2026, 7, 1),
            ),
            isFalse,
          );
        },
      );
    },
  );

  group(
    'StaffEligibility — only staff employed on the date appear; nobody is auto-marked',
    () {
      bool eligible(
        StaffStatus status, {
        DateTime? joined,
        DateTime? changed,
        DateTime? date,
      }) => StaffEligibility.isEligible(
        status: status,
        joiningDate: joined ?? DateTime(2020, 1, 1),
        statusChangeDate: changed,
        date: date ?? DateTime(2026, 6, 10),
      );

      test('active and on-notice staff appear', () {
        expect(eligible(StaffStatus.active), isTrue);
        expect(eligible(StaffStatus.onNotice), isTrue);
      });

      test('staff who have not joined yet do not appear', () {
        expect(
          eligible(StaffStatus.active, joined: DateTime(2026, 6, 11)),
          isFalse,
        );
        expect(
          eligible(StaffStatus.active, joined: DateTime(2026, 6, 10)),
          isTrue,
        );
      });

      test(
        'resigned, terminated, retired and inactive staff are off the register from their status-change date',
        () {
          for (final s in [
            StaffStatus.resigned,
            StaffStatus.terminated,
            StaffStatus.retired,
            StaffStatus.inactive,
          ]) {
            expect(
              eligible(s, changed: DateTime(2026, 6, 10)),
              isFalse,
              reason: '${s.name} on the day',
            );
            expect(
              eligible(s, changed: DateTime(2026, 6, 20)),
              isTrue,
              reason: '${s.name} still employed earlier',
            );
            expect(
              eligible(s),
              isFalse,
              reason: '${s.name} with no date is not guessed',
            );
          }
        },
      );
    },
  );
}

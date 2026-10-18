import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_academic_year.dart';
import 'package:eazy_school_360/features/attendance/domain/attendance_date.dart';
import 'package:flutter_test/flutter_test.dart';

/// ACAD-1: year boundaries are civil dates. These tests are written to hold in
/// ANY process time zone; CI also runs them with TZ=Asia/Kolkata and
/// TZ=America/Los_Angeles (`.github/workflows/ci.yml`).
Map<String, dynamic> _doc({
  required Object start,
  required Object end,
  String? startKey,
  String? endKey,
}) => {
  'name': '2026-27',
  'startDate': start,
  'endDate': end,
  'status': 'ACTIVE',
  'startDateKey': ?startKey,
  'endDateKey': ?endKey,
};

void main() {
  group('AcademicDates.read', () {
    test('a valid key wins over the stored instant', () {
      final d = AcademicDates.read(
        Timestamp.fromDate(DateTime.utc(2026, 3, 31, 18, 30)),
        '2026-04-01',
      );
      expect(d, DateTime.utc(2026, 4, 1));
    });

    test('a UTC-midnight instant is already a civil date', () {
      for (final offset in [
        const Duration(hours: 5, minutes: 30),
        const Duration(hours: -8),
        Duration.zero,
      ]) {
        expect(
          AcademicDates.read(
            Timestamp.fromDate(DateTime.utc(2026, 4, 1)),
            null,
            localOffset: offset,
          ),
          DateTime.utc(2026, 4, 1),
          reason: '$offset',
        );
      }
    });

    test('legacy local-midnight picks recover the intended date', () {
      // 1 April 2026 picked in India / in Los Angeles (PDT)
      final india = Timestamp.fromDate(DateTime.utc(2026, 3, 31, 18, 30));
      final la = Timestamp.fromDate(DateTime.utc(2026, 4, 1, 7));
      expect(
        AcademicDates.read(
          india,
          null,
          localOffset: const Duration(hours: 5, minutes: 30),
        ),
        DateTime.utc(2026, 4, 1),
      );
      expect(
        AcademicDates.read(la, null, localOffset: const Duration(hours: -7)),
        DateTime.utc(2026, 4, 1),
      );
    });

    test('malformed keys are ignored', () {
      expect(
        AcademicDates.read(
          Timestamp.fromDate(DateTime.utc(2026, 4, 1)),
          '2026-4-1',
        ),
        DateTime.utc(2026, 4, 1),
      );
    });
  });

  group('AcademicYear', () {
    test('a legacy document (local midnight, no keys) reads as the same civil '
        'date the creator picked, in any zone', () {
      // What the old picker stored: local midnight of the chosen day.
      final year = AcademicYear.fromFirestore(
        's1',
        'b1',
        'y1',
        _doc(
          start: Timestamp.fromDate(DateTime(2026, 4, 1)),
          end: Timestamp.fromDate(DateTime(2027, 3, 31)),
        ),
      );
      expect(AttendanceDate.key(year.startDate.toUtc()), '2026-04-01');
      expect(AttendanceDate.key(year.endDate.toUtc()), '2027-03-31');
      // and every reader style agrees
      expect(AttendanceDate.key(year.startDate), '2026-04-01');
      expect(AttendanceDate.dateOnly(year.endDate), DateTime(2027, 3, 31));
    });

    test('writes civil dates: UTC midnight plus keys, whatever the input', () {
      for (final input in [
        DateTime(2026, 4, 1), // local picker result
        DateTime.utc(2026, 4, 1), // already civil
        DateTime(2026, 4, 1, 15, 45), // stray time of day
      ]) {
        final year = AcademicYear(
          academicYearId: 'y1',
          schoolId: 's1',
          branchId: 'b1',
          name: '2026-27',
          startDate: input,
          endDate: DateTime(2027, 3, 31),
          status: AcademicYearStatus.draft,
        );
        final data = year.toFirestoreCreate(createdBy: 'u');
        expect(
          (data['startDate'] as Timestamp).toDate().toUtc(),
          DateTime.utc(2026, 4, 1),
        );
        expect(data['startDateKey'], '2026-04-01');
        expect(
          (data['endDate'] as Timestamp).toDate().toUtc(),
          DateTime.utc(2027, 3, 31),
        );
        expect(data['endDateKey'], '2027-03-31');
        expect(
          (year.toFirestoreUpdate(updatedBy: 'u')['startDateKey']),
          '2026-04-01',
        );
      }
    });

    test('write → read round trip is stable and idempotent', () {
      final year = AcademicYear(
        academicYearId: 'y1',
        schoolId: 's1',
        branchId: 'b1',
        name: 'n',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2027, 3, 31),
        status: AcademicYearStatus.active,
      );
      Map<String, dynamic> stored(AcademicYear y) =>
          y.toFirestoreCreate(createdBy: 'u')
            ..removeWhere((_, v) => v is FieldValue);
      final back = AcademicYear.fromFirestore('s1', 'b1', 'y1', stored(year));
      expect(back.startDate, DateTime.utc(2026, 4, 1));
      expect(back.endDate, DateTime.utc(2027, 3, 31));
      final again = AcademicYear.fromFirestore('s1', 'b1', 'y1', stored(back));
      expect(again.startDate, back.startDate);
      expect(again.endDate, back.endDate);
    });
  });

  group('SchoolAcademicYear', () {
    test(
      'registry write/read and the branch copy carry the same civil dates',
      () {
        final y = SchoolAcademicYear(
          schoolYearId: 'sy',
          schoolId: 's1',
          name: '2026-27',
          startDate: DateTime(2026, 4, 1),
          endDate: DateTime(2027, 3, 31),
        );
        final data = y.toFirestoreCreate(createdBy: 'u');
        expect(data['startDateKey'], '2026-04-01');
        expect(data['endDateKey'], '2027-03-31');
        final back = SchoolAcademicYear.fromFirestore('s1', 'sy', data);
        expect(back.startDate, DateTime.utc(2026, 4, 1));
        final branch = back
            .forBranch('north')
            .toFirestoreCreate(createdBy: 'u');
        expect(branch['startDate'], data['startDate']);
        expect(branch['endDate'], data['endDate']);
        expect(branch['startDateKey'], data['startDateKey']);
        expect(branch['endDateKey'], data['endDateKey']);
      },
    );
  });

  test('the last day of the year is inside the year in leave terms', () {
    // The user-visible symptom (IST): leave on 31 March was rejected.
    final year = AcademicYear.fromFirestore(
      's1',
      'b1',
      'y1',
      _doc(
        start: Timestamp.fromDate(DateTime(2026, 4, 1)),
        end: Timestamp.fromDate(DateTime(2027, 3, 31)),
      ),
    );
    final startKey = AttendanceDate.key(year.startDate.toUtc());
    final endKey = AttendanceDate.key(year.endDate.toUtc());
    expect('2027-03-31'.compareTo(endKey) <= 0, isTrue);
    expect('2026-04-01'.compareTo(startKey) >= 0, isTrue);
  });
}

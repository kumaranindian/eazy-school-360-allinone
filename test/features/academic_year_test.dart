import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromFirestore parses dates and status from their wire values', () {
    // Year boundaries are civil dates, stored and read as UTC midnight
    // (ACAD-1), so they read back the same in every time zone.
    final start = DateTime.utc(2026, 6, 1);
    final end = DateTime.utc(2027, 4, 30);
    final year = AcademicYear.fromFirestore('school-1', 'main', 'year-1', {
      'schoolId': 'school-1',
      'branchId': 'main',
      'name': '2026-2027',
      'startDate': Timestamp.fromDate(start),
      'endDate': Timestamp.fromDate(end),
      'status': 'ACTIVE',
    });

    expect(year.name, '2026-2027');
    expect(year.status, AcademicYearStatus.active);
    expect(year.startDate, start);
    expect(year.endDate, end);
  });

  test(
    'toFirestoreCreate writes the exact wire values firestore.rules expects',
    () {
      final year = AcademicYear(
        academicYearId: 'year-1',
        schoolId: 'school-1',
        branchId: 'main',
        name: '2026-2027',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2027, 4, 30),
        status: AcademicYearStatus.draft,
      );

      final data = year.toFirestoreCreate(createdBy: 'uid-1');

      expect(data['schoolId'], 'school-1');
      expect(data['branchId'], 'main');
      expect(data['status'], 'DRAFT');
      expect(data['createdBy'], 'uid-1');
    },
  );

  test('AcademicYearStatus wireValue round-trips through fromWireValue', () {
    for (final status in AcademicYearStatus.values) {
      expect(AcademicYearStatus.fromWireValue(status.wireValue), status);
    }
  });
}

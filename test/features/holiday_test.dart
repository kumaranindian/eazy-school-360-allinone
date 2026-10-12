import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/holiday_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'normalizeDate strips the time-of-day so duplicate-date checks are time-independent',
    () {
      final withTime = DateTime(2026, 10, 2, 14, 35);
      final normalized = Holiday.normalizeDate(withTime);
      expect(normalized, DateTime.utc(2026, 10, 2));
    },
  );

  test('toFirestoreCreate stores a normalized (midnight UTC) date', () {
    final holiday = Holiday(
      holidayId: '',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'year-1',
      date: DateTime(2026, 10, 2, 9, 0),
      name: 'Gandhi Jayanti',
      type: HolidayType.public,
      status: ActivationStatus.active,
    );

    final data = holiday.toFirestoreCreate(createdBy: 'uid-1');
    final storedDate = (data['date'] as Timestamp).toDate();

    // Compare the instant, not the DateTime's UTC/local tag — `Timestamp`
    // itself has no timezone, and `.toDate()` returns local time, so a
    // direct `==` against a UTC-tagged expectation is the wrong check here.
    expect(storedDate.isAtSameMomentAs(DateTime.utc(2026, 10, 2)), isTrue);
  });

  test('HolidayType wireValue round-trips through fromWireValue', () {
    for (final type in HolidayType.values) {
      expect(HolidayType.fromWireValue(type.wireValue), type);
    }
  });
}

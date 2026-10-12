import 'package:eazy_school_360/features/academic_setup/domain/weekday.dart';
import 'package:eazy_school_360/features/academic_setup/domain/working_days.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'defaults treat Saturday and Sunday as non-working, everything else as working',
    () {
      final defaults = WorkingDays.defaults(
        schoolId: 'school-1',
        branchId: 'main',
      );
      expect(defaults.isWorkingDay[Weekday.saturday], isFalse);
      expect(defaults.isWorkingDay[Weekday.sunday], isFalse);
      expect(defaults.isWorkingDay[Weekday.monday], isTrue);
      expect(defaults.isWorkingDay[Weekday.friday], isTrue);
    },
  );

  test('copyWith changes exactly one day without touching the others', () {
    final defaults = WorkingDays.defaults(
      schoolId: 'school-1',
      branchId: 'main',
    );
    final updated = defaults.copyWith(Weekday.saturday, true);

    expect(updated.isWorkingDay[Weekday.saturday], isTrue);
    expect(updated.isWorkingDay[Weekday.sunday], isFalse);
    expect(updated.isWorkingDay[Weekday.monday], isTrue);
  });

  test(
    'fromFirestore falls back to defaults for any day missing from the stored map',
    () {
      final loaded = WorkingDays.fromFirestore('school-1', 'main', {
        'isWorkingDay': {'MONDAY': false},
      });
      expect(loaded.isWorkingDay[Weekday.monday], isFalse);
      expect(
        loaded.isWorkingDay[Weekday.saturday],
        isFalse,
      ); // default fallback
      expect(loaded.isWorkingDay[Weekday.tuesday], isTrue); // default fallback
    },
  );

  test('toFirestore writes every weekday using its wire-value key', () {
    final defaults = WorkingDays.defaults(
      schoolId: 'school-1',
      branchId: 'main',
    );
    final data = defaults.toFirestore(updatedBy: 'uid-1');
    final stored = data['isWorkingDay'] as Map<String, dynamic>;

    expect(stored.keys.length, Weekday.values.length);
    expect(stored['SATURDAY'], isFalse);
  });

  test('Weekday.fromDateTimeWeekday maps 1-7 (Mon-Sun) correctly', () {
    expect(Weekday.fromDateTimeWeekday(DateTime.monday), Weekday.monday);
    expect(Weekday.fromDateTimeWeekday(DateTime.sunday), Weekday.sunday);
  });
}

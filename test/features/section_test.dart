import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capacity is optional and defaults to null', () {
    final section = Section.fromFirestore(
      'school-1',
      'main',
      'year-1',
      'class-1',
      'section-1',
      {'name': 'A', 'status': 'ACTIVE'},
    );
    expect(section.capacity, isNull);
  });

  test(
    'toFirestoreCreate scopes the section to its school/branch/year/class',
    () {
      const section = Section(
        sectionId: 'section-1',
        schoolId: 'school-1',
        branchId: 'main',
        academicYearId: 'year-1',
        classId: 'class-1',
        name: 'A',
        capacity: 40,
        status: ActivationStatus.active,
      );

      final data = section.toFirestoreCreate(createdBy: 'uid-1');

      expect(data['classId'], 'class-1');
      expect(data['capacity'], 40);
    },
  );
}

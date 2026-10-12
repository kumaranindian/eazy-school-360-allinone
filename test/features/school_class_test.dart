import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromFirestore defaults displayOrder to 0 when absent', () {
    final schoolClass = SchoolClass.fromFirestore(
      'school-1',
      'main',
      'year-1',
      'class-1',
      {'name': 'Class 5', 'status': 'ACTIVE'},
    );

    expect(schoolClass.name, 'Class 5');
    expect(schoolClass.displayOrder, 0);
    expect(schoolClass.status, ActivationStatus.active);
  });

  test('toFirestoreCreate carries the full tenant + year + branch scope', () {
    const schoolClass = SchoolClass(
      classId: 'class-1',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'year-1',
      name: 'Class 5',
      displayOrder: 3,
      status: ActivationStatus.active,
    );

    final data = schoolClass.toFirestoreCreate(createdBy: 'uid-1');

    expect(data['schoolId'], 'school-1');
    expect(data['branchId'], 'main');
    expect(data['academicYearId'], 'year-1');
    expect(data['displayOrder'], 3);
  });

  test(
    'toFirestoreUpdate never includes schoolId/branchId/academicYearId (immutable)',
    () {
      const schoolClass = SchoolClass(
        classId: 'class-1',
        schoolId: 'school-1',
        branchId: 'main',
        academicYearId: 'year-1',
        name: 'Class 5',
        displayOrder: 0,
        status: ActivationStatus.active,
      );

      final data = schoolClass.toFirestoreUpdate(updatedBy: 'uid-1');

      expect(data.containsKey('schoolId'), isFalse);
      expect(data.containsKey('branchId'), isFalse);
      expect(data.containsKey('academicYearId'), isFalse);
    },
  );
}

import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromFirestore parses the subject type enum', () {
    final subject = Subject.fromFirestore(
      'school-1',
      'main',
      'year-1',
      'subject-1',
      {'name': 'Mathematics', 'type': 'CORE', 'status': 'ACTIVE'},
    );
    expect(subject.type, SubjectType.core);
  });

  test(
    'SubjectType wireValue round-trips through fromWireValue for every type',
    () {
      for (final type in SubjectType.values) {
        expect(SubjectType.fromWireValue(type.wireValue), type);
      }
    },
  );

  test(
    'toFirestoreUpdate includes type and displayOrder but not audit origin',
    () {
      const subject = Subject(
        subjectId: 'subject-1',
        schoolId: 'school-1',
        branchId: 'main',
        academicYearId: 'year-1',
        name: 'Mathematics',
        type: SubjectType.core,
        displayOrder: 1,
        status: ActivationStatus.active,
      );

      final data = subject.toFirestoreUpdate(updatedBy: 'uid-1');

      expect(data['type'], 'CORE');
      expect(data.containsKey('createdBy'), isFalse);
    },
  );
}

import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/students/domain/parent_student_link.dart';
import 'package:eazy_school_360/features/students/domain/relationship_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'toFirestoreCreate scopes the relationship to school/branch/student/parent',
    () {
      const link = ParentStudentLink(
        relationshipId: 'parent-1',
        schoolId: 'school-1',
        branchId: 'main',
        studentId: 'student-1',
        parentId: 'parent-1',
        relationshipType: RelationshipType.mother,
        isPrimary: true,
        isEmergencyContact: true,
        canAccessPortal: false,
        status: ActivationStatus.active,
      );

      final data = link.toFirestoreCreate(createdBy: 'uid-1');

      expect(data['studentId'], 'student-1');
      expect(data['parentId'], 'parent-1');
      expect(data['relationshipType'], 'MOTHER');
      expect(data['isPrimary'], isTrue);
      expect(data['isEmergencyContact'], isTrue);
      expect(data['canAccessPortal'], isFalse);
    },
  );

  test('copyWith toggles exactly the flags passed, nothing else', () {
    const link = ParentStudentLink(
      relationshipId: 'parent-1',
      schoolId: 'school-1',
      branchId: 'main',
      studentId: 'student-1',
      parentId: 'parent-1',
      relationshipType: RelationshipType.father,
      status: ActivationStatus.active,
    );

    final updated = link.copyWith(canAccessPortal: true);

    expect(updated.canAccessPortal, isTrue);
    expect(updated.isPrimary, link.isPrimary);
    expect(updated.relationshipType, RelationshipType.father);
  });

  test(
    'fromFirestore uses the document id (== parentId) as relationshipId',
    () {
      final link = ParentStudentLink.fromFirestore(
        'school-1',
        'main',
        'student-1',
        'parent-1',
        {
          'relationshipType': 'GUARDIAN',
          'isPrimary': false,
          'isEmergencyContact': false,
          'canAccessPortal': false,
          'status': 'ACTIVE',
        },
      );

      expect(link.relationshipId, 'parent-1');
      expect(link.parentId, 'parent-1');
      expect(link.relationshipType, RelationshipType.guardian);
    },
  );

  test('RelationshipType wireValue round-trips through fromWireValue', () {
    for (final type in RelationshipType.values) {
      expect(RelationshipType.fromWireValue(type.wireValue), type);
    }
  });
}

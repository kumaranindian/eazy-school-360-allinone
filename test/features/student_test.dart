import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'computeDisplayName joins first/middle/last, skipping an empty middle name',
    () {
      expect(Student.computeDisplayName('Arun', null, 'Kumar'), 'Arun Kumar');
      expect(Student.computeDisplayName('Arun', '', 'Kumar'), 'Arun Kumar');
      expect(Student.computeDisplayName('Arun', 'B', 'Kumar'), 'Arun B Kumar');
    },
  );

  test(
    'toFirestoreCreate derives displayName/displayNameLower and clears the current-placement cache',
    () {
      final student = Student(
        studentId: '',
        schoolId: 'school-1',
        branchId: 'main',
        admissionNumber: 'ADM-2026-001',
        studentCode: 'STU-00000001',
        firstName: 'Arun',
        lastName: 'Kumar',
        dateOfBirth: DateTime(2015, 4, 10),
        gender: Gender.male,
        admissionDate: DateTime(2026, 6, 1),
        status: StudentStatus.active,
      );

      final data = student.toFirestoreCreate(createdBy: 'uid-1');

      expect(data['displayName'], 'Arun Kumar');
      expect(data['displayNameLower'], 'arun kumar');
      expect(data['gender'], 'MALE');
      expect(data['status'], 'ACTIVE');
      // A brand-new student has no placement yet — admitStudent() sets these
      // alongside the first academic record, not toFirestoreCreate itself.
      expect(data['currentClassId'], isNull);
      expect(data['currentSectionId'], isNull);
    },
  );

  test(
    'toFirestoreCurrentPlacementUpdate never touches profile fields — only the placement cache + audit',
    () {
      final data =
          Student(
            studentId: 's1',
            schoolId: 'school-1',
            branchId: 'main',
            admissionNumber: 'ADM-2026-001',
            studentCode: 'STU-00000001',
            firstName: 'Arun',
            lastName: 'Kumar',
            dateOfBirth: DateTime(2015, 4, 10),
            gender: Gender.male,
            admissionDate: DateTime(2026, 6, 1),
            status: StudentStatus.active,
          ).toFirestoreCurrentPlacementUpdate(
            academicYearId: 'year-2',
            classId: 'class-6',
            sectionId: 'section-b',
            rollNumber: '8',
            updatedBy: 'uid-2',
          );

      expect(data.keys.toSet(), {
        'currentAcademicYearId',
        'currentClassId',
        'currentSectionId',
        'currentRollNumber',
        'updatedAt',
        'updatedBy',
      });
      expect(data['currentClassId'], 'class-6');
      expect(data['currentSectionId'], 'section-b');
    },
  );

  test(
    'firestoreStatusChange is a static, instance-free builder (brief §20: effective date, reason, notes)',
    () {
      final effectiveDate = DateTime(2026, 12, 1);
      final data = Student.firestoreStatusChange(
        status: StudentStatus.left,
        effectiveDate: effectiveDate,
        reason: 'Relocated',
        notes: 'Family moved to another city',
        updatedBy: 'uid-1',
      );

      expect(data['status'], 'LEFT');
      expect(data['statusChangeReason'], 'Relocated');
      expect((data['statusChangeDate'] as Timestamp).toDate(), effectiveDate);
    },
  );

  test(
    'fromFirestore round-trips gender/status and the current-placement cache',
    () {
      final student = Student.fromFirestore('school-1', 'main', 's1', {
        'admissionNumber': 'ADM-2026-001',
        'studentCode': 'STU-00000001',
        'firstName': 'Arun',
        'lastName': 'Kumar',
        'dateOfBirth': Timestamp.fromDate(DateTime(2015, 4, 10)),
        'gender': 'MALE',
        'admissionDate': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'status': 'ACTIVE',
        'currentAcademicYearId': 'year-1',
        'currentClassId': 'class-5',
        'currentSectionId': 'section-a',
        'currentRollNumber': '12',
      });

      expect(student.gender, Gender.male);
      expect(student.status, StudentStatus.active);
      expect(student.hasCurrentPlacement, isTrue);
      expect(student.currentClassId, 'class-5');
    },
  );

  test('StudentStatus.isCurrentlyEnrolled is true only for active', () {
    expect(StudentStatus.active.isCurrentlyEnrolled, isTrue);
    for (final status in StudentStatus.values.where(
      (s) => s != StudentStatus.active,
    )) {
      expect(
        status.isCurrentlyEnrolled,
        isFalse,
        reason: '$status should not be "currently enrolled"',
      );
    }
  });
}

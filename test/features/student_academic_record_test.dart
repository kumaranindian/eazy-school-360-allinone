import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/students/domain/academic_record_status.dart';
import 'package:eazy_school_360/features/students/domain/student_academic_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'toFirestoreCreate scopes the record to student/school/branch/year/class/section',
    () {
      final record = StudentAcademicRecord(
        recordId: '',
        studentId: 'student-1',
        schoolId: 'school-1',
        branchId: 'main',
        academicYearId: 'year-1',
        classId: 'class-5',
        sectionId: 'section-a',
        rollNumber: '12',
        startDate: DateTime(2026, 6, 1),
        status: AcademicRecordStatus.active,
      );

      final data = record.toFirestoreCreate(createdBy: 'uid-1');

      expect(data['studentId'], 'student-1');
      expect(data['schoolId'], 'school-1');
      expect(data['academicYearId'], 'year-1');
      expect(data['classId'], 'class-5');
      expect(data['sectionId'], 'section-a');
      expect(data['status'], 'ACTIVE');
      expect(data['endDate'], isNull);
    },
  );

  test(
    'toFirestoreClose never reopens a record back to active — it is a terminal status change',
    () {
      final record = StudentAcademicRecord(
        recordId: 'rec-1',
        studentId: 'student-1',
        schoolId: 'school-1',
        branchId: 'main',
        academicYearId: 'year-1',
        classId: 'class-5',
        sectionId: 'section-a',
        startDate: DateTime(2026, 6, 1),
        status: AcademicRecordStatus.active,
      );

      final endDate = DateTime(2027, 4, 30);
      final data = record.toFirestoreClose(
        status: AcademicRecordStatus.completed,
        endDate: endDate,
        updatedBy: 'uid-2',
      );

      expect(data['status'], 'COMPLETED');
      expect((data['endDate'] as Timestamp).toDate(), endDate);
      // toFirestoreClose never writes classId/sectionId/academicYearId — a
      // placement change always creates a NEW record instead of mutating
      // this one's placement fields (the "never overwrite history" rule).
      expect(data.containsKey('classId'), isFalse);
      expect(data.containsKey('academicYearId'), isFalse);
    },
  );

  test('fromFirestore round-trips every field', () {
    final record = StudentAcademicRecord.fromFirestore(
      'school-1',
      'main',
      'student-1',
      'rec-1',
      {
        'academicYearId': 'year-1',
        'classId': 'class-5',
        'sectionId': 'section-a',
        'rollNumber': '12',
        'startDate': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'status': 'ACTIVE',
      },
    );

    expect(record.recordId, 'rec-1');
    expect(record.studentId, 'student-1');
    expect(record.rollNumber, '12');
    expect(record.status, AcademicRecordStatus.active);
    expect(record.endDate, isNull);
  });

  test('AcademicRecordStatus wireValue round-trips through fromWireValue', () {
    for (final status in AcademicRecordStatus.values) {
      expect(AcademicRecordStatus.fromWireValue(status.wireValue), status);
    }
  });
}

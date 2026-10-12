import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment_status.dart';
import 'package:flutter_test/flutter_test.dart';

TeacherAssignment _assignment({
  String yearId = 'year-2026',
  String classId = 'class-5',
  String sectionId = 'sec-a',
  String? subjectId = 'math',
  bool isClassTeacher = false,
  TeacherAssignmentStatus status = TeacherAssignmentStatus.active,
  DateTime? endDate,
}) {
  return TeacherAssignment(
    assignmentId: 'a1',
    schoolId: 'school-1',
    branchId: 'main',
    academicYearId: yearId,
    teacherStaffId: 'staff-1',
    classId: classId,
    sectionId: sectionId,
    subjectId: subjectId,
    isClassTeacher: isClassTeacher,
    startDate: DateTime(2026, 6, 1),
    endDate: endDate,
    status: status,
  );
}

void main() {
  group('slot key (the uniqueness identity)', () {
    test(
      'a subject assignment is keyed by year, class, section and subject',
      () {
        expect(_assignment().slotKey, 'year-2026__class-5__sec-a__math');
      },
    );

    test(
      'a class-teacher assignment is keyed by year, class and section only',
      () {
        expect(
          _assignment(isClassTeacher: true, subjectId: null).slotKey,
          'year-2026__class-5__sec-a__CLASS_TEACHER',
        );
      },
    );

    test(
      'a class teacher who also teaches a subject in the same section holds two different slots',
      () {
        expect(
          _assignment(isClassTeacher: true, subjectId: null).slotKey,
          isNot(_assignment().slotKey),
        );
      },
    );

    test(
      'the key ignores the teacher, so two teachers contend for the same slot',
      () {
        final other = TeacherAssignment(
          assignmentId: 'a2',
          schoolId: 'school-1',
          branchId: 'main',
          academicYearId: 'year-2026',
          teacherStaffId: 'staff-2',
          classId: 'class-5',
          sectionId: 'sec-a',
          subjectId: 'math',
          isClassTeacher: false,
          startDate: DateTime(2026, 6, 1),
          status: TeacherAssignmentStatus.active,
        );
        expect(other.slotKey, _assignment().slotKey);
      },
    );

    test(
      'sections, classes, subjects and years each produce different keys',
      () {
        final keys = {
          _assignment().slotKey,
          _assignment(sectionId: 'sec-b').slotKey,
          _assignment(classId: 'class-6').slotKey,
          _assignment(subjectId: 'science').slotKey,
          _assignment(yearId: 'year-2027').slotKey,
        };
        expect(keys, hasLength(5));
      },
    );

    test(
      'the same class, section and subject in the next academic year is a different slot (history)',
      () {
        expect(
          _assignment(yearId: 'year-2027').slotKey,
          isNot(_assignment(yearId: 'year-2026').slotKey),
        );
      },
    );

    test('matches the format firestore.rules builds in slotKeyOf', () {
      expect(
        TeacherAssignment.slotKeyFor(
          academicYearId: 'y',
          classId: 'c',
          sectionId: 's',
          subjectId: 'x',
        ),
        'y__c__s__x',
      );
      expect(
        TeacherAssignment.slotKeyFor(
          academicYearId: 'y',
          classId: 'c',
          sectionId: 's',
        ),
        'y__c__s__CLASS_TEACHER',
      );
    });
  });

  group('serialization', () {
    test(
      'create starts ACTIVE with no end date and keeps ids, never names',
      () {
        final data = _assignment().toFirestoreCreate(createdBy: 'admin-1');
        expect(data['status'], 'ACTIVE');
        expect(data['endDate'], isNull);
        expect(data['teacherStaffId'], 'staff-1');
        expect(data['academicYearId'], 'year-2026');
        expect(data['subjectId'], 'math');
        expect(data['isClassTeacher'], isFalse);
        expect(
          data.keys.where((k) => k.toLowerCase().contains('name')),
          isEmpty,
        );
        expect(data['createdBy'], 'admin-1');
      },
    );

    test(
      'a class-teacher assignment never stores a subject, even if one was set',
      () {
        final data = _assignment(
          isClassTeacher: true,
          subjectId: 'math',
        ).toFirestoreCreate(createdBy: 'a');
        expect(data['subjectId'], isNull);
        expect(data['isClassTeacher'], isTrue);
      },
    );

    test(
      'create ignores an ENDED status on the instance — a new row is always active',
      () {
        final data = _assignment(
          status: TeacherAssignmentStatus.ended,
          endDate: DateTime(2026, 9, 1),
        ).toFirestoreCreate(createdBy: 'a');
        expect(data['status'], 'ACTIVE');
        expect(data['endDate'], isNull);
      },
    );

    test(
      'ending touches only status, end date and audit — history fields are untouched',
      () {
        final data = TeacherAssignment.firestoreEnd(
          endDate: DateTime(2026, 12, 1),
          updatedBy: 'admin-2',
        );
        expect(data.keys.toSet(), {
          'status',
          'endDate',
          'updatedAt',
          'updatedBy',
        });
        expect(data['status'], 'ENDED');
        expect((data['endDate'] as Timestamp).toDate(), DateTime(2026, 12, 1));
      },
    );

    test(
      'slot data carries the assignment id and teacher so the rules can cross-check them',
      () {
        final data = _assignment().toSlotData(createdBy: 'admin-1');
        expect(data['assignmentId'], 'a1');
        expect(data['teacherStaffId'], 'staff-1');
        expect(data['schoolId'], 'school-1');
        expect(data['createdBy'], 'admin-1');
      },
    );

    test('fromFirestore reads an ended assignment with its end date', () {
      final read = TeacherAssignment.fromFirestore('school-1', 'main', 'a1', {
        'academicYearId': 'year-2026',
        'teacherStaffId': 'staff-1',
        'classId': 'class-5',
        'sectionId': 'sec-a',
        'subjectId': null,
        'isClassTeacher': true,
        'startDate': Timestamp.fromDate(DateTime(2026, 6, 1)),
        'endDate': Timestamp.fromDate(DateTime(2026, 12, 1)),
        'status': 'ENDED',
      });
      expect(read.isActive, isFalse);
      expect(read.isClassTeacher, isTrue);
      expect(read.endDate, DateTime(2026, 12, 1));
      expect(read.slotKey, 'year-2026__class-5__sec-a__CLASS_TEACHER');
    });
  });

  test('TeacherAssignmentStatus wire values round-trip', () {
    for (final status in TeacherAssignmentStatus.values) {
      expect(TeacherAssignmentStatus.fromWireValue(status.wireValue), status);
    }
  });

  group('academic-year history', () {
    test(
      'Arun 2026-27 (5-A, 6-B) and 2027-28 (6-A, 7-B) are four distinct, year-scoped slots',
      () {
        final slots = <String>{
          for (final (year, cls, sec) in [
            ('2026-27', 'c5', 'a'),
            ('2026-27', 'c6', 'b'),
            ('2027-28', 'c6', 'a'),
            ('2027-28', 'c7', 'b'),
          ])
            TeacherAssignment.slotKeyFor(
              academicYearId: year,
              classId: cls,
              sectionId: sec,
              subjectId: 'math',
            ),
        };
        expect(slots, hasLength(4));
        expect(slots.where((k) => k.startsWith('2026-27')), hasLength(2));
        expect(slots.where((k) => k.startsWith('2027-28')), hasLength(2));
      },
    );
  });
}

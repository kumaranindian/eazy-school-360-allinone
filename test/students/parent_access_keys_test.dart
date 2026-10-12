import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:eazy_school_360/features/students/domain/parent_access_keys.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_status.dart';
import 'package:flutter_test/flutter_test.dart';

Student _child(
  String id, {
  String branch = 'north',
  StudentStatus status = StudentStatus.active,
  String? classId = 'c5',
  String? sectionId = 'sa',
}) => Student(
  studentId: id,
  schoolId: 'school-1',
  branchId: branch,
  admissionNumber: 'ADM-$id',
  studentCode: 'STU-$id',
  firstName: 'Anil',
  lastName: 'Kumar',
  dateOfBirth: DateTime(2015, 4, 10),
  gender: Gender.male,
  admissionDate: DateTime(2026, 6, 1),
  status: status,
  currentAcademicYearId: 'y1',
  currentClassId: classId,
  currentSectionId: sectionId,
);

void main() {
  test('keys are exactly the strings the security rules build', () {
    final k = ParentAccessKeys.forChildren([_child('a')], branchId: 'north');
    expect(k.classKeys, ['c5']);
    expect(k.sectionKeys, ['c5__sa']);
    expect(ParentAccessKeys.sectionKey('c5', 'sa'), 'c5__sa');
  });

  test('several children give the union, sorted and without duplicates', () {
    final k = ParentAccessKeys.forChildren([
      _child('a'),
      _child('b', sectionId: 'sb'),
      _child('c', classId: 'c3', sectionId: 'sa'),
      _child('d'),
    ], branchId: 'north');
    expect(k.classKeys, ['c3', 'c5']);
    expect(k.sectionKeys, ['c3__sa', 'c5__sa', 'c5__sb']);
  });

  test(
    'left, graduated, transferred and unplaced children contribute nothing',
    () {
      final k = ParentAccessKeys.forChildren([
        _child('left', status: StudentStatus.left),
        _child('grad', status: StudentStatus.graduated),
        _child('moved', status: StudentStatus.transferred),
        _child('idle', status: StudentStatus.inactive),
        _child('unplaced', classId: null, sectionId: null),
      ], branchId: 'north');
      expect(k.isEmpty, isTrue);
    },
  );

  test('a child with a class but no section yields only the class key', () {
    final k = ParentAccessKeys.forChildren([
      _child('a', sectionId: null),
    ], branchId: 'north');
    expect(k.classKeys, ['c5']);
    expect(k.sectionKeys, isEmpty);
  });

  test('children of another branch are not in this branch\'s index', () {
    final k = ParentAccessKeys.forChildren([
      _child('a'),
      _child('b', branch: 'south', classId: 'c9', sectionId: 'sx'),
    ], branchId: 'north');
    expect(k.classKeys, ['c5']);
    expect(k.sectionKeys, ['c5__sa']);
  });
}

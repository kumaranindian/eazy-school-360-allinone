import 'package:eazy_school_360/features/students/domain/extra_placement.dart';
import 'package:eazy_school_360/features/students/domain/gender.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_status.dart';
import 'package:flutter_test/flutter_test.dart';

ExtraPlacement _p(String cls, {String year = 'y1', String sec = 's1'}) =>
    ExtraPlacement(
      recordId: 'r-$cls',
      academicYearId: year,
      classId: cls,
      sectionId: sec,
    );

void main() {
  studentHelpers();
  test('keys cover the whole class and the exact section', () {
    expect(ExtraPlacement.keysOf([_p('dc', sec: 'd1')]), ['y1|dc', 'y1|dc|d1']);
  });

  test('round-trips through the stored map', () {
    const p = ExtraPlacement(
      recordId: 'r',
      academicYearId: 'y1',
      classId: 'dc',
      sectionId: 'd1',
      label: 'Afternoon',
      rollNumber: '4',
    );
    final back = ExtraPlacement.fromMap(p.toMap());
    expect(back.label, 'Afternoon');
    expect(back.rollNumber, '4');
    expect(back.sectionKey, 'y1|dc|d1');
    expect(ExtraPlacement.listFrom(null), isEmpty);
    expect(ExtraPlacement.listFrom([p.toMap()]), hasLength(1));
  });

  group('checkAdd', () {
    String? check(
      ExtraPlacement c, {
      List<ExtraPlacement> existing = const [],
    }) => ExtraPlacement.checkAdd(
      candidate: c,
      mainYearId: 'y1',
      mainClassId: 'pre',
      existing: existing,
    );

    test('a different class is fine', () => expect(check(_p('dc')), isNull));

    test('the main class is refused', () {
      expect(check(_p('pre')), contains('main class'));
    });

    test('the same class twice is refused, even in another section', () {
      expect(check(_p('dc', sec: 's2'), existing: [_p('dc')]), isNotNull);
    });

    test('an extra class must be in the same academic year', () {
      expect(check(_p('dc', year: 'y2')), contains('same academic year'));
    });

    test('at most three extra classes', () {
      final full = [_p('a'), _p('b'), _p('c')];
      expect(check(_p('d'), existing: full), contains('at most 3'));
    });

    test('a long label is refused', () {
      final c = ExtraPlacement(
        recordId: '',
        academicYearId: 'y1',
        classId: 'dc',
        sectionId: 's1',
        label: 'x' * 31,
      );
      expect(check(c), contains('label'));
    });
  });
}

Student _kid({List<ExtraPlacement> extras = const []}) => Student(
  studentId: 's1',
  schoolId: 'sc',
  branchId: 'b',
  admissionNumber: 'A1',
  studentCode: 'S1',
  firstName: 'Kid',
  lastName: 'One',
  dateOfBirth: DateTime(2022, 1, 1),
  gender: Gender.female,
  admissionDate: DateTime(2025, 6, 1),
  status: StudentStatus.active,
  currentAcademicYearId: 'y1',
  currentClassId: 'pre',
  currentSectionId: 'p1',
  currentRollNumber: '7',
  extraPlacements: extras,
);

void studentHelpers() {
  const dayCare = ExtraPlacement(
    recordId: 'r',
    academicYearId: 'y1',
    classId: 'dc',
    sectionId: 'd1',
    label: 'Afternoon',
    rollNumber: '3',
  );

  group('Student with an extra class', () {
    test('classSections lists the main class first, then the extras', () {
      final s = _kid(extras: const [dayCare]);
      expect(s.classSections.map((p) => '${p.classId}/${p.sectionId}'), [
        'pre/p1',
        'dc/d1',
      ]);
      expect(s.classSections.last.label, 'Afternoon');
    });

    test('attendsSection covers both, nothing else', () {
      final s = _kid(extras: const [dayCare]);
      expect(s.attendsSection('pre', 'p1'), isTrue);
      expect(s.attendsSection('dc', 'd1'), isTrue);
      expect(s.attendsSection('dc', 'd2'), isFalse);
      expect(s.attendsSection(null, null), isFalse);
      expect(_kid().attendsSection('dc', 'd1'), isFalse);
    });

    test(
      'an exam of the extra class (whole class or its section) covers them',
      () {
        final s = _kid(extras: const [dayCare]);
        expect(s.attendsExam('dc', null), isTrue);
        expect(s.attendsExam('dc', 'd1'), isTrue);
        expect(s.attendsExam('dc', 'd2'), isFalse);
        expect(s.attendsExam('pre', 'p1'), isTrue);
        expect(s.attendsExam('other', null), isFalse);
      },
    );

    test('section and roll number are per class', () {
      final s = _kid(extras: const [dayCare]);
      expect(s.placementInClass('pre'), (sectionId: 'p1', rollNumber: '7'));
      expect(s.placementInClass('dc'), (sectionId: 'd1', rollNumber: '3'));
      expect(s.placementInClass('x'), (sectionId: null, rollNumber: null));
    });

    test('an unplaced student attends nothing, extras or not', () {
      final s = Student(
        studentId: 's',
        schoolId: 'sc',
        branchId: 'b',
        admissionNumber: 'A',
        studentCode: 'S',
        firstName: 'K',
        lastName: 'L',
        dateOfBirth: DateTime(2022),
        gender: Gender.male,
        admissionDate: DateTime(2025),
        status: StudentStatus.active,
        extraPlacements: const [dayCare],
      );
      expect(s.classSections, isEmpty);
    });
  });
}

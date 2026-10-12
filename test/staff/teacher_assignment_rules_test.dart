import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
    'checkTeacher — staff exists, same tenant (looked up in the branch), active, has teaching responsibility',
    () {
      test('accepts an active teacher', () {
        expect(
          TeacherAssignmentRules.checkTeacher(
            exists: true,
            isTeacher: true,
            status: StaffStatus.active,
          ),
          isNull,
        );
      });

      test('refuses a missing staff member', () {
        expect(
          TeacherAssignmentRules.checkTeacher(exists: false),
          contains('could not be found'),
        );
      });

      test('refuses a staff member with no teaching responsibility', () {
        expect(
          TeacherAssignmentRules.checkTeacher(
            exists: true,
            isTeacher: false,
            status: StaffStatus.active,
          ),
          contains('teaching responsibility'),
        );
      });

      test('refuses every non-active status, naming it', () {
        for (final status in StaffStatus.values.where(
          (s) => s != StaffStatus.active,
        )) {
          final reason = TeacherAssignmentRules.checkTeacher(
            exists: true,
            isTeacher: true,
            status: status,
          );
          expect(reason, isNotNull, reason: status.name);
          expect(
            reason!.toLowerCase(),
            contains(status.displayName.toLowerCase()),
          );
        }
      });
    },
  );

  group('checkAcademicYear', () {
    test('accepts draft and active years', () {
      expect(
        TeacherAssignmentRules.checkAcademicYear(
          exists: true,
          status: AcademicYearStatus.draft,
        ),
        isNull,
      );
      expect(
        TeacherAssignmentRules.checkAcademicYear(
          exists: true,
          status: AcademicYearStatus.active,
        ),
        isNull,
      );
    });

    test('refuses a missing year', () {
      expect(
        TeacherAssignmentRules.checkAcademicYear(exists: false),
        contains('does not exist'),
      );
    });

    test('refuses a closed year — its history is sealed', () {
      expect(
        TeacherAssignmentRules.checkAcademicYear(
          exists: true,
          status: AcademicYearStatus.closed,
        ),
        contains('closed'),
      );
    });
  });

  group(
    'checkSection — section belongs to the class and year (it is looked up under them) and is active',
    () {
      test('accepts an active section', () {
        expect(
          TeacherAssignmentRules.checkSection(
            exists: true,
            status: ActivationStatus.active,
          ),
          isNull,
        );
      });

      test('refuses a section that is not under that class and year', () {
        expect(
          TeacherAssignmentRules.checkSection(exists: false),
          contains('does not belong'),
        );
      });

      test('refuses an inactive section', () {
        expect(
          TeacherAssignmentRules.checkSection(
            exists: true,
            status: ActivationStatus.inactive,
          ),
          contains('inactive'),
        );
      });
    },
  );

  group('checkSubject — only subjects configured for the class', () {
    test('a class-teacher assignment needs no subject', () {
      expect(
        TeacherAssignmentRules.checkSubject(
          isClassTeacher: true,
          subjectId: null,
          linkedToClass: false,
        ),
        isNull,
      );
    });

    test('a subject assignment needs a subject', () {
      expect(
        TeacherAssignmentRules.checkSubject(
          isClassTeacher: false,
          subjectId: null,
          linkedToClass: false,
        ),
        contains('Choose a subject'),
      );
    });

    test(
      'Class 5 + "Advanced Physics" is refused when the subject is not linked to Class 5',
      () {
        expect(
          TeacherAssignmentRules.checkSubject(
            isClassTeacher: false,
            subjectId: 'advanced-physics',
            linkedToClass: false,
          ),
          contains('not configured'),
        );
      },
    );

    test('a subject linked to the class is accepted', () {
      expect(
        TeacherAssignmentRules.checkSubject(
          isClassTeacher: false,
          subjectId: 'math',
          linkedToClass: true,
        ),
        isNull,
      );
    });
  });

  group('checkSlotFree — no duplicate active assignment', () {
    test('a free slot is fine', () {
      expect(
        TeacherAssignmentRules.checkSlotFree(
          isClassTeacher: false,
          teacherStaffId: 't1',
          holderStaffId: null,
        ),
        isNull,
      );
      expect(
        TeacherAssignmentRules.checkSlotFree(
          isClassTeacher: true,
          teacherStaffId: 't1',
          holderStaffId: null,
        ),
        isNull,
      );
    });

    test(
      'the same teacher twice is a duplicate subject / class-teacher assignment',
      () {
        expect(
          TeacherAssignmentRules.checkSlotFree(
            isClassTeacher: false,
            teacherStaffId: 't1',
            holderStaffId: 't1',
          ),
          contains('already teaches'),
        );
        expect(
          TeacherAssignmentRules.checkSlotFree(
            isClassTeacher: true,
            teacherStaffId: 't1',
            holderStaffId: 't1',
          ),
          contains('already the class teacher'),
        );
      },
    );

    test(
      'a second class teacher for a section is refused with a pointer to ending the first',
      () {
        final reason = TeacherAssignmentRules.checkSlotFree(
          isClassTeacher: true,
          teacherStaffId: 't2',
          holderStaffId: 't1',
        );
        expect(reason, contains('already has a class teacher'));
        expect(reason, contains('End that assignment first'));
      },
    );

    test('a second teacher for the same section + subject is refused', () {
      expect(
        TeacherAssignmentRules.checkSlotFree(
          isClassTeacher: false,
          teacherStaffId: 't2',
          holderStaffId: 't1',
        ),
        contains('already assigned to another teacher'),
      );
    });
  });

  group('checkEnd', () {
    test('ends an active assignment on or after its start date', () {
      expect(
        TeacherAssignmentRules.checkEnd(
          isActive: true,
          startDate: DateTime(2026, 6, 1, 9, 30),
          endDate: DateTime(2026, 6, 1),
        ),
        isNull,
      );
      expect(
        TeacherAssignmentRules.checkEnd(
          isActive: true,
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 12, 1),
        ),
        isNull,
      );
    });

    test('refuses ending before the start date', () {
      expect(
        TeacherAssignmentRules.checkEnd(
          isActive: true,
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 5, 31),
        ),
        contains('before the start'),
      );
    });

    test('refuses ending an assignment that already ended', () {
      expect(
        TeacherAssignmentRules.checkEnd(
          isActive: false,
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 12, 1),
        ),
        contains('already ended'),
      );
    });
  });
}

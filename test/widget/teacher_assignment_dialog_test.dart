import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject_type.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/staff/presentation/widgets/teacher_assignment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/staff_fakes.dart';

AcademicYear _year(String id, String name, AcademicYearStatus status) =>
    AcademicYear(
      academicYearId: id,
      schoolId: 'school-1',
      branchId: 'main',
      name: name,
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2027, 3, 31),
      status: status,
    );

SchoolClass _class(
  String id,
  String name, {
  String year = 'y26',
  ActivationStatus status = ActivationStatus.active,
}) => SchoolClass(
  classId: id,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: year,
  name: name,
  displayOrder: 1,
  status: status,
);

Section _section(
  String id,
  String name,
  String classId, {
  ActivationStatus status = ActivationStatus.active,
}) => Section(
  sectionId: id,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y26',
  classId: classId,
  name: name,
  status: status,
);

Subject _subject(String id, String name) => Subject(
  subjectId: id,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y26',
  name: name,
  type: SubjectType.core,
  displayOrder: 1,
  status: ActivationStatus.active,
);

final _academic = FakeAcademicStructureRepository(
  years: [
    _year('y26', '2026-27', AcademicYearStatus.active),
    _year('y25', '2025-26', AcademicYearStatus.closed),
  ],
  classes: [
    _class('c5', 'Class 5'),
    _class('c6', 'Class 6'),
    _class('c7', 'Class 7', status: ActivationStatus.inactive),
  ],
  sections: [
    _section('s5a', 'A', 'c5'),
    _section('s5z', 'Z', 'c5', status: ActivationStatus.inactive),
    _section('s6a', 'A', 'c6'),
  ],
  subjects: [
    _subject('math', 'Mathematics'),
    _subject('phys', 'Advanced Physics'),
  ],
  // Advanced Physics exists in the year but is NOT configured for Class 5.
  classSubjectIds: {
    'c5': ['math'],
    'c6': ['math', 'phys'],
  },
);

Future<FakeTeacherAssignmentRepository> _open(WidgetTester tester) async {
  final assignments = FakeTeacherAssignmentRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        academicStructureRepositoryProvider.overrideWithValue(_academic),
        teacherAssignmentRepositoryProvider.overrideWithValue(assignments),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TeacherAssignmentDialog(
              teacher: fakeStaff(
                't1',
                first: 'Priya',
                last: 'S',
                isTeacher: true,
              ),
              currentUserId: 'admin-1',
              initialAcademicYearId: 'y26',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return assignments;
}

Future<void> _choose(WidgetTester tester, String label, String option) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Finder get _assignButton => find.widgetWithText(FilledButton, 'Assign');

void main() {
  testWidgets(
    'Assign stays disabled until year, class, section and (subject or class teacher) are chosen',
    (tester) async {
      await _open(tester);
      expect(tester.widget<FilledButton>(_assignButton).onPressed, isNull);

      await _choose(tester, 'Class', 'Class 5');
      await _choose(tester, 'Section', 'A');
      expect(
        tester.widget<FilledButton>(_assignButton).onPressed,
        isNull,
        reason: 'still needs a subject',
      );

      await _choose(tester, 'Subject', 'Mathematics');
      expect(tester.widget<FilledButton>(_assignButton).onPressed, isNotNull);
    },
  );

  testWidgets('closed academic years are not offered', (tester) async {
    await _open(tester);
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Academic year'),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026-27'), findsWidgets);
    expect(find.text('2025-26'), findsNothing);
  });

  testWidgets('inactive classes and sections are not offered', (tester) async {
    await _open(tester);
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Class'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Class 5'), findsWidgets);
    expect(find.text('Class 7'), findsNothing);
    await tester.tap(find.text('Class 5').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Section'),
    );
    await tester.pumpAndSettle();
    expect(find.text('A'), findsWidgets);
    expect(find.text('Z'), findsNothing);
  });

  testWidgets(
    'only subjects configured for the chosen class are offered (no Advanced Physics for Class 5)',
    (tester) async {
      await _open(tester);
      await _choose(tester, 'Class', 'Class 5');
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Subject'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mathematics'), findsWidgets);
      expect(find.text('Advanced Physics'), findsNothing);
      await tester.tap(find.text('Mathematics').last);
      await tester.pumpAndSettle();

      // Class 6 has it configured.
      await _choose(tester, 'Class', 'Class 6');
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Subject'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Advanced Physics'), findsWidgets);
    },
  );

  testWidgets(
    'changing the class clears the section and subject so a stale pair can never be submitted',
    (tester) async {
      await _open(tester);
      await _choose(tester, 'Class', 'Class 5');
      await _choose(tester, 'Section', 'A');
      await _choose(tester, 'Subject', 'Mathematics');
      expect(tester.widget<FilledButton>(_assignButton).onPressed, isNotNull);

      await _choose(tester, 'Class', 'Class 6');
      expect(tester.widget<FilledButton>(_assignButton).onPressed, isNull);
    },
  );

  testWidgets('class teacher hides the subject field and submits no subject', (
    tester,
  ) async {
    final repo = await _open(tester);
    await _choose(tester, 'Class', 'Class 5');
    await _choose(tester, 'Section', 'A');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Subject'),
      findsNothing,
    );
    await tester.tap(_assignButton);
    await tester.pumpAndSettle();

    expect(repo.assigned, hasLength(1));
    expect(repo.assigned.single['isClassTeacher'], isTrue);
    expect(repo.assigned.single['subjectId'], isNull);
  });

  testWidgets('submits the chosen ids and the signed-in actor', (tester) async {
    final repo = await _open(tester);
    await _choose(tester, 'Class', 'Class 5');
    await _choose(tester, 'Section', 'A');
    await _choose(tester, 'Subject', 'Mathematics');
    await tester.tap(_assignButton);
    await tester.pumpAndSettle();

    expect(repo.assigned.single, {
      'academicYearId': 'y26',
      'teacherStaffId': 't1',
      'classId': 'c5',
      'sectionId': 's5a',
      'subjectId': 'math',
      'isClassTeacher': false,
      'createdBy': 'admin-1',
    });
  });

  testWidgets(
    'a refused assignment shows the reason, not a raw error, and keeps the dialog open',
    (tester) async {
      final repo = await _open(tester);
      repo.assignError = const ValidationFailure(
        'This section already has a class teacher. End that assignment first.',
      );
      await _choose(tester, 'Class', 'Class 5');
      await _choose(tester, 'Section', 'A');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(_assignButton);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This section already has a class teacher. End that assignment first.',
        ),
        findsOneWidget,
      );
      expect(find.text('Assign'), findsWidgets);
    },
  );
}

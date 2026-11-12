import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/students/domain/extra_placement.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/presentation/providers/student_providers.dart';
import 'package:eazy_school_360/features/students/presentation/widgets/student_extra_classes_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/staff_fakes.dart';
import '../support/student_fakes.dart';

class _Repo extends FakeStudentListRepository {
  _Repo() : super(const []);
  final added = <({String classId, String sectionId, String label})>[];
  final removed = <String>[];

  @override
  Future<void> addExtraPlacement({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String label = '',
    String? rollNumber,
    required String updatedBy,
  }) async =>
      added.add((classId: classId, sectionId: sectionId, label: label.trim()));

  @override
  Future<void> removeExtraPlacement({
    required String schoolId,
    required String branchId,
    required String studentId,
    required String recordId,
    required String updatedBy,
  }) async => removed.add(recordId);
}

SchoolClass _c(String id, String name) => SchoolClass(
  classId: id,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  name: name,
  code: id,
  displayOrder: 1,
  status: ActivationStatus.active,
);

Section _s(String cls, String id, String name) => Section(
  sectionId: id,
  schoolId: 'school-1',
  branchId: 'main',
  academicYearId: 'y1',
  classId: cls,
  name: name,
  capacity: 20,
  status: ActivationStatus.active,
);

Future<_Repo> _pump(WidgetTester tester, Student student) async {
  tester.view.physicalSize = const Size(700, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studentRepositoryProvider.overrideWithValue(repo),
        academicStructureRepositoryProvider.overrideWithValue(
          FakeAcademicStructureRepository(
            classes: [_c('pre', 'Pre-school'), _c('dc', 'Day care')],
            sections: [_s('pre', 'p1', 'A'), _s('dc', 'd1', 'Afternoon')],
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StudentExtraClassesCard(
              student: student,
              canManage: true,
              currentUserId: 'admin',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Student _kid({List<ExtraPlacement> extras = const []}) {
  final s = fakeStudent('s1', yearId: 'y1', classId: 'pre', sectionId: 'p1');
  return Student(
    studentId: s.studentId,
    schoolId: s.schoolId,
    branchId: s.branchId,
    admissionNumber: s.admissionNumber,
    studentCode: s.studentCode,
    firstName: s.firstName,
    lastName: s.lastName,
    dateOfBirth: s.dateOfBirth,
    gender: s.gender,
    admissionDate: s.admissionDate,
    status: s.status,
    currentAcademicYearId: 'y1',
    currentClassId: 'pre',
    currentSectionId: 'p1',
    extraPlacements: extras,
  );
}

void main() {
  testWidgets('adds an extra class, offering every class but the main one', (
    tester,
  ) async {
    final repo = await _pump(tester, _kid());
    expect(find.text('No extra classes.'), findsOneWidget);
    await tester.tap(find.text('Add class'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Class'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pre-school'), findsNothing, reason: 'main class');
    await tester.tap(find.text('Day care').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Section'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Afternoon').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Session (optional)'),
      ' Afternoon ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add class'));
    await tester.pumpAndSettle();
    expect(repo.added.single.classId, 'dc');
    expect(repo.added.single.sectionId, 'd1');
    expect(repo.added.single.label, 'Afternoon');
  });

  testWidgets('lists extra classes and removes one after confirming', (
    tester,
  ) async {
    final repo = await _pump(
      tester,
      _kid(
        extras: const [
          ExtraPlacement(
            recordId: 'rec-1',
            academicYearId: 'y1',
            classId: 'dc',
            sectionId: 'd1',
            label: 'Afternoon',
          ),
        ],
      ),
    );
    expect(find.text('Day care - Afternoon'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove extra class?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(repo.removed, isEmpty);
    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(repo.removed, ['rec-1']);
  });
}

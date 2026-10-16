import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/domain/student_repository.dart';
import 'package:eazy_school_360/features/students/presentation/providers/student_providers.dart';
import 'package:eazy_school_360/features/students/presentation/widgets/student_branch_transfer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/staff_fakes.dart';
import '../support/student_fakes.dart';

class _Repo implements StudentRepository {
  final List<Map<String, Object?>> calls = [];
  Object? error;

  @override
  Future<String> transferToBranch({
    required String schoolId,
    required String fromBranchId,
    required String studentId,
    required String toBranchId,
    required String admissionNumber,
    required String academicYearId,
    required String classId,
    required String sectionId,
    String? rollNumber,
    String? reason,
    required DateTime effectiveDate,
    required String updatedBy,
  }) async {
    if (error != null) throw error!;
    calls.add({
      'to': toBranchId,
      'admission': admissionNumber,
      'year': academicYearId,
      'class': classId,
      'section': sectionId,
      'roll': rollNumber,
      'reason': reason,
      'by': updatedBy,
    });
    return 'tr-1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Branch _b(String id, String name) => Branch(
  branchId: id,
  schoolId: 'school-1',
  name: name,
  status: BranchStatus.active,
);

Future<_Repo> _pump(
  WidgetTester tester, {
  Size size = const Size(700, 1000),
  double scale = 1.0,
  List<AcademicYear>? years,
  Student? student,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final repo = _Repo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        studentRepositoryProvider.overrideWithValue(repo),
        schoolRepositoryProvider.overrideWithValue(
          FakeSchoolRepository(
            branches: {
              'school-1/main': _b('main', 'Main Campus'),
              'school-1/south': _b('south', 'South Campus'),
            },
          ),
        ),
        academicStructureRepositoryProvider.overrideWithValue(
          FakeAcademicStructureRepository(
            years:
                years ??
                [
                  AcademicYear(
                    academicYearId: 'y1',
                    schoolId: 'school-1',
                    branchId: 'south',
                    name: '2026-27',
                    startDate: DateTime(2026, 6, 1),
                    endDate: DateTime(2027, 3, 31),
                    status: AcademicYearStatus.active,
                  ),
                  AcademicYear(
                    academicYearId: 'old',
                    schoolId: 'school-1',
                    branchId: 'south',
                    name: '2019-20',
                    startDate: DateTime(2019, 6, 1),
                    endDate: DateTime(2020, 3, 31),
                    status: AcademicYearStatus.closed,
                  ),
                ],
            classes: [
              const SchoolClass(
                classId: 'c6',
                schoolId: 'school-1',
                branchId: 'south',
                academicYearId: 'y1',
                name: 'Class 6',
                code: 'C6',
                displayOrder: 6,
                status: ActivationStatus.active,
              ),
            ],
            sections: [
              const Section(
                sectionId: 'sb',
                schoolId: 'school-1',
                branchId: 'south',
                academicYearId: 'y1',
                classId: 'c6',
                name: 'Section B',
                capacity: 40,
                status: ActivationStatus.active,
              ),
            ],
          ),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StudentBranchTransferDialog(
              student: student ?? fakeStudent('stu-1'),
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

Future<void> _pick(WidgetTester t, String field, String option) async {
  await t.tap(find.text(field));
  await t.pumpAndSettle();
  await t.tap(find.text(option).last);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'offers only other branches and open years; moves with the chosen placement',
    (tester) async {
      final repo = await _pump(tester);
      FilledButton move() =>
          tester.widget(find.widgetWithText(FilledButton, 'Move student'));
      expect(move().onPressed, isNull);

      await tester.tap(find.text('New branch'));
      await tester.pumpAndSettle();
      expect(find.text('Main Campus'), findsNothing); // the current branch
      await tester.tap(find.text('South Campus').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Admission number in the new branch'),
        'S-100',
      );
      await tester.tap(find.text('Academic year'));
      await tester.pumpAndSettle();
      expect(find.text('2019-20'), findsNothing); // closed
      await tester.tap(find.text('2026-27').last);
      await tester.pumpAndSettle();
      await _pick(tester, 'Class', 'Class 6');
      await _pick(tester, 'Section', 'Section B');
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (optional)'),
        'Family moved',
      );
      // still needs the confirmation
      expect(move().onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(move().onPressed, isNotNull);

      await tester.ensureVisible(find.text('Move student'));
      await tester.tap(find.text('Move student'));
      await tester.pumpAndSettle();
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single, {
        'to': 'south',
        'admission': 'S-100',
        'year': 'y1',
        'class': 'c6',
        'section': 'sb',
        'roll': null,
        'reason': 'Family moved',
        'by': 'admin',
      });
    },
  );

  testWidgets('a refusal is shown and the form stays', (tester) async {
    final repo = await _pump(tester);
    repo.error = const ValidationFailure(
      'This admission number is already in use in the new branch.',
    );
    await tester.tap(find.text('New branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('South Campus').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Admission number in the new branch'),
      'S-100',
    );
    await tester.tap(find.text('Academic year'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-27').last);
    await tester.pumpAndSettle();
    await _pick(tester, 'Class', 'Class 6');
    await _pick(tester, 'Section', 'Section B');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Move student'));
    await tester.tap(find.text('Move student'));
    await tester.pumpAndSettle();
    expect(
      find.text('This admission number is already in use in the new branch.'),
      findsOneWidget,
    );
    expect(find.text('Move student'), findsOneWidget);
  });

  testWidgets('a branch with no open year says so', (tester) async {
    await _pump(tester, years: const []);
    await tester.tap(find.text('New branch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('South Campus').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('No open academic year'), findsOneWidget);
  });

  for (final (name, size, scale) in [
    ('small phone', const Size(320, 640), 1.5),
    ('tablet', const Size(820, 1180), 1.0),
  ]) {
    testWidgets('lays out without overflow: $name', (tester) async {
      await _pump(tester, size: size, scale: scale);
      await tester.tap(find.text('New branch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('South Campus').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

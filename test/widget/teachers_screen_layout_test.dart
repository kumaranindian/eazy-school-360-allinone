import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year.dart';
import 'package:eazy_school_360/features/academic_setup/domain/academic_year_status.dart';
import 'package:eazy_school_360/features/academic_setup/domain/school_class.dart';
import 'package:eazy_school_360/features/academic_setup/domain/section.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject.dart';
import 'package:eazy_school_360/features/academic_setup/domain/subject_type.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/staff/domain/staff.dart';
import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment.dart';
import 'package:eazy_school_360/features/staff/domain/teacher_assignment_status.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/staff/presentation/widgets/staff_status_chip.dart';
import 'package:eazy_school_360/features/staff/presentation/widgets/directory_list.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';
const _longSchool =
    'Rosewood International High School of Excellence and Learning, Chennai';

/// Pages the list: the first call returns [firstPage] teachers and a cursor.
class _PagedStaff extends FakeStaffRepository {
  final int firstPage;
  final List<Object?> cursors = [];

  _PagedStaff({required super.staff, required this.firstPage});

  @override
  Future<PagedResult<Staff>> fetchStaff({
    required String schoolId,
    required String branchId,
    StaffStatus? status,
    String? departmentId,
    String? designationId,
    employmentType,
    bool? isTeacher,
    int pageSize = 25,
    Object? cursor,
  }) async {
    cursors.add(cursor);
    final all = staff
        .where((s) => status == null || s.status == status)
        .toList();
    return cursor == null
        ? PagedResult(items: all.take(firstPage).toList(), nextCursor: 'next')
        : PagedResult(items: all.skip(firstPage).toList(), nextCursor: null);
  }
}

final _academic = FakeAcademicStructureRepository(
  years: [
    AcademicYear(
      academicYearId: 'y26',
      schoolId: 'school-1',
      branchId: 'main',
      name: '2026-27',
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2027, 3, 31),
      status: AcademicYearStatus.active,
    ),
  ],
  classes: [
    const SchoolClass(
      classId: 'c1',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y26',
      name: 'Class 1',
      displayOrder: 1,
      status: ActivationStatus.active,
    ),
  ],
  sections: [
    const Section(
      sectionId: 'sA',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y26',
      classId: 'c1',
      name: 'A',
      status: ActivationStatus.active,
    ),
  ],
  subjects: [
    const Subject(
      subjectId: 'math',
      schoolId: 'school-1',
      branchId: 'main',
      academicYearId: 'y26',
      name: 'Mathematics',
      code: 'MATH',
      type: SubjectType.core,
      displayOrder: 1,
      status: ActivationStatus.active,
    ),
  ],
);

/// Eight teachers: t1 class teacher, t2 subject teacher, t8 with a very long
/// name, t3..t7 and t8 with no assignment at all.
List<Staff> _teachers() => [
  fakeStaff('t1', first: 'Meera', last: 'Iyer', code: 'T-1', isTeacher: true),
  fakeStaff('t2', first: 'Arun', last: 'Kumar', code: 'T-2', isTeacher: true),
  for (var i = 3; i <= 7; i++)
    fakeStaff(
      't$i',
      first: 'Teacher',
      last: 'Number$i',
      code: 'T-$i',
      isTeacher: true,
    ),
  fakeStaff(
    't8',
    first: 'Venkatasubramanian',
    last: 'Ramachandran Iyer-Thiruvengadam',
    code: 'EMP-LONG-IDENTIFIER-0008',
    isTeacher: true,
  ),
];

Future<(ProviderContainer, FakeStaffRepository)> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  double textScale = 1.0,
  UserRole role = UserRole.branchAdmin,
  FakeStaffRepository? repo,
  String schoolName = 'Rosewood High',
  Map<String, Branch>? branches,
  List<Staff>? teachers,
  bool assignments = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final staff = repo ?? FakeStaffRepository(staff: teachers ?? _teachers());
  final assigned = FakeTeacherAssignmentRepository()
    ..existing = assignments
        ? [
            TeacherAssignment(
              assignmentId: 'a1',
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y26',
              teacherStaffId: 't1',
              classId: 'c1',
              sectionId: 'sA',
              isClassTeacher: true,
              startDate: DateTime(2026, 6, 1),
              status: TeacherAssignmentStatus.active,
            ),
            TeacherAssignment(
              assignmentId: 'a2',
              schoolId: 'school-1',
              branchId: 'main',
              academicYearId: 'y26',
              teacherStaffId: 't2',
              classId: 'c1',
              sectionId: 'sA',
              subjectId: 'math',
              isClassTeacher: false,
              startDate: DateTime(2026, 6, 1),
              status: TeacherAssignmentStatus.active,
            ),
          ]
        : [];
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'grace@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace Hopper',
            email: 'grace@example.com',
            role: role,
            status: UserStatus.active,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {
            'school-1': School(
              schoolId: 'school-1',
              name: schoolName,
              email: 'office@rosewood.example',
              status: SchoolStatus.active,
            ),
          },
          branches:
              branches ??
              {
                'school-1/main': const Branch(
                  branchId: 'main',
                  schoolId: 'school-1',
                  name: 'Main',
                  status: BranchStatus.active,
                ),
              },
        ),
      ),
      staffRepositoryProvider.overrideWithValue(staff),
      staffSetupRepositoryProvider.overrideWithValue(
        FakeStaffSetupRepository(),
      ),
      teacherAssignmentRepositoryProvider.overrideWithValue(assigned),
      academicStructureRepositoryProvider.overrideWithValue(_academic),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go('/teachers');
  await tester.pumpAndSettle();
  return (container, staff);
}

const _widths = <double>[360, 390, 768, 1024, 1280, 1440, 1920];

/// Whether any horizontally scrolling area other than the phone's chip row is
/// on the page (the page itself must never scroll sideways).
bool _pageScrollsSideways(WidgetTester tester) => tester
    .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
    .any((s) => s.scrollDirection == Axis.horizontal);

void main() {
  group('every required width', () {
    for (final width in _widths) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets('${width.toInt()}px, text x$scale: no overflow', (
          tester,
        ) async {
          await _pump(
            tester,
            size: Size(width, width < 600 ? 800 : 900),
            textScale: scale,
            schoolName: _longSchool,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Teaching staff'), findsOneWidget);
          expect(find.text('Meera Iyer'), findsOneWidget);
          // never wider than the window
          final card = tester.getRect(find.byType(DirectoryListCard));
          expect(card.left, greaterThanOrEqualTo(0));
          expect(card.right, lessThanOrEqualTo(width));
          expect(find.byType(Scrollable).evaluate().isNotEmpty, isTrue);
        });
      }
    }
  });

  group('structure by layout', () {
    for (final width in [360.0, 390.0]) {
      testWidgets(
        '${width.toInt()}: cards, a stacked toolbar, the filters in a sheet',
        (tester) async {
          await _pump(tester, size: Size(width, 800));
          expect(find.byType(DirectoryCard), findsWidgets);
          expect(find.byType(DirectoryTable), findsNothing);
          // no individual dropdowns inline; one Filters button with the count
          expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
          expect(find.text('Filters · 1'), findsOneWidget);
          // the hero is compact and holds the school/branch label
          expect(find.textContaining('Rosewood High · Main'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('a phone never shows a "—" placeholder', (tester) async {
      await _pump(tester, size: const Size(390, 800));
      expect(find.text('—'), findsNothing);
      // t1 is a class teacher, so it has a metadata line; the others have none
      expect(find.textContaining('Class teacher: Class 1'), findsOneWidget);
      expect(find.text('Teacher Number3'), findsOneWidget);
    });

    testWidgets(
      'the phone Filters button opens a themed sheet with every filter',
      (tester) async {
        await _pump(tester, size: const Size(390, 800));
        await tester.tap(find.text('Filters · 1'));
        await tester.pumpAndSettle();
        for (final label in [
          'Academic year',
          'Class',
          'Section',
          'Subject',
          'Status',
        ]) {
          expect(find.text(label), findsWidgets, reason: label);
        }
        expect(find.text('Done'), findsOneWidget);
      },
    );

    testWidgets(
      '768: table without the lowest-priority columns, two-row toolbar',
      (tester) async {
        await _pump(tester, size: const Size(768, 900));
        expect(find.byType(DirectoryTable), findsOneWidget);
        expect(find.byType(DirectoryCard), findsNothing);
        expect(find.text('TEACHER'), findsOneWidget);
        expect(find.text('STATUS'), findsOneWidget);
        expect(find.text('CLASS TEACHER'), findsNothing); // dropped first
        // the filters sit inline under the switch and search
        expect(find.text('Academic year'), findsWidgets);
        final search = tester.getRect(find.byType(TextField).first);
        final year = tester.getRect(
          find
              .widgetWithText(DropdownButtonFormField<String?>, '2026-27')
              .first,
        );
        expect(year.top, greaterThan(search.bottom - 1));
        expect(_pageScrollsSideways(tester), isFalse);
      },
    );

    testWidgets(
      'the sidebar is a 64px icon-only rail with tooltips on a tablet',
      (tester) async {
        await _pump(tester, size: const Size(768, 900));
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(rail.extended, isFalse);
        expect(rail.minWidth, 64);
        expect(find.byType(Tooltip), findsWidgets);
      },
    );

    testWidgets('the sidebar is a full 208px sidebar on a desktop', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1280, 900));
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(rail.minExtendedWidth, 208);
    });

    for (final width in [1024.0, 1280.0, 1440.0, 1920.0]) {
      testWidgets('${width.toInt()}: the desktop table shows every column', (
        tester,
      ) async {
        await _pump(tester, size: Size(width, 900));
        expect(find.byType(DirectoryTable), findsOneWidget);
        expect(find.text('TEACHER'), findsOneWidget);
        expect(find.text('ID'), findsOneWidget);
        expect(find.text('CLASSES'), findsOneWidget);
        expect(find.text('STATUS'), findsOneWidget);
        expect(_pageScrollsSideways(tester), isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('1440: at least six teacher rows are visible', (tester) async {
      await _pump(tester, size: const Size(1440, 900));
      final visible = [
        for (final name in [
          'Meera Iyer',
          'Arun Kumar',
          'Teacher Number3',
          'Teacher Number4',
          'Teacher Number5',
          'Teacher Number6',
        ])
          tester.getRect(find.text(name)).bottom,
      ];
      for (final bottom in visible) {
        expect(bottom, lessThan(900));
      }
    });

    testWidgets('1920: the content is capped and centred', (tester) async {
      await _pump(tester, size: const Size(1920, 1000));
      final card = tester.getRect(find.byType(DirectoryListCard));
      expect(card.width, lessThanOrEqualTo(1440));
      // centred in what is left of the window beside the sidebar
      expect(card.left, greaterThan(208 + 20));
    });

    testWidgets('rows are about 46 tall and the avatar 30', (tester) async {
      await _pump(tester, size: const Size(1440, 900));
      final r1 = tester.getRect(find.text('Meera Iyer'));
      final r2 = tester.getRect(find.text('Arun Kumar'));
      expect((r2.center.dy - r1.center.dy).abs(), inInclusiveRange(46, 48));
      final avatar = tester.getSize(find.byType(PersonAvatar).first);
      expect(avatar, const Size(30, 30));
    });
  });

  group('content', () {
    testWidgets('a desktop row with nothing to show says "—"', (tester) async {
      await _pump(tester, size: const Size(1440, 900));
      expect(find.text('—'), findsWidgets);
    });

    testWidgets('while names load the row never claims to be empty', (
      tester,
    ) async {
      // classes/subjects resolve through the academic names; a resolved class
      // reads "Class 1 – A", not a placeholder
      await _pump(tester, size: const Size(1440, 900));
      expect(find.textContaining('Class 1'), findsWidgets);
      expect(find.text('Mathematics'), findsOneWidget);
    });

    for (final width in [360.0, 768.0, 1440.0]) {
      testWidgets(
        '${width.toInt()}: a long name and ID truncate and never meet the status',
        (tester) async {
          await _pump(tester, size: Size(width, 900));
          expect(tester.takeException(), isNull);
          final name = find.textContaining('Venkatasubramanian');
          expect(name, findsOneWidget);
          final nameRect = tester.getRect(name);
          final statuses = find.descendant(
            of: find.byType(DirectoryListCard),
            matching: find.byType(StaffStatusChip),
          );
          // the status of the long-named teacher's row sits to the right of it
          final sameRow = [
            for (var i = 0; i < statuses.evaluate().length; i++)
              tester.getRect(statuses.at(i)),
          ].where((r) => (r.center.dy - nameRect.center.dy).abs() < 40);
          expect(sameRow, isNotEmpty);
          for (final r in sameRow) {
            expect(nameRect.right, lessThanOrEqualTo(r.left + 0.5));
          }
        },
      );
    }

    testWidgets('the footer counts and offers more only when there is more', (
      tester,
    ) async {
      final repo = _PagedStaff(staff: _teachers(), firstPage: 5);
      await _pump(tester, size: const Size(1440, 900), repo: repo);
      expect(find.textContaining('Showing 5'), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);
      await tester.ensureVisible(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(repo.cursors, [null, 'next']); // the same paging, untouched
      expect(find.textContaining('Showing 8'), findsOneWidget);
      expect(find.text('Load more'), findsNothing); // nothing further
      expect(find.text('Teacher Number7'), findsOneWidget);
    });

    testWidgets('on a phone the footer button is full width', (tester) async {
      final repo = _PagedStaff(staff: _teachers(), firstPage: 5);
      await _pump(tester, size: const Size(390, 800), repo: repo);
      await tester.ensureVisible(find.text('Load more'));
      final button = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Load more'),
      );
      expect(button.height, greaterThanOrEqualTo(44));
      final card = tester.getRect(find.byType(DirectoryListCard));
      expect(button.width, greaterThan(card.width - 40));
    });

    testWidgets('an empty list says so, and shows no footer', (tester) async {
      await _pump(tester, size: const Size(1440, 900), teachers: const []);
      expect(find.text('No teachers found.'), findsOneWidget);
      expect(find.textContaining('Showing'), findsNothing);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('an error keeps the header and offers a retry', (tester) async {
      final repo = FakeStaffRepository(
        staff: _teachers(),
        error: StateError('boom'),
      );
      await _pump(tester, size: const Size(1440, 900), repo: repo);
      expect(find.text('Teaching staff'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('filters and chips', () {
    testWidgets('Section is dimmed and disabled until a class is chosen', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 900));
      Finder section() =>
          find.widgetWithText(DropdownButtonFormField<String?>, 'All sections');
      expect(section(), findsOneWidget);
      expect(
        tester.widget<DropdownButtonFormField<String?>>(section()).onChanged,
        isNull,
      );
      final dim = find.ancestor(of: section(), matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(dim.first).opacity, 0.5);

      // choose a class: it is enabled and no longer dimmed
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String?>, 'All classes'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Class 1').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<DropdownButtonFormField<String?>>(section()).onChanged,
        isNotNull,
      );
      expect(
        find
            .ancestor(of: section(), matching: find.byType(Opacity))
            .evaluate()
            .where((e) => (e.widget as Opacity).opacity == 0.5),
        isEmpty,
      );
    });

    testWidgets(
      'the status chips keep their counts and the tag clears the filter',
      (tester) async {
        final (_, repo) = await _pump(tester, size: const Size(1440, 900));
        expect(find.bySemanticsLabel('All: 8'), findsOneWidget);
        expect(
          find.widgetWithText(InputChip, 'Status: Active'),
          findsOneWidget,
        );
        // the tag is at the right of the same row as the chips
        final chip = tester.getRect(find.text('Inactive'));
        final tag = tester.getRect(
          find.widgetWithText(InputChip, 'Status: Active'),
        );
        expect((tag.center.dy - chip.center.dy).abs(), lessThan(24));
        expect(tag.left, greaterThan(chip.right));
        repo.fetchCalls.clear();
        await tester.tap(
          find.descendant(
            of: find.widgetWithText(InputChip, 'Status: Active'),
            matching: find.byType(Icon),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          repo.fetchCalls.last['status'],
          isNull,
        ); // the same query as "All"
        expect(find.widgetWithText(InputChip, 'Status: Active'), findsNothing);
      },
    );

    testWidgets('tapping a count chip filters exactly as before', (
      tester,
    ) async {
      final (_, repo) = await _pump(tester, size: const Size(1440, 900));
      repo.fetchCalls.clear();
      await tester.tap(find.bySemanticsLabel('On notice: 0'));
      await tester.pumpAndSettle();
      expect(repo.fetchCalls.last['status'], StaffStatus.onNotice);
    });

    testWidgets('phone chips are 44 high to touch, and sit in a sideways row', (
      tester,
    ) async {
      await _pump(tester, size: const Size(390, 800));
      expect(
        tester.getSize(find.bySemanticsLabel('All: 8')).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('search still searches, after the same pause', (tester) async {
      final (_, repo) = await _pump(tester, size: const Size(1440, 900));
      await tester.enterText(find.byType(TextField).first, 'Meera');
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.searchCalls, isEmpty); // debounced
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(repo.searchCalls.single['query'], 'Meera');
      expect(find.text('Meera Iyer'), findsOneWidget);
      expect(find.text('Arun Kumar'), findsNothing);
    });

    testWidgets('a search with no results shows the empty state', (
      tester,
    ) async {
      await _pump(tester, size: const Size(1440, 900));
      await tester.enterText(find.byType(TextField).first, 'Zzz');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('No teachers found.'), findsOneWidget);
    });
  });

  group('header and branches', () {
    final two = {
      'school-1/main': const Branch(
        branchId: 'main',
        schoolId: 'school-1',
        name: 'Main',
        status: BranchStatus.active,
      ),
      'school-1/south': const Branch(
        branchId: 'south',
        schoolId: 'school-1',
        name: 'South Campus',
        status: BranchStatus.active,
      ),
    };

    testWidgets('a school admin chooses the branch from the hero', (
      tester,
    ) async {
      final (container, _) = await _pump(
        tester,
        role: UserRole.schoolAdmin,
        branches: two,
      );
      // no separate "Branch" dropdown row any more
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Branch'),
        findsNothing,
      );
      expect(find.byTooltip('Choose branch'), findsOneWidget);
      await tester.tap(find.byTooltip('Choose branch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('South Campus').last);
      await tester.pumpAndSettle();
      expect(container.read(selectedStaffBranchIdProvider), 'south');
      expect(find.textContaining('South Campus'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the branch selector fits a phone, with a long school name', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(360, 800),
        role: UserRole.schoolAdmin,
        branches: two,
        schoolName: _longSchool,
      );
      expect(find.byTooltip('Choose branch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a branch-scoped role has the label but no selector', (
      tester,
    ) async {
      await _pump(tester, branches: two);
      expect(find.byTooltip('Choose branch'), findsNothing);
      expect(find.textContaining('Rosewood High · Main'), findsOneWidget);
    });
  });

  group('resizing', () {
    testWidgets(
      'growing and shrinking the window swaps layouts without losing state',
      (tester) async {
        await _pump(tester, size: const Size(1440, 900));
        await tester.enterText(find.byType(TextField).first, 'Mee');
        expect(find.byType(DirectoryTable), findsOneWidget);

        tester.view.physicalSize = const Size(390, 800);
        await tester.pumpAndSettle();
        expect(find.byType(DirectoryCard), findsWidgets);
        expect(find.byType(DirectoryTable), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          'Mee', // the search text survives the layout change
        );

        tester.view.physicalSize = const Size(768, 900);
        await tester.pumpAndSettle();
        expect(find.byType(DirectoryTable), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}

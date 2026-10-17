import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/academic_setup/presentation/providers/academic_structure_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/staff/domain/staff_status.dart';
import 'package:eazy_school_360/shared/layouts/directory_list.dart';
import 'package:eazy_school_360/features/staff/presentation/providers/staff_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/staff_fakes.dart';

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);
const _branch = Branch(
  branchId: 'main',
  schoolId: 'school-1',
  name: 'Main',
  status: BranchStatus.active,
);

UserProfile _profile(UserRole role) => UserProfile(
  userId: _uid,
  schoolId: 'school-1',
  branchId: 'main',
  name: 'Grace Hopper',
  email: 'grace@example.com',
  role: role,
  status: UserStatus.active,
);

class _World {
  final ProviderContainer container;
  final FakeStaffRepository staffRepository;

  _World(this.container, this.staffRepository);

  String get location => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;

  Future<void> go(WidgetTester tester, String path) async {
    container.read(appRouterProvider).go(path);
    await tester.pumpAndSettle();
  }
}

Future<_World> _pump(
  WidgetTester tester, {
  required UserRole role,
  FakeStaffRepository? staffRepository,
  Size size = const Size(1400, 900),
}) async {
  addTearDown(() => tester.view.resetPhysicalSize());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;

  final staff = staffRepository ?? FakeStaffRepository();
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
        FakeUserRepository({_uid: _profile(role)}),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {'school-1': _school},
          branches: {'school-1/main': _branch},
        ),
      ),
      staffRepositoryProvider.overrideWithValue(staff),
      staffSetupRepositoryProvider.overrideWithValue(
        FakeStaffSetupRepository(),
      ),
      academicStructureRepositoryProvider.overrideWithValue(
        FakeAcademicStructureRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _World(container, staff);
}

void main() {
  group('route and navigation permissions', () {
    testWidgets('a parent cannot reach any staff route', (tester) async {
      final world = await _pump(tester, role: UserRole.parent);
      for (final path in [
        '/staff',
        '/staff/new',
        '/staff/abc',
        '/staff/abc/edit',
        '/staff/departments',
        '/teachers',
        '/my-profile',
      ]) {
        await world.go(tester, path);
        expect(world.location, '/dashboard', reason: path);
      }
      expect(find.text('Staff'), findsNothing);
      expect(find.text('My Profile'), findsNothing);
    });

    testWidgets('a teacher has no staff directory — only My Profile', (
      tester,
    ) async {
      final world = await _pump(tester, role: UserRole.teacher);
      for (final path in [
        '/staff',
        '/staff/new',
        '/staff/abc',
        '/staff/abc/edit',
        '/staff/departments',
        '/staff/designations',
        '/teachers',
      ]) {
        await world.go(tester, path);
        expect(world.location, '/dashboard', reason: path);
      }
      expect(find.text('Staff'), findsNothing);
      expect(find.text('My Profile'), findsWidgets);

      await world.go(tester, '/my-profile');
      expect(world.location, '/my-profile');
    });

    testWidgets(
      'finance can browse staff and teachers but not create or edit',
      (tester) async {
        final world = await _pump(tester, role: UserRole.finance);
        await world.go(tester, '/staff');
        expect(world.location, '/staff');
        await world.go(tester, '/teachers');
        expect(world.location, '/teachers');
        for (final path in ['/staff/new', '/staff/abc/edit']) {
          await world.go(tester, path);
          expect(world.location, '/dashboard', reason: path);
        }
      },
    );

    testWidgets(
      'a branch admin can open the directory, the create form and the config pages',
      (tester) async {
        final world = await _pump(tester, role: UserRole.branchAdmin);
        for (final path in [
          '/staff',
          '/staff/new',
          '/staff/departments',
          '/staff/designations',
          '/teachers',
        ]) {
          await world.go(tester, path);
          expect(world.location, path);
        }
        expect(find.text('Staff'), findsWidgets);
      },
    );
  });

  group('staff list', () {
    final people = [
      fakeStaff('s1', first: 'Priya', last: 'Sharma', code: 'EMP-0001'),
      fakeStaff(
        's2',
        first: 'Arun',
        last: 'Kumar',
        code: 'EMP-0002',
        status: StaffStatus.onNotice,
      ),
    ];

    testWidgets(
      'desktop shows the table with the specified columns and names the department / designation',
      (tester) async {
        final repo = FakeStaffRepository(staff: [people.first]);
        final world = await _pump(
          tester,
          role: UserRole.branchAdmin,
          staffRepository: repo,
        );
        await world.go(tester, '/staff');

        // 'Department', 'Designation' and 'Status' also label the filters, so
        // look for the (upper-case) column headers specifically.
        expect(find.byType(DirectoryTable), findsOneWidget);
        for (final header in [
          'STAFF',
          'ID',
          'DEPARTMENT',
          'DESIGNATION',
          'STATUS',
        ]) {
          expect(find.text(header), findsOneWidget, reason: header);
        }
        expect(find.text('EMP-0001'), findsOneWidget);
        expect(find.text('Priya Sharma'), findsOneWidget);
        expect(find.text('Academic'), findsWidgets);
        expect(find.text('Teacher'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('mobile shows cards instead of a table, without overflow', (
      tester,
    ) async {
      final repo = FakeStaffRepository(staff: [people.first]);
      final world = await _pump(
        tester,
        role: UserRole.branchAdmin,
        staffRepository: repo,
        size: const Size(390, 844),
      );
      await world.go(tester, '/staff');

      expect(find.byType(DirectoryTable), findsNothing);
      expect(find.byType(DirectoryCard), findsOneWidget);
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tablet width renders without overflow', (tester) async {
      final repo = FakeStaffRepository(staff: people);
      final world = await _pump(
        tester,
        role: UserRole.branchAdmin,
        staffRepository: repo,
        size: const Size(800, 1000),
      );
      await world.go(tester, '/staff');
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'defaults to the ACTIVE roster; choosing "All statuses" refetches',
      (tester) async {
        final repo = FakeStaffRepository(staff: people);
        final world = await _pump(
          tester,
          role: UserRole.branchAdmin,
          staffRepository: repo,
        );
        await world.go(tester, '/staff');

        expect(repo.fetchCalls.last['status'], StaffStatus.active);
        expect(find.text('Priya Sharma'), findsOneWidget);
        expect(find.text('Arun Kumar'), findsNothing);

        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<StaffStatus?>, 'Active'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('All statuses').last);
        await tester.pumpAndSettle();

        expect(repo.fetchCalls.last['status'], isNull);
        expect(find.text('Arun Kumar'), findsOneWidget);
      },
    );

    testWidgets(
      'phone keeps filters out of the way: a Filters button, chips for what '
      'is applied, and a sheet to change them',
      (tester) async {
        final repo = FakeStaffRepository(staff: people);
        final world = await _pump(
          tester,
          role: UserRole.branchAdmin,
          staffRepository: repo,
          size: const Size(390, 844),
        );
        await world.go(tester, '/staff');

        // Nothing but the search box and one button; no dropdown on the page.
        expect(
          find.byType(DropdownButtonFormField<StaffStatus?>),
          findsNothing,
        );
        expect(find.text('Filters · 1'), findsOneWidget);
        expect(
          find.widgetWithText(InputChip, 'Status: Active'),
          findsOneWidget,
        );

        await tester.tap(find.text('Filters · 1'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DropdownButtonFormField<StaffStatus?>, 'Active'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('All statuses').last);
        await tester.pumpAndSettle();

        expect(repo.fetchCalls.last['status'], isNull);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Arun Kumar'), findsOneWidget);
        expect(find.byType(InputChip), findsNothing);
        expect(find.text('Filters'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('removing a filter chip refetches without that filter', (
      tester,
    ) async {
      final repo = FakeStaffRepository(staff: people);
      final world = await _pump(
        tester,
        role: UserRole.branchAdmin,
        staffRepository: repo,
        size: const Size(390, 844),
      );
      await world.go(tester, '/staff');

      await tester.tap(
        find.descendant(
          of: find.widgetWithText(InputChip, 'Status: Active'),
          matching: find.byIcon(Icons.clear),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.fetchCalls.last['status'], isNull);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets(
      'secondary actions sit in the ⋮ menu; Add staff stays the one button',
      (tester) async {
        final world = await _pump(
          tester,
          role: UserRole.branchAdmin,
          size: const Size(390, 844),
        );
        await world.go(tester, '/staff');

        expect(find.text('Import (CSV)'), findsNothing);
        expect(find.text('Departments'), findsNothing);
        expect(find.text('Add staff'), findsOneWidget);

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        for (final label in [
          'Import (CSV)',
          'Export (CSV)',
          'Give login access',
          'Departments',
          'Designations',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
      },
    );

    testWidgets(
      'stat chips show server-side headcounts and act as quick status filters',
      (tester) async {
        final repo = FakeStaffRepository(staff: people);
        final world = await _pump(
          tester,
          role: UserRole.branchAdmin,
          staffRepository: repo,
          size: const Size(390, 844),
        );
        await world.go(tester, '/staff');

        // Counted, not downloaded: the headline numbers come from count calls.
        expect(
          repo.countCalls,
          containsAll(<StaffStatus?>[
            null,
            StaffStatus.active,
            StaffStatus.onNotice,
            StaffStatus.inactive,
          ]),
        );
        expect(find.bySemanticsLabel('All: 2'), findsOneWidget);
        expect(find.bySemanticsLabel('Active: 1'), findsOneWidget);
        expect(find.bySemanticsLabel('On notice: 1'), findsOneWidget);

        await tester.tap(find.bySemanticsLabel('On notice: 1'));
        await tester.pumpAndSettle();
        expect(repo.fetchCalls.last['status'], StaffStatus.onNotice);
        expect(find.text('Arun Kumar'), findsOneWidget);
        expect(find.text('Priya Sharma'), findsNothing);

        await tester.tap(find.bySemanticsLabel('All: 2'));
        await tester.pumpAndSettle();
        expect(repo.fetchCalls.last['status'], isNull);
        expect(find.text('Priya Sharma'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tablet keeps the key columns of the table', (tester) async {
      final repo = FakeStaffRepository(staff: [people.first]);
      final world = await _pump(
        tester,
        role: UserRole.branchAdmin,
        staffRepository: repo,
        size: const Size(900, 1000),
      );
      await world.go(tester, '/staff');
      // Name, ID and status always; the others by the width the table has.
      for (final header in [
        'STAFF',
        'ID',
        'DEPARTMENT',
        'DESIGNATION',
        'STATUS',
      ]) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      for (final dropped in ['LOGIN', 'PHONE', 'EMPLOYMENT TYPE']) {
        expect(find.text(dropped), findsNothing, reason: dropped);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide desktop shows every column', (tester) async {
      final repo = FakeStaffRepository(staff: [people.first]);
      final world = await _pump(
        tester,
        role: UserRole.branchAdmin,
        staffRepository: repo,
        size: const Size(1700, 1000),
      );
      await world.go(tester, '/staff');
      for (final header in [
        'STAFF',
        'ID',
        'DEPARTMENT',
        'DESIGNATION',
        'LOGIN',
        'PHONE',
        'EMPLOYMENT TYPE',
        'STATUS',
      ]) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the empty state when nothing matches', (tester) async {
      final world = await _pump(
        tester,
        role: UserRole.branchAdmin,
        staffRepository: FakeStaffRepository(),
      );
      await world.go(tester, '/staff');
      expect(find.text('No staff found.'), findsOneWidget);
    });

    testWidgets(
      'shows a friendly error with a retry — never the raw exception',
      (tester) async {
        final repo = FakeStaffRepository(
          error: StateError('PERMISSION_DENIED: secret internals'),
        );
        final world = await _pump(
          tester,
          role: UserRole.branchAdmin,
          staffRepository: repo,
        );
        await world.go(tester, '/staff');

        expect(find.textContaining('PERMISSION_DENIED'), findsNothing);
        expect(find.textContaining('secret internals'), findsNothing);
        expect(
          find.text('Something went wrong. Please try again.'),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets(
      'typing a search queries by the chosen field and pauses the filters',
      (tester) async {
        final repo = FakeStaffRepository(staff: people);
        final world = await _pump(
          tester,
          role: UserRole.branchAdmin,
          staffRepository: repo,
        );
        await world.go(tester, '/staff');

        await tester.enterText(find.byType(TextField).first, 'pri');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        expect(repo.searchCalls, isNotEmpty);
        expect(repo.searchCalls.last['query'], 'pri');
        expect(find.text('Priya Sharma'), findsOneWidget);
        expect(find.textContaining('Filters are paused'), findsOneWidget);
      },
    );

    testWidgets('only managers see the Add staff action', (tester) async {
      final admin = await _pump(tester, role: UserRole.branchAdmin);
      await admin.go(tester, '/staff');
      expect(find.text('Add staff'), findsOneWidget);
    });

    testWidgets('finance sees the directory without Add staff', (tester) async {
      final world = await _pump(
        tester,
        role: UserRole.finance,
        staffRepository: FakeStaffRepository(staff: people),
      );
      await world.go(tester, '/staff');
      expect(find.text('Priya Sharma'), findsOneWidget);
      expect(find.text('Add staff'), findsNothing);
    });
  });

  group('my profile', () {
    testWidgets(
      'a teacher whose account is not linked to a staff record sees an explanation',
      (tester) async {
        final world = await _pump(tester, role: UserRole.teacher);
        await world.go(tester, '/my-profile');
        expect(
          find.textContaining("isn't linked to a staff record"),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a teacher sees their own profile, with Teaching but no management actions or Documents',
      (tester) async {
        final me = fakeStaff(
          's9',
          first: 'Meera',
          last: 'Iyer',
          code: 'EMP-0009',
          isTeacher: true,
          userId: _uid,
        );
        final world = await _pump(
          tester,
          role: UserRole.teacher,
          staffRepository: FakeStaffRepository(staff: [me]),
        );
        await world.go(tester, '/my-profile');

        expect(find.text('Meera Iyer'), findsWidgets);
        expect(find.text('Teaching'), findsWidgets);
        expect(find.text('Documents'), findsNothing);
        expect(find.byTooltip('Edit'), findsNothing);
        expect(find.byTooltip('Change status'), findsNothing);
        expect(find.byTooltip('Application account'), findsNothing);
        expect(find.text('Upload photo'), findsNothing);
        expect(find.text('Replace photo'), findsNothing);
      },
    );

    testWidgets('a non-teacher staff member has no Teaching tab', (
      tester,
    ) async {
      final me = fakeStaff(
        's9',
        first: 'Asha',
        last: 'Rao',
        code: 'EMP-0010',
        isTeacher: false,
        userId: _uid,
      );
      final world = await _pump(
        tester,
        role: UserRole.finance,
        staffRepository: FakeStaffRepository(staff: [me]),
      );
      await world.go(tester, '/my-profile');
      expect(find.text('Asha Rao'), findsWidgets);
      expect(
        find.text('Teaching'),
        findsOneWidget,
      ); // only the "Teaching: No" row label
      expect(find.byType(TabBar), findsNothing);
    });
  });

  group('staff profile (manager)', () {
    testWidgets(
      'shows sections, management actions, and Documents; Teaching only for teachers',
      (tester) async {
        final repo = FakeStaffRepository(
          staff: [
            fakeStaff('s1', first: 'Priya', last: 'Sharma', isTeacher: true),
            fakeStaff(
              's2',
              first: 'Dev',
              last: 'Nair',
              code: 'EMP-0002',
              isTeacher: false,
            ),
          ],
        );
        final world = await _pump(
          tester,
          role: UserRole.branchAdmin,
          staffRepository: repo,
        );

        await world.go(tester, '/staff/s1');
        expect(find.text('Personal'), findsOneWidget);
        expect(find.text('Contact'), findsOneWidget);
        expect(find.text('Employment'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Teaching'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Documents'), findsOneWidget);
        expect(find.byTooltip('Edit'), findsOneWidget);
        expect(find.byTooltip('Change status'), findsOneWidget);

        await world.go(tester, '/staff/s2');
        expect(find.widgetWithText(Tab, 'Teaching'), findsNothing);
        expect(find.widgetWithText(Tab, 'Documents'), findsOneWidget);
      },
    );

    testWidgets('an unknown id shows a not-found message', (tester) async {
      final world = await _pump(tester, role: UserRole.branchAdmin);
      await world.go(tester, '/staff/nope');
      expect(
        find.text('This staff member could not be found.'),
        findsOneWidget,
      );
    });

    testWidgets('the status dialog offers only legal moves', (tester) async {
      final repo = FakeStaffRepository(
        staff: [fakeStaff('s1', status: StaffStatus.active)],
      );
      final world = await _pump(
        tester,
        role: UserRole.branchAdmin,
        staffRepository: repo,
      );
      await world.go(tester, '/staff/s1');

      await tester.tap(find.byTooltip('Change status'));
      await tester.pumpAndSettle();
      expect(find.text('Change status'), findsWidgets);
      await tester.tap(find.byType(DropdownButtonFormField<StaffStatus>));
      await tester.pumpAndSettle();
      for (final status in StaffStatus.values.where(
        (s) => s != StaffStatus.active,
      )) {
        expect(
          find.text(status.displayName),
          findsWidgets,
          reason: status.name,
        );
      }
    });

    testWidgets('a resigned member\'s status dialog says the status is final', (
      tester,
    ) async {
      final repo = FakeStaffRepository(
        staff: [fakeStaff('s1', status: StaffStatus.resigned)],
      );
      final world = await _pump(
        tester,
        role: UserRole.branchAdmin,
        staffRepository: repo,
      );
      await world.go(tester, '/staff/s1');

      await tester.tap(find.byTooltip('Change status'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('final and cannot be changed'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsNothing);
    });
  });

  group('teachers list', () {
    testWidgets('asks for an academic year when none exists', (tester) async {
      final world = await _pump(tester, role: UserRole.branchAdmin);
      await world.go(tester, '/teachers');
      expect(find.textContaining('Create an academic year'), findsOneWidget);
    });
  });

  group('create form', () {
    // Tall viewports so the whole (lazily built) list is on screen at once;
    // the widths are what matter for the overflow check.
    for (final size in [const Size(360, 3200), const Size(1400, 1800)]) {
      testWidgets(
        'lays out without overflow at ${size.width.toInt()}px wide and validates required fields',
        (tester) async {
          final world = await _pump(
            tester,
            role: UserRole.branchAdmin,
            size: size,
          );
          await world.go(tester, '/staff/new');

          expect(find.text('Add staff member'), findsOneWidget);
          expect(find.text('Has teaching responsibility'), findsOneWidget);

          await tester.tap(find.text('Create staff member'));
          await tester.pumpAndSettle();
          expect(find.text('Employee code is required.'), findsOneWidget);
          expect(find.text('First name is required.'), findsOneWidget);
          expect(find.text('Last name is required.'), findsOneWidget);
          expect(find.text('Date of birth is required.'), findsOneWidget);
          expect(find.text('Gender is required.'), findsOneWidget);
          expect(find.text('Phone number is required.'), findsOneWidget);
          expect(find.text('Department is required.'), findsOneWidget);
          expect(find.text('Designation is required.'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$size');
        },
      );
    }
  });
}

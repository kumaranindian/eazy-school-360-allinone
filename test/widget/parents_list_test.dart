import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/constants/activation_status.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/students/domain/paged_result.dart';
import 'package:eazy_school_360/features/students/domain/parent.dart';
import 'package:eazy_school_360/features/students/domain/parent_repository.dart';
import 'package:eazy_school_360/features/students/presentation/providers/parent_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _uid = 'uid-1';

Parent _parent(String id, String first, String last, ActivationStatus status) =>
    Parent(
      parentId: id,
      schoolId: 'school-1',
      branchId: 'main',
      firstName: first,
      lastName: last,
      phone: '9876543210',
      email: '$first@example.com',
      status: status,
    );

class _FakeParents implements ParentRepository {
  final parents = [
    _parent('p1', 'Lakshmi', 'Nair', ActivationStatus.active),
    _parent('p2', 'Vikram', 'Rao', ActivationStatus.inactive),
  ];
  final List<ActivationStatus?> fetchStatuses = [];
  final List<String> searches = [];

  @override
  Future<PagedResult<Parent>> fetchParents({
    required String schoolId,
    required String branchId,
    ActivationStatus? status,
    int pageSize = 25,
    Object? cursor,
  }) async {
    fetchStatuses.add(status);
    return PagedResult(
      items: parents
          .where((p) => status == null || p.status == status)
          .toList(),
      nextCursor: null,
    );
  }

  @override
  Future<PagedResult<Parent>> searchParentsByName({
    required String schoolId,
    required String branchId,
    required String query,
    int pageSize = 25,
    Object? cursor,
  }) async {
    searches.add(query);
    return PagedResult(
      items: parents
          .where(
            (p) => p.displayName.toLowerCase().startsWith(query.toLowerCase()),
          )
          .toList(),
      nextCursor: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeParents> _pump(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final repo = _FakeParents();
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
          _uid: const UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace Hopper',
            email: 'grace@example.com',
            role: UserRole.branchAdmin,
            status: UserStatus.active,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {
            'school-1': const School(
              schoolId: 'school-1',
              name: 'Rosewood High',
              email: 'office@rosewood.example',
              status: SchoolStatus.active,
            ),
          },
          branches: {
            'school-1/main': const Branch(
              branchId: 'main',
              schoolId: 'school-1',
              name: 'Main',
              status: BranchStatus.active,
            ),
          },
        ),
      ),
      parentRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go('/parents');
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('phone: search and a Filters button; actions in the ⋮ menu', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Lakshmi Nair'), findsOneWidget);
    expect(find.byType(DropdownButton<ActivationStatus?>), findsNothing);
    expect(find.byIcon(Icons.vpn_key_outlined), findsNothing);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Give login access'), findsOneWidget);
    expect(find.text('Refresh parent access'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the status filter sheet changes the list', (tester) async {
    final repo = await _pump(tester);
    expect(repo.fetchStatuses.last, isNull);
    expect(find.text('Vikram Rao'), findsOneWidget);

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        DropdownButtonFormField<ActivationStatus?>,
        'All statuses',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Active').last);
    await tester.pumpAndSettle();
    expect(repo.fetchStatuses.last, ActivationStatus.active);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Vikram Rao'), findsNothing);
    expect(find.widgetWithText(InputChip, 'Status: Active'), findsOneWidget);
  });

  testWidgets('search waits for a pause in typing', (tester) async {
    final repo = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'v');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'vi');
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.searches, isEmpty);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(repo.searches, ['vi']);
    expect(find.text('Vikram Rao'), findsOneWidget);
  });

  for (final (name, size) in [
    ('small phone', const Size(320, 640)),
    ('tablet', const Size(820, 1180)),
    ('desktop', const Size(1440, 900)),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('lays out without overflow: $name, text x$scale', (
        tester,
      ) async {
        await _pump(tester, size: size, textScale: scale);
        expect(find.text('Lakshmi Nair'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

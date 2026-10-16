import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/tenant/tenant_context_provider.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/login_access.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/login_access_providers.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:eazy_school_360/features/users/presentation/widgets/branch_access_section.dart';
import 'package:eazy_school_360/shared/branding/branch_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';
import '../support/login_access_fakes.dart';

Branch _b(String id, String name) => Branch(
  branchId: id,
  schoolId: 's1',
  name: name,
  status: BranchStatus.active,
);

UserProfile _user({
  UserRole role = UserRole.teacher,
  Map<String, UserRole> extra = const {},
}) => UserProfile(
  userId: 'u1',
  schoolId: 's1',
  branchId: 'north',
  name: 'Asha',
  email: 'a@x.example',
  role: role,
  status: UserStatus.active,
  branchRoles: extra,
);

List<Override> _overrides(UserProfile profile) => [
  authRepositoryProvider.overrideWithValue(
    FakeAuthRepository(
      signedInAs: const AppUser(uid: 'u1', email: 'a@x.example'),
    ),
  ),
  userRepositoryProvider.overrideWithValue(FakeUserRepository({'u1': profile})),
  schoolRepositoryProvider.overrideWithValue(
    FakeSchoolRepository(
      schools: const {
        's1': School(
          schoolId: 's1',
          name: 'Rosewood',
          email: 'o@r.example',
          status: SchoolStatus.active,
        ),
      },
      branches: {
        's1/north': _b('north', 'North Campus'),
        's1/south': _b('south', 'South Campus'),
      },
    ),
  ),
];

Future<ProviderContainer> _pumpSwitcher(
  WidgetTester tester,
  UserProfile profile,
) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/x',
    routes: [
      GoRoute(
        path: '/x',
        builder: (_, _) => Scaffold(
          appBar: AppBar(actions: const [BranchSwitcher()]),
          body: const Text('page'),
        ),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, _) => const Scaffold(body: Text('dashboard')),
      ),
    ],
  );
  final container = ProviderContainer(overrides: _overrides(profile));
  addTearDown(container.dispose);
  container.listen(tenantContextProvider, (_, _) {});
  await container.read(tenantContextProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('BranchSwitcher', () {
    testWidgets('is absent for a single-branch user', (tester) async {
      await _pumpSwitcher(tester, _user());
      expect(find.byTooltip('Switch branch'), findsNothing);
    });

    testWidgets('lists the branches with the role held in each; switching '
        'changes the tenant and returns to the dashboard', (tester) async {
      final c = await _pumpSwitcher(
        tester,
        _user(extra: {'south': UserRole.branchAdmin}),
      );
      expect(find.text('North Campus'), findsOneWidget);
      await tester.tap(find.byTooltip('Switch branch'));
      await tester.pumpAndSettle();
      expect(find.text('North Campus · Teacher'), findsOneWidget);
      expect(find.text('South Campus · Branch Admin'), findsOneWidget);

      await tester.tap(find.text('South Campus · Branch Admin'));
      await tester.pumpAndSettle();

      final t = c.read(tenantContextProvider).value!;
      expect(t.role, UserRole.branchAdmin);
      expect(t.branch?.branchId, 'south');
      expect(find.text('dashboard'), findsOneWidget);
    });

    testWidgets('does not overflow on a phone at large text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await _pumpSwitcher(tester, _user(extra: {'south': UserRole.finance}));
      expect(tester.takeException(), isNull);
    });
  });

  group('BranchAccessSection', () {
    Future<FakeLoginAccessRepository> pump(
      WidgetTester tester, {
      UserProfile? target,
    }) async {
      tester.view.physicalSize = const Size(700, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = FakeLoginAccessRepository(access: _accessStub());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._overrides(target ?? _user()),
            loginAccessRepositoryProvider.overrideWithValue(fake),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: BranchAccessSection(schoolId: 's1', uid: 'u1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('grants a role in another branch through the server call', (
      tester,
    ) async {
      final fake = await pump(tester);
      expect(find.text('South Campus'), findsOneWidget);
      expect(find.text('North Campus'), findsNothing); // the home branch

      await tester.tap(find.text('No access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finance').last);
      await tester.pumpAndSettle();

      expect(fake.branchAccessCalls, hasLength(1));
      expect(fake.branchAccessCalls.single.branchId, 'south');
      expect(fake.branchAccessCalls.single.uid, 'u1');
      expect(fake.branchAccessCalls.single.role, UserRole.finance);
    });

    testWidgets('shows the server refusal in plain words', (tester) async {
      final fake = await pump(tester);
      fake.branchAccessError = Exception('boom');
      await tester.tap(find.text('No access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Teacher').last);
      await tester.pumpAndSettle();
      expect(fake.branchAccessCalls, isEmpty);
      expect(
        find.textContaining('went wrong', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('renders nothing for a parent login', (tester) async {
      await pump(tester, target: _user(role: UserRole.parent));
      expect(find.text('Other branches'), findsNothing);
    });
  });
}

LoginAccess _accessStub() => const LoginAccess(
  id: 't1',
  uid: 'u1',
  kind: LoginKind.staff,
  name: 'Asha',
  userType: 'TEACHER',
  registeredEmail: 'a@x.example',
  registeredPhone: null,
  schoolMethods: [],
  hasAccount: true,
  enabled: true,
  methods: [],
  effective: [],
  activation: LoginActivation.active,
  emailVerified: true,
  phoneVerified: false,
  lastLogin: null,
  legacy: false,
  manageable: true,
);

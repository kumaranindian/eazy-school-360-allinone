import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/login_method.dart';
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
import 'package:eazy_school_360/features/users/presentation/pages/login_access_page.dart';
import 'package:eazy_school_360/features/users/presentation/providers/login_access_providers.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/login_access_fakes.dart';

const _sizes = <(String, Size, double)>[
  ('phone', Size(360, 740), 1.0),
  ('phone large text', Size(360, 740), 1.5),
  ('tablet', Size(820, 1180), 1.0),
  ('desktop', Size(1440, 900), 1.0),
];

LoginAccess _access({
  bool hasAccount = true,
  bool enabled = true,
  List<LoginMethod> methods = const [LoginMethod.password],
  String? email = 'asha.long.email.address@school-district.example.org',
  String? phone = '+919876543210',
  bool manageable = true,
  List<LoginMethod> school = LoginMethod.values,
}) => LoginAccess(
  id: 't1',
  uid: hasAccount ? 'uid-t1' : null,
  kind: LoginKind.parent,
  name: 'Asha Krishnamurthy-Subramanian',
  userType: 'PARENT',
  registeredEmail: email,
  registeredPhone: phone,
  schoolMethods: school,
  hasAccount: hasAccount,
  enabled: hasAccount && enabled,
  methods: hasAccount ? methods : const [],
  effective: hasAccount && enabled ? methods : const [],
  activation: hasAccount ? LoginActivation.active : LoginActivation.noAccount,
  emailVerified: true,
  phoneVerified: false,
  lastLogin: DateTime(2026, 5, 3, 9, 30),
  legacy: false,
  manageable: manageable,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Widget home,
  Size size = const Size(1440, 900),
  double textScale = 1.0,
  FakeLoginAccessRepository? repo,
  FakeAuthRepository? auth,
  UserRole role = UserRole.schoolAdmin,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        auth ??
            FakeAuthRepository(
              signedInAs: const AppUser(uid: 'u1', email: 'g@example.com'),
            ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          'u1': UserProfile(
            userId: 'u1',
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace',
            email: 'g@example.com',
            role: role,
            status: UserStatus.active,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {
            'school-1': const School(
              schoolId: 'school-1',
              name: 'Rosewood',
              email: 'o@r.example',
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
      loginAccessRepositoryProvider.overrideWithValue(
        repo ?? FakeLoginAccessRepository(access: _access()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Widget _opener() => Builder(
  builder: (context) => Center(
    child: ElevatedButton(
      onPressed: () => Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const LoginAccessPage(
            kind: LoginKind.parent,
            id: 't1',
            fallbackName: 'Asha',
          ),
        ),
      ),
      child: const Text('open'),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size, scale) in _sizes) {
    testWidgets('page lays out without overflow on $name', (tester) async {
      await _pump(tester, home: _opener(), size: size, textScale: scale);
      await _open(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Login Access'), findsWidgets);
      expect(find.text('Registered mobile'), findsOneWidget);
      expect(find.text('Registered email'), findsOneWidget);
      expect(find.text('Last login'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('page keeps the explanatory text and the four actions', (
    tester,
  ) async {
    await _pump(tester, home: _opener());
    await _open(tester);
    expect(
      find.text(
        'Turning this off blocks sign-in everywhere. Nothing is deleted.',
      ),
      findsOneWidget,
    );
    for (final label in [
      'Reset Password',
      'Check Access',
      'Sign Out All Devices',
    ]) {
      expect(
        find.text(label, skipOffstage: false),
        findsWidgets,
        reason: label,
      );
    }
    expect(
      find.text('Phone (WhatsApp code)', skipOffstage: false),
      findsWidgets,
    );
  });

  testWidgets(
    'turning the switch off and saving writes and stays with a notice',
    (tester) async {
      final repo = FakeLoginAccessRepository(access: _access());
      await _pump(tester, home: _opener(), repo: repo);
      await _open(tester);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Turn off'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.writes.single.enabled, isFalse);
      expect(find.textContaining('Saved.'), findsOneWidget);
      // Closing now reports the change to the caller.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginAccessPage), findsNothing);
    },
  );

  testWidgets('Close leaves without writing', (tester) async {
    final repo = FakeLoginAccessRepository(access: _access());
    await _pump(tester, home: _opener(), repo: repo);
    await _open(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
    await tester.pumpAndSettle();
    expect(repo.writes, isEmpty);
    expect(find.byType(LoginAccessPage), findsNothing);
  });
}

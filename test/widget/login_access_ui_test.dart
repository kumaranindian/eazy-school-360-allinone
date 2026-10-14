import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/login_method.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/authentication/presentation/widgets/phone_otp_form.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/login_access.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/pages/auth_settings_page.dart';
import 'package:eazy_school_360/features/users/presentation/providers/login_access_providers.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:eazy_school_360/features/users/presentation/widgets/login_access_dialog.dart';
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
  kind: LoginKind.staff,
  name: 'Asha Krishnamurthy-Subramanian',
  userType: 'TEACHER',
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
      child: MaterialApp(home: Scaffold(body: home)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The button inside the confirmation AlertDialog (the page also has one with
/// the same label).
Finder _confirm(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, label),
);

Widget _opener() => Builder(
  builder: (context) => Center(
    child: ElevatedButton(
      onPressed: () => showLoginAccessDialog(
        context: context,
        schoolId: 'school-1',
        branchId: 'main',
        kind: LoginKind.staff,
        id: 't1',
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
  group('Login access dialog', () {
    for (final (name, size, scale) in _sizes) {
      testWidgets('lays out without overflow on $name', (tester) async {
        await _pump(tester, home: _opener(), size: size, textScale: scale);
        await _open(tester);
        expect(find.text('Login access'), findsNWidgets(2));
        expect(find.text('Registered mobile'), findsOneWidget);
        expect(find.text('Registered email'), findsOneWidget);
        expect(find.text('Last login'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows only what the school allows and why others are off', (
      tester,
    ) async {
      final repo = FakeLoginAccessRepository(
        access: _access(school: [LoginMethod.password], phone: null),
      );
      await _pump(tester, home: _opener(), repo: repo);
      await _open(tester);
      expect(
        find.textContaining('Turned off for this school'),
        findsNWidgets(2),
      );
      // Unavailable methods cannot be ticked.
      final google = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Google'),
      );
      expect(google.onChanged, isNull);
    });

    testWidgets('changing methods asks for confirmation, then saves', (
      tester,
    ) async {
      final repo = FakeLoginAccessRepository(access: _access());
      await _pump(tester, home: _opener(), repo: repo);
      await _open(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Google'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save login access?'), findsOneWidget);
      expect(repo.writes, isEmpty, reason: 'nothing is sent before confirming');
      await tester.tap(_confirm('Save'));
      await tester.pumpAndSettle();
      expect(repo.writes.single.methods, [
        LoginMethod.password,
        LoginMethod.google,
      ]);
      expect(repo.writes.single.enabled, isTrue);
      expect(find.textContaining('Saved'), findsOneWidget);
    });

    testWidgets('turning access off warns about sign-out and revokes', (
      tester,
    ) async {
      final repo = FakeLoginAccessRepository(access: _access());
      await _pump(tester, home: _opener(), repo: repo);
      await _open(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('signed out of every device'), findsOneWidget);
      await tester.tap(_confirm('Turn off'));
      await tester.pumpAndSettle();
      expect(repo.writes.single.enabled, isFalse);
      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('server refusal is shown and nothing claims success', (
      tester,
    ) async {
      final repo = FakeLoginAccessRepository(access: _access())
        ..setError = const AccessPolicyFailure(
          'This mobile number is already used for phone sign-in by another account.',
          reason: 'PHONE_IN_USE',
        );
      await _pump(tester, home: _opener(), repo: repo);
      await _open(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Google'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(_confirm('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('already used'), findsOneWidget);
      expect(find.text('Saved.'), findsNothing);
    });

    testWidgets('a person without a login can be given one', (tester) async {
      final repo = FakeLoginAccessRepository(
        access: _access(hasAccount: false),
      );
      await _pump(tester, home: _opener(), repo: repo);
      await _open(tester);
      expect(find.text('Not set up'), findsOneWidget);
      await tester.tap(find.text('Create login'));
      await tester.pumpAndSettle();
      await tester.tap(_confirm('Save'));
      await tester.pumpAndSettle();
      expect(repo.writes, hasLength(1));
      expect(repo.writes.single.enabled, isTrue);
    });

    testWidgets('own account / administrators are read-only', (tester) async {
      final repo = FakeLoginAccessRepository(
        access: _access(manageable: false),
      );
      await _pump(tester, home: _opener(), repo: repo);
      await _open(tester);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Save'), findsNothing);
      expect(find.textContaining('cannot change login access'), findsOneWidget);
    });
  });

  group('Authentication settings page', () {
    for (final (name, size, scale) in _sizes) {
      testWidgets('lays out without overflow on $name', (tester) async {
        await _pump(
          tester,
          home: const AuthSettingsPage(),
          size: size,
          textScale: scale,
        );
        expect(find.text('Email & password'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Phone (WhatsApp code)'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Google'), findsOneWidget);
        expect(find.text('Phone (WhatsApp code)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('phone sign-in cannot be switched on until configured', (
      tester,
    ) async {
      await _pump(tester, home: const AuthSettingsPage());
      final tile = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Phone (WhatsApp code)'),
      );
      expect(tile.onChanged, isNull);
      expect(
        find.textContaining('Not configured on the server'),
        findsOneWidget,
      );
    });

    testWidgets('turning a method off warns, then saves', (tester) async {
      final repo = FakeLoginAccessRepository(access: _access());
      await _pump(tester, home: const AuthSettingsPage(), repo: repo);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save changes'),
            )
            .onPressed,
        isNull,
        reason: 'nothing to save yet',
      );
      await tester.tap(find.widgetWithText(SwitchListTile, 'Google'));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('locked out'), findsOneWidget);
      await tester.tap(_confirm('Save'));
      await tester.pumpAndSettle();
      expect(repo.settingsWrites.single.google, isFalse);
      expect(repo.settingsWrites.single.emailPassword, isTrue);
      expect(find.textContaining('3 accounts updated'), findsOneWidget);
    });

    testWidgets('cannot turn every method off', (tester) async {
      final repo = FakeLoginAccessRepository(access: _access());
      await _pump(tester, home: const AuthSettingsPage(), repo: repo);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Google'));
      await tester.pump();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Email & password'));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('at least one sign-in method'),
        findsOneWidget,
      );
      expect(repo.settingsWrites, isEmpty);
    });

    testWidgets('server lockout refusal is explained', (tester) async {
      final repo = FakeLoginAccessRepository(access: _access())
        ..settingsError = const AccessPolicyFailure(
          'That change would stop you from signing in yourself.',
          reason: 'CALLER_LOCKOUT',
        );
      await _pump(tester, home: const AuthSettingsPage(), repo: repo);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Google'));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      await tester.tap(_confirm('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('stop you from signing in'), findsOneWidget);
    });

    testWidgets('non-admins cannot open it', (tester) async {
      await _pump(
        tester,
        home: const AuthSettingsPage(),
        role: UserRole.teacher,
      );
      expect(find.textContaining('Only school administrators'), findsOneWidget);
    });
  });

  group('Phone OTP form', () {
    for (final (name, size, scale) in _sizes) {
      testWidgets('fits on $name', (tester) async {
        await _pump(
          tester,
          home: SingleChildScrollView(child: PhoneOtpForm(onBack: () {})),
          size: size,
          textScale: scale,
        );
        expect(find.text('Send code'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('validates, requests a code, then verifies it', (tester) async {
      final auth = FakeAuthRepository();
      await _pump(
        tester,
        home: SingleChildScrollView(child: PhoneOtpForm(onBack: () {})),
        auth: auth,
      );
      await tester.tap(find.text('Send code'));
      await tester.pump();
      expect(find.text('Enter your registered mobile number'), findsOneWidget);
      expect(auth.requestedPhones, isEmpty);

      await tester.enterText(find.byType(TextFormField), '98765 43210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(auth.requestedPhones, ['98765 43210']);
      expect(find.textContaining('Resend code in'), findsOneWidget);

      await tester.tap(find.text('Verify and sign in'));
      await tester.pump();
      expect(find.text('Enter the 6-digit code'), findsOneWidget);
      expect(auth.verifiedCodes, isEmpty);

      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.text('Verify and sign in'));
      await tester.pumpAndSettle();
      expect(auth.verifiedCodes, ['123456']);
    });

    testWidgets('a refusal from the server is shown to the user', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..otpError = const AccessPolicyFailure(
          'Phone sign-in is not available right now. Use another sign-in method.',
          reason: 'OTP_UNAVAILABLE',
        );
      await _pump(
        tester,
        home: SingleChildScrollView(child: PhoneOtpForm(onBack: () {})),
        auth: auth,
      );
      await tester.enterText(find.byType(TextFormField), '9876543210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not available right now'), findsOneWidget);
      expect(find.text('Send code'), findsOneWidget);
    });
  });
}

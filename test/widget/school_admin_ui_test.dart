import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/auth_repository.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:eazy_school_360/features/users/domain/school_admin.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/school_admin_providers.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);

class _FakeAdmins implements SchoolAdminRepository {
  final List<SchoolAdminSummary> admins = [
    const SchoolAdminSummary(
      uid: 'uid-1',
      name: 'Grace Hopper',
      email: 'grace@example.com',
      status: 'ACTIVE',
    ),
  ];
  final List<({String name, String email, PasswordSetupOption option})>
  created = [];
  Object? failWith;

  @override
  Future<List<SchoolAdminSummary>> list(String schoolId) async => [...admins];

  @override
  Future<CreatedSchoolAdmin> create({
    required String schoolId,
    required String name,
    required String email,
    String? phone,
    required PasswordSetup passwordSetup,
  }) async {
    if (failWith != null) throw failWith!;
    created.add((name: name, email: email, option: passwordSetup.option));
    final temp = passwordSetup.option == PasswordSetupOption.randomTemp;
    return CreatedSchoolAdmin(
      uid: 'new-uid',
      name: name,
      email: email.toLowerCase(),
      passwordSet: temp,
      tempPassword: temp ? 'Temp1234Pass' : null,
    );
  }
}

class _MailAuth extends FakeAuthRepository {
  final List<String> resetEmails = [];
  _MailAuth({super.signedInAs});

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    resetEmails.add(email);
  }
}

Future<({_FakeAdmins admins, _MailAuth auth})> _pump(
  WidgetTester tester,
  UserRole role, {
  Size size = const Size(1280, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final admins = _FakeAdmins();
  final auth = _MailAuth(
    signedInAs: const AppUser(uid: 'uid-1', email: 'grace@example.com'),
  );
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(auth as AuthRepository),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          'uid-1': UserProfile(
            userId: 'uid-1',
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
        FakeSchoolRepository(schools: {'school-1': _school}),
      ),
      schoolAdminRepositoryProvider.overrideWithValue(admins),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(AppRoutes.users);
  await tester.pumpAndSettle();
  return (admins: admins, auth: auth);
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Full name'),
    'New Person',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email'),
    'New@Example.com',
  );
}

void main() {
  testWidgets('a school admin sees the admins and an Add school admin button', (
    tester,
  ) async {
    await _pump(tester, UserRole.schoolAdmin);
    expect(find.text('Grace Hopper'), findsWidgets);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Add school admin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a branch admin is told only a school admin can do this', (
    tester,
  ) async {
    await _pump(tester, UserRole.branchAdmin);
    expect(find.text('Add school admin'), findsNothing);
    expect(find.textContaining('Only a school admin'), findsOneWidget);
  });

  testWidgets('the form checks the name and email before calling the server', (
    tester,
  ) async {
    final w = await _pump(tester, UserRole.schoolAdmin);
    await tester.tap(find.text('Add school admin'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add school admin'));
    await tester.pumpAndSettle();
    expect(find.text('Enter their name.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(w.admins.created, isEmpty);
  });

  testWidgets(
    'activation email: creates the admin and sends the set-password email',
    (tester) async {
      final w = await _pump(tester, UserRole.schoolAdmin);
      await tester.tap(find.text('Add school admin'));
      await tester.pumpAndSettle();
      await _fill(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Add school admin'));
      await tester.pumpAndSettle();
      expect(
        w.admins.created.single.option,
        PasswordSetupOption.activationEmail,
      );
      expect(w.auth.resetEmails, ['new@example.com']);
      expect(find.textContaining('is now a school admin'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Add school admin'), findsOneWidget);
    },
  );

  testWidgets('random temporary password is shown once and no email is sent', (
    tester,
  ) async {
    final w = await _pump(tester, UserRole.schoolAdmin);
    await tester.tap(find.text('Add school admin'));
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.tap(find.text('Random temporary password'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add school admin'));
    await tester.pumpAndSettle();
    expect(find.text('Temp1234Pass'), findsOneWidget);
    expect(w.auth.resetEmails, isEmpty);
  });

  testWidgets(
    'a server refusal (email already used) is shown and nothing is added',
    (tester) async {
      final w = await _pump(tester, UserRole.schoolAdmin);
      w.admins.failWith = const AccessPolicyFailure(
        'That email already belongs to another login.',
        reason: 'EMAIL_IN_USE',
      );
      await tester.tap(find.text('Add school admin'));
      await tester.pumpAndSettle();
      await _fill(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Add school admin'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('already belongs to another login'),
        findsOneWidget,
      );
      expect(find.text('Done'), findsNothing);
      expect(w.auth.resetEmails, isEmpty);
    },
  );

  for (final (name, size) in [
    ('phone', const Size(360, 740)),
    ('tablet', const Size(820, 1180)),
  ]) {
    testWidgets('page and dialog lay out without overflow: $name', (
      tester,
    ) async {
      await _pump(tester, UserRole.schoolAdmin, size: size);
      await tester.tap(find.text('Add school admin').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}

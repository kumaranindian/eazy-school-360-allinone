import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/mfa.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_role.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/providers/platform_console_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/platform_fakes.dart';

// QA PLAT-01 DEF-06: reloading a /platform/* page kept the session but landed
// on /platform. A reload starts the app at the browser's URL while sign-in,
// the profile and the second-factor check are still loading.

const _uid = 'uid-1';

Future<String> _reloadAt(
  WidgetTester tester,
  String location, {
  bool secured = true,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.binding.platformDispatcher.defaultRouteNameTestValue = location;
  addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
  final auth =
      FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'grace@avail404.com'),
        )
        ..security = SessionSecurity(
          secondFactorSignedIn: secured,
          enrolledFactors: 1,
        );
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: const UserProfile(
            userId: _uid,
            schoolId: null,
            branchId: null,
            name: 'Grace',
            email: 'grace@avail404.com',
            role: UserRole.platformAdmin,
            status: UserStatus.active,
            platformRole: PlatformRole.owner,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {
            'school-1': const School(
              schoolId: 'school-1',
              name: 'Rosewood High',
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
      platformConsoleRepositoryProvider.overrideWithValue(
        FakePlatformConsoleRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .toString();
}

void main() {
  for (final page in const [
    '/platform/schools',
    '/platform/schools/school-1',
    '/platform/audit-trail',
  ]) {
    testWidgets('reloading $page stays on $page', (tester) async {
      expect(await _reloadAt(tester, page), page);
    });
  }

  testWidgets('without the second factor it asks for it, keeping the page', (
    tester,
  ) async {
    final at = await _reloadAt(
      tester,
      '/platform/schools/school-1',
      secured: false,
    );
    expect(Uri.parse(at).path, '/platform/mfa');
    expect(Uri.parse(at).queryParameters['from'], '/platform/schools/school-1');
  });

  testWidgets('a school page is never a destination for a platform admin', (
    tester,
  ) async {
    expect(await _reloadAt(tester, '/students'), '/platform');
  });
}

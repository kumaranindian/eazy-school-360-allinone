import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_role.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/providers/platform_console_providers.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/platform_fakes.dart';

const _uid = 'uid-1';
// A long address, as real ones are: it is what pushed the app-bar actions
// over the back arrow (DEF-02 / DEF-09).
const _email = 'karthikeyan.platform.administrator@avail404.com';

Future<ProviderContainer> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: _email),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: const UserProfile(
            userId: _uid,
            schoolId: null,
            branchId: null,
            name: 'Platform Admin',
            email: _email,
            role: UserRole.platformAdmin,
            status: UserStatus.active,
            platformRole: PlatformRole.owner,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
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
  container.read(appRouterProvider).go(AppRoutes.platformSchools);
  await tester.pumpAndSettle();
  return container;
}

String _path(ProviderContainer c) =>
    c.read(appRouterProvider).routerDelegate.currentConfiguration.uri.path;

void main() {
  for (final width in const [1280.0, 800.0, 360.0, 250.0]) {
    testWidgets('Schools app bar at $width px: back arrow is free and works', (
      tester,
    ) async {
      final c = await _pump(tester, width);
      expect(tester.takeException(), isNull);

      final back = tester.getRect(find.byTooltip('Platform home'));
      final defaults = tester.getRect(
        find.byKey(const ValueKey('schools-defaults')),
      );
      expect(
        back.overlaps(defaults),
        isFalse,
        reason: 'Default modules must not sit on the back arrow',
      );
      expect(defaults.left, greaterThan(back.right));

      final account = find.byKey(const ValueKey('platform-account'));
      expect(account, findsOneWidget);
      expect(
        tester.getRect(account).overlaps(back),
        isFalse,
        reason: 'the email/role must not cover the back arrow',
      );

      await tester.tap(find.byTooltip('Platform home'));
      await tester.pumpAndSettle();
      expect(_path(c), AppRoutes.platformHome);
    });
  }
}

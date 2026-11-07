import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/branding/tenant_branding.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/branding/presentation/providers/branding_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/branding_fakes.dart';
import '../support/fakes.dart';

const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);

Future<(ProviderContainer, FakeBrandingRepository)> _pump(
  WidgetTester tester, {
  required String route,
  UserRole role = UserRole.schoolAdmin,
  Size size = const Size(1200, 1600),
  double textScale = 1.0,
  FakeBrandingRepository? repo,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final fake = repo ?? FakeBrandingRepository();
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      brandingRepositoryProvider.overrideWithValue(fake),
      brandingCacheProvider.overrideWithValue(MemoryBrandingCache()),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: 'uid-1', email: 'g@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          'uid-1': UserProfile(
            userId: 'uid-1',
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
        FakeSchoolRepository(schools: {'school-1': _school}),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(route);
  await tester.pumpAndSettle();
  return (container, fake);
}

Finder _save() => find.byKey(const ValueKey('branding-save'));
Finder _reset() => find.byKey(const ValueKey('branding-reset'));
bool _enabled(WidgetTester t, Finder f) =>
    t.widget<FilledButton>(f).onPressed != null;

void main() {
  group('School theme page', () {
    for (final (name, size) in [
      ('small phone', const Size(320, 640)),
      ('phone', const Size(390, 844)),
      ('tablet', const Size(820, 1180)),
      ('desktop', const Size(1440, 900)),
    ]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('lays out without overflow: $name, text x$scale', (
          tester,
        ) async {
          await _pump(
            tester,
            route: AppRoutes.settingsBranding,
            size: size,
            textScale: scale,
          );
          expect(find.text('School theme'), findsWidgets);
          expect(find.text('Preview'), findsOneWidget);
          expect(find.byTooltip('Back to Settings'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -3000),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('picking a preset and saving writes it for the school', (
      tester,
    ) async {
      final (_, repo) = await _pump(tester, route: AppRoutes.settingsBranding);
      expect(_enabled(tester, _save()), isFalse); // nothing changed yet
      await tester.tap(find.byKey(const ValueKey('preset-indigo')));
      await tester.pumpAndSettle();
      expect(_enabled(tester, _save()), isTrue);
      await tester.ensureVisible(_save());
      await tester.tap(_save());
      await tester.pumpAndSettle();
      expect(repo.saved, hasLength(1));
      expect(repo.saved.single['schoolId'], 'school-1');
      expect(repo.saved.single['preset'], 'indigo');
      // The app itself now wears the new colours.
      final primary = Theme.of(
        tester.element(find.text('School theme').first),
      ).colorScheme.primary;
      expect(primary, BrandPresets.builtIn[1].colors.primary);
    });

    testWidgets('an unreadable colour disables save and says why', (
      tester,
    ) async {
      await _pump(tester, route: AppRoutes.settingsBranding);
      await tester.ensureVisible(find.byKey(const ValueKey('color-text')));
      final hex = find.descendant(
        of: find.byKey(const ValueKey('color-text')),
        matching: find.byType(TextField),
      );
      await tester.enterText(hex, '#DDDDDD');
      await tester.pumpAndSettle();
      expect(find.textContaining('needs 4.5:1'), findsWidgets);
      expect(_enabled(tester, _save()), isFalse);
    });

    testWidgets('reset returns the school to the platform default', (
      tester,
    ) async {
      final repo = FakeBrandingRepository({
        'school-1': TenantBranding(
          schoolId: 'school-1',
          version: 3,
          presetId: 'indigo',
          colors: BrandPresets.builtIn[1].colors,
        ),
      });
      await _pump(tester, route: AppRoutes.settingsBranding, repo: repo);
      await tester.ensureVisible(_reset());
      await tester.tap(_reset());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await tester.pumpAndSettle();
      expect(repo.saved.single['reset'], true);
      final primary = Theme.of(
        tester.element(find.text('School theme').first),
      ).colorScheme.primary;
      expect(primary, BrandColors.emerald.primary);
    });

    for (final role in [
      UserRole.branchAdmin,
      UserRole.teacher,
      UserRole.finance,
      UserRole.parent,
    ]) {
      testWidgets('${role.name} cannot open it', (tester) async {
        await _pump(tester, route: AppRoutes.settingsBranding, role: role);
        expect(_save(), findsNothing);
      });
    }
  });

  group('Platform branding page', () {
    testWidgets('a platform admin sets the default preset', (tester) async {
      final (_, repo) = await _pump(
        tester,
        route: AppRoutes.settingsPlatformBranding,
        role: UserRole.platformAdmin,
      );
      expect(find.text('Platform branding'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('platform-default-preset')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plum').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('platform-save')));
      await tester.tap(find.byKey(const ValueKey('platform-save')));
      await tester.pumpAndSettle();
      expect(repo.platformValue.defaultPreset, 'plum');
    });

    testWidgets('a school admin cannot open platform branding', (tester) async {
      await _pump(tester, route: AppRoutes.settingsPlatformBranding);
      expect(find.byKey(const ValueKey('platform-save')), findsNothing);
    });

    testWidgets('lays out on a phone without overflow', (tester) async {
      await _pump(
        tester,
        route: AppRoutes.settingsPlatformBranding,
        role: UserRole.platformAdmin,
        size: const Size(360, 740),
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

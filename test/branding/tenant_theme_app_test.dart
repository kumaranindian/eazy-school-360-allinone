import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/branding/tenant_branding.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/theme/brand_theme.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/branding/presentation/providers/branding_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:eazy_school_360/shared/branding/school_branding_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/branding_fakes.dart';
import '../support/fakes.dart';

final _indigo = BrandPresets.builtIn[1].colors;
final _crimson = BrandPresets.builtIn[2].colors;

const _roles = [
  UserRole.schoolAdmin,
  UserRole.branchAdmin,
  UserRole.teacher,
  UserRole.finance,
  UserRole.parent,
];

const _sizes = {
  'phone': Size(390, 844),
  'tablet': Size(820, 1180),
  'desktop': Size(1440, 900),
};

Future<(ProviderContainer, FakeBrandingRepository)> _pump(
  WidgetTester tester,
  UserRole role,
  Size size, {
  String schoolId = 'school-1',
  required Map<String, TenantBranding> branding,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final repo = FakeBrandingRepository(branding);
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      brandingRepositoryProvider.overrideWithValue(repo),
      brandingCacheProvider.overrideWithValue(MemoryBrandingCache()),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: 'u1', email: 'g@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          'u1': UserProfile(
            userId: 'u1',
            schoolId: schoolId,
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
            schoolId: School(
              schoolId: schoolId,
              name: 'Maple School',
              email: 'o@r.example',
              status: SchoolStatus.active,
            ),
          },
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return (container, repo);
}

ThemeData _theme(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(SchoolBrandingAppBar)));

TenantBranding _school(
  String id,
  int v,
  BrandColors c, [
  BrandingAppearance a = BrandingAppearance.light,
]) => TenantBranding(
  schoolId: id,
  version: v,
  presetId: 'x',
  colors: c,
  appearance: a,
);

void main() {
  for (final role in _roles) {
    for (final e in _sizes.entries) {
      testWidgets(
        '${role.name} on ${e.key}: gets the school theme, no overflow',
        (tester) async {
          await _pump(
            tester,
            role,
            e.value,
            branding: {'school-1': _school('school-1', 1, _indigo)},
          );
          final t = _theme(tester);
          expect(t.colorScheme.primary, _indigo.primary);
          expect(t.colorScheme.secondary, _indigo.secondary);
          expect(
            BrandTheme.of(
              tester.element(find.byType(SchoolBrandingAppBar)),
            ).selectedNav,
            _indigo.selectedNav,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('a save by the school admin reaches the open session live', (
    tester,
  ) async {
    final (_, repo) = await _pump(
      tester,
      UserRole.teacher,
      _sizes['phone']!,
      branding: {'school-1': _school('school-1', 1, _indigo)},
    );
    expect(_theme(tester).colorScheme.primary, _indigo.primary);
    repo.set(_school('school-1', 2, _crimson));
    await tester.pumpAndSettle();
    expect(_theme(tester).colorScheme.primary, _crimson.primary);
  });

  testWidgets('another school stays on its own theme', (tester) async {
    await _pump(
      tester,
      UserRole.teacher,
      _sizes['phone']!,
      schoolId: 'school-2',
      branding: {
        'school-1': _school('school-1', 1, _indigo),
        'school-2': _school('school-2', 1, _crimson),
      },
    );
    expect(_theme(tester).colorScheme.primary, _crimson.primary);
  });

  testWidgets('a school with no theme gets the approved default', (
    tester,
  ) async {
    await _pump(tester, UserRole.parent, _sizes['phone']!, branding: {});
    expect(_theme(tester).colorScheme.primary, BrandColors.emerald.primary);
    expect(
      BrandTheme.of(
        tester.element(find.byType(SchoolBrandingAppBar)),
      ).isDefault,
      isTrue,
    );
  });

  testWidgets('forced dark appearance applies to every role', (tester) async {
    await _pump(
      tester,
      UserRole.finance,
      _sizes['phone']!,
      branding: {
        'school-1': _school('school-1', 1, _indigo, BrandingAppearance.dark),
      },
    );
    expect(_theme(tester).brightness, Brightness.dark);
    expect(
      _theme(tester).colorScheme.primary.computeLuminance(),
      greaterThan(_indigo.primary.computeLuminance()),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text with a school theme does not overflow', (
    tester,
  ) async {
    await _pump(
      tester,
      UserRole.schoolAdmin,
      _sizes['phone']!,
      branding: {'school-1': _school('school-1', 1, _crimson)},
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
  });
}

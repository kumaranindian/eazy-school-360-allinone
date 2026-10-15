import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:eazy_school_360/shared/branding/school_brand_logo.dart';
import 'package:eazy_school_360/shared/branding/school_branding_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _longName =
    'Rosewood International High School of Excellence and Learning';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  UserRole role,
  Size size, {
  double textScale = 1.0,
  String schoolName = _longName,
  String? logoUrl,
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
            'school-1': School(
              schoolId: 'school-1',
              name: schoolName,
              email: 'o@r.example',
              logoUrl: logoUrl,
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
  return container;
}

/// The shell's branding bar (not an inner screen's AppBar).
Finder get _bar => find.byType(SchoolBrandingAppBar);

Rect _barRect(WidgetTester tester) => tester.getRect(_bar);

const _roles = [
  UserRole.platformAdmin,
  UserRole.schoolAdmin,
  UserRole.branchAdmin,
  UserRole.teacher,
  UserRole.finance,
  UserRole.parent,
];

void main() {
  for (final role in _roles) {
    testWidgets('${role.name}: every role gets the same branding header', (
      tester,
    ) async {
      await _pump(
        tester,
        role,
        const Size(390, 844),
        schoolName: 'Maple School',
      );
      expect(_bar, findsOneWidget);
      // Dashboard: the school's name is the centre text.
      expect(
        find.descendant(of: _bar, matching: find.text('Maple School')),
        findsOneWidget,
      );
      // Left: the school (initial badge — this school has no logo).
      final badge = find.descendant(of: _bar, matching: find.text('M'));
      expect(badge, findsOneWidget);
      final bar = _barRect(tester);
      final title = tester.getRect(
        find.descendant(of: _bar, matching: find.text('Maple School')),
      );
      expect(tester.getRect(badge).center.dx, lessThan(title.left));
      // Right: the EazySchool mark then the actions; all inside the bar.
      final mark = tester.getRect(
        find.descendant(of: _bar, matching: find.byType(Image)).last,
      );
      expect(mark.left, greaterThan(title.right - 1));
      expect(mark.right, lessThanOrEqualTo(bar.right));
      expect(title.center.dx, closeTo(bar.center.dx, 20));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the school name is never hard-coded: another tenant, another '
      'name', (tester) async {
    await _pump(
      tester,
      UserRole.schoolAdmin,
      const Size(390, 844),
      schoolName: 'Cedar Academy',
    );
    expect(
      find.descendant(of: _bar, matching: find.text('Cedar Academy')),
      findsOneWidget,
    );
    expect(find.text('Thalir Play School'), findsNothing);
    expect(find.text('Rosewood'), findsNothing);
  });

  testWidgets('a school with a logo URL shows it on the left, the product '
      'mark on the right', (tester) async {
    await _pump(
      tester,
      UserRole.schoolAdmin,
      const Size(390, 844),
      logoUrl: 'https://cdn.example.com/s/logo.png',
    );
    final school = tester.getRect(
      find.descendant(of: _bar, matching: find.byType(SchoolLogoImage)),
    );
    final bar = _barRect(tester);
    expect(school.left, lessThan(bar.left + 30));
    expect(school.width, school.height); // square: aspect preserved
  });

  testWidgets('navigating changes the centre text to the module and keeps the '
      'logos', (tester) async {
    final container = await _pump(
      tester,
      UserRole.schoolAdmin,
      const Size(390, 844),
      schoolName: 'Maple School',
    );
    container.read(appRouterProvider).go('/users');
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _bar, matching: find.text('User Management')),
      findsOneWidget,
    );
    // The school name is not repeated next to the title.
    expect(
      find.descendant(of: _bar, matching: find.text('Maple School')),
      findsNothing,
    );
    expect(find.descendant(of: _bar, matching: find.text('M')), findsOneWidget);
    // The shell actions still work/exist.
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(320, 568),
    Size(390, 844),
    Size(844, 390),
    Size(820, 1180),
    Size(1440, 900),
  ]) {
    for (final scale in const [1.0, 1.5]) {
      testWidgets('long school name: no overflow, no overlap, centred — '
          '${size.width.toInt()}x${size.height.toInt()} @$scale', (
        tester,
      ) async {
        await _pump(tester, UserRole.schoolAdmin, size, textScale: scale);
        expect(tester.takeException(), isNull);
        final bar = _barRect(tester);
        final title = tester.getRect(
          find.descendant(of: _bar, matching: find.text(_longName)),
        );
        final badge = tester.getRect(
          find.descendant(of: _bar, matching: find.text('R')),
        );
        final signOut = tester.getRect(find.byTooltip('Sign out'));
        expect(title.left, greaterThanOrEqualTo(badge.right));
        expect(title.right, lessThanOrEqualTo(signOut.left));
        expect(title.right, lessThanOrEqualTo(bar.right));
        expect(bar.height, kToolbarHeight + 0);
      });
    }
  }
}

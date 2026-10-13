import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
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

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High School of Excellence and Learning',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);

/// Phone, tablet and desktop sizes the shell must lay out on without
/// overflowing, at normal text and at the largest scale the app allows
/// (the app caps the system text scale at 1.5, so 2.0 proves the cap holds).
const _sizes = <String, Size>{
  'small phone 320x568': Size(320, 568),
  'phone 360x800': Size(360, 800),
  'tablet 768x1024': Size(768, 1024),
  'laptop 1280x720': Size(1280, 720),
  'desktop 1920x1080': Size(1920, 1080),
};

Future<void> _pump(
  WidgetTester tester,
  UserRole role,
  Size size,
  double textScale,
) async {
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
          signedInAs: const AppUser(uid: _uid, email: 'grace@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace Hopper-Montgomery',
            email: 'grace@example.com',
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
}

void main() {
  for (final role in [UserRole.schoolAdmin, UserRole.parent]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final entry in _sizes.entries) {
        testWidgets('shell + dashboard lay out without overflow: ${role.name}, '
            '${entry.key}, text x$scale', (tester) async {
          await _pump(tester, role, entry.value, scale);
          expect(find.byType(Scaffold), findsWidgets);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

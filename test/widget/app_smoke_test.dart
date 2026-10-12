import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Widget _buildApp() {
  return ProviderScope(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      userRepositoryProvider.overrideWithValue(FakeUserRepository()),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
    ],
    child: const App(),
  );
}

void main() {
  testWidgets(
    'app starts, theme loads, router resolves to login when signed out',
    (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
      // The brand lockup is an image; its semantic label is the product name.
      expect(find.bySemanticsLabel('EazySchool 360'), findsWidgets);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(
        find.text('Sign in to continue to EazySchool 360'),
        findsOneWidget,
      );
    },
  );

  testWidgets('login form renders correctly at mobile and desktop widths', (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}

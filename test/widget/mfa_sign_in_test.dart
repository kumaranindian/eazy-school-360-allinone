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

Future<FakeAuthRepository> _pump(
  WidgetTester tester, {
  bool requireMfa = true,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = FakeAuthRepository()..requireMfa = requireMfa;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        envConfigProvider.overrideWithValue(
          EnvConfig.forEnvironment(AppEnvironment.test),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        userRepositoryProvider.overrideWithValue(FakeUserRepository()),
        schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email'),
    'grace@avail404.com',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    'correct horse',
  );
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'an account with two-step verification is asked for the code, not shown an error',
    (tester) async {
      await _pump(tester);
      await _signIn(tester);
      expect(find.text('Two-step verification'), findsOneWidget);
      expect(find.byKey(const ValueKey('mfa-code')), findsOneWidget);
      expect(find.text('Incorrect email or password.'), findsNothing);
    },
  );

  testWidgets('a wrong code is explained and can be retyped', (tester) async {
    final auth = await _pump(tester);
    await _signIn(tester);
    await tester.enterText(find.byKey(const ValueKey('mfa-code')), '000000');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pumpAndSettle();
    expect(find.text('That code is not correct.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mfa-code')),
      findsOneWidget,
      reason: 'stays open',
    );
    expect(auth.mfaCodesTried, ['000000']);
  });

  testWidgets('the right code finishes the sign-in and closes the prompt', (
    tester,
  ) async {
    final auth = await _pump(tester);
    await _signIn(tester);
    await tester.enterText(find.byKey(const ValueKey('mfa-code')), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pumpAndSettle();
    expect(auth.mfaCodesTried, ['123456']);
    expect(find.byKey(const ValueKey('mfa-code')), findsNothing);
    expect(auth.currentUser, isNotNull);
  });

  testWidgets('a malformed code is refused before it is sent', (tester) async {
    final auth = await _pump(tester);
    await _signIn(tester);
    await tester.enterText(find.byKey(const ValueKey('mfa-code')), '12');
    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pumpAndSettle();
    expect(find.text('The code is 6 digits'), findsOneWidget);
    expect(auth.mfaCodesTried, isEmpty);
  });

  testWidgets('cancelling leaves the person signed out', (tester) async {
    final auth = await _pump(tester);
    await _signIn(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mfa-code')), findsNothing);
    expect(auth.currentUser, isNull);
  });

  testWidgets('accounts without two-step verification sign in as before', (
    tester,
  ) async {
    final auth = await _pump(tester, requireMfa: false);
    await _signIn(tester);
    expect(find.byKey(const ValueKey('mfa-code')), findsNothing);
    expect(auth.currentUser, isNotNull);
  });
}

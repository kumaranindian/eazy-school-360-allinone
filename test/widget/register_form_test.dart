import 'dart:async';

import 'package:eazy_school_360/core/errors/error_mapper.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/authentication/presentation/widgets/register_form.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Counts sign-ups and holds each one open until [release] is called.
class _SlowSignUpRepository extends FakeAuthRepository {
  int signUps = 0;
  final _pending = Completer<void>();

  void release() => _pending.complete();

  @override
  Future<AppUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signUps++;
    await _pending.future;
    return AppUser(uid: 'fake-uid', email: email);
  }
}

Future<_SlowSignUpRepository> _pump(WidgetTester tester) async {
  final repo = _SlowSignUpRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: RegisterForm())),
      ),
    ),
  );
  return repo;
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _fill(
  WidgetTester tester, {
  String email = 'new.admin@example.com',
  String password = 'school2026',
  String? confirm,
}) async {
  // The first text input connection is set up on the first focus; give it
  // a frame so the first enterText is not dropped.
  await tester.tap(_field('Email'));
  await tester.pump();
  await tester.enterText(_field('Email'), email);
  await tester.enterText(_field('Password'), password);
  await tester.enterText(_field('Confirm password'), confirm ?? password);
}

void main() {
  testWidgets('a letters-only password is refused (OBS-01)', (tester) async {
    final repo = await _pump(tester);
    await _fill(tester, password: 'abcdefgh');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(
      find.text('Include at least one letter and one number.'),
      findsOneWidget,
    );
    expect(repo.signUps, 0);
  });

  testWidgets('mismatched passwords end with a full stop (OBS-04)', (
    tester,
  ) async {
    await _pump(tester);
    await _fill(tester, confirm: 'school2027');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('an error clears as soon as the field is corrected (OBS-05)', (
    tester,
  ) async {
    await _pump(tester);
    await _fill(tester, email: 'not-an-email');
    await tester.tap(find.text('Create account'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.enterText(_field('Email'), 'new.admin@example.com');
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsNothing);
  });

  testWidgets('a double click sends one sign-up (DEF-02)', (tester) async {
    final repo = await _pump(tester);
    await _fill(tester);
    // Two taps before the button has rebuilt as disabled.
    await tester.tap(find.text('Create account'));
    await tester.tap(find.text('Create account'), warnIfMissed: false);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(repo.signUps, 1);
    expect(find.byType(SnackBar), findsNothing);

    repo.release();
    await tester.pump();
    expect(repo.signUps, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'Enter in Password goes to Confirm password, not the eye icon (OBS-03)',
    (tester) async {
      await _pump(tester);
      await tester.tap(_field('Password'));
      await tester.pump();
      await tester.enterText(_field('Password'), 'school2026');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      final confirm = tester.widget<EditableText>(
        find.descendant(
          of: _field('Confirm password'),
          matching: find.byType(EditableText),
        ),
      );
      expect(confirm.focusNode.hasFocus, isTrue);
    },
  );

  test('an email that is already registered says so (DEF-01)', () {
    expect(
      userMessageFor(fb.FirebaseAuthException(code: 'email-already-in-use')),
      'This email is already registered. Sign in instead.',
    );
  });
}

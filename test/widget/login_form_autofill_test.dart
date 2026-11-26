import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/authentication/presentation/widgets/login_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

// QA PLAT-01 DEF-04: after sign-in no password may stay in the page. On the
// web the engine mirrors autofill fields into hidden DOM inputs until the
// autofill context is finished, so the form must clear the password and
// call TextInput.finishAutofillContext.

Finder _field(String label) => find.widgetWithText(TextFormField, label);

String _passwordText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: _field('Password'),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

int _finishCalls(WidgetTester tester) => tester.testTextInput.log
    .where((c) => c.method == 'TextInput.finishAutofillContext')
    .length;

Future<FakeAuthRepository> _pump(WidgetTester tester) async {
  final repo = FakeAuthRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: LoginForm())),
      ),
    ),
  );
  return repo;
}

Future<void> _signIn(WidgetTester tester) async {
  await tester.tap(_field('Email'));
  await tester.pump();
  await tester.enterText(_field('Email'), 'admin@avail404.com');
  await tester.enterText(_field('Password'), 'school2026');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pump();
}

void main() {
  testWidgets(
    'a successful sign-in clears the password and finishes autofill',
    (tester) async {
      await _pump(tester);
      tester.testTextInput.log.clear();
      await _signIn(tester);
      expect(_passwordText(tester), isEmpty);
      expect(_finishCalls(tester), greaterThan(0));
    },
  );

  testWidgets('leaving the sign-in form finishes the autofill context', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_field('Password'), 'school2026');
    tester.testTextInput.log.clear();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(_finishCalls(tester), greaterThan(0));
  });
}

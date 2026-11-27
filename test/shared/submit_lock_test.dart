import 'dart:async';

import 'package:eazy_school_360/core/utils/client_ids.dart';
import 'package:eazy_school_360/shared/forms/submit_lock.dart';
import 'package:eazy_school_360/shared/widgets/submit_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// STU-01-DEF-01 / STU-02-DEF-01: a double click must save once.
void main() {
  test('a second run while one is in progress does nothing', () async {
    final lock = SubmitLock();
    final gate = Completer<void>();
    var runs = 0;
    final first = lock.run(() async {
      runs++;
      await gate.future;
      return 1;
    });
    final second = await lock.run(() async {
      runs++;
      return 2;
    });
    expect(second, isNull);
    expect(lock.busy, isTrue);
    gate.complete();
    expect(await first, 1);
    expect(lock.busy, isFalse);
    expect(runs, 1);
    // Free again once the first finished, also after a failure.
    await expectLater(
      lock.run(() async => throw StateError('x')),
      throwsStateError,
    );
    expect(await lock.run(() async => 3), 3);
  });

  testWidgets(
    'SubmitButton: two quick taps run the action once, with a spinner',
    (tester) async {
      final gate = Completer<void>();
      var runs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubmitButton(
              label: 'Admit student',
              onPressed: () async {
                runs++;
                await gate.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Admit student'));
      await tester.tap(find.text('Admit student'), warnIfMissed: false);
      await tester.pump();
      expect(runs, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      gate.complete();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );

  test('client ids look like Firestore ids and differ', () {
    final a = newClientId();
    final b = newClientId();
    expect(a, matches(RegExp(r'^[A-Za-z0-9]{20}$')));
    expect(a, isNot(b));
  });
}

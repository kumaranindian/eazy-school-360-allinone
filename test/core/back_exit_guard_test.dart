import 'package:eazy_school_360/core/routing/back_exit_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('backTargetFor', () {
    test('the dashboard asks before closing', () {
      expect(backTargetFor('/dashboard'), isNull);
      expect(backTargetFor('/dashboard/'), isNull);
    });

    test('More goes back to the dashboard', () {
      expect(backTargetFor('/dashboard/more'), '/dashboard');
    });

    test('a module main screen goes to the dashboard', () {
      expect(backTargetFor('/fees'), '/dashboard');
      expect(backTargetFor('/my-leave'), '/dashboard');
    });

    test("a module's inner screens go to the module's main screen", () {
      expect(backTargetFor('/fees/structures'), '/fees');
      expect(backTargetFor('/my-fees/invoices/inv-1'), '/my-fees');
      expect(backTargetFor('/my-leave/apply'), '/my-leave');
    });
  });

  group('BackExitGuard', () {
    testWidgets('is a no-op when disabled (web / iOS)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BackExitGuard(
            path: '/dashboard',
            enabled: false,
            child: Text('home'),
          ),
        ),
      );
      expect(find.byType(PopScope), findsNothing);
    });

    testWidgets('on the home screen back asks first and Stay keeps the app', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BackExitGuard(
            path: '/dashboard',
            enabled: true,
            child: Text('home'),
          ),
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Close the app?'), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.text('Close the app?'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });
  });
}

import 'package:eazy_school_360/shared/forms/app_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// COM-01-OBS-01: blank lines alone do not count; a new box shows 0/4000.
void main() {
  testWidgets('the counter counts what will be saved', (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: c,
            maxLength: 4000,
            maxLines: 5,
            buildCounter: trimmedCounter(c),
          ),
        ),
      ),
    );
    expect(find.text('0/4000'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '\n\n\n\n\n\n');
    await tester.pump();
    expect(find.text('0/4000'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Sports day  \n');
    await tester.pump();
    expect(find.text('10/4000'), findsOneWidget);
  });
}

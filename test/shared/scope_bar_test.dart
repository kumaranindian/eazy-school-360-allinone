import 'package:eazy_school_360/shared/filters/filter_bar.dart';
import 'package:eazy_school_360/shared/filters/filter_field.dart';
import 'package:eazy_school_360/shared/layouts/scope_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {double width = 390}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool complete = false;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ScopeBar(
        complete: complete,
        summary: 'Class 5 · Section A',
        controlsBuilder: (context, narrow) => TextButton(
          onPressed: () => setState(() => complete = true),
          child: const Text('Pick'),
        ),
      ),
    ],
  );
}

void main() {
  testWidgets('phone: stays open until the choice is complete, then folds', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const _Harness()));
    expect(find.text('Pick'), findsOneWidget);
    expect(find.text('Class 5 · Section A'), findsNothing);

    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(find.text('Pick'), findsNothing);
    expect(find.text('Class 5 · Section A'), findsOneWidget);

    await tester.tap(find.text('Class 5 · Section A'));
    await tester.pumpAndSettle();
    expect(find.text('Pick'), findsOneWidget);
  });

  testWidgets('tablet and wider: always shows the controls, no summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ScopeBar(
          complete: true,
          summary: 'Class 5 · Section A',
          controlsBuilder: (context, narrow) => const Text('controls'),
        ),
        width: 900,
      ),
    );
    expect(find.text('controls'), findsOneWidget);
    expect(find.text('Class 5 · Section A'), findsNothing);
  });

  testWidgets('a lone filter on a bar with no search is shown, not hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        FilterBar(
          fieldsBuilder: () => [
            FilterField.dropdown<String>(
              label: 'Academic year',
              value: 'a',
              countsAsFilter: false,
              options: const [('a', '2026-27')],
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
    expect(find.text('Academic year'), findsOneWidget);
    expect(find.textContaining('Filters'), findsNothing);
  });
}

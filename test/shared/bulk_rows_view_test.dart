import 'package:eazy_school_360/features/students/domain/bulk_student_import.dart';
import 'package:eazy_school_360/shared/bulk_import/bulk_rows_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _err = BulkCellError(
  column: 'class',
  label: 'Class',
  value: 'Grade9',
  message: 'No class named "Grade9" exists.',
  fix: 'Did you mean "Grade 1"?',
);

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  _inlineFixTests();
  test('spreadsheetColumn maps indexes to letters', () {
    expect(spreadsheetColumn(0), 'A');
    expect(spreadsheetColumn(12), 'M');
    expect(spreadsheetColumn(25), 'Z');
    expect(spreadsheetColumn(26), 'AA');
  });

  testWidgets('shows every row, each with its own problems and cell', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const BulkRowsView(
          header: ['admission_number', 'class'],
          rows: [
            BulkRowView(
              line: 2,
              who: 'ADM-1 · Asha K',
              details: '',
              errors: [],
            ),
            BulkRowView(
              line: 3,
              who: 'ADM-2 · Bo L',
              details: 'Class Grade9 · Section A',
              errors: [_err],
            ),
          ],
        ),
      ),
    );

    expect(find.text('All rows (2)'), findsOneWidget);
    expect(find.text('Needs fixing (1)'), findsOneWidget);
    expect(find.text('Ready (1)'), findsOneWidget);
    // Both rows are listed.
    expect(find.textContaining('Row 2 · ADM-1'), findsOneWidget);
    expect(find.textContaining('Row 3 · ADM-2'), findsOneWidget);
    expect(find.text('Ready to import'), findsOneWidget);
    expect(find.text('1 problem to fix'), findsOneWidget);
    // Plain-language problem for row 3, pointing at spreadsheet cell B3.
    expect(find.text('1. Class  (cell B3)'), findsOneWidget);
    expect(find.text('You entered: "Grade9"'), findsOneWidget);
    expect(
      find.textContaining('How to fix: Did you mean "Grade 1"?'),
      findsOneWidget,
    );

    // Filter to only the rows that need fixing.
    await tester.tap(find.text('Needs fixing (1)'));
    await tester.pump();
    expect(find.textContaining('Row 2 · ADM-1'), findsNothing);
    expect(find.textContaining('Row 3 · ADM-2'), findsOneWidget);
  });

  testWidgets('after import it labels each row with its outcome', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const BulkRowsView(
          header: ['admission_number'],
          rows: [
            BulkRowView(
              line: 2,
              who: 'ADM-1',
              details: '',
              errors: [],
              outcome: BulkRowOutcome.imported,
            ),
            BulkRowView(
              line: 3,
              who: 'ADM-2',
              details: '',
              errors: [],
              outcome: BulkRowOutcome.failed,
              outcomeMessage: 'This admission number is already in use.',
            ),
          ],
        ),
      ),
    );
    expect(find.text('Imported'), findsWidgets);
    expect(find.text('Not imported'), findsOneWidget);
    expect(
      find.text('This admission number is already in use.'),
      findsOneWidget,
    );
    expect(find.text('Failed (1)'), findsOneWidget);
  });
}

void _inlineFixTests() {
  testWidgets('inline fix: pick a value, apply to this row or all rows', (
    tester,
  ) async {
    final edits = <BulkCellEdit>[];
    const err = BulkCellError(
      column: 'class',
      label: 'Class',
      value: 'Grade9',
      message: 'No class named "Grade9" exists.',
      fix: 'Pick one.',
      choices: ['Grade 1', 'Grade 2'],
    );
    await tester.pumpWidget(
      _wrap(
        BulkRowsView(
          header: const ['admission_number', 'class'],
          onEdit: (e) async => edits.add(e),
          rows: const [
            BulkRowView(line: 2, who: 'A', details: '', errors: [err]),
            BulkRowView(line: 3, who: 'B', details: '', errors: [err]),
          ],
        ),
      ),
    );

    // Same bad value in 2 rows -> "Fix all 2 rows" is offered.
    expect(find.text('Fix all 2 rows'), findsNWidgets(2));
    // Nothing chosen yet: apply is disabled.
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Fix this row').first,
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fix all 2 rows').first);
    await tester.pumpAndSettle();

    expect(edits, hasLength(1));
    expect(edits.single.line, isNull);
    expect(edits.single.column, 'class');
    expect(edits.single.oldValue, 'Grade9');
    expect(edits.single.newValue, 'Grade 1');
  });
}

import 'package:eazy_school_360/shared/dates/school_date_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// SET-01-DEF-02: a typed date follows the school's date format, not US.
void main() {
  test('the picker locale follows the order of the school date format', () {
    expect(pickerLocaleFor('dd/MM/yyyy'), const Locale('en', 'GB'));
    expect(pickerLocaleFor('dd.MM.yyyy'), const Locale('en', 'GB'));
    expect(pickerLocaleFor('MM/dd/yyyy'), const Locale('en', 'US'));
    expect(pickerLocaleFor('yyyy-MM-dd'), const Locale('en', 'CA'));
    expect(pickerLocaleFor('yyyy/MM/dd'), const Locale('en', 'CA'));
  });

  testWidgets('typing 25/12/2026 picks 25 December with dd/MM/yyyy', (
    tester,
  ) async {
    DateTime? picked;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: const [
          Locale('en', 'US'),
          Locale('en', 'GB'),
          Locale('en', 'CA'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showSchoolDatePicker(
              context: context,
              initialDate: DateTime(2026, 11, 27),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
              initialEntryMode: DatePickerEntryMode.input,
            ),
            child: const Text('pick'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(find.text('dd/mm/yyyy'), findsWidgets);
    await tester.enterText(find.byType(TextField), '25/12/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 12, 25));
  });
}

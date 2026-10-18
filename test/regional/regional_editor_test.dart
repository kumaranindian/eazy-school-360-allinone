import 'package:eazy_school_360/core/regional/regional_settings.dart';
import 'package:eazy_school_360/shared/regional/regional_settings_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required RegionalSettings value,
  required ValueChanged<RegionalSettings> onChanged,
  bool locked = false,
  Size size = const Size(390, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: RegionalSettingsEditor(
            value: value,
            onChanged: onChanged,
            currencyLocked: locked,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('choosing a country fills currency, zone and date format', (
    tester,
  ) async {
    RegionalSettings? got;
    await _pump(
      tester,
      value: RegionalSettings.legacy,
      onChanged: (v) => got = v,
    );
    await tester.tap(find.text('India').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('United States').last);
    await tester.pumpAndSettle();
    expect(got?.countryCode, 'US');
    expect(got?.currency, 'USD');
    expect(got?.timezone, 'America/New_York');
    expect(got?.dateFormat, 'MM/dd/yyyy');
    expect(tester.takeException(), isNull);
  });

  testWidgets('with money in the books the currency stays, even when the '
      'country changes', (tester) async {
    RegionalSettings? got;
    await _pump(
      tester,
      value: RegionalSettings.legacy,
      locked: true,
      onChanged: (v) => got = v,
    );
    expect(find.textContaining('Locked'), findsOneWidget);
    await tester.tap(find.text('India').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('United Kingdom').last);
    await tester.pumpAndSettle();
    expect(got?.countryCode, 'GB');
    expect(got?.currency, 'INR'); // kept
    expect(got?.timezone, 'Europe/London'); // still follows the country
  });

  testWidgets('lays out without overflow on a phone at large text', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await _pump(
      tester,
      value: RegionalSettings.legacy,
      onChanged: (_) {},
      size: const Size(320, 800),
    );
    expect(tester.takeException(), isNull);
  });
}

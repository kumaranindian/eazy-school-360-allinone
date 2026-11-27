import 'package:eazy_school_360/features/academic_setup/presentation/widgets/school_year_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// SET-01-OBS-01: with no school years the dialog says so (and links to
// School years) instead of "Every school year is already open here".
Widget _dialog({required bool none}) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: OpenSchoolYearDialog(
        schoolId: 's',
        branchId: 'b',
        userId: 'u',
        openable: const [],
        noSchoolYears: none,
      ),
    ),
  ),
);

void main() {
  testWidgets('no school years: says none exist and offers the way there', (
    tester,
  ) async {
    await tester.pumpWidget(_dialog(none: true));
    expect(find.byKey(const ValueKey('no-school-years')), findsOneWidget);
    expect(find.textContaining('No school years exist yet'), findsOneWidget);
    expect(find.text('Go to School years'), findsOneWidget);
    expect(find.textContaining('already open'), findsNothing);
  });

  testWidgets('all years open here: says that', (tester) async {
    await tester.pumpWidget(_dialog(none: false));
    expect(find.textContaining('already open here'), findsOneWidget);
    expect(find.text('Go to School years'), findsNothing);
  });
}

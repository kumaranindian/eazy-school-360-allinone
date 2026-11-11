import 'package:eazy_school_360/features/students/domain/student.dart';
import 'package:eazy_school_360/features/students/presentation/providers/student_providers.dart';
import 'package:eazy_school_360/features/students/presentation/widgets/student_edit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/student_fakes.dart';

class _Repo extends FakeStudentListRepository {
  _Repo() : super(const []);
  final saved = <Student>[];
  Object? error;

  @override
  Future<void> updateStudentProfile(
    Student student, {
    required String updatedBy,
  }) async {
    if (error != null) throw error!;
    saved.add(student);
  }
}

Future<void> _open(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [studentRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => Dialog(
                  child: StudentEditDialog(
                    student: fakeStudent('s1', first: 'Asha', last: 'Nair'),
                    currentUserId: 'uid-1',
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('saves the edited details and closes', (tester) async {
    final repo = _Repo();
    await _open(tester, repo);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Aarav',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'City'),
      'Chennai',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.firstName, 'Aarav');
    expect(repo.saved.single.city, 'Chennai');
    expect(repo.saved.single.studentId, 's1');
    expect(find.text('Edit student'), findsNothing);
  });

  testWidgets('a required field blocks the save', (tester) async {
    final repo = _Repo();
    await _open(tester, repo);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      '',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('First name is required.'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('Cancel saves nothing', (tester) async {
    final repo = _Repo();
    await _open(tester, repo);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.saved, isEmpty);
    expect(find.text('Edit student'), findsNothing);
  });
}

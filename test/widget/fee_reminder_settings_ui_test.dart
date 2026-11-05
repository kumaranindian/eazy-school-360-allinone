import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/fees/domain/fee_reminder_settings.dart';
import 'package:eazy_school_360/features/fees/presentation/providers/fee_reminder_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch.dart';
import 'package:eazy_school_360/features/school_setup/domain/branch_status.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'office@rosewood.example',
  status: SchoolStatus.active,
);

class _FakeRepo implements FeeReminderSettingsRepository {
  FeeReminderSettings? stored;
  final saves = <FeeReminderSettings>[];
  Object? failWith;
  _FakeRepo();

  @override
  Future<FeeReminderSettings?> load(String schoolId) async => stored;

  @override
  Future<void> save(String schoolId, FeeReminderSettings settings) async {
    if (failWith != null) throw failWith!;
    saves.add(settings);
    stored = settings;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakeRepo repo,
  Size size = const Size(1000, 1400),
  double textScale = 1.0,
  UserRole role = UserRole.schoolAdmin,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'grace@example.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: UserProfile(
            userId: _uid,
            schoolId: 'school-1',
            branchId: 'main',
            name: 'Grace Hopper',
            email: 'grace@example.com',
            role: role,
            status: UserStatus.active,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {'school-1': _school},
          branches: {
            'school-1/main': const Branch(
              branchId: 'main',
              schoolId: 'school-1',
              name: 'Main Branch',
              code: 'MAIN',
              city: 'Chennai',
              status: BranchStatus.active,
            ),
          },
        ),
      ),
      feeReminderSettingsRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(AppRoutes.settingsFeeReminders);
  await tester.pumpAndSettle();
  return container;
}

Finder _save() => find.widgetWithText(FilledButton, 'Save changes');

void main() {
  for (final (name, size) in [
    ('small phone', const Size(320, 640)),
    ('phone', const Size(390, 844)),
    ('tablet', const Size(820, 1180)),
    ('desktop', const Size(1440, 900)),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('lays out without overflow: $name, text x$scale', (
        tester,
      ) async {
        await _pump(tester, repo: _FakeRepo(), size: size, textScale: scale);
        expect(find.text('Fee reminders'), findsWidgets);
        expect(find.text('Before the due date'), findsOneWidget);
        expect(find.text('After the due date (overdue)'), findsOneWidget);
        expect(find.byTooltip('Back to Settings'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // scroll to the end: nothing overflows further down
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
        expect(find.text('What parents will see'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a school without saved settings shows the standard reminders', (
    tester,
  ) async {
    await _pump(tester, repo: _FakeRepo());
    expect(find.text('3 days before'), findsOneWidget);
    expect(find.text('On the due date'), findsOneWidget);
    expect(find.text('1 day after'), findsOneWidget);
    expect(find.text('7 days after'), findsOneWidget);
    expect(find.text('15 days after'), findsOneWidget);
    expect(
      find.textContaining('standard reminders are in use'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_save()).onPressed, isNull);
  });

  testWidgets('adding a reminder, refusing a duplicate, then saving', (
    tester,
  ) async {
    final repo = _FakeRepo();
    await _pump(tester, repo: repo);
    final addAfter = find.text('Add a reminder').last;
    await tester.ensureVisible(addAfter);
    await tester.tap(addAfter);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('That reminder is already in the list.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '30');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('30 days after'), findsOneWidget);

    await tester.ensureVisible(_save());
    await tester.tap(_save());
    await tester.pumpAndSettle();
    expect(find.text('Save fee reminders?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.saves, hasLength(1));
    expect(repo.saves.single.after.map((s) => s.days), [1, 7, 15, 30]);
    expect(find.text('Fee reminder settings saved.'), findsOneWidget);
  });

  testWidgets('turning every reminder off asks first', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, repo: repo);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Send fee reminders'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_save());
    await tester.tap(_save());
    await tester.pumpAndSettle();
    expect(find.text('Turn off all fee reminders?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();
    expect(repo.saves, isEmpty);
    await tester.tap(_save());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
    await tester.pumpAndSettle();
    expect(repo.saves.single.enabled, isFalse);
  });

  testWidgets('a server refusal is shown and the draft is kept', (
    tester,
  ) async {
    final repo = _FakeRepo()..failWith = Exception('boom');
    await _pump(tester, repo: repo);
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Show the invoice number'),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(_save());
    await tester.tap(_save());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(_save()).onPressed, isNotNull);
  });

  testWidgets('the preview follows the switches', (tester) async {
    await _pump(tester, repo: _FakeRepo());
    await tester.ensureVisible(find.text('What parents will see'));
    expect(find.textContaining('Amount:'), findsNothing);
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Show the invoice amount'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Amount: ₹1,500.00'), findsWidgets);
    expect(find.text('Fee overdue'), findsOneWidget);
  });

  testWidgets('a teacher cannot open the page', (tester) async {
    await _pump(tester, repo: _FakeRepo(), role: UserRole.teacher);
    expect(find.text('Send fee reminders'), findsNothing);
  });
}

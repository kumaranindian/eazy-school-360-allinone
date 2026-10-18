import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/login_method.dart';
import 'package:eazy_school_360/features/users/domain/login_access.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:eazy_school_360/features/users/presentation/providers/login_access_providers.dart';
import 'package:eazy_school_360/features/users/presentation/widgets/bulk_reset_password_dialog.dart';
import 'package:eazy_school_360/features/users/presentation/widgets/login_selection_bar.dart';
import 'package:eazy_school_360/features/users/presentation/widgets/provision_logins_dialog.dart'
    show LoginCandidate;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/login_access_fakes.dart';

const _sizes = <(String, Size, double)>[
  ('phone', Size(360, 740), 1.0),
  ('phone large text', Size(360, 740), 1.5),
  ('tablet', Size(820, 1180), 1.0),
  ('desktop', Size(1440, 900), 1.0),
];

final _people = <LoginCandidate>[
  (id: 'p1', name: 'Ravi Kumar', email: 'ravi@example.com'),
  (
    id: 'p2',
    name: 'Meera Subramanian-Krishnamurthy',
    email: 'meera@example.com',
  ),
  (id: 'p3', name: 'No Mail', email: null),
];

Future<FakeLoginAccessRepository> _open(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  double scale = 1.0,
  List<LoginCandidate>? people,
  Set<String> noLogin = const {},
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final repo = FakeLoginAccessRepository(access: _accessStub())
    ..noLoginIds = {...noLogin};
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        loginAccessRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            signedInAs: const AppUser(uid: 'u1', email: 'a@example.com'),
          ),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showBulkResetPasswordDialog(
                context: context,
                schoolId: 's',
                branchId: 'b',
                kind: LoginKind.parent,
                people: people ?? _people,
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
  return repo;
}

// Only the bulk call is used; a minimal access object satisfies the fake.
LoginAccess _accessStub() => const LoginAccess(
  id: 'p1',
  uid: 'uid-p1',
  kind: LoginKind.parent,
  name: 'Ravi Kumar',
  userType: 'PARENT',
  registeredEmail: 'ravi@example.com',
  registeredPhone: null,
  schoolMethods: [LoginMethod.password],
  hasAccount: true,
  enabled: true,
  methods: [LoginMethod.password],
  effective: [LoginMethod.password],
  activation: LoginActivation.active,
  emailVerified: true,
  phoneVerified: false,
  lastLogin: null,
  legacy: false,
  manageable: true,
);

void main() {
  for (final (name, size, scale) in _sizes) {
    testWidgets('bulk reset dialog lays out on $name', (tester) async {
      await _open(tester, size: size, scale: scale);
      expect(find.text('Reset passwords'), findsWidgets);
      expect(find.text('Name + mobile number'), findsOneWidget);
      await tester.ensureVisible(find.text('One password set by you'));
      await tester.tap(find.text('One password set by you'));
      await tester.pumpAndSettle();
      expect(find.text('Temporary password'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'random passwords: each person reset, CSV offered, nobody silent',
    (tester) async {
      final repo = await _open(tester, noLogin: {'p3'});
      await tester.ensureVisible(find.text('Random temporary password'));
      await tester.tap(find.text('Random temporary password'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset passwords'));
      await tester.pumpAndSettle();
      expect(repo.bulkResets.single.ids, ['p1', 'p2', 'p3']);
      expect(
        repo.bulkResets.single.setup.option,
        PasswordSetupOption.randomTemp,
      );
      expect(find.textContaining('2 of 3 passwords reset'), findsOneWidget);
      expect(find.text('Download passwords (CSV)'), findsOneWidget);
      // the person with no login is listed, with the reason
      expect(find.text('Not changed'), findsOneWidget);
      expect(find.text('Has no login yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'admin-defined: cannot start until the password is valid and confirmed',
    (tester) async {
      final repo = await _open(tester);
      await tester.ensureVisible(find.text('One password set by you'));
      await tester.tap(find.text('One password set by you'));
      await tester.pumpAndSettle();
      FilledButton start() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Reset passwords'),
      );
      expect(start().onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Temporary password'),
        'Welcome2026',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm password'),
        'Welcome2025',
      );
      await tester.pump();
      expect(start().onPressed, isNull, reason: 'mismatch');
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm password'),
        'Welcome2026',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset passwords'));
      await tester.pumpAndSettle();
      expect(repo.bulkResets.single.setup.password, 'Welcome2026');
    },
  );

  testWidgets('link option emails people and lists those without an email', (
    tester,
  ) async {
    final repo = await _open(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Send emails'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(
      repo.bulkResets,
      isEmpty,
      reason: 'links are emails, not server resets',
    );
    expect(
      find.textContaining('2 of 3 set-password emails sent'),
      findsOneWidget,
    );
    expect(find.text('No email on the record'), findsOneWidget);
  });

  testWidgets('selection bar: reset mode labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginSelectionBar(
            selected: 1,
            selectable: 4,
            onSelectAll: () {},
            onClear: () {},
            onCreate: () {},
            onCancel: () {},
            actionLabel: 'Reset passwords',
            actionIcon: Icons.lock_reset,
            selectAllLabel: 'Select all (4 with a login)',
          ),
        ),
      ),
    );
    expect(find.text('Reset passwords'), findsOneWidget);
    expect(find.text('Select all (4 with a login)'), findsOneWidget);
  });
}

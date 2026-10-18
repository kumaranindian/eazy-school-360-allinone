import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/users/domain/login_provisioning.dart';
import 'package:eazy_school_360/features/users/presentation/providers/login_provisioning_providers.dart';
import 'package:eazy_school_360/features/users/presentation/widgets/provision_logins_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

class _RecordingAuth extends FakeAuthRepository {
  final List<String> resetTo = [];
  @override
  Future<void> sendPasswordResetEmail(String email) async => resetTo.add(email);
}

class _FlakyAuth extends _RecordingAuth {
  int failTimes;
  _FlakyAuth({required this.failTimes});

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (failTimes > 0) {
      failTimes--;
      throw const NetworkFailure();
    }
    resetTo.add(email);
  }
}

class _FakeProvisioner implements LoginProvisioner {
  PasswordSetup? setup;
  Map<String, String>? emails;
  List<ProvisionResult> answer = const [];

  /// Consumed one per call, before falling back to [answer].
  final List<List<ProvisionResult>> answers = [];
  final List<List<String>> calls = [];

  @override
  Future<List<ProvisionResult>> provision({
    required String schoolId,
    required String branchId,
    required LoginKind kind,
    required List<String> ids,
    UserRole? staffRole,
    bool enablePortal = false,
    Map<String, String> emails = const {},
    PasswordSetup? passwordSetup,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    setup = passwordSetup;
    this.emails = emails;
    calls.add(ids);
    onProgress?.call(ids.length, ids.length);
    return answers.isNotEmpty ? answers.removeAt(0) : answer;
  }
}

Future<void> _open(
  WidgetTester tester,
  _FakeProvisioner prov,
  _RecordingAuth auth, {
  Size size = const Size(1000, 1400),
  List<LoginCandidate>? people,
  _RecordingAuth? auth2,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        loginProvisionerProvider.overrideWithValue(prov),
        authRepositoryProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProvisionLoginsDialog(
              schoolId: 's1',
              branchId: 'b1',
              kind: LoginKind.staff,
              people:
                  people ??
                  const [
                    (id: 'a', name: 'Asha', email: 'asha@x.com'),
                    (id: 'b', name: 'Bala', email: null),
                  ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('defaults to the activation email and sends it to new accounts', (
    tester,
  ) async {
    final prov = _FakeProvisioner()
      ..answer = const [
        ProvisionResult(
          id: 'a',
          email: 'asha@x.com',
          outcome: ProvisionOutcome.created,
          newAccount: true,
        ),
      ];
    final auth = _RecordingAuth();
    await _open(tester, prov, auth);
    await tester.tap(find.text('Create logins'));
    await tester.pumpAndSettle();
    expect(prov.setup?.option, PasswordSetupOption.activationEmail);
    expect(prov.setup?.password, isNull);
    expect(auth.resetTo, ['asha@x.com']);
  });

  testWidgets('only edited or newly typed emails are sent to the server', (
    tester,
  ) async {
    final prov = _FakeProvisioner();
    await _open(tester, prov, _RecordingAuth());
    await tester.enterText(
      find.widgetWithText(TextField, 'Asha — email (edit to change)'),
      'new@x.com',
    );
    await tester.pump();
    await tester.tap(find.text('Create logins'));
    await tester.pumpAndSettle();
    expect(prov.emails, {'a': 'new@x.com'});
  });

  testWidgets('a moved email gets the set-password link, nothing else does', (
    tester,
  ) async {
    final prov = _FakeProvisioner()
      ..answer = const [
        ProvisionResult(
          id: 'a',
          email: 'new@x.com',
          outcome: ProvisionOutcome.emailUpdated,
        ),
      ];
    final auth = _RecordingAuth();
    await _open(tester, prov, auth);
    await tester.tap(find.text('Create logins'));
    await tester.pumpAndSettle();
    expect(auth.resetTo, ['new@x.com']);
    expect(find.textContaining('1 email changed'), findsOneWidget);
  });

  testWidgets('admin-defined password needs a valid, matching pair', (
    tester,
  ) async {
    final prov = _FakeProvisioner();
    final auth = _RecordingAuth();
    await _open(tester, prov, auth);
    await tester.tap(find.text('One password set by you'));
    await tester.pump();
    FilledButton button() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create logins'),
    );
    expect(button().onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Temporary password'),
      'short',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'short',
    );
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.enterText(
      find.widgetWithText(TextField, 'Temporary password'),
      'Welcome2026',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'Welcome2026',
    );
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Create logins'));
    await tester.pumpAndSettle();
    expect(prov.setup?.option, PasswordSetupOption.adminDefined);
    expect(prov.setup?.password, 'Welcome2026');
    // Password options never trigger a set-password email.
    expect(auth.resetTo, isEmpty);
  });

  testWidgets('random temporary passwords are offered for download once', (
    tester,
  ) async {
    final prov = _FakeProvisioner()
      ..answer = const [
        ProvisionResult(
          id: 'a',
          name: 'Asha',
          email: 'asha@x.com',
          outcome: ProvisionOutcome.created,
          newAccount: true,
          passwordSet: true,
          tempPassword: 'Xk3mPq9wLz2R',
        ),
      ];
    await _open(tester, prov, _RecordingAuth());
    await tester.tap(find.text('Random temporary password'));
    await tester.pump();
    await tester.tap(find.text('Create logins'));
    await tester.pumpAndSettle();
    expect(find.text('Download passwords (CSV)'), findsOneWidget);
    // The password itself is never rendered on screen.
    expect(find.textContaining('Xk3mPq9wLz2R'), findsNothing);
  });

  for (final size in const [Size(360, 740), Size(800, 1000), Size(1400, 900)]) {
    testWidgets('lays out without overflow at ${size.width.toInt()}px', (
      tester,
    ) async {
      await _open(tester, _FakeProvisioner(), _RecordingAuth(), size: size);
      await tester.tap(find.text('One password set by you'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('people that could not be completed are retried alone', (
    tester,
  ) async {
    final prov = _FakeProvisioner()
      ..answers.addAll([
        const [
          ProvisionResult(
            id: 'a',
            email: 'asha@x.com',
            outcome: ProvisionOutcome.created,
            newAccount: true,
          ),
          ProvisionResult(id: 'b', outcome: ProvisionOutcome.retryLater),
        ],
        const [
          ProvisionResult(
            id: 'b',
            email: 'bala@x.com',
            outcome: ProvisionOutcome.created,
            newAccount: true,
          ),
        ],
      ]);
    final auth = _RecordingAuth();
    await _open(tester, prov, auth);
    await tester.tap(find.text('Create logins'));
    await tester.pumpAndSettle();
    expect(find.text('Retry 1'), findsOneWidget);
    expect(find.textContaining('Nothing was changed'), findsOneWidget);

    await tester.tap(find.text('Retry 1'));
    await tester.pumpAndSettle();
    expect(prov.calls, [
      ['a', 'b'],
      ['b'],
    ]);
    expect(find.textContaining('2 of 2 logins created'), findsOneWidget);
    expect(find.textContaining('Retry'), findsNothing);
    expect(auth.resetTo, ['asha@x.com', 'bala@x.com']);
  });

  testWidgets('a failed set-password email can be resent', (tester) async {
    final prov = _FakeProvisioner()
      ..answer = const [
        ProvisionResult(
          id: 'a',
          email: 'asha@x.com',
          outcome: ProvisionOutcome.created,
          newAccount: true,
        ),
      ];
    final auth = _FlakyAuth(failTimes: 99);
    await _open(tester, prov, auth, auth2: auth);
    await tester.tap(find.text('Create logins'));
    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(find.text('Resend emails'), findsOneWidget);
    auth.failTimes = 0;
    await tester.tap(find.text('Resend emails'));
    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(find.text('Resend emails'), findsNothing);
    expect(auth.resetTo, ['asha@x.com']);
  });

  test('PasswordSetupOption: only the two link options email people', () {
    expect(PasswordSetupOption.values.where((o) => o.sendsEmail).toList(), [
      PasswordSetupOption.activationEmail,
      PasswordSetupOption.resetLink,
    ]);
  });
}

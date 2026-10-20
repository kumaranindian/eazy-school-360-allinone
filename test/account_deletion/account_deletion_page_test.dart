import 'dart:async';

import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/account_deletion/domain/account_deletion_repository.dart';
import 'package:eazy_school_360/features/account_deletion/domain/deletion_request.dart';
import 'package:eazy_school_360/features/account_deletion/domain/reauthenticator.dart';
import 'package:eazy_school_360/features/account_deletion/presentation/pages/account_deletion_page.dart';
import 'package:eazy_school_360/features/account_deletion/presentation/providers/account_deletion_providers.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/domain/login_method.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
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

const _ref = 'DEL-ABCDEFGHJKLMNPQR';

class _Repo implements AccountDeletionRepository {
  List<DeletionRequest> stored;
  Object? requestError;
  Completer<void>? gate;
  int requests = 0;
  final cancelled = <String>[];

  _Repo([List<DeletionRequest>? initial]) : stored = initial ?? [];

  @override
  Future<DeletionRequest> request() async {
    requests++;
    await gate?.future;
    if (requestError != null) throw requestError!;
    final r = DeletionRequest(
      reference: _ref,
      status: DeletionStatus.underReview,
    );
    stored = [r];
    return r;
  }

  @override
  Future<List<DeletionRequest>> mine() async => List.of(stored);

  @override
  Future<DeletionRequest> cancel(String reference) async {
    cancelled.add(reference);
    stored = [
      DeletionRequest(reference: reference, status: DeletionStatus.cancelled),
    ];
    return stored.first;
  }
}

class _Reauth implements Reauthenticator {
  final passwords = <String>[];
  int google = 0;
  Object? error;

  @override
  Future<void> withPassword(String password) async {
    passwords.add(password);
    if (error != null) throw error!;
  }

  @override
  Future<void> withGoogle() async {
    google++;
    if (error != null) throw error!;
  }
}

class _Harness {
  final _Repo repo;
  final _Reauth reauth;
  final FakeAuthRepository auth;
  _Harness(this.repo, this.reauth, this.auth);
}

Future<_Harness> _pump(
  WidgetTester tester, {
  List<DeletionRequest>? existing,
  LoginMethod method = LoginMethod.password,
  String? phone,
  Size size = const Size(800, 1200),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final repo = _Repo(existing);
  final reauth = _Reauth();
  final auth = FakeAuthRepository(
    signedInAs: const AppUser(uid: 'u1', email: 'a@x.example'),
    signInMethod: method,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountDeletionRepositoryProvider.overrideWithValue(repo),
        reauthenticatorProvider.overrideWithValue(reauth),
        authRepositoryProvider.overrideWithValue(auth),
        userRepositoryProvider.overrideWithValue(
          FakeUserRepository({
            'u1': UserProfile(
              userId: 'u1',
              schoolId: 's1',
              branchId: 'main',
              name: 'Parent',
              email: 'a@x.example',
              phone: phone,
              role: UserRole.parent,
              status: UserStatus.active,
            ),
          }),
        ),
        schoolRepositoryProvider.overrideWithValue(
          FakeSchoolRepository(
            schools: {
              's1': const School(
                schoolId: 's1',
                name: 'School',
                email: 's@x.example',
                status: SchoolStatus.active,
              ),
            },
          ),
        ),
      ],
      child: const MaterialApp(home: AccountDeletionPage()),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(repo, reauth, auth);
}

Future<void> _scrollToRequest(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('request-deletion')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(find.byKey(const Key('request-deletion')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // Dialogs scroll on small screens / large text, as they do for a person.
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _acknowledge(WidgetTester tester) async {
  await _scrollToRequest(tester);
  await _tap(tester, find.byKey(const Key('request-deletion')));
  await _tap(tester, find.byKey(const Key('understood')));
  await _tap(tester, find.byKey(const Key('confirm-understood')));
}

void main() {
  testWidgets('explains what is deleted and kept, and offers the request', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('What we delete'), findsOneWidget);
    expect(find.text('What we may keep, and why'), findsOneWidget);
    expect(find.text('If you run a school'), findsOneWidget);
    expect(find.byKey(const Key('request-deletion')), findsOneWidget);
    expect(find.byKey(const Key('request-card')), findsNothing);
    expect(find.textContaining('hi@avail404.com'), findsWidgets);
  });

  testWidgets('nothing is requested until the person explicitly confirms', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _scrollToRequest(tester);
    await tester.tap(find.byKey(const Key('request-deletion')));
    await tester.pumpAndSettle();
    // Continue is disabled until the box is ticked.
    final continueBtn = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-understood')),
    );
    expect(continueBtn.onPressed, isNull);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(h.repo.requests, 0);
    expect(h.reauth.passwords, isEmpty);
  });

  testWidgets(
    'password account: confirm, re-enter password, then one request',
    (tester) async {
      final h = await _pump(tester);
      await _acknowledge(tester);
      expect(find.text('Confirm it is you'), findsOneWidget);
      expect(h.repo.requests, 0, reason: 'not before re-authentication');

      await tester.enterText(
        find.byKey(const Key('reauth-password')),
        'hunter22',
      );
      await tester.tap(find.byKey(const Key('reauth-confirm')));
      await tester.pumpAndSettle();

      expect(h.reauth.passwords, ['hunter22']);
      expect(h.repo.requests, 1);
      // Shows the request, its reference and that nothing is deleted yet.
      expect(find.byKey(const Key('request-card')), findsOneWidget);
      expect(find.textContaining(_ref), findsWidgets);
      expect(find.textContaining('has not been deleted yet'), findsOneWidget);
      // And no second request can be started.
      expect(find.byKey(const Key('request-deletion')), findsNothing);
    },
  );

  testWidgets('a wrong password shows an error and files no request', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.reauth.error = const AuthFailure('Incorrect password.');
    await _acknowledge(tester);
    await tester.enterText(find.byKey(const Key('reauth-password')), 'nope');
    await tester.tap(find.byKey(const Key('reauth-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect password.'), findsOneWidget);
    expect(h.repo.requests, 0);
    expect(find.text('Confirm it is you'), findsOneWidget);
  });

  testWidgets('Google account re-authenticates with Google', (tester) async {
    final h = await _pump(tester, method: LoginMethod.google);
    await _acknowledge(tester);
    expect(find.byKey(const Key('reauth-password')), findsNothing);
    await tester.tap(find.byKey(const Key('reauth-confirm')));
    await tester.pumpAndSettle();
    expect(h.reauth.google, 1);
    expect(h.repo.requests, 1);
  });

  testWidgets('phone-code account re-verifies with a WhatsApp code', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      method: LoginMethod.phoneOtp,
      phone: '+919876543210',
    );
    await _acknowledge(tester);
    await tester.tap(find.byKey(const Key('reauth-confirm'))); // send code
    await tester.pumpAndSettle();
    expect(h.auth.requestedPhones, ['+919876543210']);
    expect(h.repo.requests, 0);
    await tester.enterText(find.byKey(const Key('reauth-code')), '123456');
    await tester.tap(find.byKey(const Key('reauth-confirm')));
    await tester.pumpAndSettle();
    expect(h.auth.verifiedCodes, ['123456']);
    expect(h.repo.requests, 1);
  });

  testWidgets('a phone-code account with no phone on file cannot continue', (
    tester,
  ) async {
    final h = await _pump(tester, method: LoginMethod.phoneOtp);
    await _acknowledge(tester);
    expect(find.textContaining('no phone number'), findsOneWidget);
    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('reauth-confirm')),
    );
    expect(btn.onPressed, isNull);
    expect(h.repo.requests, 0);
  });

  testWidgets('cancelling the re-authentication files nothing', (tester) async {
    final h = await _pump(tester);
    await _acknowledge(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.repo.requests, 0);
    expect(find.byKey(const Key('request-deletion')), findsOneWidget);
  });

  testWidgets('a server refusal is shown in plain words', (tester) async {
    final h = await _pump(tester);
    h.repo.requestError = const DeletionFailure(
      DeletionFailureKind.platformAdmin,
    );
    await _acknowledge(tester);
    await tester.enterText(
      find.byKey(const Key('reauth-password')),
      'pw123456',
    );
    await tester.tap(find.byKey(const Key('reauth-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('handled by Avail404'), findsOneWidget);
    expect(find.byKey(const Key('request-card')), findsNothing);
  });

  testWidgets('tapping repeatedly while a request is in flight sends one', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.repo.gate = Completer<void>();
    await _acknowledge(tester);
    await tester.enterText(
      find.byKey(const Key('reauth-password')),
      'pw123456',
    );
    await tester.tap(find.byKey(const Key('reauth-confirm')));
    await tester.pump(const Duration(milliseconds: 300));
    // The request button is disabled while it is in flight.
    final btn = tester.widget<FilledButton>(
      find.byKey(const Key('request-deletion')),
    );
    expect(btn.onPressed, isNull);
    h.repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(h.repo.requests, 1);
  });

  testWidgets('an open request is shown and can be cancelled before approval', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      existing: [
        const DeletionRequest(
          reference: _ref,
          status: DeletionStatus.underReview,
        ),
      ],
    );
    expect(find.byKey(const Key('request-card')), findsOneWidget);
    expect(find.byKey(const Key('request-deletion')), findsNothing);
    await tester.tap(find.byKey(const Key('cancel-request')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel request'));
    await tester.pumpAndSettle();
    expect(h.repo.cancelled, [_ref]);
    expect(find.text('Cancelled'), findsOneWidget);
    // Cancelled requests do not block a new one.
    expect(find.byKey(const Key('request-deletion')), findsOneWidget);
  });

  testWidgets('an approved request can no longer be cancelled here', (
    tester,
  ) async {
    await _pump(
      tester,
      existing: [
        const DeletionRequest(reference: _ref, status: DeletionStatus.approved),
      ],
    );
    expect(find.byKey(const Key('cancel-request')), findsNothing);
    expect(find.textContaining('has not been completed yet'), findsOneWidget);
  });

  testWidgets('a sole administrator is told why the request is on hold', (
    tester,
  ) async {
    await _pump(
      tester,
      existing: [
        const DeletionRequest(
          reference: _ref,
          status: DeletionStatus.actionRequired,
          reason: DeletionReason.soleAdmin,
        ),
      ],
    );
    expect(find.textContaining('only administrator'), findsWidgets);
  });

  testWidgets('a completed request is the only one that says it was deleted', (
    tester,
  ) async {
    await _pump(
      tester,
      existing: [
        const DeletionRequest(
          reference: _ref,
          status: DeletionStatus.completed,
        ),
      ],
    );
    expect(find.textContaining('were deleted'), findsOneWidget);
  });

  group('lays out without overflow', () {
    const sizes = <String, Size>{
      'small phone 320x568': Size(320, 568),
      'phone 360x800': Size(360, 800),
      'tablet 768x1024': Size(768, 1024),
      'desktop 1920x1080': Size(1920, 1080),
    };
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final e in sizes.entries) {
        testWidgets('${e.key}, text x$scale', (tester) async {
          await _pump(tester, size: e.value, textScale: scale);
          await _acknowledge(tester);
          expect(find.text('Confirm it is you'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

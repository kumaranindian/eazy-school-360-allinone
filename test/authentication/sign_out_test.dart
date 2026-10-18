import 'dart:async';

import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/authentication/presentation/sign_out.dart';
import 'package:eazy_school_360/features/notifications/domain/push_gateway.dart';
import 'package:eazy_school_360/features/notifications/presentation/providers/notification_providers.dart';
import 'package:eazy_school_360/features/notifications/presentation/providers/push_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/communication_fakes.dart';
import '../support/fakes.dart';
import '../support/push_fakes.dart';

/// NOTIF-1 / STATE-3: every sign-out path stops this device receiving the
/// user's pushes, never waits long for it, and never runs twice.
final List<String> _log = [];

class _Auth extends FakeAuthRepository {
  _Auth()
    : super(
        signedInAs: const AppUser(uid: 'u1', email: 'a@x.example'),
      );

  @override
  Future<void> signOut() async {
    _log.add('signOut');
    await super.signOut();
  }
}

class _Repo extends FakeNotificationRepository {
  Object? error;

  @override
  Future<void> removeDevice({
    required String userId,
    required String token,
  }) async {
    _log.add('removeDevice($token)');
    if (error != null) throw error!;
    await super.removeDevice(userId: userId, token: token);
  }
}

class _Gateway extends FakePushGateway {
  Completer<String?>? hang;

  @override
  Future<String?> getToken() => hang?.future ?? super.getToken();

  @override
  Future<void> deleteToken() async {
    _log.add('deleteToken');
    await super.deleteToken();
  }
}

Future<_Auth> _pump(
  WidgetTester tester, {
  _Gateway? gateway,
  _Repo? repo,
  bool tenantResolves = true,
  Duration timeout = const Duration(seconds: 4),
}) async {
  _log.clear();
  final auth = _Auth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        pushGatewayProvider.overrideWithValue(gateway ?? _Gateway()),
        notificationRepositoryProvider.overrideWithValue(repo ?? _Repo()),
        notificationScopeProvider.overrideWith(
          (ref) async => tenantResolves
              ? const NotificationScope(
                  schoolId: 's1',
                  userId: 'u1',
                  role: UserRole.parent,
                  parentId: 'p1',
                  branchIds: ['main'],
                  canReviewLeave: false,
                )
              : throw StateError('account inactive'),
        ),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () => signOutWithCleanup(ref, cleanupTimeout: timeout),
            child: const Text('Sign out'),
          ),
        ),
      ),
    ),
  );
  return auth;
}

void main() {
  testWidgets('removes this device, then signs out (in that order)', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(_log, [
      'removeDevice(tokenAAAAAAAAAAAAAAAAAAAAAAAA)',
      'deleteToken',
      'signOut',
    ]);
  });

  testWidgets('works when the tenant cannot be resolved (account-inactive and '
      'create-school pages)', (tester) async {
    await _pump(tester, tenantResolves: false);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(_log, contains('removeDevice(tokenAAAAAAAAAAAAAAAAAAAAAAAA)'));
    expect(_log.last, 'signOut');
  });

  testWidgets('a hanging cleanup never keeps the previous user signed in', (
    tester,
  ) async {
    final g = _Gateway()..hang = Completer<String?>();
    await _pump(tester, gateway: g, timeout: const Duration(seconds: 4));
    await tester.tap(find.text('Sign out'));
    await tester.pump(const Duration(seconds: 3));
    expect(_log, isEmpty, reason: 'still waiting within the grace period');
    await tester.pump(const Duration(seconds: 2));
    expect(_log, ['signOut']);
  });

  testWidgets('an offline / failing callable still signs out', (tester) async {
    final repo = _Repo()..error = Exception('unavailable');
    await _pump(tester, repo: repo);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(_log.last, 'signOut');
  });

  testWidgets('a device without push support just signs out', (tester) async {
    await _pump(tester, gateway: _Gateway()..supported = false);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(_log, ['signOut']);
  });

  testWidgets('tapping twice signs out once', (tester) async {
    final g = _Gateway()..hang = Completer<String?>();
    await _pump(tester, gateway: g);
    await tester.tap(find.text('Sign out'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Sign out'));
    await tester.pump(const Duration(seconds: 5));
    expect(_log.where((e) => e == 'signOut'), hasLength(1));
  });

  test('push-gateway permission enum is unchanged (guard for the fake)', () {
    expect(PushPermission.values, hasLength(3));
  });
}

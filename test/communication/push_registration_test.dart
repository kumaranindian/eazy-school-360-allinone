import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/notifications/domain/notification_preferences.dart';
import 'package:eazy_school_360/features/notifications/domain/push_gateway.dart';
import 'package:eazy_school_360/features/notifications/domain/push_route.dart';
import 'package:eazy_school_360/features/notifications/presentation/providers/notification_providers.dart';
import 'package:eazy_school_360/features/notifications/presentation/providers/push_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/communication_fakes.dart';
import '../support/push_fakes.dart';

const _scope = NotificationScope(
  schoolId: 's1',
  userId: 'u1',
  role: UserRole.parent,
  parentId: 'p1',
  branchIds: ['main'],
  canReviewLeave: false,
);

Future<(ProviderContainer, FakeNotificationRepository)> _run(
  FakePushGateway gateway, {
  bool pushEnabled = true,
  Set<String> registered = const {},
}) async {
  final repo = FakeNotificationRepository();
  if (registered.isNotEmpty) repo.devices['u1'] = {...registered};
  repo.prefs['u1'] = NotificationPreferences(pushEnabled: pushEnabled);
  final c = ProviderContainer(
    overrides: [
      pushGatewayProvider.overrideWithValue(gateway),
      notificationRepositoryProvider.overrideWithValue(repo),
      notificationScopeProvider.overrideWith((ref) async => _scope),
    ],
  );
  addTearDown(c.dispose);
  c.listen(pushRegistrationProvider, (_, _) {});
  await c.read(pushRegistrationProvider.future);
  return (c, repo);
}

void main() {
  test('a native device asks once, then registers its token', () async {
    final g = FakePushGateway();
    final (_, repo) = await _run(g);
    expect(g.calls, ['initialize', 'request']);
    expect(repo.devices['u1'], {g.token});
  });

  test('an already-allowed device registers without prompting', () async {
    final g = FakePushGateway(current: PushPermission.granted);
    final (_, repo) = await _run(g);
    expect(g.calls, isNot(contains('request')));
    expect(repo.devices['u1'], {g.token});
  });

  test('a browser never prompts on its own; it waits for a click', () async {
    final g = FakePushGateway(platform: 'web', requiresUserGesture: true);
    final (c, repo) = await _run(g);
    expect(g.calls, isNot(contains('request')));
    expect(repo.devices['u1'], isNull);

    // The user presses "Enable".
    await g.requestPermission();
    c.invalidate(pushRegistrationProvider);
    expect(await g.permission(), PushPermission.granted);
    await c.read(pushRegistrationProvider.future);
    expect(repo.devices['u1'], {g.token});
  });

  test('a refusal is respected: no prompt again, nothing registered', () async {
    final g = FakePushGateway(current: PushPermission.denied);
    final (_, repo) = await _run(g);
    expect(g.calls, isNot(contains('request')));
    expect(repo.devices['u1'], isNull);
  });

  test('a prompt the user declines registers nothing', () async {
    final g = FakePushGateway(grantsWhenAsked: false);
    final (_, repo) = await _run(g);
    expect(repo.devices['u1'], isNull);
  });

  test('push switched off removes this device and never prompts', () async {
    final g = FakePushGateway();
    final (_, repo) = await _run(g, pushEnabled: false, registered: {g.token!});
    expect(g.calls, isNot(contains('request')));
    expect(repo.devices['u1'] ?? <String>{}, isEmpty);
  });

  test('an unsupported build does nothing', () async {
    final g = FakePushGateway(supported: false);
    final (_, repo) = await _run(g);
    expect(g.calls, isEmpty);
    expect(repo.devices, isEmpty);
  });

  test('a rotated token replaces the old one', () async {
    final g = FakePushGateway(current: PushPermission.granted);
    final (_, repo) = await _run(g);
    g.refresh.add('tokenBBBBBBBBBBBBBBBBBBBBBBBB');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(repo.devices['u1'], {'tokenBBBBBBBBBBBBBBBBBBBBBBBB'});
  });

  group('tap routing', () {
    test('only the notification centre is honoured', () {
      expect(
        PushRoute.resolve({'route': '/notifications'}),
        AppRoutes.notifications,
      );
      for (final bad in [
        '/settings/users',
        'https://evil.example/',
        '//evil.example',
        '/fees/receipts/x',
        '',
      ]) {
        expect(
          PushRoute.resolve({'route': bad}),
          AppRoutes.notifications,
          reason: bad,
        );
      }
      expect(PushRoute.resolve(null), AppRoutes.notifications);
      expect(PushRoute.resolve({}), AppRoutes.notifications);
    });
  });
}

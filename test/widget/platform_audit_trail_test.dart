import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/platform_admin/domain/audit_trail.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_role.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/providers/platform_console_providers.dart';
import 'package:eazy_school_360/features/platform_admin/presentation/providers/platform_ops_providers.dart';
import 'package:eazy_school_360/features/school_setup/domain/school.dart';
import 'package:eazy_school_360/features/school_setup/domain/school_status.dart';
import 'package:eazy_school_360/features/school_setup/presentation/providers/school_providers.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/users/presentation/providers/user_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/platform_fakes.dart';
import '../support/platform_ops_fakes.dart';

const _uid = 'uid-1';

class _W {
  final ProviderContainer container;
  final FakePlatformOpsRepository ops;
  _W(this.container, this.ops);
  String get location => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
}

AuditEventView _event(
  String id, {
  String type = 'STUDENT_UPDATED',
  String category = 'STUDENT',
  String result = 'SUCCESS',
  String source = 'TRIGGER',
  String trust = 'T2',
  List<Map<String, Object?>> changes = const [],
  int at = 1700000000000,
}) => AuditEventView.fromMap({
  'id': id,
  'eventType': type,
  'category': category,
  'action': 'UPDATE',
  'result': result,
  'source': source,
  'trust': trust,
  'clientReported': source == 'CLIENT_REPORTED',
  'schoolId': 'school-1',
  'actorUserId': 'u9',
  'actor': 'Asha Rao',
  'targetEntity': 'STUDENT',
  'targetEntityId': 'st1',
  'atMs': at,
  'description': 'Student updated',
  'changes': changes,
});

Future<_W> _pump(
  WidgetTester tester, {
  PlatformRole role = PlatformRole.owner,
  FakePlatformOpsRepository? ops,
  Size size = const Size(1000, 1600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final o = ops ?? FakePlatformOpsRepository(stats: fakeStats());
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          signedInAs: const AppUser(uid: _uid, email: 'grace@avail404.com'),
        ),
      ),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({
          _uid: UserProfile(
            userId: _uid,
            schoolId: null,
            branchId: null,
            name: 'Grace Hopper',
            email: 'grace@avail404.com',
            role: UserRole.platformAdmin,
            status: UserStatus.active,
            platformRole: role,
          ),
        }),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(
          schools: {
            'school-1': const School(
              schoolId: 'school-1',
              name: 'Rosewood High',
              email: 'o@r.example',
              status: SchoolStatus.active,
            ),
          },
        ),
      ),
      platformConsoleRepositoryProvider.overrideWithValue(
        FakePlatformConsoleRepository(),
      ),
      platformOpsRepositoryProvider.overrideWithValue(o),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  container.read(appRouterProvider).go(AppRoutes.platformAuditTrail);
  await tester.pumpAndSettle();
  return _W(container, o);
}

void main() {
  group('audit trail access', () {
    for (final role in [PlatformRole.owner, PlatformRole.compliance]) {
      testWidgets('${role.name} sees the trail', (tester) async {
        await _pump(tester, role: role);
        expect(find.byKey(const ValueKey('audit-summary')), findsOneWidget);
        expect(
          find.text('Your platform role cannot open the audit trail.'),
          findsNothing,
        );
      });
    }

    for (final role in [PlatformRole.support, PlatformRole.viewer]) {
      testWidgets(
        '${role.name} is told the trail is not for their role, and nothing is requested',
        (tester) async {
          final w = await _pump(tester, role: role);
          expect(
            find.text('Your platform role cannot open the audit trail.'),
            findsOneWidget,
          );
          expect(w.ops.auditQueries, isEmpty);
          expect(find.byKey(const ValueKey('audit-export')), findsNothing);
        },
      );
    }

    testWidgets('the home tile is shown to owners and compliance only', (
      tester,
    ) async {
      final w = await _pump(tester, role: PlatformRole.support);
      w.container.read(appRouterProvider).go(AppRoutes.platformHome);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('tile-platform-audit-trail')),
        findsNothing,
      );
    });

    testWidgets('owner: the home tile opens the trail', (tester) async {
      final w = await _pump(tester);
      w.container.read(appRouterProvider).go(AppRoutes.platformHome);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tile-platform-audit-trail')));
      await tester.pumpAndSettle();
      expect(w.location, AppRoutes.platformAuditTrail);
    });
  });

  group('audit trail content', () {
    testWidgets('the summary shows the headline numbers', (tester) async {
      final ops = FakePlatformOpsRepository(stats: fakeStats())
        ..auditSummaryValue = const AuditSummary(
          hours: 24,
          total: 321,
          byCategory: {},
          denied: 4,
          failures: 2,
          clientReported: 7,
        );
      await _pump(tester, ops: ops);
      expect(find.text('321'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets(
      'events list newest first with who, when and where; denied ones and app reports are marked',
      (tester) async {
        final ops = FakePlatformOpsRepository(stats: fakeStats())
          ..auditPageOne = AuditPage(
            events: [
              _event('e1'),
              _event(
                'e2',
                type: 'PERMISSION_DENIED_UI',
                category: 'SECURITY',
                result: 'DENIED',
                source: 'CLIENT_REPORTED',
                trust: 'T4',
              ),
            ],
          );
        await _pump(tester, ops: ops);
        expect(find.text('Student updated'), findsOneWidget);
        expect(find.text('Permission denied ui'), findsOneWidget);
        expect(find.text('denied'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('audit-client-reported')),
          findsOneWidget,
        );
        expect(find.textContaining('Asha Rao'), findsWidgets);
        expect(find.textContaining('school school-1'), findsWidgets);
      },
    );

    testWidgets('an empty result says so', (tester) async {
      await _pump(tester);
      expect(find.text('Nothing recorded for these filters.'), findsOneWidget);
    });

    testWidgets(
      'a detail dialog explains trust and shows changes; unrecorded values are not invented',
      (tester) async {
        final ops = FakePlatformOpsRepository(stats: fakeStats())
          ..auditPageOne = AuditPage(
            events: [
              _event(
                'e1',
                changes: [
                  {'field': 'status', 'from': 'ACTIVE', 'to': 'INACTIVE'},
                  {'field': 'phone', 'changed': true},
                ],
              ),
              _event(
                'e2',
                source: 'CLIENT_REPORTED',
                trust: 'T4',
                type: 'LOGOUT',
                category: 'AUTHENTICATION',
              ),
            ],
          );
        await _pump(tester, ops: ops);
        await tester.tap(find.byKey(const ValueKey('audit-e1')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('audit-detail')), findsOneWidget);
        expect(find.text('status: ACTIVE → INACTIVE'), findsOneWidget);
        expect(
          find.text('phone: changed (value not recorded)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Observed after the change'),
          findsOneWidget,
        );
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('audit-e2')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Reported by the app (not verified)'),
          findsOneWidget,
        );
      },
    );
  });

  group('audit trail filters and paging', () {
    testWidgets('a preset asks the server for exactly that view', (
      tester,
    ) async {
      final w = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('audit-preset-Denied')));
      await tester.pumpAndSettle();
      expect(w.ops.auditQueries.last.filter.result, 'DENIED');
      await tester.tap(find.byKey(const ValueKey('audit-preset-Security')));
      await tester.pumpAndSettle();
      expect(w.ops.auditQueries.last.filter.category, 'SECURITY');
      expect(
        w.ops.auditQueries.last.filter.result,
        isNull,
        reason: 'presets replace each other',
      );
      await tester.tap(
        find.byKey(const ValueKey('audit-preset-Reported by the app')),
      );
      await tester.pumpAndSettle();
      expect(w.ops.auditQueries.last.filter.source, 'CLIENT_REPORTED');
    });

    testWidgets('time window and area change the request', (tester) async {
      final w = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('audit-window')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last 24 hours').last);
      await tester.pumpAndSettle();
      expect(w.ops.auditQueries.last.filter.hours, 24);
      await tester.tap(find.byKey(const ValueKey('audit-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fees').last);
      await tester.pumpAndSettle();
      expect(w.ops.auditQueries.last.filter.category, 'FEES');
      expect(
        w.ops.auditQueries.last.filter.hours,
        24,
        reason: 'filters combine',
      );
    });

    testWidgets('school and user filters apply on submit and are trimmed', (
      tester,
    ) async {
      final w = await _pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('audit-school')),
        '  school-1  ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(w.ops.auditQueries.last.filter.schoolId, 'school-1');
      await tester.enterText(find.byKey(const ValueKey('audit-actor')), 'u9');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(w.ops.auditQueries.last.filter.actorUserId, 'u9');
      expect(w.ops.auditQueries.last.filter.schoolId, 'school-1');
    });

    testWidgets(
      'load more appends the next page using the cursor, then stops',
      (tester) async {
        final ops = FakePlatformOpsRepository(stats: fakeStats())
          ..auditPageOne = AuditPage(
            events: [_event('e1')],
            nextCursor: const {'m': '202611', 'id': 'e1'},
          )
          ..auditPageTwo = AuditPage(
            events: [_event('e2', type: 'INVOICE_UPDATED', category: 'FEES')],
          );
        await _pump(tester, ops: ops);
        expect(find.byKey(const ValueKey('audit-e2')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('audit-more')));
        await tester.pumpAndSettle();
        expect(ops.auditQueries.last.cursor, {'m': '202611', 'id': 'e1'});
        expect(find.byKey(const ValueKey('audit-e1')), findsOneWidget);
        expect(find.byKey(const ValueKey('audit-e2')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('audit-more')),
          findsNothing,
          reason: 'no more pages',
        );
      },
    );

    testWidgets('a wide search that was cut short says so', (tester) async {
      final ops = FakePlatformOpsRepository(stats: fakeStats())
        ..auditPageOne = AuditPage(events: [_event('e1')], truncated: true);
      await _pump(tester, ops: ops);
      expect(find.byKey(const ValueKey('audit-truncated')), findsOneWidget);
    });

    testWidgets('a failed first load shows a retry, not a blank page', (
      tester,
    ) async {
      final ops = FakePlatformOpsRepository(stats: fakeStats())
        ..error = const NetworkFailure();
      await _pump(tester, ops: ops);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('audit export', () {
    testWidgets('copies the current filter as CSV and says how many rows', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final ops = FakePlatformOpsRepository(stats: fakeStats())
        ..auditCsv =
            'time_utc,event_type\n2026-06-14T10:00:00.000Z,STUDENT_UPDATED\n';
      await _pump(tester, ops: ops);
      await tester.tap(find.byKey(const ValueKey('audit-preset-Denied')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('audit-export')));
      await tester.pumpAndSettle();
      expect(ops.auditExports.single.result, 'DENIED');
      expect(copied, contains('STUDENT_UPDATED'));
      expect(
        find.textContaining('rows copied as CSV (times in UTC)'),
        findsOneWidget,
      );
    });

    testWidgets('a refused export shows the reason and copies nothing', (
      tester,
    ) async {
      final ops = FakePlatformOpsRepository(stats: fakeStats());
      await _pump(tester, ops: ops);
      ops.error = const PermissionFailure('Your platform role cannot do that.');
      await tester.tap(find.byKey(const ValueKey('audit-export')));
      await tester.pumpAndSettle();
      expect(find.text('Your platform role cannot do that.'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final size in const [
      Size(360, 640),
      Size(768, 1024),
      Size(1400, 900),
    ]) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets('audit trail fits at $size, text x$scale', (tester) async {
          final ops = FakePlatformOpsRepository(stats: fakeStats())
            ..auditPageOne = AuditPage(
              events: [
                _event(
                  'e1',
                  type: 'A_VERY_LONG_EVENT_TYPE_NAME_THAT_MUST_WRAP_ON_A_PHONE',
                  result: 'DENIED',
                  source: 'CLIENT_REPORTED',
                  trust: 'T4',
                ),
                _event('e2'),
              ],
              nextCursor: const {'m': '202611', 'id': 'e2'},
              truncated: true,
            )
            ..auditSummaryValue = const AuditSummary(
              hours: 24,
              total: 12345,
              byCategory: {},
              denied: 12,
              failures: 3,
              clientReported: 8,
            );
          await _pump(tester, ops: ops, size: size, textScale: scale);
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('audit-e1')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.byKey(const ValueKey('audit-e1')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'detail dialog');
        });
      }
    }
  });

  group('AuditFilter', () {
    test('the request carries the window and leaves blank fields out', () {
      final now = DateTime.utc(2026, 6, 15, 12);
      final r = const AuditFilter(
        hours: 24,
        schoolId: ' s1 ',
        category: 'FEES',
        actorUserId: '  ',
      ).toRequest(now);
      expect(r['toMs'], now.millisecondsSinceEpoch);
      expect(
        r['fromMs'],
        now.subtract(const Duration(hours: 24)).millisecondsSinceEpoch,
      );
      expect(r['schoolId'], 's1');
      expect(r['category'], 'FEES');
      expect(r.containsKey('actorUserId'), isFalse);
      expect(r.containsKey('result'), isFalse);
    });

    test('copyWith keeps what is not changed and can clear a field', () {
      const f = AuditFilter(category: 'FEES', result: 'DENIED');
      expect(f.copyWith(hours: 24).category, 'FEES');
      expect(f.copyWith(category: null).category, isNull);
      expect(f.copyWith(category: null).result, 'DENIED');
      expect(
        f == const AuditFilter(category: 'FEES', result: 'DENIED'),
        isTrue,
      );
    });

    test(
      'every window the page offers is within the server limit of 92 days',
      () {
        for (final h in AuditFilter.windows) {
          expect(h, lessThanOrEqualTo(92 * 24));
        }
      },
    );
  });

  group('AuditEventView', () {
    test(
      'reads the server row; trust labels are plain; titles are readable',
      () {
        final e = _event('x', type: 'INVOICE_UPDATED', category: 'FEES');
        expect(e.title, 'Invoice updated');
        expect(e.trustLabel, 'Observed after the change');
        for (final t in ['T1', 'T2', 'T3', 'T4']) {
          expect(AuditEventView.fromMap({'trust': t}).trustLabel, isNot(t));
        }
        expect(AuditEventView.fromMap(const {}).result, 'SUCCESS');
        expect(AuditEventView.fromMap(const {}).changes, isEmpty);
      },
    );

    test('a change without values is not shown as having values', () {
      expect(
        AuditChange.fromMap({'field': 'phone', 'changed': true}).hasValues,
        isFalse,
      );
      expect(
        AuditChange.fromMap({
          'field': 'status',
          'from': 'A',
          'to': 'B',
        }).hasValues,
        isTrue,
      );
    });

    test('every category has a readable label', () {
      for (final c in auditCategories) {
        expect(auditCategoryLabel(c), isNot(c));
      }
    });
  });
}

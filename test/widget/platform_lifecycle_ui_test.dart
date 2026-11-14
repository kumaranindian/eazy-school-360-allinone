import 'package:eazy_school_360/app/app.dart';
import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/features/feature_catalogue.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_router.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/platform_admin/domain/platform_ops_models.dart';
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/platform_fakes.dart';
import '../support/platform_ops_fakes.dart';

const _uid = 'uid-1';
const _school = School(
  schoolId: 'school-1',
  name: 'Rosewood High',
  email: 'o@r.example',
  status: SchoolStatus.active,
);

UserProfile _platform(PlatformRole role) => UserProfile(
  userId: _uid,
  schoolId: null,
  branchId: null,
  name: 'Grace Hopper',
  email: 'grace@avail404.com',
  role: UserRole.platformAdmin,
  status: UserStatus.active,
  platformRole: role,
);

class _Auth extends FakeAuthRepository {
  final sent = <String>[];
  bool fail = false;
  _Auth()
    : super(
        signedInAs: const AppUser(uid: _uid, email: 'grace@avail404.com'),
      );

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    if (fail) throw const NetworkFailure();
    sent.add(email);
  }
}

class _W {
  final ProviderContainer container;
  final FakePlatformConsoleRepository console;
  final FakePlatformOpsRepository ops;
  final _Auth auth;
  _W(this.container, this.console, this.ops, this.auth);

  String get location => container
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .path;
  void go(String p) => container.read(appRouterProvider).go(p);
}

Future<_W> _pump(
  WidgetTester tester, {
  PlatformRole role = PlatformRole.owner,
  FakePlatformConsoleRepository? console,
  FakePlatformOpsRepository? ops,
  Size size = const Size(1000, 3200),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final c = console ?? FakePlatformConsoleRepository(overview: overviewWith());
  final o = ops ?? FakePlatformOpsRepository(stats: fakeStats());
  final auth = _Auth();
  final container = ProviderContainer(
    overrides: [
      envConfigProvider.overrideWithValue(
        EnvConfig.forEnvironment(AppEnvironment.test),
      ),
      authRepositoryProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(
        FakeUserRepository({_uid: _platform(role)}),
      ),
      schoolRepositoryProvider.overrideWithValue(
        FakeSchoolRepository(schools: {'school-1': _school}),
      ),
      platformConsoleRepositoryProvider.overrideWithValue(c),
      platformOpsRepositoryProvider.overrideWithValue(o),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();
  return _W(container, c, o, auth);
}

Future<void> _open(WidgetTester tester, _W w, String path) async {
  w.go(path);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

const _school1 = '/platform/schools/school-1';

void main() {
  group('suspend and reactivate', () {
    testWidgets(
      'an owner suspends a school with a real reason, after a warning',
      (tester) async {
        final w = await _pump(tester);
        await _open(tester, w, _school1);
        expect(find.text('This school is active.'), findsOneWidget);
        await _tap(tester, 'school-suspend');
        expect(find.textContaining('signed out of their data'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('reason-field')),
          'short',
        );
        await tester.tap(find.byKey(const ValueKey('reason-confirm')));
        await tester.pumpAndSettle();
        expect(find.textContaining('at least 10'), findsOneWidget);
        expect(w.ops.statusCalls, isEmpty);
        await tester.enterText(
          find.byKey(const ValueKey('reason-field')),
          'Unpaid for three months',
        );
        await tester.tap(find.byKey(const ValueKey('reason-confirm')));
        await tester.pumpAndSettle();
        expect(w.ops.statusCalls.single, (
          schoolId: 'school-1',
          status: SchoolStatusChoice.suspended,
          reason: 'Unpaid for three months',
        ));
      },
    );

    testWidgets('cancelling the warning suspends nothing', (tester) async {
      final w = await _pump(tester);
      await _open(tester, w, _school1);
      await _tap(tester, 'school-suspend');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(w.ops.statusCalls, isEmpty);
    });

    testWidgets(
      'a suspended school shows why, and an owner can reactivate it',
      (tester) async {
        final w = await _pump(
          tester,
          console: FakePlatformConsoleRepository(
            overview: overviewWith(
              status: 'SUSPENDED',
              reason: 'Unpaid for three months',
            ),
          ),
        );
        await _open(tester, w, _school1);
        expect(
          find.textContaining('All of its users are paused'),
          findsOneWidget,
        );
        expect(find.text('Reason: Unpaid for three months'), findsOneWidget);
        expect(find.byKey(const ValueKey('school-suspend')), findsNothing);
        await _tap(tester, 'school-reactivate');
        await tester.tap(find.byKey(const ValueKey('act-confirm')));
        await tester.pumpAndSettle();
        expect(w.ops.statusCalls.single.status, SchoolStatusChoice.active);
      },
    );

    testWidgets(
      'support and viewers cannot suspend; support can re-apply the status to users',
      (tester) async {
        var w = await _pump(tester, role: PlatformRole.support);
        await _open(tester, w, _school1);
        expect(find.byKey(const ValueKey('school-suspend')), findsNothing);
        await _tap(tester, 'school-reapply');
        expect(w.ops.calls, ['refresh:school-1']);
      },
    );

    testWidgets('a viewer sees status but no controls', (tester) async {
      final w = await _pump(tester, role: PlatformRole.viewer);
      await _open(tester, w, _school1);
      expect(find.byKey(const ValueKey('school-suspend')), findsNothing);
      expect(find.byKey(const ValueKey('school-reapply')), findsNothing);
      expect(find.byKey(const ValueKey('admin-add')), findsNothing);
    });

    testWidgets('a refusal is shown, not hidden', (tester) async {
      final ops = FakePlatformOpsRepository(stats: fakeStats())
        ..error = const ValidationFailure(
          'This school is being offboarded. Cancel the offboarding first.',
        );
      final w = await _pump(
        tester,
        ops: ops,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(status: 'SUSPENDED', reason: 'x'),
        ),
      );
      await _open(tester, w, _school1);
      await _tap(tester, 'school-reactivate');
      await tester.tap(find.byKey(const ValueKey('act-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('being offboarded'), findsWidgets);
    });
  });

  group('lifecycle states', () {
    testWidgets(
      'an INACTIVE school is shown as not yet activated, and an owner activates it',
      (tester) async {
        final w = await _pump(
          tester,
          console: FakePlatformConsoleRepository(
            overview: overviewWith(status: 'INACTIVE'),
          ),
        );
        await _open(tester, w, _school1);
        expect(
          find.textContaining('has not been activated yet'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('school-suspend')), findsNothing);
        await _tap(tester, 'school-activate');
        expect(find.text('Activate Rosewood High?'), findsOneWidget);
        expect(w.ops.statusCalls, isEmpty, reason: 'nothing before confirming');
        await tester.enterText(
          find.byKey(const ValueKey('act-remarks')),
          'Paperwork verified',
        );
        await tester.enterText(
          find.byKey(const ValueKey('act-notes')),
          'Called the principal',
        );
        await tester.enterText(
          find.byKey(const ValueKey('act-message')),
          'Welcome aboard',
        );
        await tester.tap(find.byKey(const ValueKey('act-confirm')));
        await tester.pumpAndSettle();
        expect(w.ops.statusCalls.single.status, SchoolStatusChoice.active);
        final sent = w.ops.activationInputs.single;
        expect(
          (sent.remarks, sent.internalNotes, sent.message),
          ('Paperwork verified', 'Called the principal', 'Welcome aboard'),
        );
      },
    );

    testWidgets('an active school can be deactivated, with a real reason', (
      tester,
    ) async {
      final w = await _pump(tester);
      await _open(tester, w, _school1);
      await _tap(tester, 'school-deactivate');
      await tester.enterText(
        find.byKey(const ValueKey('reason-field')),
        'short',
      );
      await tester.tap(find.byKey(const ValueKey('reason-confirm')));
      await tester.pumpAndSettle();
      expect(w.ops.statusCalls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('reason-field')),
        'Switching off until paperwork is done',
      );
      await tester.tap(find.byKey(const ValueKey('reason-confirm')));
      await tester.pumpAndSettle();
      expect(w.ops.statusCalls.single.status, SchoolStatusChoice.inactive);
      expect(
        w.ops.statusCalls.single.reason,
        'Switching off until paperwork is done',
      );
    });

    testWidgets('an expired school reads as expired and can be reactivated', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(status: 'EXPIRED'),
        ),
      );
      await _open(tester, w, _school1);
      expect(find.textContaining('subscription has expired'), findsOneWidget);
      expect(find.byKey(const ValueKey('school-reactivate')), findsOneWidget);
    });

    testWidgets(
      'a CLOSED school has no activation, only the recovery request',
      (tester) async {
        final w = await _pump(
          tester,
          console: FakePlatformConsoleRepository(
            overview: overviewWith(status: 'CLOSED'),
          ),
        );
        await _open(tester, w, _school1);
        expect(find.textContaining('This school is closed'), findsOneWidget);
        for (final k in [
          'school-activate',
          'school-reactivate',
          'school-suspend',
          'school-deactivate',
          'school-reapply',
        ]) {
          expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
        }
        await _tap(tester, 'recovery-request');
        await tester.enterText(
          find.byKey(const ValueKey('reason-field')),
          'too short',
        );
        await tester.tap(find.byKey(const ValueKey('reason-confirm')));
        await tester.pumpAndSettle();
        expect(w.ops.recoveryCalls, isEmpty);
        await tester.enterText(
          find.byKey(const ValueKey('reason-field')),
          'Closed by mistake, contract was renewed',
        );
        await tester.tap(find.byKey(const ValueKey('reason-confirm')));
        await tester.pumpAndSettle();
        expect(
          w.ops.recoveryCalls.single,
          startsWith('request:Closed by mistake'),
        );
      },
    );

    Map<String, dynamic> recovery(String by) => {
      'state': 'REQUESTED',
      'reason': 'Closed by mistake',
      'requestedBy': by,
      'requestedByEmail': 'ben@avail404.com',
    };

    testWidgets('a DIFFERENT owner approves a recovery', (tester) async {
      final w = await _pump(
        tester,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(
            status: 'CLOSED',
            recovery: recovery('someone-else'),
          ),
        ),
      );
      await _open(tester, w, _school1);
      expect(
        find.textContaining('Recovery requested by ben@avail404.com'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recovery-request')), findsNothing);
      await _tap(tester, 'recovery-approve');
      expect(w.ops.recoveryCalls, ['approve']);
    });

    testWidgets(
      'the requester cannot approve their own recovery, but can cancel it',
      (tester) async {
        final w = await _pump(
          tester,
          console: FakePlatformConsoleRepository(
            overview: overviewWith(status: 'CLOSED', recovery: recovery(_uid)),
          ),
        );
        await _open(tester, w, _school1);
        expect(find.byKey(const ValueKey('recovery-approve')), findsNothing);
        expect(
          find.text('Waiting for a different owner to approve.'),
          findsOneWidget,
        );
        await _tap(tester, 'recovery-cancel');
        expect(w.ops.recoveryCalls, ['cancel']);
      },
    );

    testWidgets('only owners see recovery controls', (tester) async {
      final w = await _pump(
        tester,
        role: PlatformRole.support,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(status: 'CLOSED'),
        ),
      );
      await _open(tester, w, _school1);
      expect(find.byKey(const ValueKey('recovery-request')), findsNothing);
    });

    testWidgets('support and viewers cannot activate or deactivate', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        role: PlatformRole.support,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(status: 'INACTIVE'),
        ),
      );
      await _open(tester, w, _school1);
      expect(find.byKey(const ValueKey('school-activate')), findsNothing);
    });
  });

  group('subscription', () {
    Map<String, dynamic> subOf(
      String status, {
      String cls = 'PAID',
      int grace = 0,
      String? cancelled,
    }) => {
      'planName': 'Annual',
      'classification': cls,
      'startDate': '2026-04-01',
      'endDate': '2027-03-31',
      'gracePeriodDays': grace,
      'status': status,
      'remarks': 'Signed on call',
      'internalNotes': 'Pays late',
      if (cancelled != null) 'cancellationReason': cancelled,
    };
    Future<_W> open(
      WidgetTester tester, {
      Map<String, dynamic>? subscription,
      PlatformRole role = PlatformRole.owner,
      FakePlatformOpsRepository? ops,
    }) async {
      final w = await _pump(
        tester,
        role: role,
        ops: ops,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(subscription: subscription),
        ),
      );
      await _open(tester, w, _school1);
      return w;
    }

    Future<void> type(WidgetTester t, String key, String v) async {
      await t.enterText(find.byKey(ValueKey(key)), v);
    }

    testWidgets(
      'a school with no subscription reads as legacy, and an owner can start one',
      (tester) async {
        await open(tester);
        expect(find.byKey(const ValueKey('sub-none')), findsOneWidget);
        expect(find.byKey(const ValueKey('sub-set')), findsOneWidget);
        expect(find.byKey(const ValueKey('sub-trial')), findsOneWidget);
        expect(find.byKey(const ValueKey('sub-renew')), findsNothing);
      },
    );

    testWidgets(
      'the current subscription shows status, dates in the school zone, remarks and notes',
      (tester) async {
        await open(tester, subscription: subOf('ACTIVE', grace: 5));
        expect(find.text('Active'), findsWidgets);
        expect(find.textContaining('2026-04-01 to 2027-03-31'), findsOneWidget);
        expect(find.textContaining('Grace period: 5 days'), findsOneWidget);
        expect(find.textContaining('Signed on call'), findsOneWidget);
        expect(find.textContaining('Pays late'), findsOneWidget);
      },
    );

    testWidgets('blocking states say the school is paused and offer renewal', (
      tester,
    ) async {
      await open(tester, subscription: subOf('EXPIRED'));
      expect(find.textContaining('Renew to switch it back on'), findsOneWidget);
      expect(find.byKey(const ValueKey('sub-renew')), findsOneWidget);
      expect(find.byKey(const ValueKey('sub-trial')), findsOneWidget);
    });

    testWidgets('a not-started subscription says when it begins', (
      tester,
    ) async {
      await open(tester, subscription: subOf('NOT_STARTED'));
      expect(
        find.textContaining('paused until the start date'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a cancelled one hides extend and cancel but keeps renew and shows the reason',
      (tester) async {
        await open(
          tester,
          subscription: subOf('CANCELLED', cancelled: 'Left the platform'),
        );
        expect(find.byKey(const ValueKey('sub-extend')), findsNothing);
        expect(find.byKey(const ValueKey('sub-cancel')), findsNothing);
        expect(find.byKey(const ValueKey('sub-renew')), findsOneWidget);
        expect(find.textContaining('Left the platform'), findsOneWidget);
      },
    );

    for (final role in [
      PlatformRole.support,
      PlatformRole.viewer,
      PlatformRole.compliance,
    ]) {
      testWidgets('${role.name} can read but not change the subscription', (
        tester,
      ) async {
        await open(tester, subscription: subOf('ACTIVE'), role: role);
        expect(find.byKey(const ValueKey('sub-status')), findsOneWidget);
        for (final k in [
          'sub-set',
          'sub-change',
          'sub-extend',
          'sub-renew',
          'sub-cancel',
          'sub-trial',
        ]) {
          expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
        }
      });
    }

    testWidgets(
      'set: checks the plan and dates before calling, then sends exactly what was typed',
      (tester) async {
        final w = await open(tester);
        await _tap(tester, 'sub-set');
        await tester.tap(find.byKey(const ValueKey('sub-save')));
        await tester.pumpAndSettle();
        expect(find.text('Choose a plan.'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('sub-plan')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Annual · Annual').last);
        await tester.pumpAndSettle();
        await type(tester, 'sub-start', '2026-02-30');
        await type(tester, 'sub-end', '2027-03-31');
        await tester.tap(find.byKey(const ValueKey('sub-save')));
        await tester.pumpAndSettle();
        expect(
          find.text('Enter a real start date (YYYY-MM-DD).'),
          findsOneWidget,
        );
        await type(tester, 'sub-start', '2026-04-01');
        await type(tester, 'sub-end', '2026-03-31');
        await tester.tap(find.byKey(const ValueKey('sub-save')));
        await tester.pumpAndSettle();
        expect(
          find.text('The end date cannot be before the start date.'),
          findsOneWidget,
        );
        expect(w.ops.subCalls, isEmpty, reason: 'nothing sent while invalid');
        await type(tester, 'sub-end', '2027-03-31');
        await type(tester, 'sub-grace', '5');
        await tester.tap(find.byKey(const ValueKey('sub-save')));
        await tester.pumpAndSettle();
        final c = w.ops.subCalls.single;
        expect((c.op, c.schoolId), ('set', 'school-1'));
        expect(c.args['planId'], 'annual');
        expect(
          (
            c.args['classification'],
            c.args['startDate'],
            c.args['endDate'],
            c.args['gracePeriodDays'],
          ),
          ('PAID', '2026-04-01', '2027-03-31', 5),
        );
      },
    );

    testWidgets('extend needs a real date and a reason', (tester) async {
      final w = await open(tester, subscription: subOf('ACTIVE'));
      await _tap(tester, 'sub-extend');
      await type(tester, 'sub-end', '2027-06-30');
      await tester.tap(find.byKey(const ValueKey('sub-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Give a reason of at least 10 characters.'),
        findsOneWidget,
      );
      await type(tester, 'sub-reason', 'Goodwill for the delay');
      await tester.tap(find.byKey(const ValueKey('sub-save')));
      await tester.pumpAndSettle();
      final c = w.ops.subCalls.single;
      expect(
        (c.op, c.args['endDate'], c.args['reason']),
        ('extend', '2027-06-30', 'Goodwill for the delay'),
      );
    });

    testWidgets(
      'renew sends only the end date when the start is left to the default',
      (tester) async {
        final w = await open(tester, subscription: subOf('EXPIRED'));
        await _tap(tester, 'sub-renew');
        await type(tester, 'sub-end', '2028-03-31');
        await tester.tap(find.byKey(const ValueKey('sub-save')));
        await tester.pumpAndSettle();
        final c = w.ops.subCalls.single;
        expect(
          (c.op, c.args['startDate'], c.args['endDate']),
          ('renew', null, '2028-03-31'),
        );
      },
    );

    testWidgets('cancel needs a reason and then pauses straight away', (
      tester,
    ) async {
      final w = await open(tester, subscription: subOf('ACTIVE'));
      await _tap(tester, 'sub-cancel');
      expect(find.textContaining('paused straight away'), findsOneWidget);
      await type(tester, 'sub-reason', 'short');
      await tester.tap(find.byKey(const ValueKey('sub-save')));
      await tester.pumpAndSettle();
      expect(w.ops.subCalls, isEmpty);
      await type(tester, 'sub-reason', 'Customer left the platform');
      await tester.tap(find.byKey(const ValueKey('sub-save')));
      await tester.pumpAndSettle();
      expect(w.ops.subCalls.single.op, 'cancel');
    });

    testWidgets('trial: whole days from 1 to 90', (tester) async {
      final w = await open(tester);
      await _tap(tester, 'sub-trial');
      await type(tester, 'sub-days', '91');
      await tester.tap(find.byKey(const ValueKey('sub-save')));
      await tester.pumpAndSettle();
      expect(find.text('A trial lasts 1 to 90 whole days.'), findsOneWidget);
      await type(tester, 'sub-days', '30');
      await tester.tap(find.byKey(const ValueKey('sub-save')));
      await tester.pumpAndSettle();
      expect(
        (w.ops.subCalls.single.op, w.ops.subCalls.single.args['days']),
        ('trial', 30),
      );
    });

    testWidgets(
      'a server refusal stays in the dialog in plain words, and nothing closes',
      (tester) async {
        final ops = FakePlatformOpsRepository(stats: fakeStats());
        await open(tester, subscription: subOf('ACTIVE'), ops: ops);
        await _tap(tester, 'sub-cancel');
        await type(tester, 'sub-reason', 'Customer left the platform');
        ops.error = const ValidationFailure(
          'The subscription is cancelled. Renew it first.',
        );
        await tester.tap(find.byKey(const ValueKey('sub-save')));
        await tester.pumpAndSettle();
        expect(
          find.text('The subscription is cancelled. Renew it first.'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('sub-save')), findsOneWidget);
      },
    );

    testWidgets('history lists each change, with SYSTEM changes labelled', (
      tester,
    ) async {
      final ops = FakePlatformOpsRepository(stats: fakeStats())
        ..subHistory = [
          SubscriptionHistoryEntry.fromMap({
            'id': 'h1',
            'event': 'SUBSCRIPTION_STATUS_CHANGED',
            'atMs': 1700000000000,
            'actorKind': 'SYSTEM',
            'toStatus': 'EXPIRED',
          }),
          SubscriptionHistoryEntry.fromMap({
            'id': 'h2',
            'event': 'SUBSCRIPTION_SET',
            'atMs': 1690000000000,
            'actorEmail': 'o@avail404.com',
            'toStatus': 'ACTIVE',
          }),
        ];
      await open(tester, subscription: subOf('EXPIRED'), ops: ops);
      expect(
        find.byKey(const ValueKey('sub-history-h1')),
        findsNothing,
        reason: 'collapsed until asked',
      );
      await _tap(tester, 'sub-history-toggle');
      expect(
        find.textContaining('Status changed → Expired · System'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Subscription set → Active · o@avail404.com'),
        findsOneWidget,
      );
    });
  });

  group('school administrators', () {
    testWidgets('an owner adds one, who is emailed a password link', (
      tester,
    ) async {
      final w = await _pump(tester);
      await _open(tester, w, _school1);
      await _tap(tester, 'admin-add');
      await tester.enterText(find.byKey(const ValueKey('aa-name')), 'New Head');
      await tester.enterText(
        find.byKey(const ValueKey('aa-email')),
        'New@Rosewood.example',
      );
      await tester.tap(find.byKey(const ValueKey('aa-save')));
      await tester.pumpAndSettle();
      expect(w.ops.admins.single, (
        schoolId: 'school-1',
        name: 'New Head',
        email: 'New@Rosewood.example',
      ));
      expect(w.auth.sent, ['new@rosewood.example']);
    });

    testWidgets('the add form validates first', (tester) async {
      final w = await _pump(tester);
      await _open(tester, w, _school1);
      await _tap(tester, 'admin-add');
      await tester.enterText(find.byKey(const ValueKey('aa-email')), 'nope');
      await tester.tap(find.byKey(const ValueKey('aa-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter their name'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(w.ops.admins, isEmpty);
    });

    testWidgets(
      'if the email cannot be sent the admin still exists and the person is told',
      (tester) async {
        final w = await _pump(tester);
        w.auth.fail = true;
        await _open(tester, w, _school1);
        await _tap(tester, 'admin-add');
        await tester.enterText(
          find.byKey(const ValueKey('aa-name')),
          'New Head',
        );
        await tester.enterText(
          find.byKey(const ValueKey('aa-email')),
          'new@rosewood.example',
        );
        await tester.tap(find.byKey(const ValueKey('aa-save')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(w.ops.admins, hasLength(1));
        expect(find.textContaining('email could not be sent'), findsOneWidget);
      },
    );

    testWidgets(
      'resetting access asks first, signs them out and emails a link',
      (tester) async {
        final w = await _pump(tester, role: PlatformRole.support);
        await _open(tester, w, _school1);
        await _tap(tester, 'reset-sa1');
        expect(find.textContaining('signed out everywhere'), findsOneWidget);
        expect(w.ops.resets, isEmpty);
        await tester.tap(find.byKey(const ValueKey('confirm-yes')));
        await tester.pumpAndSettle();
        expect(w.ops.resets.single, (schoolId: 'school-1', uid: 'sa1'));
        expect(w.auth.sent, ['head@rosewood.example']);
      },
    );

    testWidgets('only an owner can add administrators', (tester) async {
      final w = await _pump(tester, role: PlatformRole.support);
      await _open(tester, w, _school1);
      expect(find.byKey(const ValueKey('admin-add')), findsNothing);
    });
  });

  group('module switches', () {
    Future<void> reason(WidgetTester t, String v) async {
      await t.enterText(find.byKey(const ValueKey('reason-field')), v);
    }

    Future<void> confirmReason(WidgetTester t) async {
      await t.tap(find.byKey(const ValueKey('reason-confirm')));
      await t.pumpAndSettle();
    }

    testWidgets('switching a module off needs a real reason, then sends it', (
      tester,
    ) async {
      final w = await _pump(tester);
      await _open(tester, w, _school1);
      await _tap(tester, 'feature-homework');
      await reason(tester, 'short');
      await confirmReason(tester);
      expect(
        w.ops.featureCalls,
        isEmpty,
        reason: 'nothing sent while the reason is too short',
      );
      await reason(tester, 'Not part of this plan');
      await confirmReason(tester);
      expect(w.ops.featureCalls.single.schoolId, 'school-1');
      expect(w.ops.featureCalls.single.features, {'homework': false});
      expect(w.ops.featureArgs.single, (
        reason: 'Not part of this plan',
        confirm: false,
      ));
    });

    testWidgets(
      'a module others depend on lists them and asks to switch them off too',
      (tester) async {
        final w = await _pump(tester);
        await _open(tester, w, _school1);
        await _tap(tester, 'feature-admission');
        expect(
          find.textContaining(
            'also switches off: Public admission enquiry page',
          ),
          findsOneWidget,
        );
        await reason(tester, 'Not part of this plan');
        await confirmReason(tester);
        expect(w.ops.featureCalls.single.features, {'admission': false});
        expect(w.ops.featureArgs.single.confirm, isTrue);
      },
    );

    testWidgets('switching on needs no reason and is sent straight away', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(features: {'homework': false}),
        ),
      );
      await _open(tester, w, _school1);
      await _tap(tester, 'feature-homework');
      expect(w.ops.featureCalls.single.features, {'homework': true});
      expect(w.ops.featureArgs.single, (reason: null, confirm: false));
    });

    testWidgets(
      'a module whose dependency is off is shown off, cannot be switched on, and says why',
      (tester) async {
        final w = await _pump(
          tester,
          console: FakePlatformConsoleRepository(
            overview: overviewWith(features: {'fees': false}),
          ),
        );
        await _open(tester, w, _school1);
        final reminders = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('feature-feeReminders')),
        );
        expect(reminders.value, isFalse);
        expect(reminders.onChanged, isNull);
        expect(
          find.byKey(const ValueKey('feature-needs-feeReminders')),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Needs Fees, invoices and payments switched on first.',
          ),
          findsOneWidget,
        );
        expect(w.ops.featureCalls, isEmpty);
      },
    );

    testWidgets('the current state is shown; a missing switch means on', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(features: {'homework': false}),
        ),
      );
      await _open(tester, w, _school1);
      bool on(String k) => tester
          .widget<SwitchListTile>(find.byKey(ValueKey('feature-$k')))
          .value;
      expect(on('admission'), isTrue);
      expect(on('homework'), isFalse);
    });

    testWidgets('the whole catalogue is listed, and only real modules', (
      tester,
    ) async {
      final w = await _pump(tester, size: const Size(1000, 6000));
      await _open(tester, w, _school1);
      for (final f in kFeatureCatalogue) {
        expect(
          find.byKey(ValueKey('feature-${f.key}')),
          findsOneWidget,
          reason: f.key,
        );
      }
      for (final absent in ['transport', 'library', 'payments']) {
        expect(
          find.byKey(ValueKey('feature-$absent')),
          findsNothing,
          reason: absent,
        );
      }
    });

    for (final role in [
      PlatformRole.support,
      PlatformRole.viewer,
      PlatformRole.compliance,
    ]) {
      testWidgets('${role.name} sees the switches but cannot flip them', (
        tester,
      ) async {
        final w = await _pump(tester, role: role);
        await _open(tester, w, _school1);
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('feature-admission')),
              )
              .onChanged,
          isNull,
        );
        expect(
          find.text('Only a platform owner can change modules.'),
          findsOneWidget,
        );
      });
    }

    testWidgets('a server refusal is shown in plain words', (tester) async {
      final ops = FakePlatformOpsRepository(stats: fakeStats());
      final w = await _pump(tester, ops: ops);
      await _open(tester, w, _school1);
      ops.error = const ValidationFailure(
        'Switch on the modules this one needs first.',
      );
      await _tap(tester, 'feature-homework');
      await reason(tester, 'Not part of this plan');
      await confirmReason(tester);
      expect(
        find.text('Switch on the modules this one needs first.'),
        findsOneWidget,
      );
      expect(w.ops.featureCalls, isEmpty);
    });

    testWidgets(
      'history lists each change with its reason and whether it followed a dependency',
      (tester) async {
        final ops = FakePlatformOpsRepository(stats: fakeStats())
          ..featureHist = [
            FeatureHistoryEntry.fromMap({
              'id': 'f1',
              'feature': 'feeReminders',
              'from': true,
              'to': false,
              'cascade': true,
              'actorEmail': 'o@avail404.com',
              'atMs': 1700000000000,
              'reason': 'Fees billed elsewhere',
            }),
            FeatureHistoryEntry.fromMap({
              'id': 'f2',
              'feature': 'fees',
              'from': true,
              'to': false,
              'actorEmail': 'o@avail404.com',
              'atMs': 1700000000000,
              'reason': 'Fees billed elsewhere',
            }),
          ];
        final w = await _pump(tester, ops: ops);
        await _open(tester, w, _school1);
        expect(
          find.byKey(const ValueKey('feature-history-f1')),
          findsNothing,
          reason: 'collapsed until asked',
        );
        await _tap(tester, 'features-history-toggle');
        expect(
          find.textContaining(
            'Fee reminders off (with a module it depends on)',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Fees, invoices and payments off · o@avail404.com · Fees billed elsewhere',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('default modules for new schools', () {
    testWidgets(
      'an owner edits them; switching a module off takes its dependants with it',
      (tester) async {
        final ops = FakePlatformOpsRepository(stats: fakeStats())
          ..defaultsMap = {for (final f in kFeatureCatalogue) f.key: true};
        final w = await _pump(tester, ops: ops);
        await _open(tester, w, AppRoutes.platformSchools);
        await tester.tap(find.byKey(const ValueKey('schools-defaults')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('default-fees')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('default-feeReminders')),
              )
              .value,
          isFalse,
        );
        await tester.tap(find.byKey(const ValueKey('defaults-save')));
        await tester.pumpAndSettle();
        final saved = w.ops.defaultsSaved.single;
        expect(
          (saved['fees'], saved['feeReminders'], saved['exams']),
          (false, false, true),
        );
      },
    );

    for (final role in [PlatformRole.support, PlatformRole.viewer]) {
      testWidgets('${role.name} does not see the defaults button', (
        tester,
      ) async {
        final w = await _pump(tester, role: role);
        await _open(tester, w, AppRoutes.platformSchools);
        expect(find.byKey(const ValueKey('schools-defaults')), findsNothing);
      });
    }
  });

  group('billing', () {
    testWidgets('the school page shows what is owed and the records', (
      tester,
    ) async {
      final ops = FakePlatformOpsRepository(
        stats: fakeStats(),
        summary: BillingSummary(
          records: [
            fakeBill(),
            fakeBill(
              id: 'b2',
              due: '2020-01-01',
              period: 'Old one',
              amount: 500000,
            ),
          ],
          owed: const {'INR': (dueMinor: 2000000, overdueMinor: 500000)},
        ),
      );
      final w = await _pump(tester, ops: ops);
      await _open(tester, w, _school1);
      expect(find.textContaining('Owed ₹20,000.00'), findsOneWidget);
      expect(find.textContaining('overdue ₹5,000.00'), findsOneWidget);
      expect(find.text('Nov 2026'), findsOneWidget);
    });

    testWidgets(
      'adding a record validates the amount and saves it in minor units',
      (tester) async {
        final w = await _pump(tester);
        await _open(tester, w, _school1);
        await _tap(tester, 'billing-add');
        await tester.enterText(
          find.byKey(const ValueKey('bill-period')),
          'Nov 2026',
        );
        await tester.enterText(find.byKey(const ValueKey('bill-amount')), '0');
        await tester.tap(find.byKey(const ValueKey('bill-save')));
        await tester.pumpAndSettle();
        expect(w.ops.billSaved, isEmpty);
        await tester.enterText(
          find.byKey(const ValueKey('bill-amount')),
          '15000.50',
        );
        await tester.tap(find.byKey(const ValueKey('bill-save')));
        await tester.pumpAndSettle();
        final s = w.ops.billSaved.single;
        expect(
          (s.schoolId, s.period, s.amountMinor, s.currency),
          ('school-1', 'Nov 2026', 1500050, 'INR'),
        );
      },
    );

    testWidgets('waiving and voiding ask first and say it is final', (
      tester,
    ) async {
      final ops = FakePlatformOpsRepository(
        stats: fakeStats(),
        summary: BillingSummary(
          records: [fakeBill()],
          owed: const {'INR': (dueMinor: 1500000, overdueMinor: 0)},
        ),
      );
      final w = await _pump(tester, ops: ops);
      await _open(tester, w, _school1);
      await _tap(tester, 'bill-menu-b1');
      await tester.tap(find.text('Waive').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('cannot be changed afterwards'),
        findsOneWidget,
      );
      expect(w.ops.billSet, isEmpty);
      await tester.tap(find.byKey(const ValueKey('confirm-yes')));
      await tester.pumpAndSettle();
      expect(w.ops.billSet.single.status, 'WAIVED');
    });

    testWidgets('a settled record has no actions', (tester) async {
      final ops = FakePlatformOpsRepository(
        stats: fakeStats(),
        summary: BillingSummary(
          records: [fakeBill(status: 'PAID')],
          owed: const {},
        ),
      );
      final w = await _pump(tester, ops: ops);
      await _open(tester, w, _school1);
      expect(find.byKey(const ValueKey('bill-menu-b1')), findsNothing);
      expect(find.text('Nothing is owed.'), findsOneWidget);
    });

    testWidgets(
      'billing is for owners only, on the school page and on its own page',
      (tester) async {
        final w = await _pump(tester, role: PlatformRole.support);
        await _open(tester, w, _school1);
        expect(find.byKey(const ValueKey('billing-add')), findsNothing);
        await _open(tester, w, AppRoutes.platformBilling);
        expect(
          find.text('Only a platform owner can see billing.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the billing page totals what is owed and filters by state', (
      tester,
    ) async {
      final ops = FakePlatformOpsRepository(
        stats: fakeStats(),
        summary: BillingSummary(
          records: [
            fakeBill(),
            fakeBill(id: 'b2', status: 'PAID', period: 'Done one'),
          ],
          owed: const {
            'INR': (dueMinor: 1500000, overdueMinor: 0),
            'USD': (dueMinor: 20000, overdueMinor: 0),
          },
        ),
      );
      final w = await _pump(tester, ops: ops);
      await _open(tester, w, AppRoutes.platformBilling);
      expect(find.byKey(const ValueKey('owed-INR')), findsOneWidget);
      expect(find.byKey(const ValueKey('owed-USD')), findsOneWidget);
      expect(find.textContaining('Nov 2026'), findsOneWidget);
      expect(find.textContaining('Done one'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('billing-filter-PAID')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Done one'), findsOneWidget);
    });
  });

  group('offboarding', () {
    testWidgets('an owner starts it with a real reason after a warning', (
      tester,
    ) async {
      final w = await _pump(tester);
      await _open(tester, w, _school1);
      await _tap(tester, 'off-request');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('second owner must approve'),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('reason-field')),
        'too short',
      );
      await tester.tap(find.byKey(const ValueKey('reason-confirm')));
      await tester.pumpAndSettle();
      expect(w.ops.offboardCalls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('reason-field')),
        'Contract ended, the school asked to leave',
      );
      await tester.tap(find.byKey(const ValueKey('reason-confirm')));
      await tester.pumpAndSettle();
      expect(w.ops.offboardCalls.single, startsWith('request:Contract ended'));
    });

    Map<String, dynamic> off({
      String by = 'someone-else',
      String state = 'REQUESTED',
    }) => {
      'state': state,
      'reason': 'Contract ended',
      'requestedBy': by,
      'requestedByEmail': 'ben@avail404.com',
      'graceUntilMs': DateTime(2026, 12, 13).millisecondsSinceEpoch,
    };

    testWidgets('a DIFFERENT owner can approve; the one who asked cannot', (
      tester,
    ) async {
      var w = await _pump(
        tester,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(status: 'SUSPENDED', offboarding: off()),
        ),
      );
      await _open(tester, w, _school1);
      expect(
        find.textContaining('requested by ben@avail404.com'),
        findsOneWidget,
      );
      await _tap(tester, 'off-approve');
      expect(w.ops.offboardCalls, ['approve']);
    });

    testWidgets('the requester is told to wait for another owner', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(
            status: 'SUSPENDED',
            offboarding: off(by: _uid),
          ),
        ),
      );
      await _open(tester, w, _school1);
      expect(find.byKey(const ValueKey('off-approve')), findsNothing);
      expect(
        find.text('Waiting for a different owner to approve.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('off-cancel')), findsOneWidget);
    });

    testWidgets('it can be cancelled, and nothing says it deletes anything', (
      tester,
    ) async {
      final w = await _pump(
        tester,
        console: FakePlatformConsoleRepository(
          overview: overviewWith(
            status: 'SUSPENDED',
            offboarding: off(state: 'APPROVED'),
          ),
        ),
      );
      await _open(tester, w, _school1);
      expect(find.text('Offboarding approved.'), findsOneWidget);
      await _tap(tester, 'off-cancel');
      expect(w.ops.offboardCalls, ['cancel']);
    });
  });

  group('create a school', () {
    testWidgets(
      'an owner creates one; the administrator is emailed and the new school opens',
      (tester) async {
        final w = await _pump(
          tester,
          console: FakePlatformConsoleRepository(
            schools: [fakeSchool()],
            overview: overviewWith(),
          ),
        );
        await _open(tester, w, AppRoutes.platformSchools);
        await _tap(tester, 'schools-create');
        await tester.enterText(
          find.byKey(const ValueKey('cs-school')),
          'New Horizon School',
        );
        await tester.enterText(
          find.byKey(const ValueKey('cs-admin')),
          'Asha Rao',
        );
        await tester.enterText(
          find.byKey(const ValueKey('cs-email')),
          'Asha@Horizon.example',
        );
        await tester.tap(find.byKey(const ValueKey('cs-create')));
        await tester.pumpAndSettle();
        final c = w.ops.created.single;
        expect(
          (c.schoolName, c.countryCode, c.currency, c.timezone, c.dateFormat),
          ('New Horizon School', 'IN', 'INR', 'Asia/Kolkata', 'dd/MM/yyyy'),
        );
        expect(c.toCallable()['regional'], {
          'countryCode': 'IN',
          'currency': 'INR',
          'timezone': 'Asia/Kolkata',
          'dateFormat': 'dd/MM/yyyy',
        });
        expect(w.auth.sent, ['asha@horizon.example']);
        expect(w.location, _school1);
      },
    );

    testWidgets('the form validates before anything is created', (
      tester,
    ) async {
      final w = await _pump(tester);
      await _open(tester, w, AppRoutes.platformSchools);
      await _tap(tester, 'schools-create');
      await tester.tap(find.byKey(const ValueKey('cs-create')));
      await tester.pumpAndSettle();
      expect(find.text('Enter the school name'), findsOneWidget);
      expect(find.text('Enter their name'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(w.ops.created, isEmpty);
    });

    testWidgets('the country sets currency and date format', (tester) async {
      final w = await _pump(tester);
      await _open(tester, w, AppRoutes.platformSchools);
      await _tap(tester, 'schools-create');
      await tester.tap(find.byKey(const ValueKey('cs-country')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('United States').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('cs-school')),
        'Lincoln Prep',
      );
      await tester.enterText(find.byKey(const ValueKey('cs-admin')), 'Sam Lee');
      await tester.enterText(
        find.byKey(const ValueKey('cs-email')),
        'sam@lincoln.example',
      );
      await tester.tap(find.byKey(const ValueKey('cs-create')));
      await tester.pumpAndSettle();
      final c = w.ops.created.single;
      expect(
        (c.countryCode, c.currency, c.dateFormat),
        ('US', 'USD', 'MM/dd/yyyy'),
      );
    });

    testWidgets('a server refusal stays in the dialog', (tester) async {
      final ops = FakePlatformOpsRepository(stats: fakeStats())
        ..error = const ConflictFailure(
          'An account with this email address already exists.',
        );
      final w = await _pump(tester, ops: ops);
      await _open(tester, w, AppRoutes.platformSchools);
      await _tap(tester, 'schools-create');
      await tester.enterText(
        find.byKey(const ValueKey('cs-school')),
        'New Horizon School',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cs-admin')),
        'Asha Rao',
      );
      await tester.enterText(
        find.byKey(const ValueKey('cs-email')),
        'asha@horizon.example',
      );
      await tester.tap(find.byKey(const ValueKey('cs-create')));
      await tester.pumpAndSettle();
      expect(
        find.text('An account with this email address already exists.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('cs-create')), findsOneWidget);
    });

    testWidgets('only owners are offered it', (tester) async {
      final w = await _pump(tester, role: PlatformRole.support);
      await _open(tester, w, AppRoutes.platformSchools);
      expect(find.byKey(const ValueKey('schools-create')), findsNothing);
    });
  });

  group('platform dashboard', () {
    testWidgets('shows schools, people and activity', (tester) async {
      await _pump(tester);
      expect(find.text('Platform overview'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.textContaining('9 active · 2 suspended'), findsOneWidget);
      expect(find.text('4200'), findsOneWidget);
      expect(find.text('600'), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-stale')), findsNothing);
    });

    testWidgets(
      'warns when the nightly job has not run for over a day and a half',
      (tester) async {
        final ops = FakePlatformOpsRepository(
          stats: fakeStats(
            computedAt: DateTime.now().subtract(const Duration(hours: 40)),
          ),
        );
        await _pump(tester, ops: ops);
        expect(find.byKey(const ValueKey('stats-stale')), findsOneWidget);
      },
    );

    testWidgets(
      '"needs attention" lists only what is waiting and is limited by role',
      (tester) async {
        final ops = FakePlatformOpsRepository(
          stats: fakeStats(deletions: 2, grants: 1, offboarding: 1, overdue: 3),
        );
        await _pump(tester, ops: ops);
        expect(
          find.text('2 deletion requests waiting for review'),
          findsOneWidget,
        );
        expect(find.text('1 support sessions open right now'), findsOneWidget);
        expect(find.text('1 schools being offboarded'), findsOneWidget);
        expect(find.text('3 bills past their due date'), findsOneWidget);
      },
    );

    testWidgets('support never sees deletion or billing items', (tester) async {
      final ops = FakePlatformOpsRepository(
        stats: fakeStats(deletions: 2, grants: 1, offboarding: 1, overdue: 3),
      );
      await _pump(tester, role: PlatformRole.support, ops: ops);
      expect(find.textContaining('deletion requests'), findsNothing);
      expect(find.textContaining('bills past'), findsNothing);
      expect(find.text('1 support sessions open right now'), findsOneWidget);
    });

    testWidgets('nothing waiting says so', (tester) async {
      await _pump(tester);
      expect(find.byKey(const ValueKey('attention-none')), findsOneWidget);
    });

    testWidgets('before the first run an owner can compute the numbers now', (
      tester,
    ) async {
      final ops = FakePlatformOpsRepository();
      final w = await _pump(tester, ops: ops);
      expect(find.byKey(const ValueKey('stats-empty')), findsOneWidget);
      await _tap(tester, 'stats-refresh');
      expect(w.ops.calls, ['refreshStats']);
    });

    testWidgets('a viewer cannot recompute', (tester) async {
      await _pump(tester, role: PlatformRole.viewer);
      expect(find.byKey(const ValueKey('stats-refresh')), findsNothing);
    });

    testWidgets('a throttled refresh says it is already up to date', (
      tester,
    ) async {
      final ops = FakePlatformOpsRepository(stats: fakeStats())
        ..refreshFresh = false;
      await _pump(tester, ops: ops);
      await tester.tap(find.byKey(const ValueKey('stats-refresh')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Already up to date'), findsOneWidget);
    });
  });

  group('notices to schools', () {
    testWidgets('lists notices with their state', (tester) async {
      final ops = FakePlatformOpsRepository(
        stats: fakeStats(),
        noticeList: [
          fakePlatformNotice(),
          fakePlatformNotice(
            id: 'n2',
            title: 'Old news',
            live: false,
            status: 'WITHDRAWN',
          ),
        ],
      );
      final w = await _pump(tester, ops: ops);
      await _open(tester, w, AppRoutes.platformNotices);
      expect(find.text('Planned maintenance'), findsOneWidget);
      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Withdrawn'), findsOneWidget);
    });

    testWidgets('publishing validates, then sends to everyone', (tester) async {
      final w = await _pump(tester);
      await _open(tester, w, AppRoutes.platformNotices);
      await _tap(tester, 'notice-new');
      await tester.tap(find.byKey(const ValueKey('nt-publish')));
      await tester.pumpAndSettle();
      expect(find.text('Write a title'), findsOneWidget);
      expect(w.ops.published, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('nt-title')),
        'Holiday hours',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nt-body')),
        'Support is closed on Friday.',
      );
      await tester.tap(find.byKey(const ValueKey('nt-publish')));
      await tester.pumpAndSettle();
      final p = w.ops.published.single;
      expect(
        (p.title, p.all, p.severity),
        ('Holiday hours', true, NoticeSeverity.info),
      );
      expect(p.schools, isEmpty);
    });

    testWidgets('choosing named schools requires picking at least one', (
      tester,
    ) async {
      final w = await _pump(tester);
      await _open(tester, w, AppRoutes.platformNotices);
      await _tap(tester, 'notice-new');
      await tester.enterText(
        find.byKey(const ValueKey('nt-title')),
        'Just for you',
      );
      await tester.enterText(
        find.byKey(const ValueKey('nt-body')),
        'A private message here.',
      );
      await tester.tap(find.byKey(const ValueKey('nt-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nt-publish')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Choose at least one school'), findsOneWidget);
      expect(w.ops.published, isEmpty);
      await tester.tap(find.text('Rosewood High'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nt-publish')));
      await tester.pumpAndSettle();
      expect(w.ops.published.single.schools, ['school-1']);
      expect(w.ops.published.single.all, isFalse);
    });

    testWidgets('withdrawing asks first', (tester) async {
      final ops = FakePlatformOpsRepository(
        stats: fakeStats(),
        noticeList: [fakePlatformNotice()],
      );
      final w = await _pump(tester, ops: ops);
      await _open(tester, w, AppRoutes.platformNotices);
      await _tap(tester, 'withdraw-n1');
      expect(w.ops.withdrawn, isEmpty);
      await tester.tap(find.byKey(const ValueKey('confirm-yes')));
      await tester.pumpAndSettle();
      expect(w.ops.withdrawn, ['n1']);
    });

    testWidgets('compliance and viewers can read but not publish', (
      tester,
    ) async {
      final ops = FakePlatformOpsRepository(
        stats: fakeStats(),
        noticeList: [fakePlatformNotice()],
      );
      final w = await _pump(tester, role: PlatformRole.compliance, ops: ops);
      await _open(tester, w, AppRoutes.platformNotices);
      expect(find.text('Planned maintenance'), findsOneWidget);
      expect(find.byKey(const ValueKey('notice-new')), findsNothing);
      expect(find.byKey(const ValueKey('withdraw-n1')), findsNothing);
    });
  });

  group('app availability', () {
    testWidgets('owners only', (tester) async {
      final w = await _pump(tester, role: PlatformRole.support);
      await _open(tester, w, AppRoutes.platformAvailability);
      expect(
        find.text('Only a platform owner can change this.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'maintenance needs a message; saving sends the builds and an end time',
      (tester) async {
        final w = await _pump(tester);
        await _open(tester, w, AppRoutes.platformAvailability);
        await _tap(tester, 'av-maintenance');
        await tester.tap(find.byKey(const ValueKey('av-save')));
        await tester.pumpAndSettle();
        expect(find.text('Write the message'), findsOneWidget);
        expect(w.ops.requirementCalls, isEmpty);
        await tester.enterText(
          find.byKey(const ValueKey('av-message')),
          'Back at 6am',
        );
        await tester.enterText(find.byKey(const ValueKey('av-android')), '14');
        await tester.tap(find.byKey(const ValueKey('av-save')));
        await tester.pumpAndSettle();
        final c = w.ops.requirementCalls.single;
        expect(
          (c.android, c.ios, c.on, c.message),
          (14, 0, true, 'Back at 6am'),
        );
        expect(c.until, isNotNull);
        expect(c.until!.isAfter(DateTime.now()), isTrue);
      },
    );

    testWidgets('a build number must be a whole number', (tester) async {
      final w = await _pump(tester);
      await _open(tester, w, AppRoutes.platformAvailability);
      await tester.enterText(find.byKey(const ValueKey('av-android')), 'abc');
      await tester.tap(find.byKey(const ValueKey('av-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('whole number'), findsOneWidget);
      expect(w.ops.requirementCalls, isEmpty);
    });
  });

  group('layout', () {
    for (final size in const [
      Size(360, 640),
      Size(768, 1024),
      Size(1400, 900),
    ]) {
      for (final scale in const [1.0, 1.5]) {
        testWidgets('lifecycle screens fit at $size, text x$scale', (
          tester,
        ) async {
          final ops = FakePlatformOpsRepository(
            stats: fakeStats(
              deletions: 2,
              grants: 1,
              offboarding: 1,
              overdue: 3,
            ),
            summary: BillingSummary(
              records: [
                fakeBill(),
                fakeBill(
                  id: 'b2',
                  period: 'A very long billing period name to test wrapping',
                ),
              ],
              owed: const {'INR': (dueMinor: 2000000, overdueMinor: 500000)},
            ),
            noticeList: [
              fakePlatformNotice(
                title:
                    'A rather long notice title that must wrap nicely on a phone',
              ),
            ],
          );
          final w = await _pump(
            tester,
            ops: ops,
            console: FakePlatformConsoleRepository(
              overview: overviewWith(
                status: 'SUSPENDED',
                reason: 'A long reason for the suspension of this school',
                offboarding: {
                  'state': 'REQUESTED',
                  'reason': 'Contract ended',
                  'requestedBy': 'x',
                  'requestedByEmail': 'ben@avail404.com',
                  'graceUntilMs': 1,
                },
                subscription: {
                  'planName':
                      'An extremely long plan name for the annual school subscription',
                  'classification': 'PAID',
                  'startDate': '2026-04-01',
                  'endDate': '2027-03-31',
                  'gracePeriodDays': 7,
                  'status': 'GRACE_PERIOD',
                  'remarks':
                      'A long remark that should wrap across several lines on a phone',
                  'internalNotes':
                      'A long internal note that should also wrap on a phone screen',
                },
              ),
              schools: [
                fakeSchool(name: 'A School With A Very Long Name Academy'),
              ],
            ),
            size: size,
            textScale: scale,
          );
          expect(tester.takeException(), isNull, reason: 'home');
          await _open(tester, w, _school1);
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('sub-history-toggle')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.byKey(const ValueKey('sub-history-toggle')));
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('sub-change')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.ensureVisible(find.byKey(const ValueKey('sub-change')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('sub-change')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('sub-save')), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'subscription dialog');
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          for (final p in [
            _school1,
            AppRoutes.platformSchools,
            AppRoutes.platformBilling,
            AppRoutes.platformNotices,
            AppRoutes.platformAvailability,
          ]) {
            await _open(tester, w, p);
            expect(tester.takeException(), isNull, reason: p);
          }
        });
      }
    }
  });
}

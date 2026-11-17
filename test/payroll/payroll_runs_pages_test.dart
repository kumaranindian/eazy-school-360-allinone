import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll.dart';
import 'package:eazy_school_360/features/expenses/domain/expense.dart'
    show PaymentMode;
import 'package:eazy_school_360/features/payroll/domain/payroll_preview.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_run.dart';
import 'package:eazy_school_360/features/payroll/presentation/payroll_routes.dart';
import 'package:eazy_school_360/features/payroll/presentation/providers/payroll_providers.dart';
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
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/fakes.dart';
import '../support/payroll_fakes.dart';

const _uid = 'u1';

Future<GoRouter> _pump(
  WidgetTester tester,
  FakePayrollRepository repo, {
  UserRole role = UserRole.finance,
  String start = '/payroll',
  Size size = const Size(900, 1600),
  double textScale = 1,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: start, routes: payrollRoutes());
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        envConfigProvider.overrideWithValue(
          EnvConfig.forEnvironment(AppEnvironment.test),
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            signedInAs: const AppUser(uid: _uid, email: 'u@example.com'),
          ),
        ),
        userRepositoryProvider.overrideWithValue(
          FakeUserRepository({
            _uid: UserProfile(
              userId: _uid,
              schoolId: 'school-1',
              branchId: 'main',
              name: 'Grace Hopper',
              email: 'u@example.com',
              role: role,
              status: UserStatus.active,
            ),
          }),
        ),
        schoolRepositoryProvider.overrideWithValue(
          FakeSchoolRepository(
            schools: {
              'school-1': const School(
                schoolId: 'school-1',
                name: 'Rosewood High',
                email: 'office@rosewood.example',
                status: SchoolStatus.active,
              ),
            },
            branches: {
              'school-1/main': const Branch(
                branchId: 'main',
                schoolId: 'school-1',
                name: 'Main',
                status: BranchStatus.active,
              ),
            },
          ),
        ),
        payrollRepositoryProvider.overrideWithValue(repo),
        ...extra,
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

PayrollRun _run(
  RunStatus status, {
  String period = '2026-11',
  int warnings = 0,
  int skipped = 0,
  int net = 6300000,
  int payslips = 2,
  int version = 2,
}) => PayrollRun(
  period: period,
  status: status,
  version: version,
  currency: 'INR',
  payslipCount: payslips,
  skippedCount: skipped,
  warningCount: warnings,
  grossMinor: net,
  netMinor: net,
  workingDays: 21,
  approvedByName: status == RunStatus.approved || status == RunStatus.paid
      ? 'Omar Owner'
      : null,
  paidDate: status == RunStatus.paid ? '2026-11-30' : null,
  paymentMode: status == RunStatus.paid ? 'BANK_TRANSFER' : null,
  paymentReference: status == RunStatus.paid ? 'NEFT-991' : null,
  cancelReason: status == RunStatus.cancelled ? 'Wrong data used' : null,
);

PayslipRow _slipRow(
  String id,
  String name,
  int net, {
  int adj = 0,
  int warn = 0,
}) => PayslipRow(
  staffId: id,
  name: name,
  employeeCode: 'E$id',
  paidDays: 21,
  unpaidDays: 0,
  workingDays: 21,
  grossMinor: net,
  deductionsMinor: 0,
  netMinor: net,
  warningCount: warn,
  adjustmentCount: adj,
);

FakePayrollRepository _repoWith(PayrollRun run) => FakePayrollRepository()
  ..runItems.add(run)
  ..runSlips[run.period] = [
    _slipRow('st1', 'Asha Rao', 2100000, adj: 1, warn: 1),
    _slipRow('st2', 'Bala Iyer', 4200000),
  ]
  ..slipDetails['st1'] = const Payslip(
    row: PayslipRow(
      staffId: 'st1',
      name: 'Asha Rao',
      employeeCode: 'E1',
      paidDays: 21,
      unpaidDays: 0,
      workingDays: 21,
      grossMinor: 2600000,
      deductionsMinor: 0,
      netMinor: 2600000,
      warningCount: 1,
      adjustmentCount: 1,
    ),
    currency: 'INR',
    lines: [
      PayLineSnapshot(
        name: 'Basic salary',
        kind: PayKind.earning,
        plannedMinor: 2100000,
        amountMinor: 2100000,
      ),
    ],
    adjustments: [
      PayAdjustment(
        id: 'a1',
        kind: PayKind.earning,
        label: 'Diwali bonus',
        amountMinor: 500000,
        reason: 'Festival bonus agreed',
      ),
    ],
    warnings: ['Attendance was not marked on 2026-11-02.'],
    baseGrossMinor: 2100000,
    unrecoveredDeductionMinor: 0,
  );

void main() {
  group('which buttons a run offers (mirrors the server)', () {
    PayrollRunDetail d(
      RunStatus s, {
      bool prep = true,
      bool app = true,
      bool pay = true,
      int slips = 2,
    }) => PayrollRunDetail(
      run: _run(s, payslips: slips),
      payslips: const [],
      skipped: 0,
      canPrepare: prep,
      canApprove: app,
      canPay: pay,
      allowSelfApproval: false,
    );

    test('calculated: recalculate, adjust, approve, cancel; not pay', () {
      final x = d(RunStatus.calculated);
      expect(RunActions.canRecalculate(x), isTrue);
      expect(RunActions.canAdjust(x), isTrue);
      expect(RunActions.canApprove(x), isTrue);
      expect(RunActions.canCancel(x), isTrue);
      expect(RunActions.canPay(x), isFalse);
    });

    test('finance prepares and pays but never approves', () {
      final fin = d(RunStatus.calculated, app: false);
      expect(RunActions.canApprove(fin), isFalse);
      expect(RunActions.canRecalculate(fin), isTrue);
      expect(RunActions.canPay(d(RunStatus.approved, app: false)), isTrue);
      expect(RunActions.canCancel(d(RunStatus.approved, app: false)), isFalse);
    });

    test('approved: pay and cancel only; frozen', () {
      final x = d(RunStatus.approved);
      expect(RunActions.canPay(x), isTrue);
      expect(RunActions.canCancel(x), isTrue);
      expect(RunActions.canAdjust(x), isFalse);
      expect(RunActions.canRecalculate(x), isFalse);
      expect(RunActions.canApprove(x), isFalse);
    });

    test('paid, cancelled: nothing', () {
      for (final s in [RunStatus.paid, RunStatus.cancelled]) {
        final x = d(s);
        expect(
          [
            RunActions.canApprove(x),
            RunActions.canPay(x),
            RunActions.canAdjust(x),
            RunActions.canRecalculate(x),
            RunActions.canCancel(x),
          ],
          everyElement(isFalse),
          reason: '$s',
        );
      }
    });

    test('an empty run cannot be approved', () {
      expect(RunActions.canApprove(d(RunStatus.calculated, slips: 0)), isFalse);
    });

    test('a person with no rights gets nothing', () {
      final x = d(RunStatus.calculated, prep: false, app: false, pay: false);
      expect(RunActions.canApprove(x), isFalse);
      expect(RunActions.canRecalculate(x), isFalse);
      expect(RunActions.canAdjust(x), isFalse);
      expect(RunActions.canCancel(x), isFalse);
    });
  });

  test('history labels and review flag', () {
    expect(
      const RunHistoryEntry(seq: 1, action: 'create', to: 'CALCULATED').label,
      'Created and calculated',
    );
    expect(
      const RunHistoryEntry(seq: 2, action: 'adjust').label,
      'Adjustment added',
    );
    expect(_run(RunStatus.calculated, warnings: 1).needsReview, isTrue);
    expect(_run(RunStatus.calculated, skipped: 1).needsReview, isTrue);
    expect(_run(RunStatus.calculated).needsReview, isFalse);
  });

  group('the runs list', () {
    testWidgets('lists runs with status, count and net; opens one', (
      tester,
    ) async {
      final repo = FakePayrollRepository()
        ..runItems.addAll([
          _run(RunStatus.paid, period: '2026-10'),
          _run(RunStatus.calculated, warnings: 2),
        ]);
      final router = await _pump(tester, repo, start: '/payroll/runs');
      expect(find.text('November 2026'), findsOneWidget);
      expect(
        find.textContaining('Calculated · 2 payslips · to check'),
        findsOneWidget,
      );
      expect(find.textContaining('Paid · 2 payslips'), findsOneWidget);
      expect(find.text('₹63,000.00'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('run-2026-11')));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/payroll/runs/2026-11',
      );
    });

    testWidgets('an empty list says so; starting a month creates the run', (
      tester,
    ) async {
      final repo = FakePayrollRepository();
      final router = await _pump(tester, repo, start: '/payroll/runs');
      expect(find.text('No payroll runs yet.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('run-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-create')));
      await tester.pumpAndSettle();
      expect(repo.runCalls, ['createRun']);
      final p = repo.runArgs.single['period'] as String;
      expect(p, hasLength(7));
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/payroll/runs/$p',
      );
    });

    testWidgets('someone who cannot prepare has no start button', (
      tester,
    ) async {
      final repo = FakePayrollRepository()..canPrepare = false;
      await _pump(tester, repo, start: '/payroll/runs');
      expect(find.byKey(const ValueKey('run-new')), findsNothing);
    });

    testWidgets('a month that already has a live run is not offered again', (
      tester,
    ) async {
      final now = DateTime.now();
      final cur = recentPeriods(now.year, now.month).first;
      final repo = FakePayrollRepository()
        ..runItems.add(_run(RunStatus.calculated, period: cur));
      await _pump(tester, repo, start: '/payroll/runs');
      await tester.tap(find.byKey(const ValueKey('run-new')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-period')));
      await tester.pumpAndSettle();
      expect(
        find.text(periodLabel(cur)),
        findsOneWidget,
        reason: 'only in the list behind',
      );
    });

    testWidgets('a refusal is shown', (tester) async {
      final repo = FakePayrollRepository()
        ..failWith = const PermissionFailure('You do not have permission.');
      await _pump(tester, repo, start: '/payroll/runs');
      expect(find.textContaining('permission'), findsWidgets);
    });
  });

  group('one run', () {
    testWidgets('shows totals, status, the review box and every payslip', (
      tester,
    ) async {
      final repo = _repoWith(
        _run(RunStatus.calculated, warnings: 3, skipped: 1),
      );
      await _pump(
        tester,
        repo,
        start: '/payroll/runs/2026-11',
        role: UserRole.schoolAdmin,
      );
      expect(find.text('Calculated'), findsOneWidget);
      expect(find.text('Net pay ₹63,000.00'), findsOneWidget);
      expect(find.byKey(const ValueKey('run-review')), findsOneWidget);
      expect(find.textContaining('3 things to check'), findsOneWidget);
      expect(
        find.textContaining('1 staff have no salary structure'),
        findsOneWidget,
      );
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.textContaining('1 adjustment · 1 to check'), findsOneWidget);
      expect(find.byKey(const ValueKey('run-approve')), findsOneWidget);
      expect(find.byKey(const ValueKey('run-recalculate')), findsOneWidget);
      expect(find.byKey(const ValueKey('run-pay')), findsNothing);
    });

    testWidgets('finance sees recalculate and no approve, and why', (
      tester,
    ) async {
      final repo = _repoWith(_run(RunStatus.calculated))..canApprove = false;
      await _pump(tester, repo, start: '/payroll/runs/2026-11');
      expect(find.byKey(const ValueKey('run-approve')), findsNothing);
      expect(find.byKey(const ValueKey('run-recalculate')), findsOneWidget);
    });

    testWidgets('approving a run with things to check needs the box ticked', (
      tester,
    ) async {
      final repo = _repoWith(_run(RunStatus.calculated, warnings: 2));
      await _pump(
        tester,
        repo,
        start: '/payroll/runs/2026-11',
        role: UserRole.schoolAdmin,
      );
      await tester.tap(find.byKey(const ValueKey('run-approve')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('run-approve-confirm')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('run-reviewed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-approve-confirm')));
      await tester.pumpAndSettle();
      expect(repo.runCalls, ['approve']);
      expect(repo.runArgs.single['ack'], isTrue);
      expect(repo.runArgs.single['baseVersion'], 2);
    });

    testWidgets('a clean run is approved without the box', (tester) async {
      final repo = _repoWith(_run(RunStatus.calculated));
      await _pump(
        tester,
        repo,
        start: '/payroll/runs/2026-11',
        role: UserRole.schoolAdmin,
      );
      await tester.tap(find.byKey(const ValueKey('run-approve')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('run-reviewed')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('run-approve-confirm')));
      await tester.pumpAndSettle();
      expect(repo.runArgs.single['ack'], isFalse);
    });

    testWidgets('a server refusal (the preparer approving) is shown', (
      tester,
    ) async {
      final repo = _repoWith(_run(RunStatus.calculated));
      await _pump(
        tester,
        repo,
        start: '/payroll/runs/2026-11',
        role: UserRole.schoolAdmin,
      );
      repo.failWith = const PermissionFailure(
        'You prepared this run; another school administrator must approve it.',
      );
      await tester.tap(find.byKey(const ValueKey('run-approve')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('run-approve-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('another school administrator'),
        findsOneWidget,
      );
    });

    testWidgets('an approved run is paid with a mode and a reference', (
      tester,
    ) async {
      final repo = _repoWith(_run(RunStatus.approved));
      await _pump(tester, repo, start: '/payroll/runs/2026-11');
      expect(
        find.byKey(const ValueKey('run-recalculate')),
        findsNothing,
        reason: 'frozen',
      );
      expect(find.textContaining('Approved by Omar Owner'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('run-pay')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('pay-reference')),
        'NEFT-991',
      );
      await tester.tap(find.byKey(const ValueKey('pay-confirm')));
      await tester.pumpAndSettle();
      expect(repo.runCalls, ['pay']);
      expect(repo.runArgs.single['mode'], PaymentMode.bankTransfer);
      expect(repo.runArgs.single['reference'], 'NEFT-991');
    });

    testWidgets('a paid run shows how it was paid and offers nothing', (
      tester,
    ) async {
      final repo = _repoWith(_run(RunStatus.paid));
      await _pump(
        tester,
        repo,
        start: '/payroll/runs/2026-11',
        role: UserRole.schoolAdmin,
      );
      expect(
        find.textContaining('Paid 2026-11-30 · Bank transfer · NEFT-991'),
        findsOneWidget,
      );
      for (final k in [
        'run-approve',
        'run-pay',
        'run-recalculate',
        'run-cancel',
      ]) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
    });

    testWidgets('cancelling needs a reason of 10 characters', (tester) async {
      final repo = _repoWith(_run(RunStatus.calculated));
      await _pump(
        tester,
        repo,
        start: '/payroll/runs/2026-11',
        role: UserRole.schoolAdmin,
      );
      await tester.tap(find.byKey(const ValueKey('run-cancel')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reason-field')),
        'short',
      );
      await tester.tap(find.byKey(const ValueKey('reason-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 10 characters.'), findsOneWidget);
      expect(repo.runCalls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('reason-field')),
        'Wrong attendance data used',
      );
      await tester.tap(find.byKey(const ValueKey('reason-confirm')));
      await tester.pumpAndSettle();
      expect(repo.runArgs.single['reason'], 'Wrong attendance data used');
    });

    testWidgets('recalculating sends the version the screen saw', (
      tester,
    ) async {
      final repo = _repoWith(_run(RunStatus.calculated, version: 7));
      await _pump(tester, repo, start: '/payroll/runs/2026-11');
      await tester.tap(find.byKey(const ValueKey('run-recalculate')));
      await tester.pumpAndSettle();
      expect(repo.runArgs.single['baseVersion'], 7);
    });

    testWidgets('a payslip opens, adds and removes a one-off item', (
      tester,
    ) async {
      final repo = _repoWith(_run(RunStatus.calculated));
      await _pump(tester, repo, start: '/payroll/runs/2026-11');
      await tester.tap(find.byKey(const ValueKey('slip-st1')));
      await tester.pumpAndSettle();
      expect(find.text('Diwali bonus (one-off)'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('slip-net'))).data,
        '₹26,000.00',
      );
      expect(
        find.text('• Attendance was not marked on 2026-11-02.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('adj-remove-a1')));
      await tester.pumpAndSettle();
      expect(repo.runCalls, ['removeAdjustment']);
      await tester.tap(find.byKey(const ValueKey('adj-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('adj-label')),
        'Loan instalment',
      );
      await tester.enterText(find.byKey(const ValueKey('adj-amount')), '1000');
      await tester.enterText(
        find.byKey(const ValueKey('adj-reason')),
        'Salary advance recovery',
      );
      await tester.tap(find.byKey(const ValueKey('adj-save')));
      await tester.pumpAndSettle();
      final a = repo.runArgs.last;
      expect(
        [a['label'], a['amountMinor'], a['reason']],
        ['Loan instalment', 100000, 'Salary advance recovery'],
      );
    });

    testWidgets('the one-off form refuses an empty amount or a short reason', (
      tester,
    ) async {
      final repo = _repoWith(_run(RunStatus.calculated));
      await _pump(tester, repo, start: '/payroll/runs/2026-11');
      await tester.tap(find.byKey(const ValueKey('slip-st1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('adj-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('adj-label')), 'Bonus');
      await tester.tap(find.byKey(const ValueKey('adj-save')));
      await tester.pumpAndSettle();
      expect(find.text('Enter an amount above 0.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('adj-amount')), '100');
      await tester.enterText(find.byKey(const ValueKey('adj-reason')), 'short');
      await tester.tap(find.byKey(const ValueKey('adj-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Explain why (at least 10 characters).'),
        findsOneWidget,
      );
      expect(repo.runCalls, isEmpty);
    });

    testWidgets('once approved, a payslip is read-only', (tester) async {
      final repo = _repoWith(_run(RunStatus.approved));
      await _pump(tester, repo, start: '/payroll/runs/2026-11');
      await tester.tap(find.byKey(const ValueKey('slip-st1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('adj-add')), findsNothing);
      expect(find.byKey(const ValueKey('adj-remove-a1')), findsNothing);
    });

    testWidgets('history lists what happened', (tester) async {
      final repo = _repoWith(_run(RunStatus.calculated));
      await _pump(tester, repo, start: '/payroll/runs/2026-11');
      await tester.tap(find.byKey(const ValueKey('run-history')));
      await tester.pumpAndSettle();
      expect(find.text('Created and calculated'), findsOneWidget);
      expect(find.text('Fay Finance'), findsOneWidget);
    });

    for (final size in const [
      Size(360, 740),
      Size(800, 1100),
      Size(1400, 900),
    ]) {
      testWidgets('lays out at ${size.width.toInt()} wide, large text', (
        tester,
      ) async {
        final repo = _repoWith(
          _run(RunStatus.calculated, warnings: 2, skipped: 1),
        );
        await _pump(
          tester,
          repo,
          start: '/payroll/runs/2026-11',
          role: UserRole.schoolAdmin,
          size: size,
          textScale: 1.5,
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('slip-st1')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('slip-st1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('the self-approval switch is saved by a school admin', (
    tester,
  ) async {
    final repo = FakePayrollRepository();
    await _pump(
      tester,
      repo,
      start: '/payroll/preview',
      role: UserRole.schoolAdmin,
    );
    await tester.tap(find.byKey(const ValueKey('preview-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('allow-self-approval')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unmarked-save')));
    await tester.pumpAndSettle();
    expect(repo.savedSelfApproval, [true]);
  });
}

import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_preview.dart';
import 'package:eazy_school_360/features/expenses/presentation/pages/expense_reports_page.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_register.dart';
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

class _Saver implements CsvSaver {
  final List<({String name, String content})> saved = [];
  bool result = true;

  @override
  Future<bool> save(String fileName, String content) async {
    saved.add((name: fileName, content: content));
    return result;
  }
}

PayrollRegister _register() => const PayrollRegister(
  currency: 'INR',
  fromPeriod: '2026-04',
  toPeriod: '2026-11',
  rows: [
    RegisterRow(
      branchId: 'main',
      branchName: 'Main',
      period: '2026-11',
      payslipCount: 12,
      grossMinor: 6400000,
      deductionsMinor: 100000,
      netMinor: 6300000,
      paidDate: '2026-11-30',
      paymentMode: 'BANK_TRANSFER',
      expenseNumber: 'EXP-2026-00007',
    ),
    RegisterRow(
      branchId: 'main',
      branchName: 'Main',
      period: '2026-10',
      payslipCount: 12,
      grossMinor: 5200000,
      deductionsMinor: 100000,
      netMinor: 5100000,
      paidDate: '2026-10-31',
      paymentMode: 'CASH',
    ),
  ],
  runs: 2,
  payslipCount: 24,
  grossMinor: 11600000,
  deductionsMinor: 200000,
  netMinor: 11400000,
);

PayrollRun _paid({String? expense = 'EXP-2026-00007'}) => PayrollRun(
  period: '2026-11',
  status: RunStatus.paid,
  version: 5,
  currency: 'INR',
  payslipCount: 1,
  netMinor: 100,
  grossMinor: 100,
  paidDate: '2026-11-30',
  paymentMode: 'BANK_TRANSFER',
  expenseId: expense == null ? null : 'payroll_2026-11',
  expenseNumber: expense,
);

void main() {
  test('the register reads the server answer', () {
    final r = PayrollRegister.fromMap({
      'currency': 'INR',
      'fromPeriod': '2026-04',
      'toPeriod': '2026-11',
      'rows': [
        {
          'branchId': 'b',
          'branchName': 'Main',
          'period': '2026-11',
          'payslipCount': 3,
          'grossMinor': 10,
          'deductionsMinor': 1,
          'netMinor': 9,
          'expenseNumber': 'EXP-1',
        },
      ],
      'totals': {
        'runs': 1,
        'payslipCount': 3,
        'grossMinor': 10,
        'deductionsMinor': 1,
        'netMinor': 9,
      },
    });
    expect(
      [r.runs, r.netMinor, r.rows.single.expenseNumber, r.rows.single.paidDate],
      [1, 9, 'EXP-1', null],
    );
    expect(PayrollRegister.fromMap(const {}).rows, isEmpty);
  });

  group('the register page', () {
    testWidgets('totals, months, how each was paid and the expense it became', (
      tester,
    ) async {
      final repo = FakePayrollRepository()..registerResult = _register();
      final router = await _pump(tester, repo, start: '/payroll/register');
      expect(find.text('2 months paid'), findsOneWidget);
      expect(find.text('Net pay ₹1,14,000.00'), findsOneWidget);
      expect(
        find.textContaining(
          '12 payslips · paid 2026-11-30 · Bank transfer · EXP-2026-00007',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('paid 2026-10-31 · Cash'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('register-2026-11')));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/payroll/runs/2026-11',
      );
    });

    testWidgets('asks for the last twelve months and follows the pickers', (
      tester,
    ) async {
      final repo = FakePayrollRepository();
      await _pump(tester, repo, start: '/payroll/register');
      final now = DateTime.now();
      final months = recentPeriods(now.year, now.month, count: 24);
      expect(repo.registerCalls.single, (from: months[11], to: months.first));
      expect(find.text('Nothing was paid in these months.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('register-from')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(periodLabel(months[20])).last);
      await tester.pumpAndSettle();
      expect(repo.registerCalls.last.from, months[20]);
    });

    testWidgets('a CSV of one month is saved under a clear name', (
      tester,
    ) async {
      final repo = FakePayrollRepository()..registerResult = _register();
      final saver = _Saver();
      await _pump(
        tester,
        repo,
        start: '/payroll/register',
        extra: [expenseCsvSaverProvider.overrideWithValue(saver)],
      );
      await tester.tap(find.byKey(const ValueKey('register-csv-2026-10')));
      await tester.pumpAndSettle();
      expect(repo.exportCalls, ['2026-10']);
      expect(saver.saved.single.name, 'payroll_register_2026-10.csv');
      expect(saver.saved.single.content, startsWith('employee_code,name'));
      expect(find.text('Saved 1 payslips.'), findsOneWidget);
    });

    testWidgets('a cancelled save says nothing was saved', (tester) async {
      final repo = FakePayrollRepository()..registerResult = _register();
      final saver = _Saver()..result = false;
      await _pump(
        tester,
        repo,
        start: '/payroll/register',
        extra: [expenseCsvSaverProvider.overrideWithValue(saver)],
      );
      await tester.tap(find.byKey(const ValueKey('register-csv-2026-11')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing was saved.'), findsOneWidget);
    });

    testWidgets('a refusal is shown', (tester) async {
      final repo = FakePayrollRepository()
        ..failWith = const PermissionFailure('You do not have permission.');
      await _pump(tester, repo, start: '/payroll/register');
      expect(find.textContaining('permission'), findsWidgets);
    });

    for (final size in const [
      Size(360, 740),
      Size(800, 1100),
      Size(1400, 900),
    ]) {
      testWidgets('lays out at ${size.width.toInt()} wide, large text', (
        tester,
      ) async {
        final repo = FakePayrollRepository()..registerResult = _register();
        await _pump(
          tester,
          repo,
          start: '/payroll/register',
          size: size,
          textScale: 1.5,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('a paid run', () {
    FakePayrollRepository repoFor(PayrollRun run) => FakePayrollRepository()
      ..runItems.add(run)
      ..runSlips[run.period] = const [];

    testWidgets(
      'shows the expense it was recorded as, the register CSV and the link',
      (tester) async {
        final saver = _Saver();
        final repo = repoFor(_paid());
        await _pump(
          tester,
          repo,
          start: '/payroll/runs/2026-11',
          extra: [expenseCsvSaverProvider.overrideWithValue(saver)],
        );
        expect(
          find.text('Recorded as expense EXP-2026-00007 (Salaries)'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('run-open-expense')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('run-csv')));
        await tester.pumpAndSettle();
        expect(repo.exportCalls, ['2026-11']);
        expect(saver.saved.single.name, 'payroll_register_2026-11.csv');
      },
    );

    testWidgets('a month with nothing to pay has no expense line', (
      tester,
    ) async {
      await _pump(
        tester,
        repoFor(_paid(expense: null)),
        start: '/payroll/runs/2026-11',
      );
      expect(find.byKey(const ValueKey('run-expense')), findsNothing);
      expect(find.byKey(const ValueKey('run-open-expense')), findsNothing);
      expect(find.byKey(const ValueKey('run-csv')), findsOneWidget);
    });

    for (final s in [RunStatus.calculated, RunStatus.approved]) {
      testWidgets('a ${s.label.toLowerCase()} run has no register CSV yet', (
        tester,
      ) async {
        final run = PayrollRun(
          period: '2026-11',
          status: s,
          version: 3,
          currency: 'INR',
          payslipCount: 1,
          netMinor: 1,
          grossMinor: 1,
        );
        await _pump(tester, repoFor(run), start: '/payroll/runs/2026-11');
        expect(find.byKey(const ValueKey('run-csv')), findsNothing);
        expect(find.byKey(const ValueKey('run-expense')), findsNothing);
      });
    }

    testWidgets('lays out on a phone with large text', (tester) async {
      await _pump(
        tester,
        repoFor(_paid()),
        start: '/payroll/runs/2026-11',
        size: const Size(360, 740),
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

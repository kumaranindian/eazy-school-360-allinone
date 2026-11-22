import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_run.dart';
import 'package:eazy_school_360/features/payroll/domain/payslip_document.dart';
import 'package:eazy_school_360/features/payroll/presentation/my_payslips_routes.dart';
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
  final router = GoRouter(
    initialLocation: start,
    routes: [...payrollRoutes(), ...myPayslipsRoutes()],
  );
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

PayslipDocument _doc() => const PayslipDocument(
  schoolName: 'Rosewood High',
  branchName: 'Main campus',
  staffName: 'Asha Rao',
  employeeCode: 'E1',
  period: '2026-11',
  currency: 'INR',
  paidDate: '2026-11-30',
  paymentMode: 'BANK_TRANSFER',
  workingDays: 21,
  paidDays: 18,
  unpaidDays: 3,
  lines: [
    PayslipDocLine(
      name: 'Basic salary',
      kind: PayKind.earning,
      amountMinor: 1800000,
      plannedMinor: 2100000,
    ),
    PayslipDocLine(
      name: 'Provident fund',
      kind: PayKind.deduction,
      amountMinor: 216000,
      plannedMinor: 216000,
    ),
    PayslipDocLine(
      name: 'Diwali bonus',
      kind: PayKind.earning,
      amountMinor: 500000,
      plannedMinor: 500000,
      oneOff: true,
    ),
  ],
  grossMinor: 2300000,
  deductionsMinor: 216000,
  netMinor: 2084000,
);

void main() {
  group('my payslips', () {
    testWidgets('lists the paid months, newest first, with the net', (
      tester,
    ) async {
      final repo = FakePayrollRepository()
        ..mine.addAll(const [
          MyPayslipSummary(
            branchId: 'main',
            period: '2026-11',
            paidDate: '2026-11-30',
            netMinor: 2084000,
            currency: 'INR',
          ),
          MyPayslipSummary(
            branchId: 'main',
            period: '2026-10',
            paidDate: '2026-10-31',
            netMinor: 2100000,
            currency: 'INR',
          ),
        ]);
      final router = await _pump(
        tester,
        repo,
        role: UserRole.teacher,
        start: '/my-payslips',
      );
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Paid 2026-10-31'), findsOneWidget);
      expect(find.text('₹20,840.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mypay-2026-11')));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/my-payslips/main/2026-11',
      );
    });

    testWidgets('nothing yet says when payslips appear', (tester) async {
      await _pump(
        tester,
        FakePayrollRepository(),
        role: UserRole.teacher,
        start: '/my-payslips',
      );
      expect(
        find.textContaining('once your school has paid the month'),
        findsOneWidget,
      );
    });

    testWidgets('a refusal is shown, not a blank page', (tester) async {
      final repo = FakePayrollRepository()
        ..failWith = const PermissionFailure('You do not have permission.');
      await _pump(tester, repo, role: UserRole.teacher, start: '/my-payslips');
      expect(find.textContaining('permission'), findsWidgets);
    });

    testWidgets(
      'one payslip: the figures, the one-off item, the struck-through structure amount, the buttons',
      (tester) async {
        final repo = FakePayrollRepository()..mineDoc = _doc();
        await _pump(
          tester,
          repo,
          role: UserRole.teacher,
          start: '/my-payslips/main/2026-11',
        );
        expect(repo.mineCalls, ['main/2026-11']);
        expect(find.text('Rosewood High'), findsOneWidget);
        expect(find.text('Asha Rao'), findsOneWidget);
        expect(find.text('Paid 18 of 21 school days'), findsOneWidget);
        expect(find.text('Diwali bonus (one-off)'), findsOneWidget);
        expect(
          find.text('₹21,000.00'),
          findsOneWidget,
          reason: 'the structure amount, struck through',
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('payslip-net'))).data,
          '₹20,840.00',
        );
        expect(
          find.text('Paid on 2026-11-30 by Bank transfer'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('payslip-download')), findsOneWidget);
        expect(find.byKey(const ValueKey('payslip-print')), findsOneWidget);
      },
    );

    testWidgets('no internal notes or warnings appear on the payslip', (
      tester,
    ) async {
      final repo = FakePayrollRepository()..mineDoc = _doc();
      await _pump(
        tester,
        repo,
        role: UserRole.teacher,
        start: '/my-payslips/main/2026-11',
      );
      expect(find.textContaining('To check'), findsNothing);
      expect(find.textContaining('reason'), findsNothing);
    });

    for (final size in const [
      Size(360, 740),
      Size(800, 1100),
      Size(1400, 900),
    ]) {
      testWidgets('lays out at ${size.width.toInt()} wide, large text', (
        tester,
      ) async {
        final repo = FakePayrollRepository()
          ..mineDoc = _doc()
          ..mine.add(
            const MyPayslipSummary(
              branchId: 'main',
              period: '2026-11',
              paidDate: '2026-11-30',
              netMinor: 2084000,
              currency: 'INR',
            ),
          );
        await _pump(
          tester,
          repo,
          role: UserRole.teacher,
          start: '/my-payslips/main/2026-11',
          size: size,
          textScale: 1.5,
        );
        expect(tester.takeException(), isNull);
        await _pump(
          tester,
          repo,
          role: UserRole.teacher,
          start: '/my-payslips',
          size: size,
          textScale: 1.5,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the administrator\'s copy', () {
    PayrollRun run(RunStatus s) => PayrollRun(
      period: '2026-11',
      status: s,
      version: 5,
      currency: 'INR',
      payslipCount: 1,
      netMinor: 2084000,
      grossMinor: 2084000,
      paidDate: s == RunStatus.paid ? '2026-11-30' : null,
      paymentMode: s == RunStatus.paid ? 'CASH' : null,
    );

    FakePayrollRepository repo(RunStatus s) => FakePayrollRepository()
      ..runItems.add(run(s))
      ..runSlips['2026-11'] = [
        const PayslipRow(
          staffId: 'st1',
          name: 'Asha Rao',
          employeeCode: 'E1',
          paidDays: 21,
          unpaidDays: 0,
          workingDays: 21,
          grossMinor: 2084000,
          deductionsMinor: 0,
          netMinor: 2084000,
          warningCount: 0,
          adjustmentCount: 0,
        ),
      ]
      ..slipDetails['st1'] = const Payslip(
        row: PayslipRow(
          staffId: 'st1',
          name: 'Asha Rao',
          employeeCode: 'E1',
          paidDays: 21,
          unpaidDays: 0,
          workingDays: 21,
          grossMinor: 2084000,
          deductionsMinor: 0,
          netMinor: 2084000,
          warningCount: 0,
          adjustmentCount: 0,
        ),
        currency: 'INR',
        lines: [],
        adjustments: [],
        warnings: [],
        baseGrossMinor: 2084000,
        unrecoveredDeductionMinor: 0,
      );

    testWidgets('a paid run offers the PDF on each payslip', (tester) async {
      await _pump(tester, repo(RunStatus.paid), start: '/payroll/runs/2026-11');
      await tester.tap(find.byKey(const ValueKey('slip-st1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('slip-pdf')), findsOneWidget);
    });

    for (final s in [RunStatus.calculated, RunStatus.approved]) {
      testWidgets(
        'a ${s.label.toLowerCase()} run has no official payslip yet',
        (tester) async {
          await _pump(tester, repo(s), start: '/payroll/runs/2026-11');
          await tester.tap(find.byKey(const ValueKey('slip-st1')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('slip-pdf')), findsNothing);
        },
      );
    }
  });
}

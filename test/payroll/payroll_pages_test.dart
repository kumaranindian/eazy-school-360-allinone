import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_preview.dart';
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

StaffPaySummary _row(String id, String name, {int? net}) => StaffPaySummary(
  staff: StaffPay(id: id, name: name, employeeCode: 'E$id', status: 'ACTIVE'),
  hasStructure: net != null,
  effectiveFrom: net == null ? null : '2026-04-01',
  grossMinor: net,
  deductionsMinor: net == null ? null : 0,
  netMinor: net,
);

void main() {
  group('the staff pay list', () {
    testWidgets('shows totals, flags staff with no structure, opens one', (
      tester,
    ) async {
      final repo = FakePayrollRepository()
        ..staff.addAll([
          _row('st1', 'Asha Rao', net: 3000000),
          _row('st2', 'Bala Iyer'),
        ]);
      final router = await _pump(tester, repo);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('₹30,000.00'), findsWidgets);
      expect(find.text('No salary structure'), findsOneWidget);
      expect(
        find.textContaining('1 of 2 staff have no salary'),
        findsOneWidget,
      );
      await tester.tap(find.text('Asha Rao'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/payroll/staff/st1',
      );
    });

    testWidgets('an empty branch says so', (tester) async {
      await _pump(tester, FakePayrollRepository());
      expect(find.text('No staff in this branch yet.'), findsOneWidget);
    });

    testWidgets('a refusal from the server is shown, not a blank page', (
      tester,
    ) async {
      final repo = FakePayrollRepository()
        ..failWith = const PermissionFailure('You do not have permission.');
      await _pump(tester, repo);
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
        final repo = FakePayrollRepository()
          ..staff.addAll([
            _row('st1', 'Asha Rao with a rather long staff name', net: 3000000),
            _row('st2', 'Bala Iyer'),
          ]);
        await _pump(tester, repo, size: size, textScale: 1.5);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Asha Rao'), findsOneWidget);
      });
    }
  });

  group('pay components', () {
    testWidgets('lists them, school admin can add', (tester) async {
      final repo = FakePayrollRepository();
      await _pump(
        tester,
        repo,
        start: '/payroll/components',
        role: UserRole.schoolAdmin,
      );
      expect(find.text('Basic salary'), findsOneWidget);
      expect(find.textContaining('40% of Basic salary'), findsOneWidget);
      expect(find.text('Built in'), findsNothing, reason: 'in the subtitle');
      expect(find.byKey(const ValueKey('component-add')), findsOneWidget);
    });

    testWidgets('finance reads but has no add or edit', (tester) async {
      final repo = FakePayrollRepository()..canManage = false;
      await _pump(tester, repo, start: '/payroll/components');
      expect(find.text('Basic salary'), findsOneWidget);
      expect(find.byKey(const ValueKey('component-add')), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('adding a fixed earning sends exactly that', (tester) async {
      final repo = FakePayrollRepository();
      await _pump(
        tester,
        repo,
        start: '/payroll/components',
        role: UserRole.schoolAdmin,
      );
      await tester.tap(find.byKey(const ValueKey('component-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('component-name')),
        'Transport allowance',
      );
      await tester.tap(find.byKey(const ValueKey('component-save')));
      await tester.pumpAndSettle();
      final s = repo.savedComponents.single;
      expect(s['name'], 'Transport allowance');
      expect(s['kind'], PayKind.earning);
      expect(s['calc'], PayCalc.fixed);
      expect(s['id'], isNull);
    });

    testWidgets('a duplicate name is refused before it is sent', (
      tester,
    ) async {
      final repo = FakePayrollRepository();
      await _pump(
        tester,
        repo,
        start: '/payroll/components',
        role: UserRole.schoolAdmin,
      );
      await tester.tap(find.byKey(const ValueKey('component-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('component-name')),
        'hra',
      );
      await tester.tap(find.byKey(const ValueKey('component-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('A component with that name already exists.'),
        findsOneWidget,
      );
      expect(repo.savedComponents, isEmpty);
    });
  });

  group('the salary structure', () {
    testWidgets('finance sees the figures but no edit button', (tester) async {
      final repo = FakePayrollRepository()
        ..canEdit = false
        ..versions['st1'] = [fakeStructure()];
      await _pump(tester, repo, start: '/payroll/staff/st1');
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('In force now'), findsOneWidget);
      expect(find.text('Net pay'), findsOneWidget);
      expect(find.byKey(const ValueKey('structure-edit')), findsNothing);
    });

    testWidgets('a first structure: choose, type, see the net, save', (
      tester,
    ) async {
      final repo = FakePayrollRepository();
      await _pump(
        tester,
        repo,
        start: '/payroll/staff/st1',
        role: UserRole.schoolAdmin,
      );
      expect(find.text('No salary structure is in force yet.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('structure-edit')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('structure-reason')),
        findsNothing,
        reason: 'the first version needs no reason',
      );
      await tester.tap(find.byKey(const ValueKey('use-pc_basic')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('value-pc_basic')),
        '30000',
      );
      await tester.tap(find.byKey(const ValueKey('use-pc_hra')));
      await tester.tap(find.byKey(const ValueKey('use-pc_pf')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('structure-preview')))
            .data,
        contains('net ₹38,400.00'),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('structure-save')));
      await tester.tap(find.byKey(const ValueKey('structure-save')));
      await tester.pumpAndSettle();
      final s = repo.savedStructures.single;
      expect(s['reason'], isNull);
      expect(s['baseSeq'], 0);
      expect(s['lines'], [
        {'componentId': 'pc_basic', 'amountMinor': 3000000},
        {'componentId': 'pc_hra', 'percentBp': 4000},
        {'componentId': 'pc_pf', 'percentBp': 1200},
      ]);
    });

    testWidgets('saving without any amount is refused on screen', (
      tester,
    ) async {
      final repo = FakePayrollRepository();
      await _pump(
        tester,
        repo,
        start: '/payroll/staff/st1',
        role: UserRole.schoolAdmin,
      );
      await tester.tap(find.byKey(const ValueKey('structure-edit')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('structure-save')));
      await tester.tap(find.byKey(const ValueKey('structure-save')));
      await tester.pumpAndSettle();
      expect(find.text('Add at least one earning.'), findsOneWidget);
      expect(repo.savedStructures, isEmpty);
    });

    testWidgets('a revision needs a reason and is sent as a new version', (
      tester,
    ) async {
      final repo = FakePayrollRepository()..versions['st1'] = [fakeStructure()];
      await _pump(
        tester,
        repo,
        start: '/payroll/staff/st1',
        role: UserRole.schoolAdmin,
      );
      await tester.tap(find.byKey(const ValueKey('structure-edit')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('value-pc_basic')))
            .controller!
            .text,
        '30000.00',
        reason: 'starts from the current version',
      );
      await tester.enterText(
        find.byKey(const ValueKey('value-pc_basic')),
        '33000',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('structure-save')));
      await tester.tap(find.byKey(const ValueKey('structure-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Explain the change'), findsOneWidget);
      expect(repo.savedStructures, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('structure-reason')),
        'Annual increment of 10 percent',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('structure-save')));
      await tester.tap(find.byKey(const ValueKey('structure-save')));
      await tester.pumpAndSettle();
      final s = repo.savedStructures.single;
      expect(s['reason'], 'Annual increment of 10 percent');
      expect(s['baseSeq'], 1);
      expect((s['lines'] as List).single, {
        'componentId': 'pc_basic',
        'amountMinor': 3300000,
      });
    });

    testWidgets('a server refusal is shown on the form and nothing is lost', (
      tester,
    ) async {
      final repo = FakePayrollRepository()..versions['st1'] = [fakeStructure()];
      await _pump(
        tester,
        repo,
        start: '/payroll/staff/st1',
        role: UserRole.schoolAdmin,
      );
      await tester.tap(find.byKey(const ValueKey('structure-edit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('structure-reason')),
        'Annual increment of 10 percent',
      );
      repo.failWith = const ValidationFailure(
        'This was changed by someone else. Reload and try again.',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('structure-save')));
      await tester.tap(find.byKey(const ValueKey('structure-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('changed by someone else'), findsOneWidget);
      expect(find.byKey(const ValueKey('structure-form')), findsOneWidget);
    });

    testWidgets('history lists every version', (tester) async {
      final repo = FakePayrollRepository()
        ..versions['st1'] = [
          fakeStructure(latest: false),
          fakeStructure(seq: 2, from: '2026-12-01', basic: 3300000),
        ];
      await _pump(tester, repo, start: '/payroll/staff/st1');
      expect(find.text('History'), findsOneWidget);
      expect(
        find.textContaining('Version 2 · from 2026-12-01'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Version 1 · from 2026-04-01'),
        findsOneWidget,
      );
    });

    for (final size in const [Size(360, 740), Size(1400, 900)]) {
      testWidgets(
        'the form lays out at ${size.width.toInt()} wide, large text',
        (tester) async {
          final repo = FakePayrollRepository()
            ..versions['st1'] = [fakeStructure()];
          await _pump(
            tester,
            repo,
            start: '/payroll/staff/st1',
            role: UserRole.schoolAdmin,
            size: size,
            textScale: 1.5,
          );
          await tester.tap(find.byKey(const ValueKey('structure-edit')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('pay for a month', () {
    PayPreviewBranch branch(String period) => PayPreviewBranch(
      period: period,
      currency: 'INR',
      workingDays: 21,
      unmarkedDays: UnmarkedDays.paid,
      rows: [
        PayPreviewRow(
          staff: const StaffPay(
            id: 'st1',
            name: 'Asha Rao',
            employeeCode: 'E1',
            status: 'ACTIVE',
          ),
          hasStructure: true,
          workingDays: 21,
          paidDays: 18,
          unpaidDays: 3,
          netMinor: 1800000,
          warningCount: 2,
        ),
        const PayPreviewRow(
          staff: StaffPay(
            id: 'st2',
            name: 'Bala Iyer',
            employeeCode: 'E2',
            status: 'ACTIVE',
          ),
          hasStructure: false,
        ),
      ],
    );

    PayPreviewStaff staffPreview() => const PayPreviewStaff(
      period: '2026-11',
      currency: 'INR',
      staff: StaffPay(
        id: 'st1',
        name: 'Asha Rao',
        employeeCode: 'E1',
        status: 'ACTIVE',
      ),
      structure: null,
      calculation: PayCalculation(
        workingDays: 21,
        paidDays: 18.5,
        unpaidDays: 2.5,
        grossMinor: 1850000,
        deductionsMinor: 300000,
        netMinor: 1550000,
        unrecoveredDeductionMinor: 50000,
        warnings: [
          PayWarning('NOT_MARKED', '2026-11-02'),
          PayWarning('LEAVE_AND_PRESENT', '2026-11-04'),
        ],
        lines: [
          PayLineResult(
            name: 'Basic salary',
            kind: PayKind.earning,
            plannedMinor: 2100000,
            amountMinor: 1850000,
          ),
          PayLineResult(
            name: 'Advance',
            kind: PayKind.deduction,
            plannedMinor: 350000,
            amountMinor: 300000,
          ),
        ],
        days: {
          'present': 16,
          'absent': 2,
          'halfDay': 1,
          'unmarked': 1,
          'paidLeave': 1,
        },
      ),
    );

    testWidgets('lists the month with totals, paid days and what to check', (
      tester,
    ) async {
      final repo = FakePayrollRepository();
      repo.branchPreview = branch('x');
      await _pump(tester, repo, start: '/payroll/preview');
      expect(repo.previewCalls.single.staff, isNull);
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('₹18,000.00'), findsOneWidget);
      expect(
        find.textContaining('Paid 18 of 21 days · 2 to check'),
        findsOneWidget,
      );
      expect(find.text('No salary structure'), findsOneWidget);
      expect(find.textContaining('21 school days'), findsOneWidget);
      expect(find.textContaining('Days nobody marked: paid'), findsOneWidget);
    });

    testWidgets('choosing another month asks for that month', (tester) async {
      final repo = FakePayrollRepository();
      await _pump(tester, repo, start: '/payroll/preview');
      final first = repo.previewCalls.single.period;
      await tester.tap(find.byKey(const ValueKey('preview-period')));
      await tester.pumpAndSettle();
      final now = DateTime.now();
      final second = recentPeriods(now.year, now.month)[1];
      await tester.tap(find.text(periodLabel(second)).last);
      await tester.pumpAndSettle();
      expect(repo.previewCalls.last.period, isNot(first));
      expect(repo.previewCalls.last.period, hasLength(7));
    });

    testWidgets('an empty branch says so', (tester) async {
      await _pump(tester, FakePayrollRepository(), start: '/payroll/preview');
      expect(find.textContaining('No staff to pay'), findsOneWidget);
    });

    testWidgets('tapping a person explains the month line by line', (
      tester,
    ) async {
      final repo = FakePayrollRepository()
        ..branchPreview = branch('x')
        ..staffPreview = staffPreview();
      await _pump(tester, repo, start: '/payroll/preview');
      await tester.tap(find.byKey(const ValueKey('preview-st1')));
      await tester.pumpAndSettle();
      expect(repo.previewCalls.last.staff, 'st1');
      expect(find.text('Paid 18.5 of 21 school days'), findsOneWidget);
      expect(find.text('Present 16'), findsOneWidget);
      expect(find.text('Half days 1'), findsOneWidget);
      expect(find.text('Paid leave 1'), findsOneWidget);
      expect(find.text('Not marked 1'), findsOneWidget);
      expect(
        find.text('₹21,000.00'),
        findsOneWidget,
        reason: 'the planned amount, struck through',
      );
      expect(find.text('₹18,500.00'), findsOneWidget);
      expect(find.text('- ₹3,000.00'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('explain-net'))).data,
        '₹15,500.00',
      );
      expect(
        find.textContaining('₹500.00 of deductions could not be taken'),
        findsOneWidget,
      );
      expect(
        find.text('• Attendance was not marked on 2026-11-02.'),
        findsOneWidget,
      );
      expect(
        find.text('• Marked present on a day of unpaid leave on 2026-11-04.'),
        findsOneWidget,
      );
    });

    testWidgets('a person with no structure cannot be opened', (tester) async {
      final repo = FakePayrollRepository()..branchPreview = branch('x');
      await _pump(tester, repo, start: '/payroll/preview');
      await tester.tap(find.byKey(const ValueKey('preview-st2')));
      await tester.pumpAndSettle();
      expect(repo.previewCalls.where((c) => c.staff != null), isEmpty);
    });

    testWidgets('a school admin saves the unmarked-days policy', (
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
      await tester.tap(find.byKey(const ValueKey('unmarked-UNPAID')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('unmarked-save')));
      await tester.pumpAndSettle();
      expect(repo.savedSettings, [UnmarkedDays.unpaid]);
      expect(repo.previewCalls.length, 2, reason: 'the month is recalculated');
    });

    testWidgets('finance can read the policy but not change it', (
      tester,
    ) async {
      final repo = FakePayrollRepository()..canManage = false;
      await _pump(tester, repo, start: '/payroll/preview');
      await tester.tap(find.byKey(const ValueKey('preview-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('unmarked-save')), findsNothing);
      expect(find.text('Only a school admin can change this.'), findsOneWidget);
      expect(repo.savedSettings, isEmpty);
    });

    testWidgets('a refusal is shown, not a blank page', (tester) async {
      final repo = FakePayrollRepository()
        ..failWith = const PermissionFailure('You do not have permission.');
      await _pump(tester, repo, start: '/payroll/preview');
      expect(find.textContaining('permission'), findsWidgets);
    });

    for (final size in const [Size(360, 740), Size(1400, 900)]) {
      testWidgets('lays out at ${size.width.toInt()} wide, large text', (
        tester,
      ) async {
        final repo = FakePayrollRepository()
          ..branchPreview = branch('x')
          ..staffPreview = staffPreview();
        await _pump(
          tester,
          repo,
          start: '/payroll/preview',
          size: size,
          textScale: 1.5,
        );
        await tester.tap(find.byKey(const ValueKey('preview-st1')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('period helpers', () {
    expect(periodLabel('2026-11'), 'November 2026');
    expect(periodLabel('2026-13'), '2026-13');
    expect(recentPeriods(2026, 2, count: 4), [
      '2026-02',
      '2026-01',
      '2025-12',
      '2025-11',
    ]);
    expect(daysText(21), '21');
    expect(daysText(20.5), '20.5');
  });
}

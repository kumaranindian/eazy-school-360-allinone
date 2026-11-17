import 'package:eazy_school_360/core/features/feature_catalogue.dart';
import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/role_permissions.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/core/tenant/tenant_context.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll.dart';
import 'package:flutter_test/flutter_test.dart';

const _basic = PayComponent(
  id: 'basic',
  name: 'Basic',
  kind: PayKind.earning,
  calc: PayCalc.fixed,
);
const _hra = PayComponent(
  id: 'hra',
  name: 'HRA',
  kind: PayKind.earning,
  calc: PayCalc.percent,
  basisComponentId: 'basic',
  percentBp: 4000,
);
const _pf = PayComponent(
  id: 'pf',
  name: 'PF',
  kind: PayKind.deduction,
  calc: PayCalc.percent,
  basisComponentId: 'basic',
  percentBp: 1200,
);
const _adv = PayComponent(
  id: 'adv',
  name: 'Advance',
  kind: PayKind.deduction,
  calc: PayCalc.fixed,
);
final _all = {
  for (final c in [_basic, _hra, _pf, _adv]) c.id: c,
};

void main() {
  group('permissions mirror the server capability table', () {
    bool has(UserRole r, Permission p) => RolePermissions.roleHas(r, p);

    test('school admin reads and changes pay; finance only reads', () {
      expect(has(UserRole.schoolAdmin, Permission.viewPayroll), isTrue);
      expect(has(UserRole.schoolAdmin, Permission.managePayroll), isTrue);
      expect(has(UserRole.finance, Permission.viewPayroll), isTrue);
      expect(has(UserRole.finance, Permission.managePayroll), isFalse);
    });

    test('a branch admin, teacher and parent see no pay at all', () {
      for (final r in [
        UserRole.branchAdmin,
        UserRole.teacher,
        UserRole.parent,
      ]) {
        expect(has(r, Permission.viewPayroll), isFalse, reason: '$r');
        expect(has(r, Permission.managePayroll), isFalse, reason: '$r');
      }
    });

    test('the routes are gated by viewPayroll', () {
      for (final p in [
        AppRoutes.payroll,
        AppRoutes.payrollComponents,
        AppRoutes.payrollPreview,
        AppRoutes.payrollRuns,
        AppRoutes.payrollRun,
        AppRoutes.payrollStaff,
      ]) {
        expect(
          AppRoutes.requiredPermissions[p],
          Permission.viewPayroll,
          reason: p,
        );
      }
    });
  });

  test('a support session never gets payroll (the server refuses too)', () {
    const profile = UserProfile(
      userId: 'p1',
      schoolId: 'school-1',
      branchId: 'main',
      name: 'Support',
      email: 's@example.com',
      role: UserRole.platformAdmin,
      status: UserStatus.active,
    );
    expect(
      const TenantContext(
        user: profile,
        supportSession: true,
      ).can(Permission.viewPayroll),
      isFalse,
    );
    expect(
      const TenantContext(
        user: profile,
        supportSession: true,
      ).can(Permission.managePayroll),
      isFalse,
      reason: 'a support session is look-only',
    );
    expect(
      const TenantContext(
        user: profile,
        supportSession: true,
      ).can(Permission.viewExpenses),
      isTrue,
      reason: 'other viewing is unchanged',
    );
  });

  test('payroll is a module that needs staff', () {
    expect(featureDef('payroll')!.dependsOn, ['staff']);
    expect(featureUsable(const {}, 'payroll'), isTrue);
    expect(featureUsable(const {'staff': false}, 'payroll'), isFalse);
    expect(featureUsable(const {'payroll': false}, 'payroll'), isFalse);
  });

  group('PayrollPreview mirrors the server arithmetic', () {
    PayrollPreview run(List<SalaryLineInput> l) =>
        PayrollPreview.compute(l, _all);

    test('fixed and percentage lines, gross, deductions, net', () {
      final p = run(const [
        SalaryLineInput(componentId: 'basic', amountMinor: 3000000),
        SalaryLineInput(componentId: 'hra'),
        SalaryLineInput(componentId: 'pf'),
        SalaryLineInput(componentId: 'adv', amountMinor: 50000),
      ]);
      expect(p.valid, isTrue);
      expect(p.amounts, {
        'basic': 3000000,
        'hra': 1200000,
        'pf': 360000,
        'adv': 50000,
      });
      expect(
        [p.grossMinor, p.deductionsMinor, p.netMinor],
        [4200000, 410000, 3790000],
      );
    });

    test('rounds half up, exactly', () {
      expect(PayrollPreview.percentOf(5, 1000), 1);
      expect(PayrollPreview.percentOf(4, 1000), 0);
      expect(PayrollPreview.percentOf(15, 1000), 2);
      expect(PayrollPreview.percentOf(999999999999, 9999), 999899999999);
      expect(PayrollPreview.percentOf(1000000000000, 10000), 1000000000000);
    });

    test('a per-person percentage overrides the default', () {
      final p = run(const [
        SalaryLineInput(componentId: 'basic', amountMinor: 1000),
        SalaryLineInput(componentId: 'pf', percentBp: 1000),
      ]);
      expect(p.amounts['pf'], 100);
    });

    test('refusals say why', () {
      expect(run(const []).valid, isFalse);
      expect(
        run(const [SalaryLineInput(componentId: 'basic')]).problem,
        contains('Basic'),
      );
      expect(
        run(const [
          SalaryLineInput(componentId: 'basic', amountMinor: 0),
        ]).valid,
        isFalse,
      );
      expect(
        run(const [SalaryLineInput(componentId: 'hra')]).problem,
        contains('basis'),
        reason: 'a percentage needs its basis in the structure',
      );
      expect(
        run(const [SalaryLineInput(componentId: 'adv', amountMinor: 5)]).valid,
        isFalse,
        reason: 'no earning',
      );
      final over = run(const [
        SalaryLineInput(componentId: 'basic', amountMinor: 100),
        SalaryLineInput(componentId: 'adv', amountMinor: 101),
      ]);
      expect(over.valid, isFalse);
      expect(over.problem, contains('more than the earnings'));
      expect(
        run(const [SalaryLineInput(componentId: 'nope', amountMinor: 5)]).valid,
        isFalse,
      );
    });

    test('net may be exactly zero', () {
      expect(
        run(const [
          SalaryLineInput(componentId: 'basic', amountMinor: 100),
          SalaryLineInput(componentId: 'adv', amountMinor: 100),
        ]).valid,
        isTrue,
      );
    });
  });

  test('percent text and parsing', () {
    expect(percentText(4000), '40%');
    expect(percentText(1250), '12.5%');
    expect(percentText(1205), '12.05%');
    expect(parsePercentBp('12.5'), 1250);
    expect(parsePercentBp('40'), 4000);
    expect(parsePercentBp('100'), 10000);
    for (final bad in ['', '0', '100.01', 'abc', '-5', '12.555', '1e2']) {
      expect(parsePercentBp(bad), isNull, reason: bad);
    }
  });

  test('component names: length and duplicates', () {
    expect(PayComponent.validateName('x', const []), isNotNull);
    expect(PayComponent.validateName('Allowance', const []), isNull);
    expect(PayComponent.validateName(' basic  ', [_basic]), isNotNull);
    expect(
      PayComponent.validateName('Basic', [_basic], exceptId: 'basic'),
      isNull,
    );
  });

  test('first of month', () {
    expect(firstOfMonth(2026, 4), '2026-04-01');
    expect(firstOfMonth(2026, 12), '2026-12-01');
  });
}

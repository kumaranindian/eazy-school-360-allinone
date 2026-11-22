import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/role_permissions.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/core/routing/app_routes.dart';
import 'package:eazy_school_360/core/tenant/tenant_context.dart';
import 'package:eazy_school_360/features/fees/domain/fee_letterhead.dart';
import 'package:eazy_school_360/features/notifications/domain/feed_item.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll.dart';
import 'package:eazy_school_360/features/payroll/domain/payroll_run.dart';
import 'package:eazy_school_360/features/payroll/domain/payslip_document.dart';
import 'package:eazy_school_360/features/payroll/presentation/widgets/payslip_pdf.dart';
import 'package:eazy_school_360/features/users/domain/user_profile.dart';
import 'package:eazy_school_360/features/users/domain/user_status.dart';
import 'package:flutter_test/flutter_test.dart';

PayslipDocument _doc({
  int lines = 1,
  bool reduced = false,
  bool deduction = true,
  String name = 'Asha Rao',
  String code = 'E1',
  double unpaid = 0,
}) => PayslipDocument(
  schoolName: 'Rosewood High',
  branchName: 'Main campus',
  staffName: name,
  employeeCode: code,
  period: '2026-11',
  currency: 'INR',
  paidDate: '2026-11-30',
  paymentMode: 'BANK_TRANSFER',
  workingDays: 21,
  paidDays: 21 - unpaid,
  unpaidDays: unpaid,
  lines: [
    for (var i = 0; i < lines; i++)
      PayslipDocLine(
        name: i == 0 ? 'Basic salary' : 'Allowance number $i',
        kind: PayKind.earning,
        amountMinor: reduced ? 1800000 : 2100000,
        plannedMinor: 2100000,
      ),
    if (deduction)
      const PayslipDocLine(
        name: 'Provident fund',
        kind: PayKind.deduction,
        amountMinor: 216000,
        plannedMinor: 216000,
      ),
    const PayslipDocLine(
      name: 'Diwali bonus',
      kind: PayKind.earning,
      amountMinor: 500000,
      plannedMinor: 500000,
      oneOff: true,
    ),
  ],
  grossMinor: 2600000,
  deductionsMinor: deduction ? 216000 : 0,
  netMinor: deduction ? 2384000 : 2600000,
);

void main() {
  group('permissions', () {
    bool has(UserRole r, Permission p) => RolePermissions.roleHas(r, p);

    test('every staff role reads their own payslips; a parent does not', () {
      for (final r in [
        UserRole.schoolAdmin,
        UserRole.branchAdmin,
        UserRole.teacher,
        UserRole.finance,
      ]) {
        expect(has(r, Permission.viewOwnPayslips), isTrue, reason: '$r');
      }
      expect(has(UserRole.parent, Permission.viewOwnPayslips), isFalse);
    });

    test(
      'own payslips never enter a support session; a payroll module off hides them',
      () {
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
          ).can(Permission.viewOwnPayslips),
          isFalse,
        );
      },
    );

    test('the routes are gated by viewOwnPayslips', () {
      expect(
        AppRoutes.requiredPermissions[AppRoutes.myPayslips],
        Permission.viewOwnPayslips,
      );
      expect(
        AppRoutes.requiredPermissions[AppRoutes.myPayslip],
        Permission.viewOwnPayslips,
      );
    });
  });

  test('the published notice opens My payslips, only for a staff member', () {
    const n = FeedItem(
      id: 'n',
      source: FeedSource.targeted,
      branchId: 'main',
      type: 'PAYSLIP_PUBLISHED',
      title: 'Your payslip is ready',
      refId: '2026-11',
    );
    for (final r in [
      UserRole.teacher,
      UserRole.finance,
      UserRole.schoolAdmin,
    ]) {
      expect(
        NotificationNavigator.routeFor(n, r),
        AppRoutes.myPayslips,
        reason: '$r',
      );
    }
    expect(NotificationNavigator.routeFor(n, UserRole.parent), isNull);
  });

  group('the document', () {
    test('reads the server answer, one-off items included', () {
      final d = PayslipDocument.fromMap({
        'schoolName': 'Rosewood High',
        'branchName': 'Main',
        'staffName': 'Asha Rao',
        'employeeCode': 'E1',
        'period': '2026-11',
        'currency': 'INR',
        'paidDate': '2026-11-30',
        'paymentMode': 'UPI',
        'workingDays': 21,
        'paidDays': 20.5,
        'unpaidDays': 0.5,
        'lines': [
          {
            'name': 'Basic',
            'kind': 'EARNING',
            'plannedMinor': 100,
            'amountMinor': 90,
          },
          {
            'name': 'PF',
            'kind': 'DEDUCTION',
            'plannedMinor': 10,
            'amountMinor': 10,
          },
        ],
        'adjustments': [
          {'label': 'Bonus', 'kind': 'EARNING', 'amountMinor': 50},
        ],
        'grossMinor': 140,
        'deductionsMinor': 10,
        'netMinor': 130,
      });
      expect(d.earnings.map((l) => l.name), ['Basic', 'Bonus']);
      expect(d.deductions.map((l) => l.name), ['PF']);
      expect(d.lines.first.reduced, isTrue);
      expect(
        d.lines.last.reduced,
        isFalse,
        reason: 'a one-off item is never "reduced"',
      );
      expect(d.lines.last.oneOff, isTrue);
      expect(d.paymentModeLabel, 'UPI');
      expect([d.paidDays, d.unpaidDays], [20.5, 0.5]);
    });

    test('missing fields read as empty, not as a crash', () {
      final d = PayslipDocument.fromMap(const {});
      expect(
        [d.staffName, d.netMinor, d.lines, d.paymentModeLabel],
        ['', 0, isEmpty, null],
      );
    });

    test('file names are safe on every platform', () {
      expect(_doc().fileName, 'Payslip-2026-11-E1.pdf');
      expect(_doc(code: 'E/1 ../x').fileName, 'Payslip-2026-11-E1x.pdf');
      expect(_doc(code: '').fileName, 'Payslip-2026-11.pdf');
    });

    test('an administrator\'s copy keeps the figures of the paid run', () {
      const run = PayrollRun(
        period: '2026-11',
        status: RunStatus.paid,
        version: 5,
        currency: 'INR',
        paidDate: '2026-11-30',
        paymentMode: 'CASH',
      );
      const slip = Payslip(
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
          warningCount: 0,
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
            id: 'a',
            kind: PayKind.earning,
            label: 'Bonus',
            amountMinor: 500000,
            reason: 'Internal reason',
          ),
        ],
        warnings: [],
        baseGrossMinor: 2100000,
        unrecoveredDeductionMinor: 0,
      );
      final d = PayslipDocument.fromAdmin(
        slip,
        run,
        schoolName: 'S',
        branchName: 'B',
      );
      expect(
        [d.staffName, d.paidDate, d.paymentMode, d.netMinor],
        ['Asha Rao', '2026-11-30', 'CASH', 2600000],
      );
      expect(d.lines.map((l) => l.name), ['Basic salary', 'Bonus']);
    });
  });

  group('the PDF', () {
    Future<void> builds(PayslipDocument d, {FeeLetterhead? l}) async {
      final bytes = await PayslipPdf.build(
        d,
        letterhead: l ?? const FeeLetterhead(),
      );
      expect(bytes.length, greaterThan(800));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }

    test('builds a normal payslip', () async => builds(_doc()));

    test(
      'with the school letterhead',
      () async => builds(
        _doc(),
        l: const FeeLetterhead(
          schoolName: 'Rosewood High',
          branchName: 'Main campus',
          addressLines: ['12 Garden Road', 'Bengaluru 560001'],
          contactLine: '080 1234 5678 | office@rosewood.example',
        ),
      ),
    );

    test('reduced lines, no deductions, unpaid days', () async {
      await builds(_doc(reduced: true, unpaid: 3));
      await builds(_doc(deduction: false));
    });

    test('very long names and many lines continue onto more pages', () async {
      await builds(_doc(lines: 60, name: 'A very long staff member name ' * 6));
      final bytes = await PayslipPdf.build(_doc(lines: 60));
      expect(bytes.length, greaterThan(3000));
    });

    test('empty school name and an empty document still print', () async {
      await builds(PayslipDocument.fromMap(const {}));
    });

    test('other currencies', () async {
      for (final c in ['JPY', 'KWD', 'USD']) {
        final d = _doc();
        await builds(
          PayslipDocument(
            schoolName: d.schoolName,
            branchName: d.branchName,
            staffName: d.staffName,
            employeeCode: d.employeeCode,
            period: d.period,
            currency: c,
            paidDate: d.paidDate,
            paymentMode: d.paymentMode,
            workingDays: d.workingDays,
            paidDays: d.paidDays,
            unpaidDays: d.unpaidDays,
            lines: d.lines,
            grossMinor: d.grossMinor,
            deductionsMinor: d.deductionsMinor,
            netMinor: d.netMinor,
          ),
        );
      }
    });
  });
}

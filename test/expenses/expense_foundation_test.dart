import 'package:eazy_school_360/core/features/feature_catalogue.dart';
import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/role_permissions.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/expenses/domain/expense_category.dart';
import 'package:eazy_school_360/features/expenses/domain/expense_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/expense_fakes.dart';

void main() {
  group('permissions mirror the server capability table', () {
    bool has(UserRole r, Permission p) => RolePermissions.roleHas(r, p);

    test('school admin can do everything; teachers and parents nothing', () {
      for (final p in [
        Permission.viewExpenses,
        Permission.createExpenses,
        Permission.approveExpenses,
        Permission.payExpenses,
        Permission.manageExpenseSettings,
        Permission.viewExpenseReports,
      ]) {
        expect(has(UserRole.schoolAdmin, p), isTrue, reason: '$p');
        expect(has(UserRole.teacher, p), isFalse, reason: '$p');
        expect(has(UserRole.parent, p), isFalse, reason: '$p');
      }
    });

    test('finance records and pays but never approves or manages', () {
      expect(has(UserRole.finance, Permission.createExpenses), isTrue);
      expect(has(UserRole.finance, Permission.payExpenses), isTrue);
      expect(has(UserRole.finance, Permission.approveExpenses), isFalse);
      expect(has(UserRole.finance, Permission.manageExpenseSettings), isFalse);
    });

    test(
      'a branch admin approves (when allowed) but never pays or manages',
      () {
        expect(has(UserRole.branchAdmin, Permission.approveExpenses), isTrue);
        expect(has(UserRole.branchAdmin, Permission.payExpenses), isFalse);
        expect(
          has(UserRole.branchAdmin, Permission.manageExpenseSettings),
          isFalse,
        );
      },
    );
  });

  test('expenses is a module with no dependencies, on by default', () {
    expect(featureDef('expenses'), isNotNull);
    expect(featureDef('expenses')!.dependsOn, isEmpty);
    expect(featureUsable(const {}, 'expenses'), isTrue);
    expect(featureUsable(const {'expenses': false}, 'expenses'), isFalse);
  });

  group('ExpenseSettings', () {
    test('defaults: approval required, no self approval, school admin', () {
      const s = ExpenseSettings();
      expect(s.approvalRequired, isTrue);
      expect(s.allowSelfApproval, isFalse);
      expect(s.approverRoles, [UserRole.schoolAdmin]);
      expect(s.canApprove(UserRole.schoolAdmin), isTrue);
      expect(s.canApprove(UserRole.branchAdmin), isFalse);
      expect(s.canApprove(UserRole.finance), isFalse);
    });

    test('reads the server map, ignoring unknown roles, and round-trips', () {
      final s = ExpenseSettings.fromMap({
        'approvalRequired': false,
        'approverRoles': ['BRANCH_ADMIN', 'MYSTERY'],
        'receiptRequiredOverMinor': 50000,
        'version': 3,
      });
      expect(s.approvalRequired, isFalse);
      expect(s.approverRoles, [UserRole.branchAdmin]);
      expect(s.canApprove(UserRole.branchAdmin), isTrue);
      expect(s.version, 3);
      expect(s.toRequest(), {
        'approvalRequired': false,
        'allowSelfApproval': false,
        'approverRoles': ['BRANCH_ADMIN'],
        'receiptRequiredOverMinor': 50000,
      });
    });

    test(
      'an empty or unknown approver list falls back to the school admin',
      () {
        expect(
          ExpenseSettings.fromMap({'approverRoles': <String>[]}).approverRoles,
          [UserRole.schoolAdmin],
        );
      },
    );

    test('copyWith can clear the receipt threshold', () {
      const s = ExpenseSettings(receiptRequiredOverMinor: 100);
      expect(
        s.copyWith(receiptRequiredOverMinor: null).receiptRequiredOverMinor,
        isNull,
      );
      expect(s.copyWith(approvalRequired: false).receiptRequiredOverMinor, 100);
    });
  });

  group('ExpenseCategory.validateName', () {
    const existing = [
      ExpenseCategory(id: 'a', name: 'Utilities'),
      ExpenseCategory(id: 'b', name: 'Garden'),
    ];
    test('length and uniqueness, ignoring case and spacing', () {
      expect(ExpenseCategory.validateName('G', existing), isNotNull);
      expect(ExpenseCategory.validateName('x' * 61, existing), isNotNull);
      expect(ExpenseCategory.validateName('  utilities ', existing), isNotNull);
      expect(ExpenseCategory.validateName('Repairs', existing), isNull);
      expect(
        ExpenseCategory.validateName('Utilities', existing, exceptId: 'a'),
        isNull,
        reason: 'renaming a category to itself is fine',
      );
    });
  });

  test(
    'the fake repository protects the system category like the server',
    () async {
      final repo = FakeExpenseRepository();
      await repo.saveCategory(
        's',
        categoryId: 'cat_salaries',
        name: 'Pay',
        active: false,
      );
      final all = await repo.categories('s', includeInactive: true);
      expect(all.first.name, 'Salaries');
      expect(all.first.system, isTrue);
    },
  );
}

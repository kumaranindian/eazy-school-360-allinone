import 'package:eazy_school_360/core/features/feature_catalogue.dart';
import 'package:eazy_school_360/core/permissions/permission.dart';
import 'package:eazy_school_360/core/permissions/role_permissions.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/expenses/domain/expense.dart';
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

  group('ExpenseFormRules', () {
    ({ExpenseInput? input, Map<String, String> errors}) v({
      String? category = 'cat_other',
      String amount = '1250.50',
      String currency = 'INR',
      String? date = '2026-11-10',
      String today = '2026-11-15',
      String payee = '',
      String description = '',
      String reference = '',
    }) => ExpenseFormRules.validate(
      categoryId: category,
      amountText: amount,
      currency: currency,
      dateKey: date,
      todayKey: today,
      payee: payee,
      description: description,
      paymentReference: reference,
    );

    test('a good form becomes minor units, trimmed', () {
      final r = v(amount: '1,250.50', payee: '  Raj  ');
      expect(r.errors, isEmpty);
      expect(r.input!.amountMinor, 125050);
      expect(r.input!.payee, 'Raj');
    });

    test('amounts follow the currency decimals, never rounding silently', () {
      expect(v(amount: '12.345').errors.keys, contains('amount'));
      expect(v(amount: '0').errors['amount'], contains('more than zero'));
      expect(v(amount: '-5').errors.keys, contains('amount'));
      expect(v(amount: 'abc').errors.keys, contains('amount'));
      expect(v(amount: '1500', currency: 'JPY').input!.amountMinor, 1500);
      expect(
        v(amount: '15.5', currency: 'JPY').errors.keys,
        contains('amount'),
      );
      expect(v(amount: '1.234', currency: 'KWD').input!.amountMinor, 1234);
    });

    test('category, date and lengths', () {
      expect(v(category: null).errors.keys, contains('category'));
      expect(v(category: '').errors.keys, contains('category'));
      expect(v(date: null).errors.keys, contains('date'));
      expect(v(date: '2026-11-16').errors['date'], contains('future'));
      expect(v(date: '2026-11-15').errors, isEmpty, reason: 'today is allowed');
      expect(v(payee: 'x' * 121).errors.keys, contains('payee'));
      expect(v(description: 'x' * 501).errors.keys, contains('description'));
      expect(v(reference: 'x' * 61).errors.keys, contains('reference'));
    });

    test('all errors are reported together, not one at a time', () {
      expect(v(category: null, amount: '', date: null).errors.keys.toSet(), {
        'category',
        'amount',
        'date',
      });
    });
  });

  group('Expense', () {
    Expense e({ExpenseStatus s = ExpenseStatus.draft, String? by = 'u1'}) =>
        Expense(
          id: '1',
          number: 'EXP-1',
          branchId: 'b',
          categoryId: 'c',
          categoryName: 'Other',
          amountMinor: 125000,
          currency: 'INR',
          expenseDate: '2026-11-10',
          status: s,
          createdBy: by,
        );

    test('only a draft is editable, by its creator or an admin', () {
      expect(e().canEdit(uid: 'u1', isAdmin: false), isTrue);
      expect(e().canEdit(uid: 'u2', isAdmin: false), isFalse);
      expect(e().canEdit(uid: 'u2', isAdmin: true), isTrue);
      for (final s in ExpenseStatus.values.where(
        (s) => s != ExpenseStatus.draft,
      )) {
        expect(
          e(s: s).canEdit(uid: 'u1', isAdmin: true),
          isFalse,
          reason: s.name,
        );
      }
    });

    test('statuses and payment modes round-trip their wire values', () {
      for (final s in ExpenseStatus.values) {
        expect(ExpenseStatus.fromWire(s.wire), s);
      }
      for (final m in PaymentMode.values) {
        expect(PaymentMode.fromWire(m.wire), m);
      }
      expect(PaymentMode.fromWire('BITCOIN'), isNull);
      expect(ExpenseStatus.fromWire('???'), ExpenseStatus.draft);
    });

    test('the page reads the server map', () {
      final p = ExpensePage.fromMap({
        'expenses': [
          {'id': 'a', 'amountMinor': 500, 'currency': 'INR', 'status': 'PAID'},
        ],
        'nextCursor': {'id': 'a'},
      });
      expect(p.expenses.single.status, ExpenseStatus.paid);
      expect(p.nextCursor, {'id': 'a'});
      expect(ExpensePage.fromMap({}).nextCursor, isNull);
    });
  });
}

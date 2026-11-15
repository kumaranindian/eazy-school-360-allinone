import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/expenses/domain/expense.dart';
import 'package:eazy_school_360/features/expenses/domain/expense_report.dart';
import 'package:eazy_school_360/features/expenses/domain/expense_settings.dart';
import 'package:eazy_school_360/features/expenses/presentation/pages/expense_reports_page.dart';
import 'package:eazy_school_360/features/admission/presentation/providers/document_picker.dart';
import 'package:eazy_school_360/features/expenses/presentation/expenses_routes.dart';
import 'package:eazy_school_360/features/expenses/presentation/providers/expense_providers.dart';
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

import '../support/expense_fakes.dart';
import '../support/fakes.dart';

const _uid = 'u1';

Expense _expense(
  String id, {
  String payee = 'Raj Hardware',
  int amount = 125000,
  ExpenseStatus status = ExpenseStatus.draft,
  String date = '2026-11-10',
  String category = 'cat_other',
  String? createdBy = _uid,
}) => Expense(
  id: id,
  number: 'EXP-2026-000$id',
  branchId: 'main',
  categoryId: category,
  categoryName: category == 'cat_other' ? 'Other' : 'Salaries',
  amountMinor: amount,
  currency: 'INR',
  expenseDate: date,
  status: status,
  payee: payee,
  createdBy: createdBy,
);

Future<GoRouter> _pump(
  WidgetTester tester,
  FakeExpenseRepository repo, {
  UserRole role = UserRole.finance,
  String start = '/expenses',
  Size size = const Size(900, 1600),
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: start, routes: expenseRoutes());
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
        expenseRepositoryProvider.overrideWithValue(repo),
        ...extra,
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('the list', () {
    testWidgets(
      'shows each expense with its number, category, date, amount and status',
      (tester) async {
        final repo = FakeExpenseRepository()
          ..items.addAll([
            _expense('1'),
            _expense(
              '2',
              payee: 'Water board',
              amount: 4550,
              status: ExpenseStatus.paid,
            ),
          ]);
        await _pump(tester, repo);
        expect(find.text('Raj Hardware'), findsOneWidget);
        expect(find.text('₹1,250.00'), findsOneWidget);
        expect(find.text('₹45.50'), findsOneWidget);
        expect(find.text('Paid'), findsOneWidget);
        expect(find.textContaining('EXP-2026-0001'), findsOneWidget);
        expect(find.byKey(const ValueKey('expenses-add')), findsOneWidget);
      },
    );

    testWidgets('an empty list says so and offers to add one', (tester) async {
      await _pump(tester, FakeExpenseRepository());
      expect(find.text('No expenses recorded yet.'), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-add-empty')), findsOneWidget);
    });

    testWidgets('a status filter asks the server for exactly that status', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()
        ..items.addAll([
          _expense('1'),
          _expense('2', payee: 'Water board', status: ExpenseStatus.paid),
        ]);
      await _pump(tester, repo);
      await tester.tap(find.text('All statuses').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paid').last);
      await tester.pumpAndSettle();
      expect(repo.listQueries.last.status, ExpenseStatus.paid);
      expect(find.text('Water board'), findsOneWidget);
      expect(find.text('Raj Hardware'), findsNothing);
    });

    testWidgets('"Load more" appends the next page and then goes away', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()..pageSize = 2;
      for (var i = 1; i <= 3; i++) {
        repo.items.add(_expense('$i', payee: 'Vendor $i'));
      }
      await _pump(tester, repo);
      expect(find.text('Vendor 1'), findsOneWidget);
      expect(find.text('Vendor 3'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('expenses-load-more')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('expenses-load-more')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Vendor 3'), 200);
      expect(find.text('Vendor 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('expenses-load-more')), findsNothing);
    });

    testWidgets('a server failure is shown with a retry, not a blank page', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()
        ..failWith = const NetworkFailure('Check your connection.');
      await _pump(tester, repo);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('the form', () {
    testWidgets('missing and bad values are explained and nothing is sent', (
      tester,
    ) async {
      final repo = FakeExpenseRepository();
      await _pump(tester, repo, start: '/expenses/new');
      await tester.enterText(
        find.byKey(const ValueKey('expense-amount')),
        '12.345',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('expense-save')));
      await tester.tap(find.byKey(const ValueKey('expense-save')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a category.'), findsOneWidget);
      expect(find.textContaining('up to 2 decimals'), findsOneWidget);
      expect(repo.created, isEmpty);
    });

    testWidgets(
      'a valid form sends minor units, the school day and one request id',
      (tester) async {
        final repo = FakeExpenseRepository();
        await _pump(tester, repo, start: '/expenses/new');
        await tester.tap(find.byKey(const ValueKey('expense-category')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Other').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('expense-amount')),
          '1,250.50',
        );
        await tester.enterText(
          find.byKey(const ValueKey('expense-payee')),
          '  Raj Hardware ',
        );
        await tester.ensureVisible(find.byKey(const ValueKey('expense-save')));
        await tester.tap(find.byKey(const ValueKey('expense-save')));
        await tester.pumpAndSettle();
        expect(repo.created, hasLength(1));
        final c = repo.created.single;
        expect(c.amountMinor, 125050);
        expect(c.categoryId, 'cat_other');
        expect(c.payee, 'Raj Hardware');
        expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(c.expenseDate), isTrue);
        expect(repo.requestIds.single, matches(RegExp(r'^[a-z0-9]{24}$')));
        expect(
          find.text('Raj Hardware'),
          findsOneWidget,
          reason: 'back on the list',
        );
      },
    );

    testWidgets('after a failed save the retry uses the SAME request id', (
      tester,
    ) async {
      final repo = FakeExpenseRepository();
      await _pump(tester, repo, start: '/expenses/new');
      await tester.tap(find.byKey(const ValueKey('expense-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expense-amount')),
        '10',
      );
      repo.failWith = const NetworkFailure('Offline');
      await tester.ensureVisible(find.byKey(const ValueKey('expense-save')));
      await tester.tap(find.byKey(const ValueKey('expense-save')));
      await tester.pumpAndSettle();
      expect(repo.created, isEmpty);
      repo.failWith = null;
      await tester.tap(find.byKey(const ValueKey('expense-save')));
      await tester.pumpAndSettle();
      expect(repo.requestIds, hasLength(1));
      expect(repo.created, hasLength(1));
    });

    testWidgets('editing a draft loads it and sends the version it saw', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()..items.add(_expense('1'));
      await _pump(tester, repo, start: '/expenses/1/edit');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('expense-amount')))
            .controller!
            .text,
        '1250.00',
      );
      await tester.enterText(
        find.byKey(const ValueKey('expense-amount')),
        '99',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('expense-save')));
      await tester.tap(find.byKey(const ValueKey('expense-save')));
      await tester.pumpAndSettle();
      expect(repo.updated.single.id, '1');
      expect(repo.updated.single.input.amountMinor, 9900);
    });
  });

  group('the detail', () {
    testWidgets('its creator can edit a draft; nobody edits a paid expense', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()
        ..items.addAll([
          _expense('1'),
          _expense('2', status: ExpenseStatus.paid),
        ]);
      await _pump(tester, repo, start: '/expenses/1');
      expect(find.byKey(const ValueKey('expense-edit')), findsOneWidget);
      await _pump(tester, repo, start: '/expenses/2');
      expect(find.byKey(const ValueKey('expense-edit')), findsNothing);
    });

    testWidgets("finance cannot edit someone else's draft; an admin can", (
      tester,
    ) async {
      final repo = FakeExpenseRepository()
        ..items.add(_expense('1', createdBy: 'someone-else'));
      await _pump(tester, repo, start: '/expenses/1');
      expect(find.byKey(const ValueKey('expense-edit')), findsNothing);
      await _pump(
        tester,
        repo,
        role: UserRole.branchAdmin,
        start: '/expenses/1',
      );
      expect(find.byKey(const ValueKey('expense-edit')), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('a school admin changes approval and saves with the version', (
      tester,
    ) async {
      final repo = FakeExpenseRepository(
        current: const ExpenseSettings(version: 4),
      );
      await _pump(
        tester,
        repo,
        role: UserRole.schoolAdmin,
        start: '/expenses/settings',
      );
      final save = find.byKey(const ValueKey('expense-settings-save'));
      expect(
        tester.widget<FilledButton>(save).onPressed,
        isNull,
        reason: 'nothing changed yet',
      );
      await tester.tap(find.byKey(const ValueKey('expense-approval-required')));
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.savedSettings.single.approvalRequired, isFalse);
      expect(repo.current.version, 5);
    });

    testWidgets(
      'a person who cannot manage sees the settings but no save button',
      (tester) async {
        final repo = FakeExpenseRepository(canManage: false);
        await _pump(tester, repo, start: '/expenses/settings');
        expect(
          find.text('Only a school administrator can change these.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('expense-settings-save')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('expense-category-add')),
          findsNothing,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.byKey(const ValueKey('expense-approval-required')),
              )
              .onChanged,
          isNull,
        );
      },
    );

    testWidgets(
      'a duplicate category name is refused before anything is sent',
      (tester) async {
        final repo = FakeExpenseRepository();
        await _pump(
          tester,
          repo,
          role: UserRole.schoolAdmin,
          start: '/expenses/settings',
        );
        await tester.tap(find.byKey(const ValueKey('expense-category-add')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('expense-category-name')),
          ' other ',
        );
        await tester.tap(find.byKey(const ValueKey('expense-category-save')));
        await tester.pumpAndSettle();
        expect(
          find.text('A category with that name already exists.'),
          findsOneWidget,
        );
        expect(repo.stored.length, 2);
        await tester.enterText(
          find.byKey(const ValueKey('expense-category-name')),
          'Garden',
        );
        await tester.tap(find.byKey(const ValueKey('expense-category-save')));
        await tester.pumpAndSettle();
        expect(repo.stored.map((c) => c.name), contains('Garden'));
      },
    );

    testWidgets('the built-in Salaries category has no rename or switch', (
      tester,
    ) async {
      final repo = FakeExpenseRepository();
      await _pump(
        tester,
        repo,
        role: UserRole.schoolAdmin,
        start: '/expenses/settings',
      );
      final salaries = find.byKey(
        const ValueKey('expense-category-cat_salaries'),
      );
      expect(salaries, findsOneWidget);
      expect(
        find.descendant(of: salaries, matching: find.byType(Switch)),
        findsNothing,
      );
      expect(find.text('Built in'), findsOneWidget);
    });
  });

  group('receipts', () {
    final pdf = [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34];

    List<Override> pickerAndStore(
      FakeReceiptStore store,
      PickedDocument? picked,
    ) => [
      expenseReceiptStoreProvider.overrideWithValue(store),
      documentPickerProvider.overrideWithValue(_Picker(picked)),
    ];

    testWidgets('attaching walks the three steps and shows the receipt', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()..items.add(_expense('1'));
      final store = FakeReceiptStore();
      await _pump(
        tester,
        repo,
        start: '/expenses/1',
        extra: pickerAndStore(store, PickedDocument('bill.pdf', pdf)),
      );
      expect(find.text('No receipt attached.'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('receipt-attach')));
      await tester.tap(find.byKey(const ValueKey('receipt-attach')));
      await tester.pumpAndSettle();
      expect(repo.receiptRequests.single.contentType, 'application/pdf');
      expect(repo.receiptRequests.single.sizeBytes, pdf.length);
      expect(
        repo.receiptRequests.single.requestId,
        matches(RegExp(r'^[a-z0-9]{24}$')),
      );
      expect(store.uploads.single, contains('/expenseReceipts/1/r1/'));
      expect(repo.receiptConfirms, ['r1']);
      expect(find.text('bill.pdf'), findsOneWidget);
    });

    testWidgets(
      'a file that is not allowed is refused before anything is sent',
      (tester) async {
        final repo = FakeExpenseRepository()..items.add(_expense('1'));
        final store = FakeReceiptStore();
        for (final bad in [
          PickedDocument('page.html', [1, 2, 3]),
          PickedDocument('huge.pdf', List.filled(5 * 1024 * 1024 + 1, 0)),
          PickedDocument('empty.png', const []),
        ]) {
          await _pump(
            tester,
            repo,
            start: '/expenses/1',
            extra: pickerAndStore(store, bad),
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('receipt-attach')),
          );
          await tester.tap(find.byKey(const ValueKey('receipt-attach')));
          await tester.pumpAndSettle();
        }
        expect(repo.receiptRequests, isEmpty);
        expect(store.uploads, isEmpty);
      },
    );

    testWidgets('a failed upload does not confirm and says why', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()..items.add(_expense('1'));
      final store = FakeReceiptStore()
        ..failWith = const NetworkFailure('Offline');
      await _pump(
        tester,
        repo,
        start: '/expenses/1',
        extra: pickerAndStore(store, PickedDocument('bill.pdf', pdf)),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('receipt-attach')));
      await tester.tap(find.byKey(const ValueKey('receipt-attach')));
      await tester.pumpAndSettle();
      expect(repo.receiptConfirms, isEmpty);
      expect(find.text('No receipt attached.'), findsOneWidget);
    });

    testWidgets('removing asks first, then removes', (tester) async {
      final repo = FakeExpenseRepository()
        ..items.add(_expense('1'))
        ..receiptsByExpense['1'] = [
          const ExpenseReceipt(
            id: 'r9',
            fileName: 'old.png',
            contentType: 'image/png',
            sizeBytes: 2048,
            storagePath: 'p/r9',
          ),
        ];
      await _pump(tester, repo, start: '/expenses/1');
      await tester.ensureVisible(
        find.byKey(const ValueKey('receipt-remove-r9')),
      );
      await tester.tap(find.byKey(const ValueKey('receipt-remove-r9')));
      await tester.pumpAndSettle();
      expect(
        repo.receiptRemovals,
        isEmpty,
        reason: 'not before the person agrees',
      );
      await tester.tap(find.byKey(const ValueKey('receipt-remove-confirm')));
      await tester.pumpAndSettle();
      expect(repo.receiptRemovals, ['r9']);
      expect(find.text('No receipt attached.'), findsOneWidget);
    });

    testWidgets('a paid expense shows its receipts but offers no change', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()
        ..items.add(_expense('1', status: ExpenseStatus.paid))
        ..receiptsByExpense['1'] = [
          const ExpenseReceipt(
            id: 'r9',
            fileName: 'old.png',
            contentType: 'image/png',
            sizeBytes: 2048,
            storagePath: 'p/r9',
          ),
        ];
      await _pump(tester, repo, start: '/expenses/1');
      expect(find.text('old.png'), findsOneWidget);
      expect(find.byKey(const ValueKey('receipt-attach')), findsNothing);
      expect(find.byKey(const ValueKey('receipt-remove-r9')), findsNothing);
    });

    testWidgets('no more than three receipts: the attach button goes away', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()
        ..items.add(_expense('1'))
        ..receiptsByExpense['1'] = [
          for (var i = 1; i <= 3; i++)
            ExpenseReceipt(
              id: 'r$i',
              fileName: 'f$i.png',
              contentType: 'image/png',
              sizeBytes: 100,
              storagePath: 'p/r$i',
            ),
        ];
      await _pump(tester, repo, start: '/expenses/1');
      expect(find.byKey(const ValueKey('receipt-attach')), findsNothing);
    });

    testWidgets('the list shows how many receipts an expense has', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()
        ..items.add(
          Expense(
            id: '1',
            number: 'EXP-1',
            branchId: 'main',
            categoryId: 'cat_other',
            categoryName: 'Other',
            amountMinor: 100,
            currency: 'INR',
            expenseDate: '2026-11-10',
            status: ExpenseStatus.draft,
            receiptCount: 2,
          ),
        );
      await _pump(tester, repo);
      expect(find.textContaining('📎 2'), findsOneWidget);
    });
  });

  group('workflow', () {
    Future<void> tapKey(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    testWidgets('the maker submits a draft and sees it as submitted', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()..items.add(_expense('1'));
      await _pump(tester, repo, start: '/expenses/1');
      expect(find.byKey(const ValueKey('expense-approve')), findsNothing);
      await tapKey(tester, 'expense-submit');
      expect(repo.steps, ['submit:1']);
      expect(find.text('Submitted'), findsWidgets);
      expect(find.byKey(const ValueKey('expense-submit')), findsNothing);
    });

    testWidgets(
      'a school admin approves someone else\'s expense after confirming',
      (tester) async {
        final repo = FakeExpenseRepository()
          ..items.add(
            _expense(
              '1',
              status: ExpenseStatus.submitted,
              createdBy: 'someone',
            ),
          );
        await _pump(
          tester,
          repo,
          role: UserRole.schoolAdmin,
          start: '/expenses/1',
        );
        await tapKey(tester, 'expense-approve');
        expect(repo.steps, isEmpty, reason: 'not before the person confirms');
        await tester.tap(find.byKey(const ValueKey('expense-approve-confirm')));
        await tester.pumpAndSettle();
        expect(repo.steps, ['approve:1']);
        expect(find.text('Approved'), findsWidgets);
      },
    );

    testWidgets('rejecting needs a real reason and sends it', (tester) async {
      final repo = FakeExpenseRepository()
        ..items.add(
          _expense('1', status: ExpenseStatus.submitted, createdBy: 'someone'),
        );
      await _pump(
        tester,
        repo,
        role: UserRole.schoolAdmin,
        start: '/expenses/1',
      );
      await tapKey(tester, 'expense-reject');
      await tester.enterText(
        find.byKey(const ValueKey('expense-reason')),
        'too short',
      );
      await tester.tap(find.byKey(const ValueKey('expense-reason-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Write at least 10 characters.'), findsOneWidget);
      expect(repo.steps, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('expense-reason')),
        'Please attach the supplier invoice.',
      );
      await tester.tap(find.byKey(const ValueKey('expense-reason-confirm')));
      await tester.pumpAndSettle();
      expect(repo.steps, ['reject:1']);
      expect(
        repo.decisions.single.reason,
        'Please attach the supplier invoice.',
      );
    });

    testWidgets(
      'nobody sees Approve on their own expense, and finance never does',
      (tester) async {
        final mine = FakeExpenseRepository()
          ..items.add(_expense('1', status: ExpenseStatus.submitted));
        await _pump(
          tester,
          mine,
          role: UserRole.schoolAdmin,
          start: '/expenses/1',
        );
        expect(find.byKey(const ValueKey('expense-approve')), findsNothing);
        final other = FakeExpenseRepository()
          ..items.add(
            _expense(
              '1',
              status: ExpenseStatus.submitted,
              createdBy: 'someone',
            ),
          );
        await _pump(
          tester,
          other,
          role: UserRole.finance,
          start: '/expenses/1',
        );
        expect(find.byKey(const ValueKey('expense-approve')), findsNothing);
        expect(find.byKey(const ValueKey('expense-reject')), findsNothing);
      },
    );

    testWidgets(
      'finance marks an approved expense paid: the mode is required',
      (tester) async {
        final repo = FakeExpenseRepository()
          ..items.add(
            _expense('1', status: ExpenseStatus.approved, createdBy: 'someone'),
          );
        await _pump(tester, repo, start: '/expenses/1');
        await tapKey(tester, 'expense-pay');
        await tester.tap(find.byKey(const ValueKey('pay-confirm')));
        await tester.pumpAndSettle();
        expect(find.text('Choose how it was paid.'), findsOneWidget);
        expect(repo.payments, isEmpty);
        await tester.tap(find.byKey(const ValueKey('pay-mode')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('UPI').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('pay-reference')),
          '  UTR123 ',
        );
        await tester.tap(find.byKey(const ValueKey('pay-confirm')));
        await tester.pumpAndSettle();
        expect(repo.payments.single.mode, PaymentMode.upi);
        expect(repo.payments.single.reference, 'UTR123');
        expect(
          repo.payments.single.date,
          matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
        );
        expect(find.text('Paid'), findsWidgets);
      },
    );

    testWidgets('a branch admin cannot pay', (tester) async {
      final repo = FakeExpenseRepository()
        ..items.add(
          _expense('1', status: ExpenseStatus.approved, createdBy: 'someone'),
        );
      await _pump(
        tester,
        repo,
        role: UserRole.branchAdmin,
        start: '/expenses/1',
      );
      expect(find.byKey(const ValueKey('expense-pay')), findsNothing);
    });

    testWidgets(
      'cancelling a submitted expense needs a reason; a draft does not',
      (tester) async {
        final sub = FakeExpenseRepository()
          ..items.add(_expense('1', status: ExpenseStatus.submitted));
        await _pump(tester, sub, start: '/expenses/1');
        await tapKey(tester, 'expense-cancel');
        await tester.tap(find.byKey(const ValueKey('expense-reason-confirm')));
        await tester.pumpAndSettle();
        expect(sub.steps, isEmpty);
        await tester.enterText(
          find.byKey(const ValueKey('expense-reason')),
          'Entered twice by mistake.',
        );
        await tester.tap(find.byKey(const ValueKey('expense-reason-confirm')));
        await tester.pumpAndSettle();
        expect(sub.steps, ['cancel:1']);
        final draft = FakeExpenseRepository()..items.add(_expense('2'));
        await _pump(tester, draft, start: '/expenses/2');
        await tapKey(tester, 'expense-cancel');
        await tester.tap(find.byKey(const ValueKey('expense-reason-confirm')));
        await tester.pumpAndSettle();
        expect(draft.steps, ['cancel:2']);
      },
    );

    testWidgets(
      'a rejected expense shows why and can be reopened by its maker',
      (tester) async {
        final repo = FakeExpenseRepository()
          ..items.add(
            Expense(
              id: '1',
              number: 'EXP-1',
              branchId: 'main',
              categoryId: 'cat_other',
              categoryName: 'Other',
              amountMinor: 100,
              currency: 'INR',
              expenseDate: '2026-11-10',
              status: ExpenseStatus.rejected,
              createdBy: _uid,
              decisionReason: 'Wrong category, please fix.',
            ),
          );
        await _pump(tester, repo, start: '/expenses/1');
        expect(
          find.textContaining('Wrong category, please fix.'),
          findsOneWidget,
        );
        await tapKey(tester, 'expense-reopen');
        expect(repo.steps, ['reopen:1']);
        expect(find.text('Draft'), findsWidgets);
      },
    );

    testWidgets('a paid or cancelled expense offers no action', (tester) async {
      for (final s in [ExpenseStatus.paid, ExpenseStatus.cancelled]) {
        final repo = FakeExpenseRepository()
          ..items.add(_expense('1', status: s));
        await _pump(
          tester,
          repo,
          role: UserRole.schoolAdmin,
          start: '/expenses/1',
        );
        for (final k in [
          'submit',
          'approve',
          'reject',
          'pay',
          'cancel',
          'reopen',
          'edit',
        ]) {
          expect(
            find.byKey(ValueKey('expense-$k')),
            findsNothing,
            reason: '${s.name} $k',
          );
        }
      }
    });

    testWidgets('the history shows each step, who did it and why', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()
        ..items.add(_expense('1', status: ExpenseStatus.approved))
        ..historyEntries.addAll([
          ExpenseHistoryEntry(
            seq: 1,
            action: 'submit',
            from: ExpenseStatus.draft,
            to: ExpenseStatus.submitted,
            actorName: 'Grace Hopper',
            at: DateTime(2026, 11, 10, 9),
          ),
          const ExpenseHistoryEntry(
            seq: 2,
            action: 'approve',
            from: ExpenseStatus.submitted,
            to: ExpenseStatus.approved,
            auto: true,
            reason: 'approval is not required in this school',
          ),
        ]);
      await _pump(tester, repo, start: '/expenses/1');
      await tester.ensureVisible(find.byKey(const ValueKey('expense-history')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-1')), findsOneWidget);
      expect(find.textContaining('Grace Hopper'), findsOneWidget);
      expect(find.text('Approved automatically'), findsOneWidget);
    });

    testWidgets('a refused step is explained and the expense does not change', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()..items.add(_expense('1'));
      await _pump(tester, repo, start: '/expenses/1');
      repo.failWith = const ValidationFailure(
        'A receipt is required for this amount; attach one before submitting.',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('expense-submit')));
      await tester.tap(find.byKey(const ValueKey('expense-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('A receipt is required'), findsOneWidget);
      expect(repo.steps, isEmpty);
      expect(find.byKey(const ValueKey('expense-submit')), findsOneWidget);
    });
  });

  group('reports', () {
    ExpenseReport report({
      bool whole = false,
      bool truncated = false,
      int rows = 3,
    }) => ExpenseReport(
      currency: 'INR',
      fromDate: '2026-11-01',
      toDate: '2026-11-15',
      scope: whole ? 'SCHOOL' : 'BRANCH',
      rows: rows,
      truncated: truncated,
      totals: const ExpenseTotals(
        spentMinor: 450000,
        paidMinor: 400000,
        unpaidApprovedMinor: 50000,
        awaitingApprovalMinor: 70000,
      ),
      byStatus: {
        for (final s in ExpenseStatus.values)
          s: (count: s == ExpenseStatus.paid ? 2 : 0, totalMinor: 0),
      },
      byCategory: const [
        ExpenseBucket(
          label: 'Utilities',
          key: 'cat_u',
          count: 2,
          totalMinor: 300000,
          paidMinor: 300000,
        ),
        ExpenseBucket(
          label: 'Other',
          key: 'cat_o',
          count: 1,
          totalMinor: 150000,
          paidMinor: 100000,
        ),
      ],
      byMonth: const [
        ExpenseBucket(
          label: '2026-11',
          key: '2026-11',
          count: 3,
          totalMinor: 450000,
          paidMinor: 400000,
        ),
      ],
      byBranch: whole
          ? const [
              ExpenseBucket(
                label: 'North',
                key: 'b2',
                count: 2,
                totalMinor: 300000,
                paidMinor: 300000,
              ),
            ]
          : const [],
    );

    testWidgets('shows the totals, the breakdowns and what spend means', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()..reportToReturn = report();
      await _pump(tester, repo, start: '/expenses/reports');
      Finder inCard(String key, String text) => find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.text(text),
      );
      expect(inCard('report-spent', '₹4,500.00'), findsOneWidget);
      expect(inCard('report-paid', '₹4,000.00'), findsOneWidget);
      expect(inCard('report-unpaid', '₹500.00'), findsOneWidget);
      expect(inCard('report-awaiting', '₹700.00'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-by-category')), findsOneWidget);
      expect(find.text('Utilities'), findsOneWidget);
      expect(find.text('2026-11'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-by-branch')), findsNothing);
      expect(
        find.textContaining('Spend counts approved and paid'),
        findsOneWidget,
      );
      expect(repo.reportQueries.single.branchId, 'main');
    });

    testWidgets('an empty period says so and offers no export', (tester) async {
      final repo = FakeExpenseRepository()..reportToReturn = report(rows: 0);
      await _pump(tester, repo, start: '/expenses/reports');
      expect(find.text('No expenses in this period.'), findsOneWidget);
      expect(find.byKey(const ValueKey('report-export')), findsNothing);
    });

    testWidgets('a truncated report says the numbers are partial', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()
        ..reportToReturn = report(truncated: true);
      await _pump(tester, repo, start: '/expenses/reports');
      expect(find.byKey(const ValueKey('report-truncated')), findsOneWidget);
    });

    testWidgets('choosing another range asks for exactly that range', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()..reportToReturn = report();
      await _pump(tester, repo, start: '/expenses/reports');
      await tester.tap(find.byKey(const ValueKey('range-thisYear')));
      await tester.pumpAndSettle();
      expect(repo.reportQueries.last.from, endsWith('-01-01'));
      await tester.tap(find.byKey(const ValueKey('range-lastMonth')));
      await tester.pumpAndSettle();
      expect(repo.reportQueries.last.from, endsWith('-01'));
      expect(repo.reportQueries.length, greaterThanOrEqualTo(3));
    });

    testWidgets('only a school admin can ask for every branch', (tester) async {
      final repo = FakeExpenseRepository()..reportToReturn = report();
      await _pump(tester, repo, start: '/expenses/reports');
      expect(find.byKey(const ValueKey('report-all-branches')), findsNothing);
      final admin = FakeExpenseRepository()
        ..reportToReturn = report(whole: true);
      await _pump(
        tester,
        admin,
        role: UserRole.schoolAdmin,
        start: '/expenses/reports',
      );
      expect(admin.reportQueries.last.branchId, 'main');
      await tester.tap(find.byKey(const ValueKey('report-all-branches')));
      await tester.pumpAndSettle();
      expect(admin.reportQueries.last.branchId, isNull);
      expect(find.byKey(const ValueKey('report-by-branch')), findsOneWidget);
    });

    testWidgets('export saves the CSV under a name that carries the range', (
      tester,
    ) async {
      final repo = FakeExpenseRepository()..reportToReturn = report();
      final saver = _Saver();
      await _pump(
        tester,
        repo,
        start: '/expenses/reports',
        extra: [expenseCsvSaverProvider.overrideWithValue(saver)],
      );
      await tester.ensureVisible(find.byKey(const ValueKey('report-export')));
      await tester.tap(find.byKey(const ValueKey('report-export')));
      await tester.pumpAndSettle();
      expect(repo.exports.single.branchId, 'main');
      expect(
        saver.saved.single.name,
        matches(
          RegExp(r'^expenses_\d{4}-\d{2}-\d{2}_to_\d{4}-\d{2}-\d{2}\.csv$'),
        ),
      );
      expect(saver.saved.single.content, startsWith('number,date'));
      expect(find.text('Saved 1 rows.'), findsOneWidget);
    });

    testWidgets(
      'a capped export tells the person, a cancelled save says nothing was saved',
      (tester) async {
        final repo = FakeExpenseRepository()
          ..reportToReturn = report()
          ..csvCapped = true;
        final saver = _Saver();
        await _pump(
          tester,
          repo,
          start: '/expenses/reports',
          extra: [expenseCsvSaverProvider.overrideWithValue(saver)],
        );
        await tester.ensureVisible(find.byKey(const ValueKey('report-export')));
        await tester.tap(find.byKey(const ValueKey('report-export')));
        await tester.pumpAndSettle();
        expect(find.textContaining('the maximum'), findsOneWidget);
        saver.result = false;
        await tester.pump(const Duration(seconds: 5));
        await tester.tap(find.byKey(const ValueKey('report-export')));
        await tester.pumpAndSettle();
        expect(find.text('Nothing was saved.'), findsOneWidget);
      },
    );

    testWidgets('a failed report offers a retry', (tester) async {
      final repo = FakeExpenseRepository()
        ..failWith = const NetworkFailure('Offline');
      await _pump(tester, repo, start: '/expenses/reports');
      expect(find.text('Retry'), findsOneWidget);
    });

    for (final (name, size, scale) in [
      ('phone', const Size(360, 700), 1.5),
      ('tablet', const Size(800, 1000), 1.0),
    ]) {
      testWidgets('the report fits on a $name at text x$scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final repo = FakeExpenseRepository()
          ..reportToReturn = report(whole: true, truncated: true);
        await _pump(
          tester,
          repo,
          role: UserRole.schoolAdmin,
          start: '/expenses/reports',
          size: size,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('layout of the workflow states', () {
    for (final status in ExpenseStatus.values) {
      testWidgets('${status.name} fits on a phone at text x1.5', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        final repo = FakeExpenseRepository()
          ..items.add(_expense('1', status: status, createdBy: 'someone'))
          ..historyEntries.add(
            const ExpenseHistoryEntry(
              seq: 1,
              action: 'submit',
              from: ExpenseStatus.draft,
              to: ExpenseStatus.submitted,
              actorName: 'A person with a rather long display name',
              reason: 'a long reason that goes on and on for a while',
            ),
          );
        await _pump(
          tester,
          repo,
          role: UserRole.schoolAdmin,
          start: '/expenses/1',
          size: const Size(360, 700),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('layout', () {
    for (final (name, size, scale) in [
      ('phone', const Size(360, 700), 1.5),
      ('tablet', const Size(800, 1000), 1.0),
    ]) {
      for (final path in [
        '/expenses',
        '/expenses/new',
        '/expenses/1',
        '/expenses/settings',
      ]) {
        testWidgets('$path fits on a $name at text x$scale', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearAllTestValues);
          final repo = FakeExpenseRepository()
            ..items.add(
              _expense(
                '1',
                payee: 'A very long vendor name that keeps going on and on',
              ),
            );
          await _pump(
            tester,
            repo,
            role: UserRole.schoolAdmin,
            start: path,
            size: size,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

class _Picker implements DocumentPicker {
  final PickedDocument? picked;
  _Picker(this.picked);

  @override
  Future<PickedDocument?> pick({required bool photoOnly}) async => picked;
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

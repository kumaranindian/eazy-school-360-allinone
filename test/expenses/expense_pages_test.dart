import 'package:eazy_school_360/core/config/app_environment.dart';
import 'package:eazy_school_360/core/config/env_config.dart';
import 'package:eazy_school_360/core/config/env_config_provider.dart';
import 'package:eazy_school_360/core/errors/app_failure.dart';
import 'package:eazy_school_360/core/permissions/user_role.dart';
import 'package:eazy_school_360/features/authentication/domain/app_user.dart';
import 'package:eazy_school_360/features/authentication/presentation/providers/auth_providers.dart';
import 'package:eazy_school_360/features/expenses/domain/expense.dart';
import 'package:eazy_school_360/features/expenses/domain/expense_settings.dart';
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

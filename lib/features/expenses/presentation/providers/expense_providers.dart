import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../users/presentation/providers/user_providers.dart'
    show firebaseStorageProvider;
import '../../data/firebase_expense_repository.dart';
import '../../domain/expense.dart';
import '../../domain/expense_category.dart';
import '../../domain/expense_repository.dart';
import '../../domain/expense_settings.dart';

final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => FirebaseExpenseRepository(),
);

final expenseSettingsProvider = FutureProvider.autoDispose
    .family<({ExpenseSettings settings, bool canManage}), String>(
      (ref, schoolId) =>
          ref.watch(expenseRepositoryProvider).settings(schoolId),
    );

final expenseCategoriesProvider = FutureProvider.autoDispose
    .family<List<ExpenseCategory>, String>(
      (ref, schoolId) =>
          ref.watch(expenseRepositoryProvider).categories(schoolId),
    );

typedef ExpenseListKey = ({
  String schoolId,
  String branchId,
  ExpenseStatus? status,
  String? categoryId,
});

/// The first page of a branch's expenses for one filter. Further pages are
/// fetched by the page itself ("Load more") with the returned cursor.
final expenseListProvider = FutureProvider.autoDispose
    .family<ExpensePage, ExpenseListKey>(
      (ref, key) => ref
          .watch(expenseRepositoryProvider)
          .expenses(
            key.schoolId,
            key.branchId,
            status: key.status,
            categoryId: key.categoryId,
          ),
    );

typedef ExpenseKey = ({String schoolId, String branchId, String expenseId});

final expenseProvider = FutureProvider.autoDispose.family<Expense, ExpenseKey>(
  (ref, k) => ref
      .watch(expenseRepositoryProvider)
      .expense(k.schoolId, k.branchId, k.expenseId),
);

/// Every category including switched-off ones (what a manager sees).
final expenseAllCategoriesProvider = FutureProvider.autoDispose
    .family<List<ExpenseCategory>, String>(
      (ref, schoolId) => ref
          .watch(expenseRepositoryProvider)
          .categories(schoolId, includeInactive: true),
    );

/// The bytes of receipts (Storage). Overridden in tests.
final expenseReceiptStoreProvider = Provider<ExpenseReceiptStore>(
  (ref) =>
      FirebaseExpenseReceiptStore(storage: ref.watch(firebaseStorageProvider)),
);

final expenseReceiptsProvider = FutureProvider.autoDispose
    .family<List<ExpenseReceipt>, ExpenseKey>(
      (ref, k) => ref
          .watch(expenseRepositoryProvider)
          .receipts(k.schoolId, k.branchId, k.expenseId),
    );

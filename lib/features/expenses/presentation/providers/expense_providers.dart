import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/firebase_expense_repository.dart';
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

import 'expense.dart';
import 'expense_category.dart';
import 'expense_settings.dart';

/// Expense data. Every call goes through a Cloud Function: clients have no
/// Firestore rules for expenses, so money and approvals cannot be written
/// (or read around the role and branch checks) from the app.
abstract interface class ExpenseRepository {
  Future<({ExpenseSettings settings, bool canManage})> settings(
    String schoolId,
  );

  /// Returns the new version.
  Future<int> saveSettings(
    String schoolId,
    ExpenseSettings settings, {
    int? baseVersion,
  });

  Future<List<ExpenseCategory>> categories(
    String schoolId, {
    bool includeInactive = false,
  });

  /// Adds (no [categoryId]) or updates a category; returns its id.
  Future<String> saveCategory(
    String schoolId, {
    String? categoryId,
    required String name,
    bool? active,
  });

  /// Records a new draft; returns its id. [clientRequestId] makes a retry
  /// return the first result instead of creating a second expense.
  Future<String> createExpense(
    String schoolId,
    String branchId,
    ExpenseInput input, {
    String? clientRequestId,
  });

  /// Edits a draft; returns the new version.
  Future<int> updateExpense(
    String schoolId,
    String branchId,
    String expenseId,
    ExpenseInput input, {
    int? baseVersion,
  });

  Future<Expense> expense(String schoolId, String branchId, String expenseId);

  /// A page of the branch's expenses, newest date first.
  Future<ExpensePage> expenses(
    String schoolId,
    String branchId, {
    ExpenseStatus? status,
    String? categoryId,
    String? fromDate,
    String? toDate,
    Map<String, dynamic>? cursor,
  });
}

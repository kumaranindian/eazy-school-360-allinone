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

  // ---- receipts (docs/expense-management/, phase E3) ----

  /// Step 1: asks the server to approve an upload; returns where to put it.
  /// A repeated [requestId] returns the first request.
  Future<({String id, String storagePath})> requestReceiptUpload(
    String schoolId,
    String branchId,
    String expenseId, {
    required String fileName,
    required String contentType,
    required int sizeBytes,
    String? requestId,
  });

  /// Step 3: the server checks what was stored and marks the receipt in use.
  Future<void> confirmReceiptUpload(
    String schoolId,
    String branchId,
    String expenseId,
    String receiptId,
  );

  Future<void> removeReceipt(
    String schoolId,
    String branchId,
    String expenseId,
    String receiptId,
  );

  Future<List<ExpenseReceipt>> receipts(
    String schoolId,
    String branchId,
    String expenseId,
  );
}

/// The bytes of receipts (Storage). Behind an interface so tests need no
/// Firebase; Storage rules decide who may write and read.
abstract interface class ExpenseReceiptStore {
  Future<void> upload({
    required String path,
    required List<int> bytes,
    required String contentType,
  });

  Future<List<int>> read(String path);
}

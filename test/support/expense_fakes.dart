import 'package:eazy_school_360/features/expenses/domain/expense.dart';
import 'package:eazy_school_360/features/expenses/domain/expense_category.dart';
import 'package:eazy_school_360/features/expenses/domain/expense_report.dart';
import 'package:eazy_school_360/features/expenses/domain/expense_repository.dart';
import 'package:eazy_school_360/features/expenses/domain/expense_settings.dart';

class FakeExpenseRepository implements ExpenseRepository {
  ExpenseSettings current;
  bool canManage;
  final List<ExpenseCategory> stored;
  Object? failWith;
  final List<ExpenseSettings> savedSettings = [];

  FakeExpenseRepository({
    this.current = const ExpenseSettings(),
    this.canManage = true,
    List<ExpenseCategory>? categories,
  }) : stored =
           categories ??
           [
             const ExpenseCategory(
               id: 'cat_salaries',
               name: 'Salaries',
               system: true,
             ),
             const ExpenseCategory(id: 'cat_other', name: 'Other'),
           ];

  void _maybeFail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<({ExpenseSettings settings, bool canManage})> settings(
    String schoolId,
  ) async {
    _maybeFail();
    return (settings: current, canManage: canManage);
  }

  @override
  Future<int> saveSettings(
    String schoolId,
    ExpenseSettings settings, {
    int? baseVersion,
  }) async {
    _maybeFail();
    savedSettings.add(settings);
    current = ExpenseSettings(
      approvalRequired: settings.approvalRequired,
      allowSelfApproval: settings.allowSelfApproval,
      approverRoles: settings.approverRoles,
      receiptRequiredOverMinor: settings.receiptRequiredOverMinor,
      version: current.version + 1,
    );
    return current.version;
  }

  @override
  Future<List<ExpenseCategory>> categories(
    String schoolId, {
    bool includeInactive = false,
  }) async {
    _maybeFail();
    return [
      for (final c in stored)
        if (includeInactive || c.active) c,
    ];
  }

  @override
  Future<String> saveCategory(
    String schoolId, {
    String? categoryId,
    required String name,
    bool? active,
  }) async {
    _maybeFail();
    if (categoryId == null) {
      final id = 'cat_${stored.length + 1}';
      stored.add(ExpenseCategory(id: id, name: name, active: active ?? true));
      return id;
    }
    final i = stored.indexWhere((c) => c.id == categoryId);
    final c = stored[i];
    stored[i] = ExpenseCategory(
      id: c.id,
      name: c.system ? c.name : name,
      active: active ?? c.active,
      system: c.system,
    );
    return categoryId;
  }

  // ---- expenses ----
  final List<Expense> items = [];
  final List<ExpenseInput> created = [];
  final List<({String id, ExpenseInput input})> updated = [];
  final List<String?> requestIds = [];
  int pageSize = 25;
  String currency = 'INR';
  String uid = 'u1';

  @override
  Future<String> createExpense(
    String schoolId,
    String branchId,
    ExpenseInput input, {
    String? clientRequestId,
  }) async {
    _maybeFail();
    created.add(input);
    requestIds.add(clientRequestId);
    final id = 'x${items.length + 1}';
    items.insert(
      0,
      Expense(
        id: id,
        number: 'EXP-2026-${(items.length + 1).toString().padLeft(5, '0')}',
        branchId: branchId,
        categoryId: input.categoryId,
        categoryName: stored
            .firstWhere(
              (c) => c.id == input.categoryId,
              orElse: () => const ExpenseCategory(id: '', name: 'Other'),
            )
            .name,
        amountMinor: input.amountMinor,
        currency: currency,
        expenseDate: input.expenseDate,
        status: ExpenseStatus.draft,
        payee: input.payee,
        description: input.description,
        paymentMode: input.paymentMode,
        paymentReference: input.paymentReference,
        createdBy: uid,
      ),
    );
    return id;
  }

  @override
  Future<int> updateExpense(
    String schoolId,
    String branchId,
    String expenseId,
    ExpenseInput input, {
    int? baseVersion,
  }) async {
    _maybeFail();
    updated.add((id: expenseId, input: input));
    final i = items.indexWhere((e) => e.id == expenseId);
    final e = items[i];
    items[i] = Expense(
      id: e.id,
      number: e.number,
      branchId: e.branchId,
      categoryId: input.categoryId,
      categoryName: e.categoryName,
      amountMinor: input.amountMinor,
      currency: e.currency,
      expenseDate: input.expenseDate,
      status: e.status,
      payee: input.payee,
      description: input.description,
      paymentMode: input.paymentMode,
      paymentReference: input.paymentReference,
      version: e.version + 1,
      createdBy: e.createdBy,
    );
    return e.version + 1;
  }

  @override
  Future<Expense> expense(
    String schoolId,
    String branchId,
    String expenseId,
  ) async {
    _maybeFail();
    return items.firstWhere((e) => e.id == expenseId);
  }

  final List<({ExpenseStatus? status, String? categoryId})> listQueries = [];

  @override
  Future<ExpensePage> expenses(
    String schoolId,
    String branchId, {
    ExpenseStatus? status,
    String? categoryId,
    String? fromDate,
    String? toDate,
    Map<String, dynamic>? cursor,
  }) async {
    _maybeFail();
    listQueries.add((status: status, categoryId: categoryId));
    final all = [
      for (final e in items)
        if ((status == null || e.status == status) &&
            (categoryId == null || e.categoryId == categoryId))
          e,
    ];
    final start = cursor == null ? 0 : (cursor['at'] as int);
    final end = (start + pageSize).clamp(0, all.length);
    return ExpensePage(
      expenses: all.sublist(start, end),
      nextCursor: end < all.length ? {'at': end} : null,
    );
  }

  // ---- reports ----
  ExpenseReport reportToReturn = const ExpenseReport(
    currency: 'INR',
    fromDate: '2026-11-01',
    toDate: '2026-11-15',
    scope: 'BRANCH',
    rows: 0,
    truncated: false,
    totals: ExpenseTotals(),
    byStatus: {},
    byCategory: [],
    byMonth: [],
    byBranch: [],
  );
  final List<({String? branchId, String from, String to})> reportQueries = [];
  final List<
    ({String? branchId, String from, String to, ExpenseStatus? status})
  >
  exports = [];
  String csvToReturn = 'number,date\nEXP-1,2026-11-10';
  bool csvCapped = false;

  @override
  Future<ExpenseReport> report(
    String schoolId, {
    String? branchId,
    required String fromDate,
    required String toDate,
  }) async {
    _maybeFail();
    reportQueries.add((branchId: branchId, from: fromDate, to: toDate));
    return reportToReturn;
  }

  @override
  Future<({String csv, int rows, bool capped})> exportCsv(
    String schoolId, {
    String? branchId,
    required String fromDate,
    required String toDate,
    ExpenseStatus? status,
  }) async {
    _maybeFail();
    exports.add((
      branchId: branchId,
      from: fromDate,
      to: toDate,
      status: status,
    ));
    return (
      csv: csvToReturn,
      rows: csvToReturn.split('\n').length - 1,
      capped: csvCapped,
    );
  }

  // ---- workflow ----
  final List<String> steps = [];
  final List<({String? reason, bool? approve})> decisions = [];
  final List<({PaymentMode mode, String reference, String? date})> payments =
      [];
  final List<ExpenseHistoryEntry> historyEntries = [];
  ExpenseSettings approvalOff = const ExpenseSettings(approvalRequired: false);

  void _move(String expenseId, ExpenseStatus to) {
    final i = items.indexWhere((e) => e.id == expenseId);
    final e = items[i];
    items[i] = Expense(
      id: e.id,
      number: e.number,
      branchId: e.branchId,
      categoryId: e.categoryId,
      categoryName: e.categoryName,
      amountMinor: e.amountMinor,
      currency: e.currency,
      expenseDate: e.expenseDate,
      status: to,
      payee: e.payee,
      description: e.description,
      paymentMode: e.paymentMode,
      paymentReference: e.paymentReference,
      version: e.version + 1,
      createdBy: e.createdBy,
      receiptCount: e.receiptCount,
    );
  }

  @override
  Future<ExpenseStatus> submitExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    int? baseVersion,
  }) async {
    _maybeFail();
    steps.add('submit:$expenseId');
    final to = current.approvalRequired
        ? ExpenseStatus.submitted
        : ExpenseStatus.approved;
    _move(expenseId, to);
    return to;
  }

  @override
  Future<ExpenseStatus> decideExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    required bool approve,
    String? reason,
    int? baseVersion,
  }) async {
    _maybeFail();
    steps.add('${approve ? 'approve' : 'reject'}:$expenseId');
    decisions.add((reason: reason, approve: approve));
    final to = approve ? ExpenseStatus.approved : ExpenseStatus.rejected;
    _move(expenseId, to);
    return to;
  }

  @override
  Future<ExpenseStatus> payExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    required PaymentMode paymentMode,
    String paymentReference = '',
    String? paidDate,
    int? baseVersion,
  }) async {
    _maybeFail();
    steps.add('pay:$expenseId');
    payments.add((
      mode: paymentMode,
      reference: paymentReference,
      date: paidDate,
    ));
    _move(expenseId, ExpenseStatus.paid);
    return ExpenseStatus.paid;
  }

  @override
  Future<ExpenseStatus> cancelExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    String? reason,
    int? baseVersion,
  }) async {
    _maybeFail();
    steps.add('cancel:$expenseId');
    decisions.add((reason: reason, approve: null));
    _move(expenseId, ExpenseStatus.cancelled);
    return ExpenseStatus.cancelled;
  }

  @override
  Future<ExpenseStatus> reopenExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    int? baseVersion,
  }) async {
    _maybeFail();
    steps.add('reopen:$expenseId');
    _move(expenseId, ExpenseStatus.draft);
    return ExpenseStatus.draft;
  }

  @override
  Future<List<ExpenseHistoryEntry>> history(
    String schoolId,
    String branchId,
    String expenseId,
  ) async {
    _maybeFail();
    return List.of(historyEntries);
  }

  // ---- receipts ----
  final Map<String, List<ExpenseReceipt>> receiptsByExpense = {};
  final List<
    ({String fileName, String contentType, int sizeBytes, String? requestId})
  >
  receiptRequests = [];
  final List<String> receiptConfirms = [];
  final List<String> receiptRemovals = [];

  @override
  Future<({String id, String storagePath})> requestReceiptUpload(
    String schoolId,
    String branchId,
    String expenseId, {
    required String fileName,
    required String contentType,
    required int sizeBytes,
    String? requestId,
  }) async {
    _maybeFail();
    receiptRequests.add((
      fileName: fileName,
      contentType: contentType,
      sizeBytes: sizeBytes,
      requestId: requestId,
    ));
    final id = 'r${receiptRequests.length}';
    return (
      id: id,
      storagePath:
          'schools/$schoolId/branches/$branchId/expenseReceipts/$expenseId/$id/receipt',
    );
  }

  @override
  Future<void> confirmReceiptUpload(
    String schoolId,
    String branchId,
    String expenseId,
    String receiptId,
  ) async {
    _maybeFail();
    receiptConfirms.add(receiptId);
    final req = receiptRequests[int.parse(receiptId.substring(1)) - 1];
    (receiptsByExpense[expenseId] ??= []).add(
      ExpenseReceipt(
        id: receiptId,
        fileName: req.fileName,
        contentType: req.contentType,
        sizeBytes: req.sizeBytes,
        storagePath: 'p/$receiptId',
      ),
    );
  }

  @override
  Future<void> removeReceipt(
    String schoolId,
    String branchId,
    String expenseId,
    String receiptId,
  ) async {
    _maybeFail();
    receiptRemovals.add(receiptId);
    receiptsByExpense[expenseId]?.removeWhere((r) => r.id == receiptId);
  }

  @override
  Future<List<ExpenseReceipt>> receipts(
    String schoolId,
    String branchId,
    String expenseId,
  ) async {
    _maybeFail();
    return List.of(receiptsByExpense[expenseId] ?? const []);
  }
}

class FakeReceiptStore implements ExpenseReceiptStore {
  final Map<String, List<int>> objects = {};
  final List<String> uploads = [];
  Object? failWith;

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    required String contentType,
  }) async {
    if (failWith != null) throw failWith!;
    uploads.add(path);
    objects[path] = bytes;
  }

  @override
  Future<List<int>> read(String path) async => objects[path] ?? const [];
}

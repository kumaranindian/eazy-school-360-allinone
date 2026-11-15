/// An expense record and what a person enters to create or edit one. The
/// server owns the number, currency, status and who created it; the client
/// only ever sends [ExpenseInput].
library;

import '../../../core/permissions/user_role.dart';
import '../../fees/domain/money.dart';
import 'expense_settings.dart';

enum ExpenseStatus {
  draft('DRAFT', 'Draft'),
  submitted('SUBMITTED', 'Submitted'),
  approved('APPROVED', 'Approved'),
  rejected('REJECTED', 'Rejected'),
  paid('PAID', 'Paid'),
  cancelled('CANCELLED', 'Cancelled');

  final String wire;
  final String label;
  const ExpenseStatus(this.wire, this.label);

  static ExpenseStatus fromWire(String? v) => ExpenseStatus.values.firstWhere(
    (s) => s.wire == v,
    orElse: () => ExpenseStatus.draft,
  );
}

enum PaymentMode {
  cash('CASH', 'Cash'),
  bankTransfer('BANK_TRANSFER', 'Bank transfer'),
  upi('UPI', 'UPI'),
  cheque('CHEQUE', 'Cheque'),
  card('CARD', 'Card'),
  other('OTHER', 'Other');

  final String wire;
  final String label;
  const PaymentMode(this.wire, this.label);

  static PaymentMode? fromWire(String? v) {
    for (final m in PaymentMode.values) {
      if (m.wire == v) return m;
    }
    return null;
  }
}

class Expense {
  final String id;
  final String number;
  final String branchId;
  final String categoryId;
  final String categoryName;
  final int amountMinor;
  final String currency;

  /// `yyyy-MM-dd`, a school day (never an instant).
  final String expenseDate;
  final String payee;
  final String description;
  final PaymentMode? paymentMode;
  final String paymentReference;
  final ExpenseStatus status;
  final int version;
  final String? createdBy;
  final String? createdByName;

  /// Receipts in use (maintained by the server).
  final int receiptCount;

  /// Workflow details (empty until the step happens).
  final String? submittedBy;
  final String? decidedByName;
  final String? decisionReason;
  final String? paidDate;
  final String? cancelReason;

  const Expense({
    required this.id,
    required this.number,
    required this.branchId,
    required this.categoryId,
    required this.categoryName,
    required this.amountMinor,
    required this.currency,
    required this.expenseDate,
    required this.status,
    this.payee = '',
    this.description = '',
    this.paymentMode,
    this.paymentReference = '',
    this.version = 1,
    this.createdBy,
    this.createdByName,
    this.receiptCount = 0,
    this.submittedBy,
    this.decidedByName,
    this.decisionReason,
    this.paidDate,
    this.cancelReason,
  });

  factory Expense.fromMap(Map<String, dynamic> m) => Expense(
    id: (m['id'] as String?) ?? '',
    number: (m['number'] as String?) ?? '',
    branchId: (m['branchId'] as String?) ?? '',
    categoryId: (m['categoryId'] as String?) ?? '',
    categoryName: (m['categoryName'] as String?) ?? '',
    amountMinor: (m['amountMinor'] as num?)?.toInt() ?? 0,
    currency: (m['currency'] as String?) ?? '',
    expenseDate: (m['expenseDate'] as String?) ?? '',
    payee: (m['payee'] as String?) ?? '',
    description: (m['description'] as String?) ?? '',
    paymentMode: PaymentMode.fromWire(m['paymentMode'] as String?),
    paymentReference: (m['paymentReference'] as String?) ?? '',
    status: ExpenseStatus.fromWire(m['status'] as String?),
    version: (m['version'] as num?)?.toInt() ?? 1,
    createdBy: m['createdBy'] as String?,
    createdByName: m['createdByName'] as String?,
    receiptCount: (m['receiptCount'] as num?)?.toInt() ?? 0,
    submittedBy: m['submittedBy'] as String?,
    decidedByName: m['decidedByName'] as String?,
    decisionReason: m['decisionReason'] as String?,
    paidDate: m['paidDate'] as String?,
    cancelReason: m['cancelReason'] as String?,
  );

  bool get isDraft => status == ExpenseStatus.draft;

  /// Whether [uid] may edit this expense: only a draft, and only its creator
  /// or an admin (`isAdmin`). The server enforces the same.
  bool canEdit({required String uid, required bool isAdmin}) =>
      isDraft && (createdBy == uid || isAdmin);

  String get amountText => Money.format(amountMinor, currency: currency);

  /// What the list shows as the title.
  String get title => payee.isNotEmpty
      ? payee
      : (description.isNotEmpty ? description : categoryName);
}

/// What a person enters (the part of an expense they control).
class ExpenseInput {
  final String categoryId;
  final int amountMinor;
  final String expenseDate;
  final String payee;
  final String description;
  final PaymentMode? paymentMode;
  final String paymentReference;

  const ExpenseInput({
    required this.categoryId,
    required this.amountMinor,
    required this.expenseDate,
    this.payee = '',
    this.description = '',
    this.paymentMode,
    this.paymentReference = '',
  });

  Map<String, dynamic> toRequest() => {
    'categoryId': categoryId,
    'amountMinor': amountMinor,
    'expenseDate': expenseDate,
    'payee': payee,
    'description': description,
    'paymentMode': paymentMode?.wire,
    'paymentReference': paymentReference,
  };
}

/// Form validation (pure, so it is unit-tested without a widget). The server
/// re-checks everything; this only spares a round trip and words the errors.
abstract final class ExpenseFormRules {
  static const maxPayee = 120;
  static const maxDescription = 500;
  static const maxReference = 60;

  /// [todayKey] is the school's today (`SchoolTime.todayKey()`).
  static ({ExpenseInput? input, Map<String, String> errors}) validate({
    required String? categoryId,
    required String amountText,
    required String currency,
    required String? dateKey,
    required String todayKey,
    String payee = '',
    String description = '',
    PaymentMode? paymentMode,
    String paymentReference = '',
  }) {
    final errors = <String, String>{};
    if (categoryId == null || categoryId.isEmpty) {
      errors['category'] = 'Choose a category.';
    }
    final minor = Money.parseMinor(amountText, currency: currency);
    if (minor == null) {
      errors['amount'] = Money.invalidAmountMessage(currency);
    } else if (minor < 1) {
      errors['amount'] = 'The amount must be more than zero.';
    }
    if (dateKey == null || dateKey.isEmpty) {
      errors['date'] = 'Choose the date of the expense.';
    } else if (dateKey.compareTo(todayKey) > 0) {
      errors['date'] = 'The date cannot be in the future.';
    }
    final p = payee.trim();
    final d = description.trim();
    final r = paymentReference.trim();
    if (p.length > maxPayee) errors['payee'] = 'Up to $maxPayee characters.';
    if (d.length > maxDescription) {
      errors['description'] = 'Up to $maxDescription characters.';
    }
    if (r.length > maxReference) {
      errors['reference'] = 'Up to $maxReference characters.';
    }
    if (errors.isNotEmpty) return (input: null, errors: errors);
    return (
      input: ExpenseInput(
        categoryId: categoryId!,
        amountMinor: minor!,
        expenseDate: dateKey!,
        payee: p,
        description: d,
        paymentMode: paymentMode,
        paymentReference: r,
      ),
      errors: const {},
    );
  }

  /// The amount as typed in an edit field.
  static String amountField(int minor, String currency) =>
      Money.plain(minor, currency: currency);
}

class ExpensePage {
  final List<Expense> expenses;

  /// Pass back to fetch the next page; null when there are no more.
  final Map<String, dynamic>? nextCursor;

  const ExpensePage({required this.expenses, this.nextCursor});

  factory ExpensePage.fromMap(Map<String, dynamic> m) => ExpensePage(
    expenses: [
      for (final e in (m['expenses'] as List? ?? const []))
        Expense.fromMap(Map<String, dynamic>.from(e as Map)),
    ],
    nextCursor: m['nextCursor'] is Map
        ? Map<String, dynamic>.from(m['nextCursor'] as Map)
        : null,
  );
}

/// A receipt attached to an expense (only the metadata; the file itself is in
/// Storage and is read through the signed-in user's own access).
class ExpenseReceipt {
  final String id;
  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String storagePath;

  const ExpenseReceipt({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.storagePath,
  });

  factory ExpenseReceipt.fromMap(Map<String, dynamic> m) => ExpenseReceipt(
    id: (m['id'] as String?) ?? '',
    fileName: (m['fileName'] as String?) ?? '',
    contentType: (m['contentType'] as String?) ?? '',
    sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
    storagePath: (m['storagePath'] as String?) ?? '',
  );

  bool get isImage => contentType.startsWith('image/');
  bool get isPdf => contentType == 'application/pdf';
}

/// What a receipt may be (the same limits as the server and storage.rules).
abstract final class ReceiptRules {
  static const maxBytes = 5 * 1024 * 1024;
  static const maxPerExpense = 3;
  static const _types = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
  };
  static const extensions = ['pdf', 'jpg', 'jpeg', 'png'];

  /// The content type for a file name, or null when it is not allowed.
  static String? contentTypeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return null;
    return _types[fileName.substring(dot + 1).toLowerCase()];
  }

  /// A plain-words problem with a chosen file, or null when it can be sent.
  static String? problem(String fileName, int sizeBytes) {
    if (contentTypeFor(fileName) == null) {
      return 'Choose a PDF, JPEG or PNG file.';
    }
    if (sizeBytes < 1) return 'That file is empty.';
    if (sizeBytes > maxBytes) return 'A receipt can be at most 5 MB.';
    if (fileName.length > 120 || RegExp(r'[\\/\x00-\x1f]').hasMatch(fileName)) {
      return 'Rename the file with a shorter name and no slashes.';
    }
    return null;
  }
}

/// One step in an expense's history (append-only on the server).
class ExpenseHistoryEntry {
  final int seq;
  final String action;
  final ExpenseStatus from;
  final ExpenseStatus to;
  final String? reason;

  /// A step the system took itself (approval switched off for the school).
  final bool auto;
  final String? actorName;
  final String? actorRole;
  final DateTime? at;

  const ExpenseHistoryEntry({
    required this.seq,
    required this.action,
    required this.from,
    required this.to,
    this.reason,
    this.auto = false,
    this.actorName,
    this.actorRole,
    this.at,
  });

  factory ExpenseHistoryEntry.fromMap(Map<String, dynamic> m) =>
      ExpenseHistoryEntry(
        seq: (m['seq'] as num?)?.toInt() ?? 0,
        action: (m['action'] as String?) ?? '',
        from: ExpenseStatus.fromWire(m['from'] as String?),
        to: ExpenseStatus.fromWire(m['to'] as String?),
        reason: m['reason'] as String?,
        auto: m['auto'] == true,
        actorName: m['actorName'] as String?,
        actorRole: m['actorRole'] as String?,
        at: m['atMs'] is num
            ? DateTime.fromMillisecondsSinceEpoch((m['atMs'] as num).toInt())
            : null,
      );

  /// "Submitted", "Approved", ... for the timeline.
  String get label => switch (action) {
    'submit' => 'Submitted',
    'approve' => auto ? 'Approved automatically' : 'Approved',
    'reject' => 'Rejected',
    'pay' => 'Paid',
    'cancel' => 'Cancelled',
    'reopen' => 'Reopened as a draft',
    _ => action,
  };
}

enum ExpenseAction { edit, submit, approve, reject, pay, cancel, reopen }

/// What a person may do to an expense, for showing the right buttons. This
/// mirrors the server (`expense_workflow.js mayAct`), which decides for real:
/// hiding a button is never the guard.
abstract final class ExpenseActions {
  static Set<ExpenseAction> available(
    Expense e, {
    required UserRole role,
    required String uid,
    required ExpenseSettings settings,
  }) {
    final own = e.createdBy == uid;
    final admin = role == UserRole.schoolAdmin || role == UserRole.branchAdmin;
    final maker = own || admin;
    final mine = own || e.submittedBy == uid;
    final mayDecide =
        (role == UserRole.schoolAdmin ||
            (role == UserRole.branchAdmin &&
                settings.approverRoles.contains(UserRole.branchAdmin))) &&
        (!mine || settings.allowSelfApproval);
    final mayPay = role == UserRole.schoolAdmin || role == UserRole.finance;
    final out = <ExpenseAction>{};
    switch (e.status) {
      case ExpenseStatus.draft:
        if (maker) {
          out.addAll({
            ExpenseAction.edit,
            ExpenseAction.submit,
            ExpenseAction.cancel,
          });
        }
      case ExpenseStatus.submitted:
        if (mayDecide) {
          out.addAll({ExpenseAction.approve, ExpenseAction.reject});
        }
        if (admin || own) out.add(ExpenseAction.cancel);
      case ExpenseStatus.approved:
        if (mayPay) out.add(ExpenseAction.pay);
        if (admin) out.add(ExpenseAction.cancel);
      case ExpenseStatus.rejected:
        if (maker) out.add(ExpenseAction.reopen);
      case ExpenseStatus.paid:
      case ExpenseStatus.cancelled:
        break;
    }
    return out;
  }
}

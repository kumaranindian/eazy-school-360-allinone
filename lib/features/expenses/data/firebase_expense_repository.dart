import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../core/config/functions_region.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/errors/error_mapper.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';
import '../domain/expense_repository.dart';
import '../domain/expense_settings.dart';

class FirebaseExpenseRepository implements ExpenseRepository {
  final FirebaseFunctions _functions;

  FirebaseExpenseRepository({FirebaseFunctions? functions})
    : _functions = functions ?? appFunctions();

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final r = await _functions.httpsCallable(name).call(data);
      return (r.data as Map?)?.cast<String, dynamic>() ?? const {};
    } on FirebaseFunctionsException catch (e, st) {
      final cause = (e.details is Map ? (e.details as Map)['cause'] : null)
          ?.toString();
      switch (e.code) {
        case 'invalid-argument':
          throw ValidationFailure(
            cause == null || cause.isEmpty
                ? 'Some details were not accepted. Check and try again.'
                : 'Some details were not accepted ($cause).',
          );
        case 'permission-denied':
          throw const PermissionFailure(
            'You do not have permission to manage expenses here.',
          );
        case 'not-found':
          throw const NotFoundFailure('That item could not be found.');
        case 'aborted':
          throw const ValidationFailure(
            'This was changed by someone else. Reload and try again.',
          );
        case 'already-exists':
          throw const ValidationFailure(
            'A category with that name already exists.',
          );
        case 'failed-precondition':
          throw ValidationFailure(
            cause == null || cause.isEmpty
                ? 'That is not possible right now.'
                : cause,
          );
        default:
          throw mapExceptionToFailure(e, st);
      }
    } catch (e, st) {
      if (e is AppFailure) rethrow;
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<({ExpenseSettings settings, bool canManage})> settings(
    String schoolId,
  ) async {
    final out = await _call('getExpenseSettings', {'schoolId': schoolId});
    return (
      settings: ExpenseSettings.fromMap(
        Map<String, dynamic>.from((out['settings'] as Map?) ?? const {}),
      ),
      canManage: out['canManage'] == true,
    );
  }

  @override
  Future<int> saveSettings(
    String schoolId,
    ExpenseSettings settings, {
    int? baseVersion,
  }) async {
    final out = await _call('saveExpenseSettings', {
      'schoolId': schoolId,
      'settings': settings.toRequest(),
      'baseVersion': ?baseVersion,
    });
    return (out['version'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<List<ExpenseCategory>> categories(
    String schoolId, {
    bool includeInactive = false,
  }) async {
    final out = await _call('listExpenseCategories', {
      'schoolId': schoolId,
      'includeInactive': includeInactive,
    });
    return [
      for (final c in (out['categories'] as List? ?? const []))
        ExpenseCategory.fromMap(Map<String, dynamic>.from(c as Map)),
    ];
  }

  @override
  Future<String> saveCategory(
    String schoolId, {
    String? categoryId,
    required String name,
    bool? active,
  }) async {
    final out = await _call('saveExpenseCategory', {
      'schoolId': schoolId,
      'categoryId': ?categoryId,
      'name': name,
      'active': ?active,
    });
    return (out['id'] as String?) ?? '';
  }

  @override
  Future<String> createExpense(
    String schoolId,
    String branchId,
    ExpenseInput input, {
    String? clientRequestId,
  }) async {
    final out = await _call('createExpense', {
      'schoolId': schoolId,
      'branchId': branchId,
      'expense': input.toRequest(),
      'clientRequestId': ?clientRequestId,
    });
    return (out['id'] as String?) ?? '';
  }

  @override
  Future<int> updateExpense(
    String schoolId,
    String branchId,
    String expenseId,
    ExpenseInput input, {
    int? baseVersion,
  }) async {
    final out = await _call('updateExpense', {
      'schoolId': schoolId,
      'branchId': branchId,
      'expenseId': expenseId,
      'expense': input.toRequest(),
      'baseVersion': ?baseVersion,
    });
    return (out['version'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<Expense> expense(
    String schoolId,
    String branchId,
    String expenseId,
  ) async {
    final out = await _call('getExpense', {
      'schoolId': schoolId,
      'branchId': branchId,
      'expenseId': expenseId,
    });
    return Expense.fromMap(
      Map<String, dynamic>.from((out['expense'] as Map?) ?? const {}),
    );
  }

  @override
  Future<ExpensePage> expenses(
    String schoolId,
    String branchId, {
    ExpenseStatus? status,
    String? categoryId,
    String? fromDate,
    String? toDate,
    Map<String, dynamic>? cursor,
  }) async => ExpensePage.fromMap(
    await _call('listExpenses', {
      'schoolId': schoolId,
      'branchId': branchId,
      'status': ?status?.wire,
      'categoryId': ?categoryId,
      'fromDate': ?fromDate,
      'toDate': ?toDate,
      'cursor': ?cursor,
    }),
  );

  Future<ExpenseStatus> _step(
    String name,
    String schoolId,
    String branchId,
    String expenseId,
    Map<String, dynamic> extra,
  ) async {
    final out = await _call(name, {
      'schoolId': schoolId,
      'branchId': branchId,
      'expenseId': expenseId,
      ...extra,
    });
    return ExpenseStatus.fromWire(out['status'] as String?);
  }

  @override
  Future<ExpenseStatus> submitExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    int? baseVersion,
  }) => _step('submitExpense', schoolId, branchId, expenseId, {
    'baseVersion': ?baseVersion,
  });

  @override
  Future<ExpenseStatus> decideExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    required bool approve,
    String? reason,
    int? baseVersion,
  }) => _step('decideExpense', schoolId, branchId, expenseId, {
    'decision': approve ? 'APPROVE' : 'REJECT',
    'reason': ?reason,
    'baseVersion': ?baseVersion,
  });

  @override
  Future<ExpenseStatus> payExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    required PaymentMode paymentMode,
    String paymentReference = '',
    String? paidDate,
    int? baseVersion,
  }) => _step('payExpense', schoolId, branchId, expenseId, {
    'payment': {
      'paymentMode': paymentMode.wire,
      'paymentReference': paymentReference,
      'paidDate': ?paidDate,
    },
    'baseVersion': ?baseVersion,
  });

  @override
  Future<ExpenseStatus> cancelExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    String? reason,
    int? baseVersion,
  }) => _step('cancelExpense', schoolId, branchId, expenseId, {
    'reason': ?reason,
    'baseVersion': ?baseVersion,
  });

  @override
  Future<ExpenseStatus> reopenExpense(
    String schoolId,
    String branchId,
    String expenseId, {
    int? baseVersion,
  }) => _step('reopenExpense', schoolId, branchId, expenseId, {
    'baseVersion': ?baseVersion,
  });

  @override
  Future<List<ExpenseHistoryEntry>> history(
    String schoolId,
    String branchId,
    String expenseId,
  ) async {
    final out = await _call('getExpenseHistory', {
      'schoolId': schoolId,
      'branchId': branchId,
      'expenseId': expenseId,
    });
    return [
      for (final h in (out['history'] as List? ?? const []))
        ExpenseHistoryEntry.fromMap(Map<String, dynamic>.from(h as Map)),
    ];
  }

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
    final out = await _call('requestExpenseReceiptUpload', {
      'schoolId': schoolId,
      'branchId': branchId,
      'expenseId': expenseId,
      'receipt': {
        'fileName': fileName,
        'contentType': contentType,
        'sizeBytes': sizeBytes,
      },
      'requestId': ?requestId,
    });
    return (
      id: (out['id'] as String?) ?? '',
      storagePath: (out['storagePath'] as String?) ?? '',
    );
  }

  @override
  Future<void> confirmReceiptUpload(
    String schoolId,
    String branchId,
    String expenseId,
    String receiptId,
  ) async {
    await _call('confirmExpenseReceiptUpload', {
      'schoolId': schoolId,
      'branchId': branchId,
      'expenseId': expenseId,
      'receiptId': receiptId,
    });
  }

  @override
  Future<void> removeReceipt(
    String schoolId,
    String branchId,
    String expenseId,
    String receiptId,
  ) async {
    await _call('removeExpenseReceipt', {
      'schoolId': schoolId,
      'branchId': branchId,
      'expenseId': expenseId,
      'receiptId': receiptId,
    });
  }

  @override
  Future<List<ExpenseReceipt>> receipts(
    String schoolId,
    String branchId,
    String expenseId,
  ) async {
    final out = await _call('listExpenseReceipts', {
      'schoolId': schoolId,
      'branchId': branchId,
      'expenseId': expenseId,
    });
    return [
      for (final r in (out['receipts'] as List? ?? const []))
        ExpenseReceipt.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }
}

class FirebaseExpenseReceiptStore implements ExpenseReceiptStore {
  final FirebaseStorage _storage;

  FirebaseExpenseReceiptStore({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  @override
  Future<void> upload({
    required String path,
    required List<int> bytes,
    required String contentType,
  }) async {
    try {
      await _storage
          .ref(path)
          .putData(
            Uint8List.fromList(bytes),
            SettableMetadata(contentType: contentType),
          )
          .timeout(const Duration(minutes: 2));
    } catch (e, st) {
      throw mapExceptionToFailure(e, st);
    }
  }

  @override
  Future<List<int>> read(String path) async {
    try {
      final data = await _storage
          .ref(path)
          .getData(ReceiptRules.maxBytes)
          .timeout(const Duration(minutes: 2));
      if (data == null) {
        throw const NotFoundFailure('That file could not be found.');
      }
      return data;
    } catch (e, st) {
      if (e is AppFailure) rethrow;
      throw mapExceptionToFailure(e, st);
    }
  }
}

import 'package:cloud_functions/cloud_functions.dart';

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
}

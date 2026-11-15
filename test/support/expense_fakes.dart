import 'package:eazy_school_360/features/expenses/domain/expense_category.dart';
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
}

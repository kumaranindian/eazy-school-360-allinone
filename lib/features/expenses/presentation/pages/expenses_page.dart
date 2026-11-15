import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../shared/filters/filter_bar.dart';
import '../../../../shared/filters/filter_field.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/expense.dart';
import '../providers/expense_providers.dart';

/// `/expenses`: the branch's expenses, newest first, with status and category
/// filters. Everyone who may see expenses can read; only people who may
/// record them (`createExpenses`) see the add button.
class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          if (ref
                  .watch(tenantContextProvider)
                  .value
                  ?.can(Permission.viewExpenseReports) ??
              false)
            IconButton(
              key: const ValueKey('expenses-reports'),
              tooltip: 'Reports',
              icon: const Icon(Icons.insights_outlined),
              onPressed: () => context.go('/expenses/reports'),
            ),
          IconButton(
            key: const ValueKey('expenses-settings'),
            tooltip: 'Categories and settings',
            icon: const Icon(Icons.tune),
            onPressed: () => context.go('/expenses/settings'),
          ),
        ],
      ),
      body: StaffBranchScope(
        builder: (context, tenant, schoolId, branchId) => _ExpenseList(
          key: ValueKey('$schoolId/$branchId'),
          schoolId: schoolId,
          branchId: branchId,
          canCreate: tenant.can(Permission.createExpenses),
        ),
      ),
    );
  }
}

class _ExpenseList extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final bool canCreate;

  const _ExpenseList({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.canCreate,
  });

  @override
  ConsumerState<_ExpenseList> createState() => _ExpenseListState();
}

class _ExpenseListState extends ConsumerState<_ExpenseList> {
  ExpenseStatus? _status;
  String? _categoryId;
  final List<Expense> _more = [];
  Map<String, dynamic>? _cursor;
  bool _cursorSet = false;
  bool _loadingMore = false;

  ExpenseListKey get _key => (
    schoolId: widget.schoolId,
    branchId: widget.branchId,
    status: _status,
    categoryId: _categoryId,
  );

  void _resetPaging() {
    _more.clear();
    _cursor = null;
    _cursorSet = false;
  }

  Future<void> _loadMore(Map<String, dynamic> cursor) async {
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(expenseRepositoryProvider)
          .expenses(
            widget.schoolId,
            widget.branchId,
            status: _status,
            categoryId: _categoryId,
            cursor: cursor,
          );
      if (!mounted) return;
      setState(() {
        _more.addAll(page.expenses);
        _cursor = page.nextCursor;
        _cursorSet = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(expenseListProvider(_key));
    final categories =
        ref.watch(expenseCategoriesProvider(widget.schoolId)).value ?? const [];
    return Column(
      children: [
        FilterBar(
          fieldsBuilder: () => [
            FilterField.dropdown<ExpenseStatus>(
              label: 'Status',
              value: _status,
              options: [
                (null, 'All statuses'),
                for (final s in ExpenseStatus.values) (s, s.label),
              ],
              onChanged: (v) => setState(() {
                _status = v;
                _resetPaging();
              }),
            ),
            FilterField.dropdown<String>(
              label: 'Category',
              value: _categoryId,
              options: [
                (null, 'All categories'),
                for (final c in categories) (c.id, c.name),
              ],
              onChanged: (v) => setState(() {
                _categoryId = v;
                _resetPaging();
              }),
            ),
          ],
        ),
        Expanded(
          child: page.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(expenseListProvider(_key)),
            ),
            data: (first) {
              final rows = [...first.expenses, ..._more];
              final cursor = _cursorSet ? _cursor : first.nextCursor;
              if (rows.isEmpty) {
                return EmptyView(
                  icon: Icons.receipt_long_outlined,
                  message: _status == null && _categoryId == null
                      ? 'No expenses recorded yet.'
                      : 'No expenses match these filters.',
                  action: widget.canCreate
                      ? FilledButton.icon(
                          key: const ValueKey('expenses-add-empty'),
                          onPressed: () => context.go('/expenses/new'),
                          icon: const Icon(Icons.add),
                          label: const Text('Add expense'),
                        )
                      : null,
                );
              }
              return Stack(
                children: [
                  ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      96,
                    ),
                    itemCount: rows.length + (cursor == null ? 0 : 1),
                    itemBuilder: (context, i) {
                      if (i == rows.length) {
                        return Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Center(
                            child: OutlinedButton(
                              key: const ValueKey('expenses-load-more'),
                              onPressed: _loadingMore
                                  ? null
                                  : () => _loadMore(cursor!),
                              child: Text(
                                _loadingMore ? 'Loading…' : 'Load more',
                              ),
                            ),
                          ),
                        );
                      }
                      return _ExpenseTile(expense: rows[i]);
                    },
                  ),
                  if (widget.canCreate)
                    Positioned(
                      right: AppSpacing.md,
                      bottom: AppSpacing.md,
                      child: FloatingActionButton.extended(
                        key: const ValueKey('expenses-add'),
                        onPressed: () => context.go('/expenses/new'),
                        icon: const Icon(Icons.add),
                        label: const Text('Add expense'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final Expense expense;

  const _ExpenseTile({required this.expense});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      key: ValueKey('expense-${expense.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ListTile(
        title: Text(
          expense.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${expense.number} · ${expense.categoryName} · '
          '${SchoolTime.formatKey(expense.expenseDate)}'
          '${expense.receiptCount > 0 ? ' · 📎 ${expense.receiptCount}' : ''}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(expense.amountText, style: text.titleSmall),
            Text(
              expense.status.label,
              style: text.labelSmall?.copyWith(
                color:
                    expense.status == ExpenseStatus.rejected ||
                        expense.status == ExpenseStatus.cancelled
                    ? scheme.error
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        onTap: () => context.go('/expenses/${expense.id}'),
      ),
    );
  }
}

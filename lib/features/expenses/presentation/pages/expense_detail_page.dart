import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/expense.dart';
import '../providers/expense_providers.dart';

/// `/expenses/:id`: one expense, read-only. A draft can be edited by its
/// creator or an admin (the server checks the same).
class ExpenseDetailPage extends ConsumerWidget {
  final String expenseId;

  const ExpenseDetailPage({super.key, required this.expenseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Expense')),
      body: StaffBranchScope(
        showBranchRow: false,
        builder: (context, tenant, schoolId, branchId) {
          final key = (
            schoolId: schoolId,
            branchId: branchId,
            expenseId: expenseId,
          );
          final a = ref.watch(expenseProvider(key));
          return a.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
              message: userMessageFor(e),
              onRetry: () => ref.invalidate(expenseProvider(key)),
            ),
            data: (e) {
              final isAdmin =
                  tenant.role == UserRole.schoolAdmin ||
                  tenant.role == UserRole.branchAdmin;
              final canEdit =
                  tenant.can(Permission.createExpenses) &&
                  e.canEdit(uid: tenant.user.userId, isAdmin: isAdmin);
              return _Body(expense: e, canEdit: canEdit);
            },
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Expense expense;
  final bool canEdit;

  const _Body({required this.expense, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row(String k, String v) => v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: text.labelMedium),
                Text(v, style: text.bodyLarge),
              ],
            ),
          );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(expense.amountText, style: text.headlineSmall),
        Text('${expense.number} · ${expense.status.label}'),
        const SizedBox(height: AppSpacing.md),
        row('Category', expense.categoryName),
        row('Date', SchoolTime.formatKey(expense.expenseDate)),
        row('Paid to', expense.payee),
        row('Details', expense.description),
        row('Payment mode', expense.paymentMode?.label ?? ''),
        row('Reference', expense.paymentReference),
        row('Recorded by', expense.createdByName ?? ''),
        if (canEdit)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: FilledButton.icon(
              key: const ValueKey('expense-edit'),
              onPressed: () => context.go('/expenses/${expense.id}/edit'),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit draft'),
            ),
          ),
      ],
    );
  }
}

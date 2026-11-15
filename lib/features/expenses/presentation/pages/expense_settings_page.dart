import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../domain/expense_category.dart';
import '../../domain/expense_settings.dart';
import '../providers/expense_providers.dart';

/// `/expenses/settings`: whether expenses need approval, who approves, and the
/// categories. Anyone who can see expenses can read it; only a school admin
/// changes it (the server checks the same).
class ExpenseSettingsPage extends ConsumerWidget {
  const ExpenseSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolId = ref.watch(tenantContextProvider).value?.user.schoolId;
    return Scaffold(
      appBar: AppBar(title: const Text('Expense settings')),
      body: schoolId == null
          ? const Center(child: CircularProgressIndicator())
          : _Settings(schoolId: schoolId),
    );
  }
}

class _Settings extends ConsumerStatefulWidget {
  final String schoolId;

  const _Settings({required this.schoolId});

  @override
  ConsumerState<_Settings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<_Settings> {
  ExpenseSettings? _draft;
  bool _saving = false;

  void _toast(Object e) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));

  Future<void> _save(ExpenseSettings s) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(expenseRepositoryProvider)
          .saveSettings(widget.schoolId, s, baseVersion: s.version);
      ref.invalidate(expenseSettingsProvider(widget.schoolId));
      if (mounted) {
        setState(() => _draft = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Settings saved.')));
      }
    } catch (e) {
      if (mounted) _toast(e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editCategory([ExpenseCategory? c]) async {
    final existing =
        ref.read(expenseAllCategoriesProvider(widget.schoolId)).value ??
        const <ExpenseCategory>[];
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _CategoryDialog(current: c, existing: existing),
    );
    if (name == null) return;
    try {
      await ref
          .read(expenseRepositoryProvider)
          .saveCategory(widget.schoolId, categoryId: c?.id, name: name);
      ref.invalidate(expenseAllCategoriesProvider(widget.schoolId));
      ref.invalidate(expenseCategoriesProvider(widget.schoolId));
    } catch (e) {
      if (mounted) _toast(e);
    }
  }

  Future<void> _toggle(ExpenseCategory c, bool active) async {
    try {
      await ref
          .read(expenseRepositoryProvider)
          .saveCategory(
            widget.schoolId,
            categoryId: c.id,
            name: c.name,
            active: active,
          );
      ref.invalidate(expenseAllCategoriesProvider(widget.schoolId));
      ref.invalidate(expenseCategoriesProvider(widget.schoolId));
    } catch (e) {
      if (mounted) _toast(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(expenseSettingsProvider(widget.schoolId));
    if (loaded.hasError) {
      return ErrorView(
        message: userMessageFor(loaded.error!),
        onRetry: () => ref.invalidate(expenseSettingsProvider(widget.schoolId)),
      );
    }
    final data = loaded.value;
    if (data == null) return const Center(child: CircularProgressIndicator());
    final canManage = data.canManage;
    final s = _draft ?? data.settings;
    final cats = ref.watch(expenseAllCategoriesProvider(widget.schoolId));
    final text = Theme.of(context).textTheme;
    final enabled = canManage && !_saving;

    void change(ExpenseSettings next) => setState(() => _draft = next);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (!canManage)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('Only a school administrator can change these.'),
          ),
        Text('Approval', style: text.titleMedium),
        SwitchListTile(
          key: const ValueKey('expense-approval-required'),
          title: const Text('Expenses need approval'),
          subtitle: const Text(
            'When off, a submitted expense is approved at once.',
          ),
          value: s.approvalRequired,
          onChanged: enabled
              ? (v) => change(s.copyWith(approvalRequired: v))
              : null,
        ),
        SwitchListTile(
          key: const ValueKey('expense-self-approval'),
          title: const Text('The person who submitted may also approve'),
          value: s.allowSelfApproval,
          onChanged: enabled && s.approvalRequired
              ? (v) => change(s.copyWith(allowSelfApproval: v))
              : null,
        ),
        CheckboxListTile(
          key: const ValueKey('expense-branch-approver'),
          title: const Text('Branch administrators can approve'),
          subtitle: const Text('School administrators can always approve.'),
          value: s.approverRoles.contains(UserRole.branchAdmin),
          onChanged: enabled && s.approvalRequired
              ? (v) => change(
                  s.copyWith(
                    approverRoles: [
                      UserRole.schoolAdmin,
                      if (v == true) UserRole.branchAdmin,
                    ],
                  ),
                )
              : null,
        ),
        if (canManage)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const ValueKey('expense-settings-save'),
              onPressed: _draft == null || _saving ? null : () => _save(s),
              child: Text(_saving ? 'Saving…' : 'Save settings'),
            ),
          ),
        const Divider(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(child: Text('Categories', style: text.titleMedium)),
            if (canManage)
              TextButton.icon(
                key: const ValueKey('expense-category-add'),
                onPressed: () => _editCategory(),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
          ],
        ),
        cats.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ErrorView(
            message: userMessageFor(e),
            onRetry: () =>
                ref.invalidate(expenseAllCategoriesProvider(widget.schoolId)),
          ),
          data: (list) => Column(
            children: [
              for (final c in list)
                ListTile(
                  key: ValueKey('expense-category-${c.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name),
                  subtitle: c.system ? const Text('Built in') : null,
                  trailing: canManage && !c.system
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rename',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editCategory(c),
                            ),
                            Switch(
                              value: c.active,
                              onChanged: (v) => _toggle(c, v),
                            ),
                          ],
                        )
                      : null,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  final ExpenseCategory? current;
  final List<ExpenseCategory> existing;

  const _CategoryDialog({required this.current, required this.existing});

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current?.name ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.current == null ? 'Add category' : 'Rename category'),
      content: TextField(
        key: const ValueKey('expense-category-name'),
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(labelText: 'Name', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('expense-category-save'),
          onPressed: () {
            final err = ExpenseCategory.validateName(
              _name.text,
              widget.existing,
              exceptId: widget.current?.id,
            );
            if (err != null) {
              setState(() => _error = err);
              return;
            }
            Navigator.pop(context, _name.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

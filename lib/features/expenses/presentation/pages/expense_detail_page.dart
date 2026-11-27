import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/permissions/user_role.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/error_view.dart';
import 'package:printing/printing.dart';

import '../../../admission/presentation/providers/document_picker.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/expense.dart';
import '../../domain/expense_repository.dart';
import '../../domain/expense_settings.dart';
import '../providers/expense_providers.dart';
import '../../../../shared/dates/school_date_picker.dart';

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
              final settings =
                  ref
                      .watch(expenseSettingsProvider(schoolId))
                      .value
                      ?.settings ??
                  const ExpenseSettings();
              return _Body(
                expense: e,
                canEdit: canEdit,
                actions: ExpenseActions.available(
                  e,
                  role: tenant.role,
                  uid: tenant.user.userId,
                  settings: settings,
                ),
                schoolId: schoolId,
                branchId: branchId,
              );
            },
          );
        },
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  final Expense expense;
  final bool canEdit;
  final Set<ExpenseAction> actions;
  final String schoolId;
  final String branchId;

  const _Body({
    required this.expense,
    required this.canEdit,
    required this.actions,
    required this.schoolId,
    required this.branchId,
  });

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  Expense get e => widget.expense;
  ExpenseKey get _key =>
      (schoolId: widget.schoolId, branchId: widget.branchId, expenseId: e.id);

  /// Runs one workflow step, then refreshes everything that shows the expense.
  Future<void> _run(
    Future<ExpenseStatus> Function(ExpenseRepository repo) step,
    String done,
  ) async {
    setState(() => _busy = true);
    try {
      await step(ref.read(expenseRepositoryProvider));
      ref.invalidate(expenseProvider(_key));
      ref.invalidate(expenseHistoryProvider(_key));
      ref.invalidate(expenseListProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessageFor(err))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(
    (r) => r.submitExpense(
      widget.schoolId,
      widget.branchId,
      e.id,
      baseVersion: e.version,
    ),
    'Submitted.',
  );

  Future<void> _approve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve this expense?'),
        content: Text('${e.number} · ${e.amountText}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            key: const ValueKey('expense-approve-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      (r) => r.decideExpense(
        widget.schoolId,
        widget.branchId,
        e.id,
        approve: true,
        baseVersion: e.version,
      ),
      'Approved.',
    );
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Reject this expense',
        hint: 'Tell the person what to fix',
        action: 'Reject',
        required: true,
      ),
    );
    if (reason == null) return;
    await _run(
      (r) => r.decideExpense(
        widget.schoolId,
        widget.branchId,
        e.id,
        approve: false,
        reason: reason,
        baseVersion: e.version,
      ),
      'Rejected.',
    );
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Cancel this expense',
        hint: 'Why is it being cancelled?',
        action: 'Cancel expense',
        required: !e.isDraft,
      ),
    );
    if (reason == null) return;
    await _run(
      (r) => r.cancelExpense(
        widget.schoolId,
        widget.branchId,
        e.id,
        reason: reason.isEmpty ? null : reason,
        baseVersion: e.version,
      ),
      'Cancelled.',
    );
  }

  Future<void> _reopen() => _run(
    (r) => r.reopenExpense(
      widget.schoolId,
      widget.branchId,
      e.id,
      baseVersion: e.version,
    ),
    'Reopened as a draft.',
  );

  Future<void> _pay() async {
    final p = await showDialog<_Payment>(
      context: context,
      builder: (_) => const _PayDialog(),
    );
    if (p == null) return;
    await _run(
      (r) => r.payExpense(
        widget.schoolId,
        widget.branchId,
        e.id,
        paymentMode: p.mode,
        paymentReference: p.reference,
        paidDate: p.dateKey,
        baseVersion: e.version,
      ),
      'Marked as paid.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final a = widget.actions;
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
    Widget button(
      String key,
      String label,
      IconData icon,
      VoidCallback onTap, {
      bool primary = false,
    }) {
      final child = primary
          ? FilledButton.icon(
              key: ValueKey(key),
              onPressed: _busy ? null : onTap,
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              key: ValueKey(key),
              onPressed: _busy ? null : onTap,
              icon: Icon(icon),
              label: Text(label),
            );
      return child;
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(e.amountText, style: text.headlineSmall),
        Wrap(
          spacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(e.number),
            Chip(
              key: const ValueKey('expense-status'),
              visualDensity: VisualDensity.compact,
              label: Text(e.status.label),
              backgroundColor:
                  e.status == ExpenseStatus.rejected ||
                      e.status == ExpenseStatus.cancelled
                  ? scheme.errorContainer
                  : e.status == ExpenseStatus.paid
                  ? scheme.primaryContainer
                  : null,
            ),
            if (e.isPayroll)
              const Chip(
                key: ValueKey('expense-payroll'),
                visualDensity: VisualDensity.compact,
                label: Text('Payroll'),
              ),
          ],
        ),
        if (e.isPayroll && e.payrollPeriod != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('expense-open-run'),
                onPressed: () => context.go('/payroll/runs/${e.payrollPeriod}'),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(
                  'Open ${periodLabelOf(e.payrollPeriod!)} payroll run',
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (a.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (a.contains(ExpenseAction.submit))
                  button(
                    'expense-submit',
                    'Submit',
                    Icons.send_outlined,
                    _submit,
                    primary: true,
                  ),
                if (a.contains(ExpenseAction.approve))
                  button(
                    'expense-approve',
                    'Approve',
                    Icons.check_circle_outline,
                    _approve,
                    primary: true,
                  ),
                if (a.contains(ExpenseAction.pay))
                  button(
                    'expense-pay',
                    'Mark as paid',
                    Icons.payments_outlined,
                    _pay,
                    primary: true,
                  ),
                if (a.contains(ExpenseAction.reopen))
                  button(
                    'expense-reopen',
                    'Reopen as draft',
                    Icons.undo,
                    _reopen,
                    primary: true,
                  ),
                if (a.contains(ExpenseAction.edit) && widget.canEdit)
                  button(
                    'expense-edit',
                    'Edit draft',
                    Icons.edit_outlined,
                    () => context.go('/expenses/${e.id}/edit'),
                  ),
                if (a.contains(ExpenseAction.reject))
                  button('expense-reject', 'Reject', Icons.block, _reject),
                if (a.contains(ExpenseAction.cancel))
                  button('expense-cancel', 'Cancel', Icons.close, _cancel),
              ],
            ),
          ),
        if ((e.decisionReason ?? '').isNotEmpty &&
            e.status == ExpenseStatus.rejected)
          Card(
            key: const ValueKey('expense-decision-reason'),
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text('Rejected: ${e.decisionReason}'),
            ),
          ),
        row('Category', e.categoryName),
        row('Date', SchoolTime.formatKey(e.expenseDate)),
        row('Paid to', e.payee),
        row('Details', e.description),
        row('Recorded by', e.createdByName ?? ''),
        if (e.status == ExpenseStatus.paid) ...[
          row(
            'Paid on',
            e.paidDate == null ? '' : SchoolTime.formatKey(e.paidDate!),
          ),
          row('Payment mode', e.paymentMode?.label ?? ''),
          row('Reference', e.paymentReference),
        ],
        if ((e.cancelReason ?? '').isNotEmpty)
          row('Cancelled because', e.cancelReason!),
        const Divider(height: AppSpacing.xl),
        _Receipts(
          schoolId: widget.schoolId,
          branchId: widget.branchId,
          expenseId: e.id,
          canChange: widget.canEdit && e.isDraft,
        ),
        const Divider(height: AppSpacing.xl),
        _Timeline(expenseKey: _key),
      ],
    );
  }
}

class _Timeline extends ConsumerWidget {
  final ExpenseKey expenseKey;

  const _Timeline({required this.expenseKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final h = ref.watch(expenseHistoryProvider(expenseKey));
    return Column(
      key: const ValueKey('expense-history'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('History', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        h.when(
          loading: () => const LinearProgressIndicator(),
          error: (err, _) => Text(userMessageFor(err)),
          data: (items) => items.isEmpty
              ? const Text('Nothing has happened to this expense yet.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final x in items)
                      ListTile(
                        key: ValueKey('history-${x.seq}'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.circle, size: 10),
                        title: Text(x.label),
                        subtitle: Text(
                          [
                            if (x.actorName != null && !x.auto) x.actorName!,
                            if (x.at != null) formatInstant(x.at),
                            if ((x.reason ?? '').isNotEmpty && !x.auto)
                              x.reason!,
                          ].join(' · '),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Asks for a reason (required to reject, and to cancel once submitted).
class _ReasonDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String action;
  final bool required;

  const _ReasonDialog({
    required this.title,
    required this.hint,
    required this.action,
    required this.required,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('expense-reason'),
        controller: _c,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: widget.required
              ? widget.hint
              : '${widget.hint} (optional)',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          key: const ValueKey('expense-reason-confirm'),
          onPressed: () {
            final r = _c.text.trim();
            if (widget.required && r.length < 10) {
              setState(() => _error = 'Write at least 10 characters.');
              return;
            }
            if (r.length > 300) {
              setState(() => _error = 'Up to 300 characters.');
              return;
            }
            Navigator.pop(context, r);
          },
          child: Text(widget.action),
        ),
      ],
    );
  }
}

class _Payment {
  final PaymentMode mode;
  final String reference;
  final String dateKey;

  const _Payment(this.mode, this.reference, this.dateKey);
}

class _PayDialog extends StatefulWidget {
  const _PayDialog();

  @override
  State<_PayDialog> createState() => _PayDialogState();
}

class _PayDialogState extends State<_PayDialog> {
  PaymentMode? _mode;
  final _ref = TextEditingController();
  String _date = SchoolTime.todayKey();
  String? _error;

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final today = SchoolTime.today();
    final picked = await showSchoolDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? today,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
    );
    if (picked != null) setState(() => _date = SchoolTime.keyOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mark as paid'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<PaymentMode>(
              key: const ValueKey('pay-mode'),
              value: _mode,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Payment mode',
                errorText: _error,
              ),
              items: [
                for (final m in PaymentMode.values)
                  DropdownMenuItem(value: m, child: Text(m.label)),
              ],
              onChanged: (v) => setState(() => _mode = v),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('pay-reference'),
              controller: _ref,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: Text('Paid on ${SchoolTime.formatKey(_date)}')),
                TextButton(
                  key: const ValueKey('pay-date'),
                  onPressed: _pick,
                  child: const Text('Change'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        FilledButton(
          key: const ValueKey('pay-confirm'),
          onPressed: () {
            if (_mode == null) {
              setState(() => _error = 'Choose how it was paid.');
              return;
            }
            Navigator.pop(context, _Payment(_mode!, _ref.text.trim(), _date));
          },
          child: const Text('Mark as paid'),
        ),
      ],
    );
  }
}

/// The receipts of an expense: view them, and (on a draft the person may edit)
/// attach or remove. Uploading is three steps (ask the server, upload to
/// Storage, confirm); the server checks the stored file before it counts.
class _Receipts extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String expenseId;
  final bool canChange;

  const _Receipts({
    required this.schoolId,
    required this.branchId,
    required this.expenseId,
    required this.canChange,
  });

  @override
  ConsumerState<_Receipts> createState() => _ReceiptsState();
}

class _ReceiptsState extends ConsumerState<_Receipts> {
  bool _busy = false;

  ExpenseKey get _key => (
    schoolId: widget.schoolId,
    branchId: widget.branchId,
    expenseId: widget.expenseId,
  );

  static String _newRequestId() {
    final r = Random.secure();
    return List.generate(
      24,
      (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)],
    ).join();
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _attach() async {
    final picked = await ref
        .read(documentPickerProvider)
        .pick(photoOnly: false);
    if (picked == null || !mounted) return;
    final problem = ReceiptRules.problem(picked.name, picked.bytes.length);
    if (problem != null) {
      _toast(problem);
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(expenseRepositoryProvider);
      final contentType = ReceiptRules.contentTypeFor(picked.name)!;
      final req = await repo.requestReceiptUpload(
        widget.schoolId,
        widget.branchId,
        widget.expenseId,
        fileName: picked.name,
        contentType: contentType,
        sizeBytes: picked.bytes.length,
        requestId: _newRequestId(),
      );
      await ref
          .read(expenseReceiptStoreProvider)
          .upload(
            path: req.storagePath,
            bytes: picked.bytes,
            contentType: contentType,
          );
      await repo.confirmReceiptUpload(
        widget.schoolId,
        widget.branchId,
        widget.expenseId,
        req.id,
      );
      ref.invalidate(expenseReceiptsProvider(_key));
      ref.invalidate(expenseProvider(_key));
      ref.invalidate(expenseListProvider);
    } catch (e) {
      if (mounted) _toast(userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ExpenseReceipt r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this receipt?'),
        content: Text(r.fileName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('receipt-remove-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(expenseRepositoryProvider)
          .removeReceipt(
            widget.schoolId,
            widget.branchId,
            widget.expenseId,
            r.id,
          );
      ref.invalidate(expenseReceiptsProvider(_key));
      ref.invalidate(expenseProvider(_key));
      ref.invalidate(expenseListProvider);
    } catch (e) {
      if (mounted) _toast(userMessageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _view(ExpenseReceipt r) async {
    try {
      final bytes = Uint8List.fromList(
        await ref.read(expenseReceiptStoreProvider).read(r.storagePath),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          key: const ValueKey('receipt-viewer'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(r.fileName, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ),
              Flexible(
                child: SizedBox(
                  width: 600,
                  height: 500,
                  child: r.isImage
                      ? InteractiveViewer(child: Image.memory(bytes))
                      : PdfPreview(
                          build: (_) async => bytes,
                          canChangeOrientation: false,
                          canChangePageFormat: false,
                          canDebug: false,
                        ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) _toast(userMessageFor(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final list = ref.watch(expenseReceiptsProvider(_key));
    return Column(
      key: const ValueKey('expense-receipts'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Receipts', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        list.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(userMessageFor(e)),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (items.isEmpty)
                const Text('No receipt attached.')
              else
                for (final r in items)
                  ListTile(
                    key: ValueKey('receipt-${r.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r.isPdf
                          ? Icons.picture_as_pdf_outlined
                          : Icons.image_outlined,
                    ),
                    title: Text(r.fileName, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${(r.sizeBytes / 1024).ceil()} KB'),
                    onTap: () => _view(r),
                    trailing: widget.canChange
                        ? IconButton(
                            key: ValueKey('receipt-remove-${r.id}'),
                            tooltip: 'Remove',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy ? null : () => _remove(r),
                          )
                        : null,
                  ),
              if (widget.canChange && items.length < ReceiptRules.maxPerExpense)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: OutlinedButton.icon(
                    key: const ValueKey('receipt-attach'),
                    onPressed: _busy ? null : _attach,
                    icon: const Icon(Icons.attach_file),
                    label: Text(_busy ? 'Working…' : 'Attach receipt'),
                  ),
                ),
              if (widget.canChange)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'PDF, JPEG or PNG, up to 5 MB, '
                    '${ReceiptRules.maxPerExpense} per expense.',
                    style: text.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// `2026-11` -> "November 2026" (kept here so expenses need not import payroll).
String periodLabelOf(String period) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final m = period.length >= 7 ? int.tryParse(period.substring(5, 7)) : null;
  return m == null || m < 1 || m > 12
      ? period
      : '${names[m - 1]} ${period.substring(0, 4)}';
}

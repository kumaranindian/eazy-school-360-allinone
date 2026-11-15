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
import '../../../../shared/error/error_view.dart';
import 'package:printing/printing.dart';

import '../../../admission/presentation/providers/document_picker.dart';
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
              return _Body(
                expense: e,
                canEdit: canEdit,
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

class _Body extends StatelessWidget {
  final Expense expense;
  final bool canEdit;
  final String schoolId;
  final String branchId;

  const _Body({
    required this.expense,
    required this.canEdit,
    required this.schoolId,
    required this.branchId,
  });

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
        const Divider(height: AppSpacing.xl),
        _Receipts(
          schoolId: schoolId,
          branchId: branchId,
          expenseId: expense.id,
          canChange: canEdit,
        ),
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
      builder: (_) => AlertDialog(
        title: const Text('Remove this receipt?'),
        content: Text(r.fileName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            key: const ValueKey('receipt-remove-confirm'),
            onPressed: () => Navigator.pop(context, true),
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
        builder: (_) => Dialog(
          key: const ValueKey('receipt-viewer'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(r.fileName, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
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

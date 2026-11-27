import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/regional/regional_providers.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/error_view.dart';
import '../../../fees/domain/money.dart';
import '../../../staff/presentation/widgets/staff_branch_scope.dart';
import '../../domain/expense.dart';
import '../providers/expense_providers.dart';
import '../../../../shared/dates/school_date_picker.dart';

/// `/expenses/new` and `/expenses/:id/edit`: record or change a DRAFT expense.
/// The server owns the number, currency, status and creator; this form only
/// sends [ExpenseInput].
class ExpenseFormPage extends StatelessWidget {
  /// Null to record a new expense.
  final String? expenseId;

  const ExpenseFormPage({super.key, this.expenseId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(expenseId == null ? 'Add expense' : 'Edit expense'),
      ),
      body: StaffBranchScope(
        showBranchRow: expenseId == null,
        builder: (context, tenant, schoolId, branchId) => _Loader(
          key: ValueKey('$schoolId/$branchId/$expenseId'),
          schoolId: schoolId,
          branchId: branchId,
          expenseId: expenseId,
        ),
      ),
    );
  }
}

class _Loader extends ConsumerWidget {
  final String schoolId;
  final String branchId;
  final String? expenseId;

  const _Loader({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.expenseId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(expenseCategoriesProvider(schoolId));
    final existing = expenseId == null
        ? null
        : ref.watch(
            expenseProvider((
              schoolId: schoolId,
              branchId: branchId,
              expenseId: expenseId!,
            )),
          );
    for (final a in [cats, ?existing]) {
      if (a.hasError) {
        return ErrorView(
          message: userMessageFor(a.error!),
          onRetry: () {
            ref.invalidate(expenseCategoriesProvider(schoolId));
            if (expenseId != null) {
              ref.invalidate(
                expenseProvider((
                  schoolId: schoolId,
                  branchId: branchId,
                  expenseId: expenseId!,
                )),
              );
            }
          },
        );
      }
      if (a.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
    }
    return _Form(
      schoolId: schoolId,
      branchId: branchId,
      categories: cats.value!,
      existing: existing?.value,
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final List<dynamic> categories;
  final Expense? existing;

  const _Form({
    required this.schoolId,
    required this.branchId,
    required this.categories,
    required this.existing,
  });

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final TextEditingController _amount;
  late final TextEditingController _payee;
  late final TextEditingController _description;
  late final TextEditingController _reference;
  String? _categoryId;
  String? _dateKey;
  PaymentMode? _mode;
  Map<String, String> _errors = const {};
  bool _saving = false;

  /// One id per opened form: a retry after a dropped connection returns the
  /// first expense instead of creating a second.
  late final String _requestId = _newRequestId();

  static String _newRequestId() {
    final r = Random.secure();
    return List.generate(
      24,
      (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)],
    ).join();
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final currency = ref.read(regionalSettingsProvider).currency;
    _amount = TextEditingController(
      text: e == null ? '' : Money.plain(e.amountMinor, currency: e.currency),
    );
    _payee = TextEditingController(text: e?.payee ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _reference = TextEditingController(text: e?.paymentReference ?? '');
    _categoryId = e?.categoryId;
    _dateKey = e?.expenseDate ?? SchoolTime.todayKey();
    _mode = e?.paymentMode;
    if (currency.isEmpty) _errors = const {};
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _description.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = SchoolTime.today();
    final current = DateTime.tryParse(_dateKey ?? '') ?? today;
    final picked = await showSchoolDatePicker(
      context: context,
      initialDate: current.isAfter(today) ? today : current,
      firstDate: DateTime(today.year - 5, today.month, today.day),
      lastDate: today,
    );
    if (picked != null) setState(() => _dateKey = SchoolTime.keyOf(picked));
  }

  Future<void> _save() async {
    final currency =
        widget.existing?.currency ??
        ref.read(regionalSettingsProvider).currency;
    final r = ExpenseFormRules.validate(
      categoryId: _categoryId,
      amountText: _amount.text,
      currency: currency,
      dateKey: _dateKey,
      todayKey: SchoolTime.todayKey(),
      payee: _payee.text,
      description: _description.text,
      paymentMode: _mode,
      paymentReference: _reference.text,
    );
    setState(() => _errors = r.errors);
    if (r.input == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(expenseRepositoryProvider);
      final e = widget.existing;
      if (e == null) {
        await repo.createExpense(
          widget.schoolId,
          widget.branchId,
          r.input!,
          clientRequestId: _requestId,
        );
      } else {
        await repo.updateExpense(
          widget.schoolId,
          widget.branchId,
          e.id,
          r.input!,
          baseVersion: e.version,
        );
        ref.invalidate(
          expenseProvider((
            schoolId: widget.schoolId,
            branchId: widget.branchId,
            expenseId: e.id,
          )),
        );
      }
      ref.invalidate(expenseListProvider);
      if (mounted) context.go('/expenses');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(userMessageFor(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        widget.existing?.currency ??
        ref.watch(regionalSettingsProvider).currency;
    final active = [
      for (final c in widget.categories)
        if ((c.active as bool) || c.id == _categoryId) c,
    ];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (widget.existing != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              widget.existing!.number,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        DropdownButtonFormField<String>(
          key: const ValueKey('expense-category'),
          isExpanded: true,
          value: _categoryId,
          decoration: InputDecoration(
            labelText: 'Category',
            errorText: _errors['category'],
          ),
          items: [
            for (final c in active)
              DropdownMenuItem<String>(
                value: c.id as String,
                child: Text(c.name as String),
              ),
          ],
          onChanged: _saving ? null : (v) => setState(() => _categoryId = v),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('expense-amount'),
          controller: _amount,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount ($currency)',
            errorText: _errors['amount'],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Date',
            errorText: _errors['date'],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dateKey == null ? '—' : SchoolTime.formatKey(_dateKey!),
                ),
              ),
              TextButton(
                key: const ValueKey('expense-date'),
                onPressed: _saving ? null : _pickDate,
                child: const Text('Change'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('expense-payee'),
          controller: _payee,
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: 'Paid to (optional)',
            errorText: _errors['payee'],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('expense-description'),
          controller: _description,
          enabled: !_saving,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Details (optional)',
            errorText: _errors['description'],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<PaymentMode?>(
          key: const ValueKey('expense-mode'),
          isExpanded: true,
          value: _mode,
          decoration: const InputDecoration(
            labelText: 'Payment mode (optional)',
          ),
          items: [
            const DropdownMenuItem<PaymentMode?>(
              value: null,
              child: Text('Not set'),
            ),
            for (final m in PaymentMode.values)
              DropdownMenuItem<PaymentMode?>(value: m, child: Text(m.label)),
          ],
          onChanged: _saving ? null : (v) => setState(() => _mode = v),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('expense-reference'),
          controller: _reference,
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: 'Reference (optional)',
            errorText: _errors['reference'],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          key: const ValueKey('expense-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save as draft'),
        ),
      ],
    );
  }
}

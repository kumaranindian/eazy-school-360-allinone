import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/regional/currency.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../fees/domain/money.dart';
import '../providers/platform_ops_providers.dart';

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Adds a manual billing record: what Avail404 invoices this school for.
class BillingRecordDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String schoolName;
  final String defaultCurrency;

  const BillingRecordDialog({
    super.key,
    required this.schoolId,
    required this.schoolName,
    required this.defaultCurrency,
  });

  @override
  ConsumerState<BillingRecordDialog> createState() =>
      _BillingRecordDialogState();
}

class _BillingRecordDialogState extends ConsumerState<BillingRecordDialog> {
  final _form = GlobalKey<FormState>();
  final _period = TextEditingController();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  late String _currency =
      Currencies.all.any((c) => c.code == widget.defaultCurrency)
      ? widget.defaultCurrency
      : 'INR';
  DateTime _due = DateTime.now().add(const Duration(days: 14));
  String? _error;

  @override
  void dispose() {
    for (final c in [_period, _amount, _reference, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d != null) setState(() => _due = d);
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final minor = Money.parseMinor(_amount.text, currency: _currency)!;
    setState(() => _error = null);
    final ok = await ref
        .read(platformOpsActionsProvider.notifier)
        .saveBilling(
          schoolId: widget.schoolId,
          period: _period.text,
          amountMinor: minor,
          currency: _currency,
          dueDate: dayKey(_due),
          reference: _reference.text,
          note: _note.text,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(
        () => _error = userMessageFor(
          ref.read(platformOpsActionsProvider).error!,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    return AlertDialog(
      title: Text('Billing record: ${widget.schoolName}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  key: const ValueKey('bill-period'),
                  controller: _period,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Period',
                    hintText: 'Nov 2026, or Annual 2026-27',
                  ),
                  validator: (v) => (v ?? '').trim().length < 2
                      ? 'Say what this bill is for'
                      : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const ValueKey('bill-amount'),
                        controller: _amount,
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Amount'),
                        validator: (v) {
                          final m = Money.parseMinor(
                            v ?? '',
                            currency: _currency,
                          );
                          return m == null || m <= 0
                              ? Money.invalidAmountMessage(_currency)
                              : null;
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 110,
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('bill-currency'),
                        value: _currency,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                        items: [
                          for (final c in Currencies.all)
                            DropdownMenuItem(
                              value: c.code,
                              child: Text(c.code),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(() => _currency = v ?? _currency),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey('bill-due'),
                  onPressed: busy ? null : _pickDue,
                  icon: const Icon(Icons.event_outlined),
                  label: Text('Due ${dayKey(_due)}'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _reference,
                  enabled: !busy,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Invoice reference (optional)',
                  ),
                ),
                TextFormField(
                  controller: _note,
                  enabled: !busy,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('bill-save'),
          onPressed: busy ? null : _save,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// The day a bill was paid (today or earlier).
Future<String?> pickPaidDate(BuildContext context) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: now,
    firstDate: DateTime(now.year - 2),
    lastDate: now,
    helpText: 'Date paid',
  );
  return d == null ? null : dayKey(d);
}

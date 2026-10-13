import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_repositories.dart';
import '../../domain/invoice.dart';
import '../../domain/money.dart';
import '../../domain/payment.dart';
import '../../domain/payment_rules.dart';
import '../providers/fee_providers.dart';

Widget _footer(
  BuildContext context, {
  required bool busy,
  required String action,
  required VoidCallback onSubmit,
}) {
  return Wrap(
    alignment: WrapAlignment.end,
    spacing: AppSpacing.sm,
    children: [
      TextButton(
        onPressed: busy ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy ? null : onSubmit,
        child: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(action),
      ),
    ],
  );
}

/// Collect a payment against one invoice.
///
/// The idempotency key is created once when the dialog opens and reused if
/// the submit is retried (or the button is pressed twice), so the same attempt
/// can never record two payments. Validation here (positive, not above the
/// balance, reference for non-cash) is for good messages — the repository's
/// transaction and `firestore.rules` enforce it again.
class CollectPaymentDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String collectorId;
  final String collectorName;
  final Invoice invoice;

  const CollectPaymentDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.collectorId,
    required this.collectorName,
    required this.invoice,
  });

  @override
  ConsumerState<CollectPaymentDialog> createState() =>
      _CollectPaymentDialogState();
}

class _CollectPaymentDialogState extends ConsumerState<CollectPaymentDialog> {
  final _key = newPaymentKey();
  final _formKey = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: Money.plain(widget.invoice.balanceMinor),
  );
  final _reference = TextEditingController();
  final _methodLabel = TextEditingController();
  final _notes = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  late String _dateKey = FeeDates.todayKey();
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final amount = Money.parseMinor(_amount.text)!;
    final problem = PaymentRules.checkCollect(
      status: widget.invoice.status,
      balanceMinor: widget.invoice.balanceMinor,
      amountMinor: amount,
      method: _method,
      methodLabel: _methodLabel.text,
      referenceNo: _reference.text,
      paymentDateKey: _dateKey,
      todayKey: FeeDates.todayKey(),
      currency: widget.invoice.currency,
    );
    if (problem != null) {
      context.showSnackBar(problem, isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(paymentRepositoryProvider)
          .collectPayment(
            CollectPaymentRequest(
              schoolId: widget.schoolId,
              branchId: widget.branchId,
              invoiceId: widget.invoice.invoiceId,
              paymentId: _key,
              amountMinor: amount,
              method: _method,
              methodLabel: _methodLabel.text,
              referenceNo: _reference.text,
              paymentDateKey: _dateKey,
              notes: _notes.text,
              collectorId: widget.collectorId,
              collectorName: widget.collectorName,
              // Receipt numbering follows the INVOICE's academic year, not
              // whichever year the screen happens to be showing.
              info: InvoiceSchoolInfo(
                schoolName: widget.invoice.schoolName,
                branchName: widget.invoice.branchName,
                academicYearName: widget.invoice.academicYearName,
                academicYearStartYear: widget.invoice.numberYear,
                currency: widget.invoice.currency,
              ),
            ),
          );
      if (mounted) Navigator.of(context).pop(_key);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        context.showSnackBar(userMessageFor(error), isError: true);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_amount, _reference, _methodLabel, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Collect payment', style: context.textStyles.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${invoice.invoiceNumber} · ${invoice.studentName}',
            style: context.textStyles.bodySmall,
          ),
          Text(
            'Balance due: ${Money.format(invoice.balanceMinor, currency: invoice.currency)}',
            style: context.textStyles.titleSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _amount,
            enabled: !_busy,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount (${invoice.currency})',
              helperText:
                  'Partial payments are fine; not more than the balance.',
            ),
            validator: (v) {
              final minor = Money.parseMinor(v ?? '');
              if (minor == null) {
                return 'Enter a valid amount, up to 2 decimals.';
              }
              if (minor <= 0) return 'Enter an amount greater than zero.';
              if (minor > invoice.balanceMinor) {
                return 'More than the balance due.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<PaymentMethod>(
            isExpanded: true,
            value: _method,
            decoration: const InputDecoration(labelText: 'Payment method'),
            items: [
              for (final m in PaymentMethod.values)
                DropdownMenuItem(value: m, child: Text(m.displayName)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _method = v ?? _method),
          ),
          if (_method == PaymentMethod.other) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _methodLabel,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Method name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Name the payment method.' : null,
            ),
          ],
          if (_method.needsReference) ...[
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _reference,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: _method == PaymentMethod.cheque
                    ? 'Cheque number'
                    : 'Transaction / reference number',
              ),
              validator: (v) => (v ?? '').trim().length < 3
                  ? 'Enter the reference number.'
                  : null,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: DateTime(now.year - 1),
                      lastDate: now,
                    );
                    if (picked != null) {
                      setState(() => _dateKey = FeeDates.todayKey(picked));
                    }
                  },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('Payment date: ${FeeDates.display(_dateKey)}'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _notes,
            enabled: !_busy,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: AppSpacing.md),
          _footer(
            context,
            busy: _busy,
            action: 'Record payment',
            onSubmit: _submit,
          ),
        ],
      ),
    );
  }
}

/// Asks for a reason (and optionally an amount) for a sensitive action:
/// waiver, void, reversal/refund.
class ReasonDialog extends StatefulWidget {
  final String title;
  final String? description;
  final String actionLabel;
  final bool destructive;
  final String? amountLabel;
  final int? maxAmountMinor;
  final String currency;
  final List<ReversalKind>? kinds;

  /// Does the work. Throws on failure (shown to the user); the dialog closes on success.
  final Future<void> Function(
    String reason,
    int? amountMinor,
    ReversalKind? kind,
  )
  onConfirm;

  const ReasonDialog({
    super.key,
    required this.title,
    this.description,
    required this.actionLabel,
    this.destructive = false,
    this.amountLabel,
    this.maxAmountMinor,
    this.currency = 'INR',
    this.kinds,
    required this.onConfirm,
  });

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final _amount = TextEditingController(
    text: widget.maxAmountMinor == null
        ? ''
        : Money.plain(widget.maxAmountMinor!),
  );
  late ReversalKind? _kind = widget.kinds?.first;
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm(
        _reason.text.trim(),
        widget.amountLabel == null ? null : Money.parseMinor(_amount.text),
        _kind,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        context.showSnackBar(userMessageFor(error), isError: true);
      }
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: context.textStyles.titleLarge),
          if (widget.description != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(widget.description!),
            ),
          const SizedBox(height: AppSpacing.md),
          if (widget.kinds != null) ...[
            DropdownButtonFormField<ReversalKind>(
              isExpanded: true,
              value: _kind,
              decoration: const InputDecoration(
                labelText: 'Type',
                helperText:
                    'Reversal: recorded in error. Refund: money returned.',
              ),
              items: [
                for (final k in widget.kinds!)
                  DropdownMenuItem(value: k, child: Text(k.displayName)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _kind = v),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (widget.amountLabel != null) ...[
            TextFormField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: widget.amountLabel),
              validator: (v) {
                final minor = Money.parseMinor(v ?? '');
                if (minor == null || minor <= 0) {
                  return 'Enter an amount greater than zero.';
                }
                if (widget.maxAmountMinor != null &&
                    minor > widget.maxAmountMinor!) {
                  return 'More than ${Money.format(widget.maxAmountMinor!, currency: widget.currency)}.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextFormField(
            controller: _reason,
            enabled: !_busy,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Reason (recorded in the audit log)',
            ),
            validator: (v) =>
                (v ?? '').trim().length < 3 ? 'Give a reason.' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: widget.destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.actionLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Convenience used by tests and pages: whether a payment can still be reversed.
bool canReverse(Payment payment) => payment.isActive;

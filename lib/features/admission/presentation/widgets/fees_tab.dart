import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/regional/regional_providers.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../fees/domain/fee_enums.dart' as fees;
import '../../../fees/domain/fee_structure.dart';
import '../../../fees/domain/money.dart';
import '../../../fees/presentation/providers/fee_providers.dart';
import '../../../students/presentation/widgets/parents/parents_ui.dart';
import '../../domain/admission_enquiry.dart';
import '../../domain/admission_fee.dart';
import '../providers/admission_providers.dart';

/// The admission fees of one enquiry: what is asked, what was paid (with the
/// receipt number), what is still due, and refunds. Payments are recorded by
/// hand; nothing is ever shown as paid unless a payment was recorded.
class FeesTab extends ConsumerWidget {
  final AdmissionEnquiry enquiry;
  final EnquiryKey keyData;
  const FeesTab({super.key, required this.enquiry, required this.keyData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fees = ref.watch(enquiryFeesProvider(keyData));
    final payments = ref.watch(enquiryFeePaymentsProvider(keyData));
    final currency = ref.watch(regionalSettingsProvider).currency;
    final tenant = ref.watch(tenantContextProvider).value;
    final canDecide = tenant != null && tenant.can(Permission.decideAdmissions);
    // Fees cannot change once the enquiry is closed or confirmed, except for
    // refunds of money already held.
    final locked = !enquiry.status.isOpen;
    return fees.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ParentsCard(child: Text(userMessageFor(e))),
      data: (list) {
        final byCategory = {for (final f in list) f.category: f};
        final summary = AdmissionFeeSummary.of(list);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ParentsCard(
              child: Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  _Total('Total', summary.amountMinor, currency),
                  _Total('Paid (net)', summary.netPaidMinor, currency),
                  _Total('Balance due', summary.balanceMinor, currency),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final c in FeeCategory.values) ...[
              _FeeCard(
                category: c,
                fee: byCategory[c],
                currency: currency,
                keyData: keyData,
                locked: locked,
                canDecide: canDecide,
                enquiry: enquiry,
              ),
              const SizedBox(height: 12),
            ],
            const ParentsSectionTitle(
              icon: Icons.receipt_long_outlined,
              title: 'Payments and refunds',
            ),
            const SizedBox(height: 8),
            payments.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(userMessageFor(e)),
              data: (p) => p.isEmpty
                  ? const ParentsCard(child: Text('No payments recorded yet.'))
                  : ParentsCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final x in p)
                            ListTile(
                              leading: Icon(
                                x.isRefund
                                    ? Icons.undo_outlined
                                    : Icons.payments_outlined,
                              ),
                              title: Text(
                                '${x.isRefund ? 'Refund' : 'Payment'} · '
                                '${Money.format(x.amountMinor, currency: x.currency)}',
                              ),
                              subtitle: Text(
                                [
                                  x.category.label,
                                  x.method.label,
                                  if (x.receiptNumber != null)
                                    'Receipt ${x.receiptNumber}',
                                  if ((x.referenceNo ?? '').isNotEmpty)
                                    'Ref ${x.referenceNo}',
                                  x.paymentDate,
                                ].join(' · '),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final int minor;
  final String currency;
  const _Total(this.label, this.minor, this.currency);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Text(
        Money.format(minor, currency: currency),
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  );
}

class _FeeCard extends ConsumerWidget {
  final FeeCategory category;
  final AdmissionFee? fee;
  final String currency;
  final EnquiryKey keyData;
  final bool locked;
  final bool canDecide;
  final AdmissionEnquiry enquiry;
  const _FeeCard({
    required this.category,
    required this.fee,
    required this.currency,
    required this.keyData,
    required this.locked,
    required this.canDecide,
    required this.enquiry,
  });

  void _done(BuildContext context, WidgetRef ref, bool ok, String message) {
    ref.invalidate(enquiryFeesProvider(keyData));
    ref.invalidate(enquiryFeePaymentsProvider(keyData));
    if (!context.mounted) return;
    if (ok) {
      context.showSnackBar(message);
    } else {
      final err = ref.read(admissionWriteControllerProvider).error;
      context.showSnackBar(
        err == null ? 'That did not work.' : userMessageFor(err),
        isError: true,
      );
    }
  }

  AdmissionWriteController _c(WidgetRef ref) =>
      ref.read(admissionWriteControllerProvider.notifier);

  Future<void> _set(BuildContext context, WidgetRef ref) async {
    final picked = await showDialog<({int minor, String? structureId})>(
      context: context,
      builder: (_) => _AmountDialog(
        title: '${category.label} amount',
        currency: currency,
        initial: fee?.amountMinor,
        initialStructureId: fee?.feeStructureId,
        keyData: keyData,
        enquiry: enquiry,
      ),
    );
    if (picked == null || !context.mounted) return;
    final ok = await _c(ref).setFee(
      key: keyData,
      category: category,
      amountMinor: picked.minor,
      feeStructureId: picked.structureId,
      baseRevision: fee?.revision,
    );
    if (context.mounted) _done(context, ref, ok, 'Fee saved.');
  }

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final f = fee!;
    final r = await showDialog<AdmissionPaymentInput>(
      context: context,
      builder: (_) => AdmissionPaymentDialog(fee: f),
    );
    if (r == null || !context.mounted) return;
    final receipt = await _c(ref).recordPayment(
      key: keyData,
      category: category,
      requestId: r.requestId,
      amountMinor: r.amountMinor,
      method: r.method,
      referenceNo: r.referenceNo,
      notes: r.notes,
    );
    if (context.mounted) {
      _done(
        context,
        ref,
        receipt != null,
        receipt == null ? '' : 'Payment recorded. Receipt $receipt.',
      );
    }
  }

  Future<void> _refund(BuildContext context, WidgetRef ref) async {
    final f = fee!;
    final r = await showDialog<AdmissionPaymentInput>(
      context: context,
      builder: (_) => AdmissionPaymentDialog(fee: f, refund: true),
    );
    if (r == null || !context.mounted) return;
    final ok = await _c(ref).refund(
      key: keyData,
      category: category,
      requestId: r.requestId,
      amountMinor: r.amountMinor,
      method: r.method,
      reason: r.notes ?? '',
      referenceNo: r.referenceNo,
    );
    if (context.mounted) _done(context, ref, ok, 'Refund recorded.');
  }

  Future<void> _reason(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required Future<bool> Function(String reason) action,
    required String done,
  }) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(title: title),
    );
    if (reason == null || !context.mounted) return;
    final ok = await action(reason);
    if (context.mounted) _done(context, ref, ok, done);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = fee;
    final busy = ref.watch(admissionWriteControllerProvider).isLoading;
    final tone = switch (f?.status) {
      AdmissionFeeStatus.paid => ParentsTone.success,
      AdmissionFeeStatus.waived => ParentsTone.neutral,
      AdmissionFeeStatus.cancelled => ParentsTone.neutral,
      AdmissionFeeStatus.partial => ParentsTone.warning,
      AdmissionFeeStatus.due => ParentsTone.danger,
      null => ParentsTone.neutral,
    };
    return ParentsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ParentsBadge(f?.status.label ?? 'Not set', tone: tone),
            ],
          ),
          if (f != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  'Amount ${Money.format(f.amountMinor, currency: f.currency)}',
                ),
                Text(
                  'Paid ${Money.format(f.netPaidMinor, currency: f.currency)}',
                ),
                if (f.waivedMinor > 0)
                  Text(
                    'Waived ${Money.format(f.waivedMinor, currency: f.currency)}',
                  ),
                Text(
                  'Balance ${Money.format(f.balanceMinor, currency: f.currency)}',
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!locked && (f == null || !f.isCancelled))
                OutlinedButton(
                  onPressed: busy ? null : () => _set(context, ref),
                  child: Text(f == null ? 'Set amount' : 'Change amount'),
                ),
              if (!locked && f != null && f.canTakePayment)
                FilledButton(
                  onPressed: busy ? null : () => _pay(context, ref),
                  child: const Text('Record payment'),
                ),
              if (canDecide && !locked && f != null && f.canTakePayment)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => _reason(
                          context,
                          ref,
                          title: 'Waive the balance',
                          action: (r) => _c(ref).waiveFee(
                            key: keyData,
                            category: category,
                            reason: r,
                          ),
                          done: 'Balance waived.',
                        ),
                  child: const Text('Waive balance'),
                ),
              if (canDecide && f != null && f.netPaidMinor > 0)
                OutlinedButton(
                  onPressed: busy ? null : () => _refund(context, ref),
                  child: const Text('Refund'),
                ),
              if (!locked && f != null && !f.isCancelled && f.netPaidMinor == 0)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _reason(
                          context,
                          ref,
                          title: 'Cancel this fee',
                          action: (r) => _c(ref).cancelFee(
                            key: keyData,
                            category: category,
                            reason: r,
                          ),
                          done: 'Fee cancelled.',
                        ),
                  child: const Text('Cancel fee'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class AdmissionPaymentInput {
  final String requestId;
  final int amountMinor;
  final AdmissionPaymentMethod method;
  final String? referenceNo;
  final String? notes;
  const AdmissionPaymentInput(
    this.requestId,
    this.amountMinor,
    this.method,
    this.referenceNo,
    this.notes,
  );
}

class _AmountDialog extends ConsumerStatefulWidget {
  final String title;
  final String currency;
  final int? initial;
  final String? initialStructureId;
  final EnquiryKey keyData;
  final AdmissionEnquiry enquiry;
  const _AmountDialog({
    required this.title,
    required this.currency,
    required this.keyData,
    required this.enquiry,
    this.initial,
    this.initialStructureId,
  });

  @override
  ConsumerState<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends ConsumerState<_AmountDialog> {
  late final _c = TextEditingController(
    text: widget.initial == null
        ? ''
        : Money.format(
            widget.initial!,
            currency: widget.currency,
          ).replaceAll(RegExp(r'[^0-9.]'), ''),
  );
  String? _structureId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _structureId = widget.initialStructureId;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _choose(String? id, List<FeeStructure> options) {
    setState(() {
      _structureId = id;
      final s = options.where((x) => x.structureId == id).firstOrNull;
      if (s != null) {
        _c.text = Money.format(
          s.amountMinor,
          currency: widget.currency,
        ).replaceAll(RegExp(r'[^0-9.]'), '');
        _error = null;
      }
    });
  }

  void _submit() {
    final minor = Money.parseMinor(_c.text, currency: widget.currency);
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    Navigator.pop(context, (minor: minor, structureId: _structureId));
  }

  @override
  Widget build(BuildContext context) {
    // The branch's active ADMISSION fee structures for this applicant's year
    // (all classes, or this class).
    final options =
        (ref
                    .watch(
                      feeStructuresProvider((
                        schoolId: widget.keyData.schoolId,
                        branchId: widget.keyData.branchId,
                        academicYearId: widget.enquiry.academicYearId,
                      )),
                    )
                    .value ??
                const <FeeStructure>[])
            .where(
              (s) =>
                  s.isActive &&
                  s.category == fees.FeeCategory.admission &&
                  (s.classId == null ||
                      s.classId == widget.enquiry.interestedClassId),
            )
            .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (options.isNotEmpty) ...[
              DropdownButtonFormField<String?>(
                value: options.any((s) => s.structureId == _structureId)
                    ? _structureId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'From a fee structure',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('None: type an amount'),
                  ),
                  for (final s in options)
                    DropdownMenuItem(
                      value: s.structureId,
                      child: Text(
                        '${s.name} · ${Money.format(s.amountMinor, currency: widget.currency)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => _choose(v, options),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (${widget.currency})',
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class AdmissionPaymentDialog extends StatefulWidget {
  final AdmissionFee fee;
  final bool refund;
  const AdmissionPaymentDialog({
    super.key,
    required this.fee,
    this.refund = false,
  });

  @override
  State<AdmissionPaymentDialog> createState() => _AdmissionPaymentDialogState();
}

class _AdmissionPaymentDialogState extends State<AdmissionPaymentDialog> {
  // One id per dialog: a double tap or a retry records the payment once.
  final _requestId = AdmissionWriteController.newRequestId();
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  final _notes = TextEditingController();
  AdmissionPaymentMethod _method = AdmissionPaymentMethod.cash;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final f = widget.fee;
    final minor = Money.parseMinor(_amount.text, currency: f.currency);
    final limit = widget.refund ? f.netPaidMinor : f.balanceMinor;
    if (minor == null || minor <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (minor > limit) {
      setState(
        () => _error = widget.refund
            ? 'That is more than the amount held.'
            : 'That is more than the balance due.',
      );
      return;
    }
    if (_method.needsReference && _ref.text.trim().isEmpty) {
      setState(() => _error = 'A reference is needed for ${_method.label}.');
      return;
    }
    if (widget.refund && _notes.text.trim().length < 3) {
      setState(() => _error = 'Give a reason for the refund.');
      return;
    }
    Navigator.pop(
      context,
      AdmissionPaymentInput(
        _requestId,
        minor,
        _method,
        _ref.text.trim().isEmpty ? null : _ref.text.trim(),
        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.refund ? 'Refund' : 'Record payment'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount (${widget.fee.currency})',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AdmissionPaymentMethod>(
            value: _method,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Method'),
            items: [
              for (final m in AdmissionPaymentMethod.values)
                DropdownMenuItem(value: m, child: Text(m.label)),
            ],
            onChanged: (m) => setState(() => _method = m ?? _method),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ref,
            decoration: InputDecoration(
              labelText: _method.needsReference
                  ? 'Reference (required)'
                  : 'Reference (optional)',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: widget.refund ? 'Reason' : 'Notes (optional)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(widget.refund ? 'Refund' : 'Record'),
      ),
    ],
  );
}

class _ReasonDialog extends StatefulWidget {
  final String title;
  const _ReasonDialog({required this.title});

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      maxLines: 2,
      maxLength: 300,
      decoration: const InputDecoration(labelText: 'Reason'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: _c.text.trim().length < 3
            ? null
            : () => Navigator.pop(context, _c.text.trim()),
        child: const Text('Confirm'),
      ),
    ],
  );
}

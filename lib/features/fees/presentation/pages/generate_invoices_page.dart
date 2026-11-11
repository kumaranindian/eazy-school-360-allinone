import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/billing_period.dart';
import '../../domain/fee_dates.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_planners.dart';
import '../../domain/fee_repositories.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_scope.dart';

/// `/fees/invoices/generate` — bulk invoice generation for a class/section and
/// billing period, in three explicit steps: choose → **preview** (who is
/// billed what, who is skipped and why) → confirm. Re-running after a partial
/// failure is safe: invoices that exist are skipped, never duplicated.
class GenerateInvoicesPage extends StatelessWidget {
  const GenerateInvoicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate invoices')),
      body: FeeScope(builder: (context, fee) => _Generate(fee: fee)),
    );
  }
}

class _Generate extends ConsumerStatefulWidget {
  final FeeContext fee;

  const _Generate({required this.fee});

  @override
  ConsumerState<_Generate> createState() => _GenerateState();
}

class _GenerateState extends ConsumerState<_Generate> {
  String? _classId;
  String? _sectionId;
  FeeFrequency _kind = FeeFrequency.monthly;
  int? _monthIndex;
  int _quarter = 1;
  int _half = 1;
  final _label = TextEditingController();
  String _issueKey = FeeDates.todayKey();

  InvoicePlan? _plan;
  BillingPeriod? _period;
  BillingContext? _billing;
  List<BillableFeeOption> _options = const [];
  Set<String> _selected = {};

  /// Students ticked off in the preview; they get no invoice.
  Set<String> _excluded = {};

  List<ProposedInvoice> get _chosen => [
    for (final p in _plan?.proposals ?? const <ProposedInvoice>[])
      if (!_excluded.contains(p.student.studentId)) p,
  ];

  void _toggleStudent(String studentId, bool on) => setState(() {
    final next = {..._excluded};
    on ? next.remove(studentId) : next.add(studentId);
    _excluded = next;
  });

  void _toggleAllStudents(bool on) => setState(() {
    _excluded = on
        ? <String>{}
        : {for (final p in _plan!.proposals) p.student.studentId};
  });
  bool _loading = false;
  String? _error;
  ({int done, int total})? _progress;
  BulkResult? _result;

  List<(int, int)> get _months {
    final y = widget.fee.year;
    final result = <(int, int)>[];
    var d = DateTime(y.startDate.year, y.startDate.month);
    while (!d.isAfter(DateTime(y.endDate.year, y.endDate.month))) {
      result.add((d.year, d.month));
      d = DateTime(d.year, d.month + 1);
    }
    return result;
  }

  BillingPeriod? _buildPeriod() {
    final year = widget.fee.year.startDate.year;
    switch (_kind) {
      case FeeFrequency.monthly:
        final months = _months;
        final i =
            _monthIndex ??
            months
                .indexWhere(
                  (m) =>
                      m.$1 == SchoolTime.wallNow().year &&
                      m.$2 == SchoolTime.wallNow().month,
                )
                .clamp(0, months.length - 1);
        return BillingPeriod.monthly(months[i].$1, months[i].$2);
      case FeeFrequency.quarterly:
        return BillingPeriod.quarterly(year, _quarter);
      case FeeFrequency.halfYearly:
        return BillingPeriod.halfYearly(year, _half);
      case FeeFrequency.annual:
        return BillingPeriod.annual(year);
      case FeeFrequency.oneTime:
        return BillingPeriod.validateLabel(_label.text) == null
            ? BillingPeriod.oneTime(_label.text)
            : null;
      case FeeFrequency.custom:
        return BillingPeriod.validateLabel(_label.text) == null
            ? BillingPeriod.custom(_label.text)
            : null;
    }
  }

  InvoicePlan _planFor(
    BillingContext billing,
    BillingPeriod period,
    Set<String> selected,
  ) {
    return InvoicePlanner.plan(
      students: billing.students,
      assignmentsByStudent: billing.assignmentsByStudent,
      period: period,
      academicYearId: widget.fee.year.academicYearId,
      issueDateKey: _issueKey,
      existingChargeIds: billing.existingChargeIds,
      existingInvoiceIds: billing.existingInvoiceIds,
      addDays: FeeDates.addDays,
      selectedStructureIds: selected,
    );
  }

  void _toggleFee(String structureId, bool on) {
    final selected = {..._selected};
    on ? selected.add(structureId) : selected.remove(structureId);
    setState(() {
      _selected = selected;
      _plan = _planFor(_billing!, _period!, selected);
    });
  }

  void _toggleAll(bool on) {
    final selected = on
        ? {for (final o in _options) o.structureId}
        : <String>{};
    setState(() {
      _selected = selected;
      _plan = _planFor(_billing!, _period!, selected);
    });
  }

  Future<void> _preview() async {
    final period = _buildPeriod();
    if (period == null) {
      context.showSnackBar(
        BillingPeriod.validateLabel(_label.text) ?? 'Choose a billing period.',
        isError: true,
      );
      return;
    }
    final fee = widget.fee;
    setState(() {
      _loading = true;
      _error = null;
      _plan = null;
      _billing = null;
      _options = const [];
      _excluded = {};
      _result = null;
    });
    try {
      final billing = await ref
          .read(invoiceRepositoryProvider)
          .loadBillingContext(
            schoolId: fee.schoolId,
            branchId: fee.branchId,
            academicYearId: fee.year.academicYearId,
            classId: _classId!,
            sectionId: _sectionId,
            period: period,
          );
      final options = InvoicePlanner.availableFees(
        students: billing.students,
        assignmentsByStudent: billing.assignmentsByStudent,
        period: period,
        academicYearId: fee.year.academicYearId,
        issueDateKey: _issueKey,
        existingChargeIds: billing.existingChargeIds,
      );
      final selected = {for (final o in options) o.structureId};
      final plan = _planFor(billing, period, selected);
      AppLogger.debug(
        'Invoice preview: period=${period.key} kind=${period.kind.wireValue} '
        'students=${billing.students.length} '
        'withAssignments=${billing.assignmentsByStudent.length} '
        'proposals=${plan.proposals.length} skipped=${plan.skipped.length}',
        tag: 'Fees',
      );
      if (!mounted) return;
      setState(() {
        _billing = billing;
        _options = options;
        _selected = selected;
        _plan = plan;
        _period = period;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Invoice preview failed',
        tag: 'Fees',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _error = userMessageFor(error);
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    final chosen = _chosen;
    if (chosen.isEmpty) return;
    final chosenTotal = chosen.fold<int>(0, (s, p) => s + p.payableMinor);
    final fee = widget.fee;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate invoices?'),
        content: Text(
          '${chosen.length} invoices for ${_period!.label} '
          '(${_options.where((o) => _selected.contains(o.structureId)).map((o) => o.name).join(', ')}), '
          'totalling ${Money.format(chosenTotal, currency: fee.currency)}. '
          'Each gets a number and is issued to the student. Issued invoices can be voided only by an authorized user.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _progress = (done: 0, total: chosen.length));
    try {
      final result = await ref
          .read(invoiceRepositoryProvider)
          .generateInvoices(
            schoolId: fee.schoolId,
            branchId: fee.branchId,
            academicYearId: fee.year.academicYearId,
            period: _period!,
            issueDateKey: _issueKey,
            proposals: chosen,
            info: fee.info,
            actorId: fee.userId,
            onProgress: (done, total) {
              if (mounted) {
                setState(() => _progress = (done: done, total: total));
              }
            },
          );
      if (!mounted) return;
      notifyFeeDataChanged(context);
      setState(() {
        _result = result;
        _progress = null;
        _plan = null;
        _billing = null;
        _options = const [];
        _selected = {};
        _excluded = {};
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Invoice generation failed',
        tag: 'Fees',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _progress = null);
      context.showSnackBar(userMessageFor(error), isError: true);
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    final classes = (ref.watch(classesProvider(fee.yearKey)).value ?? const [])
        .where((c) => c.status.wireValue == 'ACTIVE')
        .toList();
    final sections = _classId == null
        ? const []
        : (ref
                      .watch(
                        sectionsProvider((
                          schoolId: fee.schoolId,
                          branchId: fee.branchId,
                          academicYearId: fee.year.academicYearId,
                          classId: _classId!,
                        )),
                      )
                      .value ??
                  const [])
              .where((s) => s.status.wireValue == 'ACTIVE')
              .toList();
    final months = _months;
    final busy = _loading || _progress != null;

    Widget dd<T>(
      String label,
      T? value,
      List<DropdownMenuItem<T>> items,
      ValueChanged<T?>? onChanged, {
      double width = 190,
    }) => SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: items,
        onChanged: busy ? null : onChanged,
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            dd<String>(
              'Class',
              _classId,
              [
                for (final c in classes)
                  DropdownMenuItem(value: c.classId, child: Text(c.name)),
              ],
              (v) => setState(() {
                _classId = v;
                _sectionId = null;
                _plan = null;
              }),
            ),
            dd<String?>(
              'Section',
              sections.any((s) => s.sectionId == _sectionId)
                  ? _sectionId
                  : null,
              [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All sections'),
                ),
                for (final s in sections)
                  DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
              ],
              _classId == null
                  ? null
                  : (v) => setState(() {
                      _sectionId = v;
                      _plan = null;
                    }),
            ),
            dd<FeeFrequency>(
              'Billing period',
              _kind,
              [
                for (final f in FeeFrequency.values)
                  DropdownMenuItem(value: f, child: Text(f.displayName)),
              ],
              (v) => setState(() {
                _kind = v ?? _kind;
                _plan = null;
              }),
            ),
            if (_kind == FeeFrequency.monthly)
              dd<int>(
                'Month',
                _monthIndex ??
                    (months.indexWhere(
                              (m) =>
                                  m.$1 == SchoolTime.wallNow().year &&
                                  m.$2 == SchoolTime.wallNow().month,
                            ) >=
                            0
                        ? months.indexWhere(
                            (m) =>
                                m.$1 == SchoolTime.wallNow().year &&
                                m.$2 == SchoolTime.wallNow().month,
                          )
                        : 0),
                [
                  for (var i = 0; i < months.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        BillingPeriod.monthly(months[i].$1, months[i].$2).label,
                      ),
                    ),
                ],
                (v) => setState(() {
                  _monthIndex = v;
                  _plan = null;
                }),
              ),
            if (_kind == FeeFrequency.quarterly)
              dd<int>(
                'Quarter',
                _quarter,
                [
                  for (var q = 1; q <= 4; q++)
                    DropdownMenuItem(value: q, child: Text('Quarter $q')),
                ],
                (v) => setState(() {
                  _quarter = v ?? 1;
                  _plan = null;
                }),
              ),
            if (_kind == FeeFrequency.halfYearly)
              dd<int>(
                'Half',
                _half,
                [
                  for (var h = 1; h <= 2; h++)
                    DropdownMenuItem(value: h, child: Text('Half $h')),
                ],
                (v) => setState(() {
                  _half = v ?? 1;
                  _plan = null;
                }),
              ),
            if (_kind == FeeFrequency.oneTime || _kind == FeeFrequency.custom)
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _label,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: _kind == FeeFrequency.oneTime
                        ? 'Run name (e.g. Admission 2026)'
                        : 'Period name (e.g. Term 1)',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() => _plan = null),
                ),
              ),
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      final now = SchoolTime.wallNow();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: now,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 1),
                      );
                      if (picked != null && mounted) {
                        setState(() {
                          _issueKey = FeeDates.todayKey(picked);
                          _plan = null;
                        });
                      }
                    },
              icon: const Icon(Icons.event_outlined),
              label: Text('Issue date: ${FeeDates.display(_issueKey)}'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: (_classId == null || busy) ? null : _preview,
            icon: _loading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.visibility_outlined),
            label: const Text('Preview'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_error != null)
          Text(_error!, style: TextStyle(color: context.colors.error)),
        if (_progress != null) ...[
          LinearProgressIndicator(
            value: _progress!.total == 0
                ? null
                : _progress!.done / _progress!.total,
          ),
          const SizedBox(height: 4),
          Text('Generating… ${_progress!.done} of ${_progress!.total}'),
        ],
        if (_result != null)
          _ResultCard(
            result: _result!,
            onViewInvoices: () => context.push('/fees/invoices'),
          ),
        if (_billing != null && _period != null)
          _FeePicker(
            options: _options,
            selected: _selected,
            currency: fee.currency,
            enabled: !busy,
            onToggle: _toggleFee,
            onToggleAll: _toggleAll,
          ),
        if (_plan != null)
          _Preview(
            plan: _plan!,
            currency: fee.currency,
            period: _period!,
            chosen: _chosen,
            excluded: _excluded,
            enabled: !busy,
            onToggleStudent: _toggleStudent,
            onToggleAll: _toggleAllStudents,
            onConfirm: busy ? null : _confirm,
          ),
      ],
    );
  }
}

/// Which fee heads to put on the invoices. Only fees that still have
/// something to bill are listed — one already invoiced to everyone for this
/// period is not offered again.
class _FeePicker extends StatelessWidget {
  final List<BillableFeeOption> options;
  final Set<String> selected;
  final String currency;
  final bool enabled;
  final void Function(String structureId, bool on) onToggle;
  final void Function(bool on) onToggleAll;

  const _FeePicker({
    required this.options,
    required this.selected,
    required this.currency,
    required this.enabled,
    required this.onToggle,
    required this.onToggleAll,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (options.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: EmptyView(
          icon: Icons.task_alt_outlined,
          message:
              'Every fee for this class and period has already been invoiced.',
        ),
      );
    }
    final all = selected.length == options.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text('Fees to invoice', style: text.titleMedium),
            ),
            CheckboxListTile(
              dense: true,
              value: all ? true : (selected.isEmpty ? false : null),
              tristate: true,
              // Partly ticked -> select all; fully ticked -> clear.
              onChanged: enabled ? (_) => onToggleAll(!all) : null,
              title: const Text('Select all'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(height: 1),
            for (final o in options)
              CheckboxListTile(
                dense: true,
                value: selected.contains(o.structureId),
                onChanged: enabled
                    ? (v) => onToggle(o.structureId, v ?? false)
                    : null,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(o.name),
                subtitle: Text(
                  '${o.students} student${o.students == 1 ? '' : 's'} · ${Money.format(o.totalMinor, currency: currency)}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final BulkResult result;
  final VoidCallback onViewInvoices;

  const _ResultCard({required this.result, required this.onViewInvoices});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: result.failed > 0
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${result.created} invoice${result.created == 1 ? '' : 's'} generated.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (result.skippedExisting > 0)
              Text(
                '${result.skippedExisting} already existed and were left unchanged.',
              ),
            if (result.failed > 0) ...[
              Text(
                '${result.failed} could not be generated. Run the preview again to retry only what is missing.',
              ),
              for (final e in result.errors) Text('• $e'),
            ],
            TextButton(
              onPressed: onViewInvoices,
              child: const Text('View invoices'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final InvoicePlan plan;
  final String currency;
  final BillingPeriod period;
  final List<ProposedInvoice> chosen;
  final Set<String> excluded;
  final bool enabled;
  final void Function(String studentId, bool on) onToggleStudent;
  final void Function(bool on) onToggleAll;
  final VoidCallback? onConfirm;

  const _Preview({
    required this.plan,
    required this.currency,
    required this.period,
    required this.chosen,
    required this.excluded,
    required this.enabled,
    required this.onToggleStudent,
    required this.onToggleAll,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preview · ${period.label}', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          children: [
            Text('${chosen.length} invoices'),
            Text(
              'Subtotal ${Money.format(chosen.fold<int>(0, (s, p) => s + p.subtotalMinor), currency: currency)}',
            ),
            Text(
              'Concessions −${Money.format(chosen.fold<int>(0, (s, p) => s + p.discountMinor), currency: currency)}',
            ),
            Text(
              'Total ${Money.format(chosen.fold<int>(0, (s, p) => s + p.payableMinor), currency: currency)}',
              style: text.titleSmall,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (plan.skipped.isNotEmpty) _SkippedPanel(skipped: plan.skipped),
        if (plan.proposals.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: EmptyView(
              icon: Icons.receipt_long_outlined,
              message:
                  'Nothing to invoice for this selection. Choose at least one fee, or see the reasons above.',
            ),
          )
        else
          Card(
            child: Column(
              children: [
                CheckboxListTile(
                  dense: true,
                  tristate: true,
                  value: excluded.isEmpty
                      ? true
                      : (chosen.isEmpty ? false : null),
                  // Partly ticked -> select all; fully ticked -> clear.
                  onChanged: enabled
                      ? (_) => onToggleAll(excluded.isNotEmpty)
                      : null,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Select all students (${chosen.length} of ${plan.proposals.length})',
                  ),
                ),
                const Divider(height: 1),
                for (final p in plan.proposals)
                  Row(
                    children: [
                      Checkbox(
                        value: !excluded.contains(p.student.studentId),
                        onChanged: enabled
                            ? (v) => onToggleStudent(
                                p.student.studentId,
                                v ?? false,
                              )
                            : null,
                      ),
                      Expanded(
                        child: ExpansionTile(
                          dense: true,
                          title: Text(p.student.name),
                          subtitle: Text(
                            '${p.lines.map((l) => l.name).join(', ')} · due ${FeeDates.display(p.dueDateKey)}',
                          ),
                          trailing: Text(
                            Money.format(p.payableMinor, currency: currency),
                          ),
                          children: [
                            for (final l in p.lines)
                              ListTile(
                                dense: true,
                                title: Text(l.name),
                                subtitle: l.discountMinor > 0
                                    ? Text(
                                        'Concession −${Money.format(l.discountMinor, currency: currency)}${l.concessionNote == null ? '' : ' (${l.concessionNote})'}',
                                      )
                                    : null,
                                trailing: Text(
                                  Money.format(l.netMinor, currency: currency),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: chosen.isEmpty ? null : onConfirm,
          icon: const Icon(Icons.check),
          label: Text('Generate ${chosen.length} invoices'),
        ),
      ],
    );
  }
}

/// Why students will NOT get an invoice, grouped by reason with how to fix
/// it — shown above the preview so an empty result is never a mystery.
class _SkippedPanel extends StatelessWidget {
  final List<SkippedItem> skipped;
  const _SkippedPanel({required this.skipped});

  static String _hint(String reason) {
    if (reason.startsWith('No fees assigned')) {
      return 'Assign a fee structure to these students first '
          '(Fees → Assign).';
    }
    if (reason.contains('not effective')) {
      return 'Edit the fee structure\'s effective dates, or change the issue '
          'date above.';
    }
    if (reason.contains(' is ') && reason.contains(', not ')) {
      return 'The fee\'s frequency differs from the billing period type you '
          'chose — pick the matching period type, or edit the structure.';
    }
    if (reason.contains('inactive')) {
      return 'Re-activate the fee structure under Fees → Structures.';
    }
    if (reason.startsWith('Already invoiced') ||
        reason.contains('already billed')) {
      return 'Nothing to do — this period was already billed.';
    }
    if (reason.startsWith('Not currently enrolled')) {
      return 'The student is inactive or has no class/section in this year — '
          'check their placement.';
    }
    if (reason.startsWith('Fully concessed')) {
      return 'The concession covers the whole amount.';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final byReason = <String, List<String>>{};
    for (final s in skipped) {
      byReason.putIfAbsent(s.reason, () => []).add(s.studentName);
    }
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${skipped.length} student(s) will not be invoiced',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final e in byReason.entries) ...[
              Text('• ${e.value.length} × ${e.key}'),
              if (_hint(e.key).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    'How to fix: ${_hint(e.key)}',
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 6),
                child: Text(
                  e.value.take(8).join(', ') +
                      (e.value.length > 8
                          ? ' … +${e.value.length - 8} more'
                          : ''),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

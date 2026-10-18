import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/fee_enums.dart';
import '../../domain/fee_planners.dart';
import '../../domain/fee_structure.dart';
import '../../domain/money.dart';
import '../providers/fee_providers.dart';
import 'fee_scope.dart';

/// One student's fee heads for the year: what is assigned (with any approved
/// concession), cancel / re-activate, and assign another fee head. Setting a
/// concession needs `grantConcessions`; the rules require the same.
class StudentFeesDialog extends ConsumerStatefulWidget {
  final FeeContext fee;
  final FeeStudent student;
  final List<FeeStructure> structures;

  const StudentFeesDialog({
    super.key,
    required this.fee,
    required this.student,
    required this.structures,
  });

  @override
  ConsumerState<StudentFeesDialog> createState() => _StudentFeesDialogState();
}

class _StudentFeesDialogState extends ConsumerState<StudentFeesDialog> {
  FeeStructure? _structure;
  ConcessionType _concession = ConcessionType.none;
  final _value = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) context.showSnackBar(success);
    } catch (error) {
      if (mounted) context.showSnackBar(userMessageFor(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _concessionValue() {
    if (_concession == ConcessionType.none) return 0;
    if (_concession == ConcessionType.percent) {
      final n = double.tryParse(_value.text.trim());
      return n == null ? null : (n * 100).round();
    }
    return Money.parseMinor(_value.text, currency: widget.fee.currency);
  }

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    final canConcede = fee.tenant.can(Permission.grantConcessions);
    final key = (
      schoolId: fee.schoolId,
      branchId: fee.branchId,
      studentId: widget.student.studentId,
      academicYearId: fee.year.academicYearId,
    );
    final assigned = ref.watch(studentAssignmentsProvider(key));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.student.name, style: context.textStyles.titleLarge),
        Text(
          '${widget.student.className} ${widget.student.sectionName} · ${fee.year.name}',
          style: context.textStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        AsyncValueWidget(
          value: assigned,
          errorMessage: userMessageFor,
          data: (list) {
            final assignedIds = {for (final a in list) a.structureId};
            final options = widget.structures
                .where(
                  (s) =>
                      s.isActive &&
                      !assignedIds.contains(s.structureId) &&
                      s.appliesTo(
                        classId: widget.student.classId,
                        sectionId: widget.student.sectionId,
                      ),
                )
                .toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (list.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text('No fees assigned yet.'),
                  ),
                for (final a in list)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      a.structureName,
                      style: a.isActive
                          ? null
                          : const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            ),
                    ),
                    subtitle: Text(
                      a.hasConcession
                          ? 'Concession: ${a.concessionType == ConcessionType.percent ? '${(a.concessionValue / 100).toStringAsFixed(2)}%' : Money.format(a.concessionValue, currency: fee.currency)} — ${a.concessionReason ?? ''}'
                          : (a.isActive ? 'Active' : 'Cancelled'),
                    ),
                    trailing: fee.tenant.can(Permission.assignFees)
                        ? TextButton(
                            onPressed: _busy
                                ? null
                                : () => _run(
                                    () => ref
                                        .read(feeConfigRepositoryProvider)
                                        .setAssignmentActive(
                                          a,
                                          !a.isActive,
                                          actorId: fee.userId,
                                        ),
                                    a.isActive
                                        ? 'Fee cancelled for this student.'
                                        : 'Fee re-activated.',
                                  ),
                            child: Text(a.isActive ? 'Cancel' : 'Re-activate'),
                          )
                        : null,
                  ),
                const Divider(),
                if (fee.tenant.can(Permission.assignFees)) ...[
                  Text('Assign a fee', style: context.textStyles.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  DropdownButtonFormField<FeeStructure>(
                    value: options.contains(_structure) ? _structure : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: options.isEmpty
                          ? 'No other applicable fees'
                          : 'Fee',
                    ),
                    items: [
                      for (final s in options)
                        DropdownMenuItem(
                          value: s,
                          child: Text(
                            '${s.name} · ${Money.format(s.amountMinor, currency: fee.currency)} ${s.frequency.displayName.toLowerCase()}',
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _structure = v),
                  ),
                  if (canConcede) ...[
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<ConcessionType>(
                      isExpanded: true,
                      value: _concession,
                      decoration: const InputDecoration(
                        labelText: 'Concession / scholarship',
                      ),
                      items: [
                        for (final c in ConcessionType.values)
                          DropdownMenuItem(
                            value: c,
                            child: Text(c.displayName),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(
                              () => _concession = v ?? ConcessionType.none,
                            ),
                    ),
                    if (_concession != ConcessionType.none) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _value,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _concession == ConcessionType.percent
                              ? 'Percentage (0-100)'
                              : 'Amount per billing (${fee.currency})',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _reason,
                        decoration: const InputDecoration(
                          labelText: 'Reason / approval note',
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: (_busy || _structure == null)
                          ? null
                          : () {
                              final value = _concessionValue();
                              if (value == null) {
                                context.showSnackBar(
                                  'Enter a valid concession value.',
                                  isError: true,
                                );
                                return;
                              }
                              _run(
                                () => ref
                                    .read(feeConfigRepositoryProvider)
                                    .assignOne(
                                      schoolId: fee.schoolId,
                                      branchId: fee.branchId,
                                      academicYearId: fee.year.academicYearId,
                                      student: widget.student,
                                      structure: _structure!,
                                      concessionType: _concession,
                                      concessionValue: value,
                                      concessionReason: _reason.text.trim(),
                                      actorId: fee.userId,
                                    ),
                                'Fee assigned successfully.',
                              );
                            },
                      child: const Text('Assign'),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(
                      '/fees/invoices?studentId=${widget.student.studentId}',
                    );
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View invoices & ledger'),
                ),
              ],
            );
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }
}

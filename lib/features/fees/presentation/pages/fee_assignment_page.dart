import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/fee_planners.dart';
import '../../domain/fee_repositories.dart';
import '../../domain/fee_structure.dart';
import '../../domain/money.dart';
import '../../domain/student_fee_assignment.dart';
import '../providers/fee_providers.dart';
import '../widgets/fee_scope.dart';
import '../widgets/student_fees_dialog.dart';

/// `/fees/assign` — assign fee heads to a whole class/section at once, with a
/// breakdown to review first, or open one student to assign individually
/// (and, if permitted, with a concession). Optional fees are never ticked by
/// default; students who are not enrolled are never charged.
class FeeAssignmentPage extends StatelessWidget {
  const FeeAssignmentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assign fees')),
      body: FeeScope(builder: (context, fee) => _Assign(fee: fee)),
    );
  }
}

class _Assign extends ConsumerStatefulWidget {
  final FeeContext fee;

  const _Assign({required this.fee});

  @override
  ConsumerState<_Assign> createState() => _AssignState();
}

class _AssignState extends ConsumerState<_Assign> {
  String? _classId;
  String? _sectionId;
  List<FeeStudent>? _students;
  List<StudentFeeAssignment> _existing = const [];
  final Set<String> _selected = {};
  AssignmentPlan? _plan;
  bool _loading = false;
  String? _error;
  ({int done, int total})? _progress;
  BulkResult? _result;

  Future<void> _load() async {
    final fee = widget.fee;
    setState(() {
      _loading = true;
      _error = null;
      _plan = null;
      _result = null;
      _students = null;
    });
    try {
      final repo = ref.read(feeConfigRepositoryProvider);
      final students = await repo.loadPlacementStudents(
        schoolId: fee.schoolId,
        branchId: fee.branchId,
        academicYearId: fee.year.academicYearId,
        classId: _classId!,
        sectionId: _sectionId,
      );
      final existing = await repo.fetchAssignmentsForPlacement(
        schoolId: fee.schoolId,
        branchId: fee.branchId,
        academicYearId: fee.year.academicYearId,
        classId: _classId!,
        sectionId: _sectionId,
      );
      if (!mounted) return;
      setState(() {
        _students = students;
        _existing = existing;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userMessageFor(error);
        _loading = false;
      });
    }
  }

  void _buildPlan(List<FeeStructure> all) {
    final chosen = all.where((s) => _selected.contains(s.structureId)).toList();
    setState(
      () => _plan = AssignmentPlanner.plan(
        students: _students!,
        structures: chosen,
        academicYearId: widget.fee.year.academicYearId,
        existingAssignmentIds: {for (final a in _existing) a.assignmentId},
      ),
    );
  }

  Future<void> _confirm() async {
    final plan = _plan!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign these fees?'),
        content: Text(
          '${plan.toCreate.length} assignments will be created (${Money.format(plan.totalMinor, currency: widget.fee.currency)} per billing, before any concessions). Nothing is invoiced yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _progress = (done: 0, total: plan.toCreate.length));
    try {
      final result = await ref
          .read(feeConfigRepositoryProvider)
          .createAssignments(
            plan.toCreate,
            actorId: widget.fee.userId,
            onProgress: (done, total) {
              if (mounted) {
                setState(() => _progress = (done: done, total: total));
              }
            },
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _progress = null;
        _plan = null;
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _progress = null);
      context.showSnackBar(userMessageFor(error), isError: true);
    }
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
    final structures =
        (ref.watch(feeStructuresProvider(fee.yearKey)).value ??
                const <FeeStructure>[])
            .where((s) => s.isActive)
            .toList();
    final applicable = structures
        .where(
          (s) => _classId == null || s.classId == null || s.classId == _classId,
        )
        .toList();
    final busy = _loading || _progress != null;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                value: _classId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Class',
                  isDense: true,
                ),
                items: [
                  for (final c in classes)
                    DropdownMenuItem(value: c.classId, child: Text(c.name)),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        _classId = v;
                        _sectionId = null;
                        _students = null;
                        _plan = null;
                        _selected.clear();
                      }),
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                value: sections.any((s) => s.sectionId == _sectionId)
                    ? _sectionId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Section',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All sections'),
                  ),
                  for (final s in sections)
                    DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
                ],
                onChanged: (busy || _classId == null)
                    ? null
                    : (v) => setState(() {
                        _sectionId = v;
                        _students = null;
                        _plan = null;
                      }),
              ),
            ),
            FilledButton.icon(
              onPressed: (_classId == null || busy) ? null : _load,
              icon: _loading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.groups_outlined),
              label: const Text('Load students'),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(_error!, style: TextStyle(color: context.colors.error)),
          ),
        if (_progress != null) ...[
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(
            value: _progress!.total == 0
                ? null
                : _progress!.done / _progress!.total,
          ),
          Text('Assigning… ${_progress!.done} of ${_progress!.total}'),
        ],
        if (_result != null)
          Card(
            color: _result!.failed > 0
                ? context.colors.errorContainer
                : context.colors.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_result!.created} fee assignment${_result!.created == 1 ? '' : 's'} created.',
                  ),
                  if (_result!.skippedExisting > 0)
                    Text('${_result!.skippedExisting} already existed.'),
                  if (_result!.failed > 0)
                    Text(
                      '${_result!.failed} failed: ${_result!.errors.join('; ')}',
                    ),
                ],
              ),
            ),
          ),
        if (_students != null) ...[
          const SizedBox(height: AppSpacing.md),
          if (_students!.isEmpty)
            const EmptyView(
              icon: Icons.groups_outlined,
              message:
                  'No students are placed in this class/section for the academic year.',
            )
          else ...[
            Text(
              'Fees to assign to all ${_students!.length} students',
              style: context.textStyles.titleMedium,
            ),
            if (applicable.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'No active fees apply to this class. Add them under Fee structures.',
                ),
              )
            else
              for (final s in applicable)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(s.structureId),
                  title: Text('${s.name}${s.isOptional ? ' (optional)' : ''}'),
                  subtitle: Text(
                    '${Money.format(s.amountMinor, currency: fee.currency)} · ${s.frequency.displayName}',
                  ),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          v == true
                              ? _selected.add(s.structureId)
                              : _selected.remove(s.structureId);
                          _plan = null;
                        }),
                ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: (busy || _selected.isEmpty)
                    ? null
                    : () => _buildPlan(applicable),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview assignment'),
              ),
            ),
            if (_plan != null)
              _PlanCard(
                plan: _plan!,
                currency: fee.currency,
                onConfirm: busy ? null : _confirm,
              ),
            const SizedBox(height: AppSpacing.md),
            Text('Students', style: context.textStyles.titleMedium),
            Text(
              'Open a student to assign a single fee or grant a concession.',
              style: context.textStyles.bodySmall,
            ),
            for (final s in _students!)
              ListTile(
                dense: true,
                title: Text(s.name),
                subtitle: Text(
                  '${s.admissionNumber} · ${s.sectionName}${s.isEnrolled ? '' : ' · not enrolled'}',
                ),
                trailing: Text(
                  '${_existing.where((a) => a.studentId == s.studentId && a.isActive).length} fees',
                ),
                onTap: () => showAdaptiveAppDialog<void>(
                  context: context,
                  builder: (context) => StudentFeesDialog(
                    fee: fee,
                    student: s,
                    structures: structures,
                  ),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final AssignmentPlan plan;
  final String currency;
  final VoidCallback? onConfirm;

  const _PlanCard({
    required this.plan,
    required this.currency,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final breakdown = plan.breakdown;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preview', style: context.textStyles.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            if (breakdown.isEmpty)
              const Text(
                'Nothing new to assign — every eligible student already has these fees.',
              ),
            for (final e in breakdown.entries)
              Text(
                '${e.key}: ${e.value.students} students · ${Money.format(e.value.totalMinor, currency: currency)}',
              ),
            if (breakdown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Total per billing: ${Money.format(plan.totalMinor, currency: currency)} (before concessions)',
                  style: context.textStyles.titleSmall,
                ),
              ),
            if (plan.skipped.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('${plan.skipped.length} skipped'),
                children: [
                  for (final s in plan.skipped.take(100))
                    ListTile(
                      dense: true,
                      title: Text(s.studentName),
                      subtitle: Text(s.reason),
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: plan.toCreate.isEmpty ? null : onConfirm,
              icon: const Icon(Icons.check),
              label: Text('Assign ${plan.toCreate.length}'),
            ),
          ],
        ),
      ),
    );
  }
}

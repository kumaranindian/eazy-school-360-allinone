import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../core/validators/validators.dart';
import '../../../school_setup/domain/branch.dart';
import '../../domain/school_academic_year.dart';
import '../providers/academic_structure_providers.dart';

/// Defines a school-wide academic year (name + dates). School admin only.
class SchoolYearFormDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String userId;
  final List<String> existingNames;

  const SchoolYearFormDialog({
    super.key,
    required this.schoolId,
    required this.userId,
    required this.existingNames,
  });

  @override
  ConsumerState<SchoolYearFormDialog> createState() =>
      _SchoolYearFormDialogState();
}

class _SchoolYearFormDialogState extends ConsumerState<SchoolYearFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final problem = SchoolYearRules.validate(
      name: _name.text,
      start: _start,
      end: _end,
      existingNames: widget.existingNames,
    );
    if (problem != null) {
      context.showSnackBar(problem, isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(schoolYearRepositoryProvider)
          .createSchoolYear(
            SchoolAcademicYear(
              schoolYearId: '',
              schoolId: widget.schoolId,
              name: _name.text.trim(),
              startDate: _start!,
              endDate: _end!,
            ),
            createdBy: widget.userId,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackBar(userMessageFor(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add school year', style: context.textStyles.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Defined once for the whole school. Name and dates cannot be '
            'changed afterwards; each branch then opens it.',
            style: context.textStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. 2026-2027',
            ),
            validator: (v) => Validators.required(v, fieldName: 'Name'),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                onPressed: () => _pick(start: true),
                child: Text(
                  _start == null
                      ? 'Start date'
                      : 'Starts ${formatDisplayDate(_start!)}',
                ),
              ),
              OutlinedButton(
                onPressed: () => _pick(start: false),
                child: Text(
                  _end == null
                      ? 'End date'
                      : 'Ends ${formatDisplayDate(_end!)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens [year] in the chosen branches (creating each branch's own DRAFT copy).
/// Branches that already have it are listed but not selectable.
class OpenInBranchesDialog extends ConsumerStatefulWidget {
  final SchoolAcademicYear year;
  final List<Branch> branches;
  final Set<String> alreadyOpen;
  final String userId;

  const OpenInBranchesDialog({
    super.key,
    required this.year,
    required this.branches,
    required this.alreadyOpen,
    required this.userId,
  });

  @override
  ConsumerState<OpenInBranchesDialog> createState() =>
      _OpenInBranchesDialogState();
}

class _OpenInBranchesDialogState extends ConsumerState<OpenInBranchesDialog> {
  late final Set<String> _chosen = {
    for (final b in widget.branches)
      if (!widget.alreadyOpen.contains(b.branchId)) b.branchId,
  };
  bool _saving = false;
  List<OpenYearResult>? _results;

  Future<void> _open() async {
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(schoolYearRepositoryProvider)
          .openInBranches(
            widget.year,
            _chosen.toList(),
            createdBy: widget.userId,
          );
      if (!mounted) return;
      if (r.every((x) => x.outcome != OpenYearOutcome.failed)) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _saving = false;
        _results = r;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackBar(userMessageFor(e), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed = {
      for (final r in _results ?? const <OpenYearResult>[])
        if (r.outcome == OpenYearOutcome.failed) r.branchId: r.message,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Open ${widget.year.name}', style: context.textStyles.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Each branch gets its own draft copy to set up classes and students. '
          'It becomes the branch\'s active year when its admin activates it.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final b in widget.branches)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value:
                widget.alreadyOpen.contains(b.branchId) ||
                _chosen.contains(b.branchId),
            onChanged: widget.alreadyOpen.contains(b.branchId) || _saving
                ? null
                : (v) => setState(
                    () => v == true
                        ? _chosen.add(b.branchId)
                        : _chosen.remove(b.branchId),
                  ),
            title: Text(b.name),
            subtitle: widget.alreadyOpen.contains(b.branchId)
                ? const Text('Already open')
                : failed.containsKey(b.branchId)
                ? Text(
                    failed[b.branchId] ?? 'Could not open.',
                    style: TextStyle(color: theme.colorScheme.error),
                  )
                : null,
          ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _saving || _chosen.isEmpty ? null : _open,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Open in ${_chosen.length} branch'
                      '${_chosen.length == 1 ? '' : 'es'}',
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A branch admin opens one school-wide year in their own branch.
class OpenSchoolYearDialog extends ConsumerStatefulWidget {
  final String schoolId;
  final String branchId;
  final String userId;
  final List<SchoolAcademicYear> openable;

  const OpenSchoolYearDialog({
    super.key,
    required this.schoolId,
    required this.branchId,
    required this.userId,
    required this.openable,
  });

  @override
  ConsumerState<OpenSchoolYearDialog> createState() =>
      _OpenSchoolYearDialogState();
}

class _OpenSchoolYearDialogState extends ConsumerState<OpenSchoolYearDialog> {
  String? _chosen;
  bool _saving = false;

  Future<void> _open() async {
    final year = widget.openable.firstWhere((y) => y.schoolYearId == _chosen);
    setState(() => _saving = true);
    final r = await ref.read(schoolYearRepositoryProvider).openInBranches(
      year,
      [widget.branchId],
      createdBy: widget.userId,
    );
    if (!mounted) return;
    final one = r.single;
    if (one.outcome == OpenYearOutcome.failed) {
      setState(() => _saving = false);
      context.showSnackBar(
        one.message ?? 'Could not open the year.',
        isError: true,
      );
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Open a school year', style: context.textStyles.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Academic years are set by the school. Choose one to start setting '
          'up this branch for it.',
          style: context.textStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (widget.openable.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              'Every school year is already open here. A school admin can add '
              'a new one in School years.',
            ),
          )
        else
          for (final y in widget.openable)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: y.schoolYearId,
              groupValue: _chosen,
              onChanged: _saving ? null : (v) => setState(() => _chosen = v),
              title: Text(y.name),
              subtitle: Text(
                '${formatDisplayDate(y.startDate)} – ${formatDisplayDate(y.endDate)}',
              ),
            ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            TextButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _saving || _chosen == null ? null : _open,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Open'),
            ),
          ],
        ),
      ],
    );
  }
}

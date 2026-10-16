import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../../staff/presentation/providers/staff_providers.dart';
import '../../domain/student.dart';
import '../providers/student_providers.dart';

/// Moves an active student to another branch of the same school (school admin
/// only; the rules enforce it). The old record is kept as TRANSFERRED with all
/// its history; the new branch gets the student placed in a section, plus the
/// guardians. See `BranchTransferWrites`.
class StudentBranchTransferDialog extends ConsumerStatefulWidget {
  final Student student;
  final String currentUserId;

  const StudentBranchTransferDialog({
    super.key,
    required this.student,
    required this.currentUserId,
  });

  @override
  ConsumerState<StudentBranchTransferDialog> createState() =>
      _StudentBranchTransferDialogState();
}

class _StudentBranchTransferDialogState
    extends ConsumerState<StudentBranchTransferDialog> {
  String? _branchId;
  String? _yearId;
  String? _classId;
  String? _sectionId;
  final _admission = TextEditingController();
  final _roll = TextEditingController();
  final _reason = TextEditingController();
  bool _saving = false;
  bool _confirmed = false;

  @override
  void dispose() {
    _admission.dispose();
    _roll.dispose();
    _reason.dispose();
    super.dispose();
  }

  bool get _ready =>
      _branchId != null &&
      _yearId != null &&
      _classId != null &&
      _sectionId != null &&
      _admission.text.trim().isNotEmpty &&
      _confirmed;

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(studentRepositoryProvider)
          .transferToBranch(
            schoolId: widget.student.schoolId,
            fromBranchId: widget.student.branchId,
            studentId: widget.student.studentId,
            toBranchId: _branchId!,
            admissionNumber: _admission.text.trim(),
            academicYearId: _yearId!,
            classId: _classId!,
            sectionId: _sectionId!,
            rollNumber: _roll.text.trim().isEmpty ? null : _roll.text.trim(),
            reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
            effectiveDate: DateTime.now(),
            updatedBy: widget.currentUserId,
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
    final theme = Theme.of(context);
    final schoolId = widget.student.schoolId;
    final branches =
        (ref.watch(schoolBranchesProvider(schoolId)).value ?? const [])
            .where((b) => b.branchId != widget.student.branchId)
            .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Move to another branch', style: context.textStyles.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${widget.student.displayName} stays on record in this branch as '
          'Transferred, with their attendance, fees and results. The new '
          'branch gets a new admission, and the parents keep their access.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: _branchId,
          decoration: const InputDecoration(labelText: 'New branch'),
          items: [
            for (final b in branches)
              DropdownMenuItem(value: b.branchId, child: Text(b.name)),
          ],
          onChanged: _saving
              ? null
              : (v) => setState(() {
                  _branchId = v;
                  _yearId = null;
                  _classId = null;
                  _sectionId = null;
                }),
        ),
        if (branches.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'This school has no other branch.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _admission,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Admission number in the new branch',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_branchId != null) ..._placementFields(schoolId, _branchId!),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _reason,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _confirmed,
          onChanged: _saving
              ? null
              : (v) => setState(() => _confirmed = v == true),
          title: const Text('I understand this cannot be undone here'),
          subtitle: const Text(
            'To bring the student back, admit them again in this branch.',
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
              onPressed: _saving || !_ready ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Move student'),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _placementFields(String schoolId, String branchId) {
    final years = ref.watch(
      academicYearsProvider((schoolId: schoolId, branchId: branchId)),
    );
    return [
      const SizedBox(height: AppSpacing.sm),
      years.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => const Text('Unable to load academic years.'),
        data: (list) {
          final open = [
            for (final y in list)
              if (y.status != AcademicYearStatus.closed) y,
          ];
          if (open.isEmpty) {
            return const Text(
              'No open academic year in that branch. Open a school year there first.',
            );
          }
          return DropdownButtonFormField<String>(
            isExpanded: true,
            value: open.any((y) => y.academicYearId == _yearId)
                ? _yearId
                : null,
            decoration: const InputDecoration(labelText: 'Academic year'),
            items: [
              for (final y in open)
                DropdownMenuItem(value: y.academicYearId, child: Text(y.name)),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() {
                    _yearId = v;
                    _classId = null;
                    _sectionId = null;
                  }),
          );
        },
      ),
      if (_yearId != null) ...[
        const SizedBox(height: AppSpacing.sm),
        ref
            .watch(
              classesProvider((
                schoolId: schoolId,
                branchId: branchId,
                academicYearId: _yearId!,
              )),
            )
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Unable to load classes.'),
              data: (classes) => DropdownButtonFormField<String>(
                isExpanded: true,
                value: classes.any((c) => c.classId == _classId)
                    ? _classId
                    : null,
                decoration: const InputDecoration(labelText: 'Class'),
                items: [
                  for (final c in classes)
                    DropdownMenuItem(value: c.classId, child: Text(c.name)),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                        _classId = v;
                        _sectionId = null;
                      }),
              ),
            ),
      ],
      if (_yearId != null && _classId != null) ...[
        const SizedBox(height: AppSpacing.sm),
        ref
            .watch(
              sectionsProvider((
                schoolId: schoolId,
                branchId: branchId,
                academicYearId: _yearId!,
                classId: _classId!,
              )),
            )
            .when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Unable to load sections.'),
              data: (sections) => DropdownButtonFormField<String>(
                isExpanded: true,
                value: sections.any((s) => s.sectionId == _sectionId)
                    ? _sectionId
                    : null,
                decoration: const InputDecoration(labelText: 'Section'),
                items: [
                  for (final s in sections)
                    DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _sectionId = v),
              ),
            ),
      ],
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _roll,
        enabled: !_saving,
        decoration: const InputDecoration(labelText: 'Roll number (optional)'),
      ),
    ];
  }
}

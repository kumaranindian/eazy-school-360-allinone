import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/extra_placement.dart';
import '../../domain/student.dart';
import '../providers/student_providers.dart';

/// Adds an extra class to a student (same academic year as their main class).
class StudentExtraClassDialog extends ConsumerStatefulWidget {
  final Student student;
  final String currentUserId;

  const StudentExtraClassDialog({
    super.key,
    required this.student,
    required this.currentUserId,
  });

  @override
  ConsumerState<StudentExtraClassDialog> createState() =>
      _StudentExtraClassDialogState();
}

class _StudentExtraClassDialogState
    extends ConsumerState<StudentExtraClassDialog> {
  String? _classId;
  String? _sectionId;
  final _label = TextEditingController();
  final _roll = TextEditingController();
  bool _saving = false;

  String get _yearId => widget.student.currentAcademicYearId!;

  Future<void> _save() async {
    if (_saving) return;
    if (_classId == null || _sectionId == null) {
      context.showSnackBar('Choose a class and section.', isError: true);
      return;
    }
    final s = widget.student;
    final candidate = ExtraPlacement(
      recordId: '',
      academicYearId: _yearId,
      classId: _classId!,
      sectionId: _sectionId!,
      label: _label.text.trim(),
    );
    final problem = ExtraPlacement.checkAdd(
      candidate: candidate,
      mainYearId: s.currentAcademicYearId,
      mainClassId: s.currentClassId,
      existing: s.extraPlacements,
    );
    if (problem != null) {
      context.showSnackBar(problem, isError: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await ref
        .read(studentWriteControllerProvider.notifier)
        .addExtraPlacement(
          schoolId: s.schoolId,
          branchId: s.branchId,
          studentId: s.studentId,
          academicYearId: _yearId,
          classId: _classId!,
          sectionId: _sectionId!,
          label: _label.text,
          rollNumber: _roll.text,
          updatedBy: widget.currentUserId,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      final error = ref.read(studentWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to add the class.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(studentWriteControllerProvider);
    final s = widget.student;
    final classes = ref
        .watch(
          classesProvider((
            schoolId: s.schoolId,
            branchId: s.branchId,
            academicYearId: _yearId,
          )),
        )
        .value;
    final sections = _classId == null
        ? null
        : ref
              .watch(
                sectionsProvider((
                  schoolId: s.schoolId,
                  branchId: s.branchId,
                  academicYearId: _yearId,
                  classId: _classId!,
                )),
              )
              .value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add extra class', style: context.textStyles.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${s.displayName} stays in their main class and also joins this '
          'one.',
          style: context.textStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        if (classes == null)
          const LinearProgressIndicator()
        else
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: classes.any((c) => c.classId == _classId) ? _classId : null,
            decoration: const InputDecoration(labelText: 'Class'),
            items: [
              for (final c in classes)
                if (c.classId != s.currentClassId &&
                    !s.extraPlacements.any((e) => e.classId == c.classId))
                  DropdownMenuItem(value: c.classId, child: Text(c.name)),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() {
                    _classId = v;
                    _sectionId = null;
                  }),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (_classId != null)
          if (sections == null)
            const LinearProgressIndicator()
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: sections.any((x) => x.sectionId == _sectionId)
                  ? _sectionId
                  : null,
              decoration: const InputDecoration(labelText: 'Section'),
              items: [
                for (final x in sections)
                  DropdownMenuItem(value: x.sectionId, child: Text(x.name)),
              ],
              onChanged: _saving ? null : (v) => setState(() => _sectionId = v),
            ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _label,
          enabled: !_saving,
          maxLength: ExtraPlacement.maxLabelLength,
          decoration: const InputDecoration(
            labelText: 'Session (optional)',
            hintText: 'e.g. Morning, Afternoon',
          ),
        ),
        TextField(
          controller: _roll,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Roll number in this class (optional)',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
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
                  : const Text('Add class'),
            ),
          ],
        ),
      ],
    );
  }
}

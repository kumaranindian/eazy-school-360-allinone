import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../academic_setup/domain/academic_year_status.dart';
import '../../../academic_setup/presentation/providers/academic_setup_keys.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/staff.dart';
import '../providers/staff_providers.dart';

/// Assigns a teacher to a section — either as its class teacher or for one
/// subject. Offers only what is valid: open academic years, classes of that
/// year, the sections of that class, and only the subjects configured for
/// that class. The repository and `firestore.rules` re-check all of it.
class TeacherAssignmentDialog extends ConsumerStatefulWidget {
  final Staff teacher;
  final String currentUserId;
  final String? initialAcademicYearId;

  const TeacherAssignmentDialog({
    super.key,
    required this.teacher,
    required this.currentUserId,
    this.initialAcademicYearId,
  });

  @override
  ConsumerState<TeacherAssignmentDialog> createState() =>
      _TeacherAssignmentDialogState();
}

class _TeacherAssignmentDialogState
    extends ConsumerState<TeacherAssignmentDialog> {
  late String? _yearId = widget.initialAcademicYearId;
  String? _classId;
  String? _sectionId;
  String? _subjectId;
  bool _isClassTeacher = false;
  DateTime _startDate = DateTime.now();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _submit() async {
    final success = await ref
        .read(teacherAssignmentWriteControllerProvider.notifier)
        .assign(
          teacher: widget.teacher,
          academicYearId: _yearId!,
          classId: _classId!,
          sectionId: _sectionId!,
          subjectId: _isClassTeacher ? null : _subjectId,
          isClassTeacher: _isClassTeacher,
          startDate: _startDate,
          createdBy: widget.currentUserId,
        );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(teacherAssignmentWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to save this assignment.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref
        .watch(teacherAssignmentWriteControllerProvider)
        .isLoading;
    final teacher = widget.teacher;
    final branchKey = (schoolId: teacher.schoolId, branchId: teacher.branchId);

    final years =
        (ref.watch(academicYearsProvider(branchKey)).value ?? const [])
            .where((y) => y.status != AcademicYearStatus.closed)
            .toList();
    final yearKey = _yearId == null
        ? null
        : (
            schoolId: teacher.schoolId,
            branchId: teacher.branchId,
            academicYearId: _yearId!,
          );
    final classes = yearKey == null
        ? const []
        : (ref.watch(classesProvider(yearKey)).value ?? const [])
              .where((c) => c.status.wireValue == 'ACTIVE')
              .toList();
    final ClassKey? classKey = (yearKey == null || _classId == null)
        ? null
        : (
            schoolId: teacher.schoolId,
            branchId: teacher.branchId,
            academicYearId: _yearId!,
            classId: _classId!,
          );
    final sections = classKey == null
        ? const []
        : (ref.watch(sectionsProvider(classKey)).value ?? const [])
              .where((s) => s.status.wireValue == 'ACTIVE')
              .toList();
    final classSubjects = classKey == null
        ? const []
        : (ref.watch(classSubjectsProvider(classKey)).value ?? const []);

    final canSave =
        _yearId != null &&
        _classId != null &&
        _sectionId != null &&
        (_isClassTeacher || _subjectId != null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Assign ${teacher.displayName}',
          style: context.textStyles.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          value: years.any((y) => y.academicYearId == _yearId) ? _yearId : null,
          decoration: const InputDecoration(labelText: 'Academic year'),
          items: [
            for (final y in years)
              DropdownMenuItem(value: y.academicYearId, child: Text(y.name)),
          ],
          onChanged: (v) => setState(() {
            _yearId = v;
            _classId = null;
            _sectionId = null;
            _subjectId = null;
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          value: classes.any((c) => c.classId == _classId) ? _classId : null,
          decoration: const InputDecoration(labelText: 'Class'),
          items: [
            for (final c in classes)
              DropdownMenuItem(value: c.classId, child: Text(c.name)),
          ],
          onChanged: _yearId == null
              ? null
              : (v) => setState(() {
                  _classId = v;
                  _sectionId = null;
                  _subjectId = null;
                }),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          value: sections.any((s) => s.sectionId == _sectionId)
              ? _sectionId
              : null,
          decoration: const InputDecoration(labelText: 'Section'),
          items: [
            for (final s in sections)
              DropdownMenuItem(value: s.sectionId, child: Text(s.name)),
          ],
          onChanged: _classId == null
              ? null
              : (v) => setState(() => _sectionId = v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Class teacher'),
          subtitle: const Text(
            'One class teacher per section and academic year.',
          ),
          value: _isClassTeacher,
          onChanged: isSaving
              ? null
              : (v) => setState(() => _isClassTeacher = v),
        ),
        if (!_isClassTeacher)
          DropdownButtonFormField<String>(
            value: classSubjects.any((s) => s.subjectId == _subjectId)
                ? _subjectId
                : null,
            decoration: InputDecoration(
              labelText: 'Subject',
              helperText: _classId != null && classSubjects.isEmpty
                  ? 'No subjects are configured for this class yet.'
                  : 'Only subjects configured for the class.',
            ),
            items: [
              for (final s in classSubjects)
                DropdownMenuItem(
                  value: s.subjectId,
                  child: Text(s.subjectName),
                ),
            ],
            onChanged: _classId == null
                ? null
                : (v) => setState(() => _subjectId = v),
          ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: _pickDate,
          child: Text('Starts: ${formatDisplayDate(_startDate)}'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: isSaving
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: isSaving || !canSave ? null : _submit,
              child: isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Assign'),
            ),
          ],
        ),
      ],
    );
  }
}

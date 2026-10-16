import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/academic_record_status.dart';
import '../../domain/student.dart';
import '../providers/student_providers.dart';

/// Moves a student to a new class/section/academic year (brief §19). The
/// old academic record is closed (never overwritten) with the chosen
/// [AcademicRecordStatus] — a same-year section change should normally
/// close as `transferred`, an end-of-year promotion as `completed`.
///
/// A move to another branch is a separate, audited action — see
/// `StudentBranchTransferDialog`.
class StudentTransferDialog extends ConsumerStatefulWidget {
  final Student student;
  final String currentUserId;

  const StudentTransferDialog({
    super.key,
    required this.student,
    required this.currentUserId,
  });

  @override
  ConsumerState<StudentTransferDialog> createState() =>
      _StudentTransferDialogState();
}

class _StudentTransferDialogState extends ConsumerState<StudentTransferDialog> {
  String? _academicYearId;
  String? _classId;
  String? _sectionId;
  final _rollNumber = TextEditingController();
  AcademicRecordStatus _closeOldRecordAs = AcademicRecordStatus.transferred;

  @override
  void initState() {
    super.initState();
    _academicYearId = widget.student.currentAcademicYearId;
  }

  Future<void> _submit() async {
    if (_academicYearId == null || _classId == null || _sectionId == null) {
      context.showSnackBar(
        'Please choose an academic year, class, and section.',
        isError: true,
      );
      return;
    }
    final success = await ref
        .read(studentWriteControllerProvider.notifier)
        .transferStudent(
          schoolId: widget.student.schoolId,
          branchId: widget.student.branchId,
          studentId: widget.student.studentId,
          newAcademicYearId: _academicYearId!,
          newClassId: _classId!,
          newSectionId: _sectionId!,
          newRollNumber: _rollNumber.text.trim().isEmpty
              ? null
              : _rollNumber.text.trim(),
          closeOldRecordAs: _closeOldRecordAs,
          updatedBy: widget.currentUserId,
        );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(studentWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to transfer this student.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _rollNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(studentWriteControllerProvider).isLoading;
    final branchKey = (
      schoolId: widget.student.schoolId,
      branchId: widget.student.branchId,
    );
    final yearsAsync = ref.watch(academicYearsProvider(branchKey));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Transfer student', style: context.textStyles.titleLarge),
        const SizedBox(height: AppSpacing.md),
        yearsAsync.when(
          data: (years) => DropdownButtonFormField<String>(
            isExpanded: true,
            value: years.any((y) => y.academicYearId == _academicYearId)
                ? _academicYearId
                : null,
            decoration: const InputDecoration(labelText: 'Academic year'),
            items: [
              for (final y in years)
                DropdownMenuItem(value: y.academicYearId, child: Text(y.name)),
            ],
            onChanged: (value) => setState(() {
              _academicYearId = value;
              _classId = null;
              _sectionId = null;
            }),
          ),
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Unable to load academic years.'),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (_academicYearId != null)
          Consumer(
            builder: (context, ref, _) {
              final classesAsync = ref.watch(
                classesProvider((
                  schoolId: branchKey.schoolId,
                  branchId: branchKey.branchId,
                  academicYearId: _academicYearId!,
                )),
              );
              return classesAsync.when(
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
                  onChanged: (value) => setState(() {
                    _classId = value;
                    _sectionId = null;
                  }),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Unable to load classes.'),
              );
            },
          ),
        const SizedBox(height: AppSpacing.sm),
        if (_academicYearId != null && _classId != null)
          Consumer(
            builder: (context, ref, _) {
              final sectionsAsync = ref.watch(
                sectionsProvider((
                  schoolId: branchKey.schoolId,
                  branchId: branchKey.branchId,
                  academicYearId: _academicYearId!,
                  classId: _classId!,
                )),
              );
              return sectionsAsync.when(
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
                  onChanged: (value) => setState(() => _sectionId = value),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Unable to load sections.'),
              );
            },
          ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _rollNumber,
          decoration: const InputDecoration(
            labelText: 'Roll number (optional)',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<AcademicRecordStatus>(
          isExpanded: true,
          value: _closeOldRecordAs,
          decoration: const InputDecoration(
            labelText: 'Close previous placement as',
          ),
          items: const [
            DropdownMenuItem(
              value: AcademicRecordStatus.transferred,
              child: Text('Transferred'),
            ),
            DropdownMenuItem(
              value: AcademicRecordStatus.completed,
              child: Text('Completed'),
            ),
          ],
          onChanged: (value) =>
              setState(() => _closeOldRecordAs = value ?? _closeOldRecordAs),
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
              onPressed: isSaving ? null : _submit,
              child: isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Transfer'),
            ),
          ],
        ),
      ],
    );
  }
}

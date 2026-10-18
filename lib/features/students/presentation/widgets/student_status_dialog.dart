import '../../../../core/regional/school_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../domain/student.dart';
import '../../domain/student_status.dart';
import '../providers/student_providers.dart';

/// A lifecycle status change (brief §20: withdrawal, graduation, ...) —
/// captures effective date, reason, and notes; never deletes the student.
class StudentStatusDialog extends ConsumerStatefulWidget {
  final Student student;
  final String currentUserId;

  const StudentStatusDialog({
    super.key,
    required this.student,
    required this.currentUserId,
  });

  @override
  ConsumerState<StudentStatusDialog> createState() =>
      _StudentStatusDialogState();
}

class _StudentStatusDialogState extends ConsumerState<StudentStatusDialog> {
  late StudentStatus _status = widget.student.status;
  DateTime _effectiveDate = SchoolTime.wallNow();
  final _reason = TextEditingController();
  final _notes = TextEditingController();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _effectiveDate = picked);
  }

  Future<void> _submit() async {
    final success = await ref
        .read(studentWriteControllerProvider.notifier)
        .changeStatus(
          schoolId: widget.student.schoolId,
          branchId: widget.student.branchId,
          studentId: widget.student.studentId,
          status: _status,
          effectiveDate: _effectiveDate,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          updatedBy: widget.currentUserId,
        );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(studentWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to change status.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSaving = ref.watch(studentWriteControllerProvider).isLoading;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Change status', style: context.textStyles.titleLarge),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<StudentStatus>(
          isExpanded: true,
          value: _status,
          decoration: const InputDecoration(labelText: 'New status'),
          items: [
            for (final s in StudentStatus.values)
              DropdownMenuItem(value: s, child: Text(s.displayName)),
          ],
          onChanged: (value) => setState(() => _status = value ?? _status),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton(
          onPressed: _pickDate,
          child: Text('Effective: ${formatDisplayDate(_effectiveDate)}'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _reason,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
          maxLines: 2,
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
                  : const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

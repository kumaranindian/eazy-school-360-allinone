import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../domain/staff.dart';
import '../../domain/staff_status.dart';
import '../providers/staff_providers.dart';

/// A lifecycle change (notice, resignation, retirement, ...). Only moves
/// allowed by [StaffStatus.allowedTransitions] are offered; staff are never
/// deleted. Leaving the active workforce ends the member's active teaching
/// assignments — the dialog says so before the admin confirms.
class StaffStatusDialog extends ConsumerStatefulWidget {
  final Staff staff;
  final String currentUserId;

  const StaffStatusDialog({
    super.key,
    required this.staff,
    required this.currentUserId,
  });

  @override
  ConsumerState<StaffStatusDialog> createState() => _StaffStatusDialogState();
}

class _StaffStatusDialogState extends ConsumerState<StaffStatusDialog> {
  late final List<StaffStatus> _options = widget.staff.status.allowedTransitions
      .toList();
  late StaffStatus? _status = _options.isEmpty ? null : _options.first;
  DateTime _effectiveDate = DateTime.now();
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
    final status = _status;
    if (status == null) return;
    final success = await ref
        .read(staffWriteControllerProvider.notifier)
        .changeStatus(
          staff: widget.staff,
          status: status,
          effectiveDate: _effectiveDate,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          updatedBy: widget.currentUserId,
        );
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      final error = ref.read(staffWriteControllerProvider).error;
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
    final isSaving = ref.watch(staffWriteControllerProvider).isLoading;
    final status = _status;

    if (status == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Change status', style: context.textStyles.titleLarge),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${widget.staff.displayName} is ${widget.staff.status.displayName.toLowerCase()}. This status is final and cannot be changed.',
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close'),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Change status', style: context.textStyles.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Currently ${widget.staff.status.displayName.toLowerCase()}.',
          style: context.textStyles.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<StaffStatus>(
          value: status,
          decoration: const InputDecoration(labelText: 'New status'),
          items: [
            for (final s in _options)
              DropdownMenuItem(value: s, child: Text(s.displayName)),
          ],
          onChanged: (value) => setState(() => _status = value ?? _status),
        ),
        if (status.isTerminal)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '${status.displayName} is final — the record is kept but cannot be reactivated.',
              style: context.textStyles.bodySmall,
            ),
          ),
        if (status.endsActiveAssignments && widget.staff.isTeacher)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              "This ends all of the teacher's active class, section and subject assignments as of the effective date. They stay in the assignment history.",
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
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

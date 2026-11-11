import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/extra_placement.dart';
import '../../domain/student.dart';
import '../providers/student_providers.dart';
import 'student_extra_class_dialog.dart';

/// "Extra classes" of a student — e.g. the afternoon day-care class of a
/// child who is in pre-school in the morning. Shown on the Academic tab;
/// adding and removing is for users who can manage student data.
class StudentExtraClassesCard extends ConsumerWidget {
  final Student student;
  final bool canManage;
  final String currentUserId;

  const StudentExtraClassesCard({
    super.key,
    required this.student,
    required this.canManage,
    required this.currentUserId,
  });

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    ExtraPlacement p,
    String name,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove extra class?'),
        content: Text(
          '${student.displayName} will no longer be in $name. Their '
          'attendance and other records there are kept; no new ones are '
          'created.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final success = await ref
        .read(studentWriteControllerProvider.notifier)
        .removeExtraPlacement(
          schoolId: student.schoolId,
          branchId: student.branchId,
          studentId: student.studentId,
          recordId: p.recordId,
          updatedBy: currentUserId,
        );
    if (!context.mounted) return;
    if (success) {
      context.showSnackBar('Extra class removed.');
    } else {
      final error = ref.read(studentWriteControllerProvider).error;
      context.showSnackBar(
        error == null ? 'Unable to remove it.' : userMessageFor(error),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the auto-dispose write controller alive while a save runs.
    ref.watch(studentWriteControllerProvider);
    final extras = student.extraPlacements;
    final canAdd =
        canManage &&
        student.hasCurrentPlacement &&
        extras.length < ExtraPlacement.maxPerStudent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Extra classes',
                    style: context.textStyles.titleMedium,
                  ),
                ),
                if (canAdd)
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add class'),
                    onPressed: () async {
                      final added = await showAdaptiveAppDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => StudentExtraClassDialog(
                          student: student,
                          currentUserId: currentUserId,
                        ),
                      );
                      if (added == true && context.mounted) {
                        context.showSnackBar('Extra class added.');
                      }
                    },
                  ),
              ],
            ),
            Text(
              'For a child who attends a second class, e.g. day care in the '
              'afternoon. The main class stays as it is.',
              style: context.textStyles.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (extras.isEmpty)
              const Text('No extra classes.')
            else
              for (final p in extras)
                _ExtraRow(
                  student: student,
                  placement: p,
                  onRemove: canManage
                      ? (name) => _remove(context, ref, p, name)
                      : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _ExtraRow extends ConsumerWidget {
  final Student student;
  final ExtraPlacement placement;
  final void Function(String name)? onRemove;

  const _ExtraRow({
    required this.student,
    required this.placement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classes = ref
        .watch(
          classesProvider((
            schoolId: student.schoolId,
            branchId: student.branchId,
            academicYearId: placement.academicYearId,
          )),
        )
        .value;
    final sections = ref
        .watch(
          sectionsProvider((
            schoolId: student.schoolId,
            branchId: student.branchId,
            academicYearId: placement.academicYearId,
            classId: placement.classId,
          )),
        )
        .value;
    final className = classes
        ?.where((c) => c.classId == placement.classId)
        .firstOrNull
        ?.name;
    final sectionName = sections
        ?.where((s) => s.sectionId == placement.sectionId)
        .firstOrNull
        ?.name;
    final name = [
      className ?? 'Class',
      if (sectionName != null) sectionName,
    ].join(' - ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.school_outlined),
      title: Text(name),
      subtitle: Text(
        [
          if (placement.label.isNotEmpty) placement.label,
          if ((placement.rollNumber ?? '').isNotEmpty)
            'Roll no ${placement.rollNumber}',
        ].join(' · '),
      ),
      trailing: onRemove == null
          ? null
          : IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
              onPressed: () => onRemove!(name),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/dialogs/app_dialog.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../academic_setup/domain/academic_year.dart';
import '../../../academic_setup/presentation/providers/academic_structure_providers.dart';
import '../../domain/staff.dart';
import '../../domain/teacher_assignment.dart';
import '../providers/academic_names_provider.dart';
import '../providers/staff_providers.dart';
import 'teacher_assignment_dialog.dart';

/// A teacher's classes, sections, subjects and class-teacher duties,
/// grouped by academic year — current *and* ended, so the history of who
/// taught what is always visible. Only managers see the assign / end
/// actions (and the rules enforce it regardless).
class TeachingTab extends ConsumerWidget {
  final Staff staff;
  final bool canManage;
  final String currentUserId;

  const TeachingTab({
    super.key,
    required this.staff,
    required this.canManage,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (
      schoolId: staff.schoolId,
      branchId: staff.branchId,
      staffId: staff.staffId,
    );
    final years =
        ref
            .watch(
              academicYearsProvider((
                schoolId: staff.schoolId,
                branchId: staff.branchId,
              )),
            )
            .value ??
        const <AcademicYear>[];

    return AsyncValueWidget(
      value: ref.watch(teacherAssignmentsProvider(key)),
      errorMessage: userMessageFor,
      data: (assignments) {
        final byYear = <String, List<TeacherAssignment>>{};
        for (final a in assignments) {
          byYear.putIfAbsent(a.academicYearId, () => []).add(a);
        }
        // Years the app knows about first (in its own order), then any
        // year an assignment references that is no longer listed.
        final orderedYearIds = [
          ...years.map((y) => y.academicYearId).where(byYear.containsKey),
          ...byYear.keys.where(
            (id) => !years.any((y) => y.academicYearId == id),
          ),
        ];
        final yearNames = {for (final y in years) y.academicYearId: y.name};

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (canManage)
              Align(
                alignment: Alignment.centerLeft,
                child: staff.canReceiveAssignments
                    ? FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Assign class / subject'),
                        onPressed: () async {
                          final saved = await showAdaptiveAppDialog<bool>(
                            context: context,
                            builder: (context) => TeacherAssignmentDialog(
                              teacher: staff,
                              currentUserId: currentUserId,
                            ),
                          );
                          if (saved == true && context.mounted) {
                            context.showSnackBar(
                              'Assignment saved successfully.',
                            );
                          }
                        },
                      )
                    : Text(
                        'New assignments are only available while the staff member is active.',
                        style: context.textStyles.bodySmall,
                      ),
              ),
            const SizedBox(height: AppSpacing.md),
            if (orderedYearIds.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: EmptyView(
                  icon: Icons.class_outlined,
                  message: 'No teaching assignments yet.',
                ),
              )
            else
              for (final yearId in orderedYearIds)
                _YearSection(
                  staff: staff,
                  yearId: yearId,
                  yearName: yearNames[yearId] ?? 'Academic year',
                  assignments: byYear[yearId]!,
                  canManage: canManage,
                  currentUserId: currentUserId,
                  initiallyExpanded: yearId == orderedYearIds.first,
                ),
          ],
        );
      },
    );
  }
}

class _YearSection extends ConsumerWidget {
  final Staff staff;
  final String yearId;
  final String yearName;
  final List<TeacherAssignment> assignments;
  final bool canManage;
  final String currentUserId;
  final bool initiallyExpanded;

  const _YearSection({
    required this.staff,
    required this.yearId,
    required this.yearName,
    required this.assignments,
    required this.canManage,
    required this.currentUserId,
    required this.initiallyExpanded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final namesAsync = ref.watch(
      academicNamesProvider((
        schoolId: staff.schoolId,
        branchId: staff.branchId,
        academicYearId: yearId,
      )),
    );
    final activeCount = assignments.where((a) => a.isActive).length;

    // Active first, then by start date (newest first).
    final sorted = [...assignments]
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return b.startDate.compareTo(a.startDate);
      });

    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text(yearName),
        subtitle: Text(
          '$activeCount active · ${assignments.length - activeCount} ended',
        ),
        children: [
          namesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: LinearProgressIndicator(),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(userMessageFor(error)),
            ),
            data: (names) => Column(
              children: [
                for (final a in sorted)
                  ListTile(
                    leading: Icon(
                      a.isClassTeacher
                          ? Icons.star_outline
                          : Icons.menu_book_outlined,
                    ),
                    title: Text(
                      a.isClassTeacher
                          ? '${names.classSection(a.classId, a.sectionId)} · Class teacher'
                          : '${names.classSection(a.classId, a.sectionId)} · ${names.subjectName(a.subjectId)}',
                    ),
                    subtitle: Text(
                      a.isActive
                          ? 'Since ${formatDisplayDate(a.startDate)}'
                          : 'Ended · ${formatDisplayDate(a.startDate)} – ${a.endDate == null ? '' : formatDisplayDate(a.endDate!)}',
                    ),
                    trailing: canManage && a.isActive
                        ? TextButton(
                            onPressed: () => _end(context, ref, a),
                            child: const Text('End'),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _end(
    BuildContext context,
    WidgetRef ref,
    TeacherAssignment assignment,
  ) async {
    final now = DateTime.now();
    final endDate = await showDatePicker(
      context: context,
      helpText: 'Assignment end date',
      initialDate: now.isBefore(assignment.startDate)
          ? assignment.startDate
          : now,
      firstDate: assignment.startDate,
      lastDate: DateTime(now.year + 2),
    );
    if (endDate == null || !context.mounted) return;

    final success = await ref
        .read(teacherAssignmentWriteControllerProvider.notifier)
        .end(assignment, endDate: endDate, updatedBy: currentUserId);
    if (!context.mounted) return;
    if (success) {
      context.showSnackBar('Assignment ended. It stays in the history.');
    } else {
      final error = ref.read(teacherAssignmentWriteControllerProvider).error;
      context.showSnackBar(
        error == null
            ? 'Unable to end this assignment.'
            : userMessageFor(error),
        isError: true,
      );
    }
  }
}

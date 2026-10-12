import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/timetable_enums.dart';
import '../../domain/timetable_validation.dart';

/// Validation results, errors first. Each message names the day, period,
/// teacher, class or room involved.
class IssueList extends StatelessWidget {
  final List<TimetableIssue> issues;
  final String okMessage;

  const IssueList({
    super.key,
    required this.issues,
    this.okMessage = 'No problems found.',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (issues.isEmpty) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(okMessage)),
        ],
      );
    }
    final errors = issues.where((i) => i.isError).toList();
    final warnings = issues.where((i) => !i.isError).toList();
    Widget tile(TimetableIssue i) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            i.isError ? Icons.error_outline : Icons.warning_amber_outlined,
            size: 20,
            color: i.isError
                ? theme.colorScheme.error
                : theme.colorScheme.tertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(i.message)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (errors.isNotEmpty) ...[
          Text(
            '${errors.length} problem${errors.length == 1 ? '' : 's'} to fix',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final i in errors) tile(i),
        ],
        if (warnings.isNotEmpty) ...[
          Text(
            '${warnings.length} thing${warnings.length == 1 ? '' : 's'} to be aware of',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final i in warnings) tile(i),
        ],
      ],
    );
  }
}

String issueSummary(List<TimetableIssue> issues) {
  final e = issues.where((i) => i.isError).length;
  final w = issues.length - e;
  if (issues.isEmpty) return 'No problems';
  return [
    if (e > 0) '$e problem${e == 1 ? '' : 's'}',
    if (w > 0) '$w warning${w == 1 ? '' : 's'}',
  ].join(' · ');
}

extension IssueKindLabel on IssueKind {
  String get label => switch (this) {
    IssueKind.teacherConflict => 'Teacher double-booked',
    IssueKind.roomConflict => 'Room double-booked',
    IssueKind.notAssigned => 'Teacher not assigned',
    IssueKind.invalidSlot => 'Invalid period',
    IssueKind.nonWorkingDay => 'Non-working day',
    IssueKind.missingPeriodSet => 'Missing schedule',
    IssueKind.sectionOverlap => 'Replaces a version',
    IssueKind.teacherOnLeave => 'Teacher on leave',
    IssueKind.empty => 'Empty',
    IssueKind.stalePeriods => 'Out of date',
  };
}

import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/attendance_status.dart';
import '../../domain/attendance_tally.dart';
import 'attendance_status_buttons.dart';

/// Total · Present · Absent · Late · Half day · Not marked.
class AttendanceSummaryBar extends StatelessWidget {
  final AttendanceTally tally;
  final String totalLabel;

  const AttendanceSummaryBar({
    super.key,
    required this.tally,
    this.totalLabel = 'Total',
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, int value, {Color? color}) {
      return Chip(
        visualDensity: VisualDensity.compact,
        side: BorderSide(
          color: (color ?? Theme.of(context).colorScheme.outline).withValues(
            alpha: 0.5,
          ),
        ),
        label: Text('$label: $value', style: TextStyle(color: color)),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        chip(totalLabel, tally.total),
        for (final status in AttendanceStatus.values)
          chip(
            status.displayName,
            tally.countOf(status),
            color: attendanceStatusColor(context, status),
          ),
        chip('Not marked', tally.notMarked),
      ],
    );
  }
}

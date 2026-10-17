import 'package:flutter/material.dart';

import '../../domain/staff_status.dart';

class StaffStatusChip extends StatelessWidget {
  final StaffStatus status;

  /// Drops the 48px tap-target padding, for chips inside list rows that are
  /// tappable as a whole.
  final bool dense;

  const StaffStatusChip({super.key, required this.status, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      StaffStatus.active => scheme.primary,
      StaffStatus.onNotice => scheme.tertiary,
      StaffStatus.terminated => scheme.error,
      StaffStatus.inactive ||
      StaffStatus.resigned ||
      StaffStatus.retired => scheme.outline,
    };
    return Chip(
      label: Text(
        status.displayName,
        style: TextStyle(color: color, fontSize: 12),
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: dense ? MaterialTapTargetSize.shrinkWrap : null,
      side: BorderSide(color: color.withValues(alpha: 0.4)),
    );
  }
}

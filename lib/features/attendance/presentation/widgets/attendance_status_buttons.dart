import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

import '../../domain/attendance_status.dart';

Color attendanceStatusColor(BuildContext context, AttendanceStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    AttendanceStatus.present => AppColors.success,
    AttendanceStatus.absent => scheme.error,
    AttendanceStatus.late => AppColors.warning,
    AttendanceStatus.halfDay => scheme.tertiary,
  };
}

/// P / A / L / H selector. Each target is at least 44×44 (48 on touch
/// layouts) and focusable, so it is quick with a thumb or a keyboard. The
/// current choice is shown by fill *and* by the letter/tooltip, not by colour
/// alone.
class AttendanceStatusButtons extends StatelessWidget {
  final AttendanceStatus? selected;
  final bool enabled;
  final bool expanded;
  final ValueChanged<AttendanceStatus> onSelected;

  const AttendanceStatusButtons({
    super.key,
    required this.selected,
    required this.enabled,
    this.expanded = false,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (final status in AttendanceStatus.values)
        _StatusButton(
          status: status,
          isSelected: selected == status,
          enabled: enabled,
          onTap: () => onSelected(status),
        ),
    ];
    if (expanded) {
      return Row(
        children: [
          for (final b in buttons)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: b,
              ),
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in buttons)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: b),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  final AttendanceStatus status;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  const _StatusButton({
    required this.status,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = attendanceStatusColor(context, status);
    return Semantics(
      button: true,
      selected: isSelected,
      label: status.displayName,
      child: Tooltip(
        message: status.displayName,
        child: Material(
          color: isSelected ? color : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: enabled ? color : Theme.of(context).disabledColor,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Center(
                child: Text(
                  status.shortLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? Colors.white
                        : (enabled ? color : Theme.of(context).disabledColor),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

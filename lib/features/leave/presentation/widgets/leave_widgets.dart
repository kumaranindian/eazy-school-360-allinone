import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/leave_application.dart';
import '../../domain/leave_enums.dart';
import '../../domain/leave_units.dart';

String leaveDate(String key) {
  final p = key.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : key;
}

String leaveRange(LeaveApplication a) => a.startDateKey == a.endDateKey
    ? leaveDate(a.startDateKey)
    : '${leaveDate(a.startDateKey)} to ${leaveDate(a.endDateKey)}';

String leaveSession(HalfDay h) =>
    h == HalfDay.none ? '' : ' (${h.displayName})';

class LeaveStatusChip extends StatelessWidget {
  final LeaveStatus status;

  const LeaveStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      LeaveStatus.approved => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      LeaveStatus.pending => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      LeaveStatus.rejected => (scheme.errorContainer, scheme.onErrorContainer),
      LeaveStatus.returned => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      LeaveStatus.withdrawn || LeaveStatus.cancelled => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Chip(
      label: Text(status.displayName),
      backgroundColor: bg,
      labelStyle: TextStyle(color: fg),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      padding: EdgeInsets.zero,
    );
  }
}

/// One application as a card (mobile) / list tile.
class LeaveApplicationTile extends StatelessWidget {
  final LeaveApplication application;
  final VoidCallback? onTap;
  final bool showSubject;

  const LeaveApplicationTile({
    super.key,
    required this.application,
    this.onTap,
    this.showSubject = true,
  });

  @override
  Widget build(BuildContext context) {
    final a = application;
    final theme = Theme.of(context);
    final classPart = a.className == null
        ? ''
        : ' · ${a.className}${a.sectionName == null ? '' : ' ${a.sectionName}'}';
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showSubject ? '${a.subjectName}$classPart' : a.typeName,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${showSubject ? '${a.typeName} · ' : ''}'
                      '${leaveRange(a)}${leaveSession(a.halfDay)} · '
                      '${LeaveUnits.formatDays(a.units)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              LeaveStatusChip(a.status),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for remarks and returns them, or null if cancelled. [required] makes
/// an empty answer invalid. The caller does the confirmed action.
Future<String?> askLeaveRemarks(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required String message,
  bool required = true,
  bool destructive = false,
}) {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: required ? 'Remarks' : 'Remarks (optional)',
              ),
              validator: (v) => required && (v ?? '').trim().length < 3
                  ? 'Give a reason.'
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/permissions/permission.dart';
import '../../../../core/regional/school_time.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/layouts/section_page.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/fee_reminder_settings.dart';
import '../providers/fee_reminder_providers.dart';

/// Settings → Fee reminders: when parents are reminded about an invoice (days
/// before and after the due date), at what time, and what the text shows.
/// One policy for the whole school; the time zone is the Regional setting. The
/// server validates every save and runs the schedule.
class FeeReminderSettingsPage extends ConsumerStatefulWidget {
  const FeeReminderSettingsPage({super.key});

  @override
  ConsumerState<FeeReminderSettingsPage> createState() =>
      _FeeReminderSettingsPageState();
}

class _FeeReminderSettingsPageState
    extends ConsumerState<FeeReminderSettingsPage> {
  FeeReminderSettings? _draft;
  bool _saving = false;
  String? _error;

  void _edit(FeeReminderSettings next) => setState(() {
    _draft = next;
    _error = null;
  });

  Future<void> _save(
    String schoolId,
    FeeReminderSettings saved,
    FeeReminderSettings draft,
  ) async {
    if (_saving) return;
    final problem = draft.validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final stopsAll = draft.nothingWillSend && !saved.nothingWillSend;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          stopsAll ? 'Turn off all fee reminders?' : 'Save fee reminders?',
        ),
        content: Text(
          stopsAll
              ? 'Parents will no longer get any reminder about fees that are '
                    'due or overdue. Payment receipts are not affected.'
              : 'This applies to every branch of the school from the next '
                    'reminder run. Reminders already sent are not repeated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(stopsAll ? 'Turn off' : 'Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(feeReminderSettingsRepositoryProvider)
          .save(schoolId, draft);
      ref.invalidate(feeReminderSettingsProvider(schoolId));
      if (!mounted) return;
      setState(() {
        _saving = false;
        _draft = null;
      });
      context.showSnackBar('Fee reminder settings saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = userMessageFor(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantState = ref.watch(tenantContextProvider);
    return AsyncValueWidget(
      value: tenantState,
      data: (tenant) {
        if (tenant?.school == null) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message: 'No school found for your account.',
          );
        }
        if (!tenant!.can(Permission.manageSchool)) {
          return const EmptyView(
            icon: Icons.lock_outline,
            message: 'Only school administrators can change fee reminders.',
          );
        }
        final school = tenant.school!;
        final schoolId = school.schoolId;
        final async = ref.watch(feeReminderSettingsProvider(schoolId));
        return AsyncValueWidget(
          value: async,
          errorMessage: userMessageFor,
          onRetry: () => ref.invalidate(feeReminderSettingsProvider(schoolId)),
          data: (saved) {
            final current = _draft ?? saved;
            final dirty = current != saved;
            return SectionPage(
              title: 'Fee reminders',
              description:
                  'Remind parents about fees that are coming due or overdue. '
                  'Reminders go to the parents linked to the student, in the '
                  'app, at the time you choose.',
              parentRoute: AppRoutes.settings,
              parentLabel: 'Settings',
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GeneralCard(
                      settings: current,
                      timezone: school.regional.timezone,
                      enabled: !_saving,
                      onChanged: _edit,
                    ),
                    _StepsCard(
                      key: const ValueKey('before'),
                      title: 'Before the due date',
                      caption:
                          'Remind this many days ahead. 0 means on the due date.',
                      after: false,
                      groupEnabled: current.beforeEnabled,
                      steps: current.before,
                      enabled: !_saving && current.enabled,
                      onGroup: (v) => _edit(current.copyWith(beforeEnabled: v)),
                      onSteps: (v) => _edit(current.copyWith(before: v)),
                    ),
                    _StepsCard(
                      key: const ValueKey('after'),
                      title: 'After the due date (overdue)',
                      caption:
                          'Remind this many days after an unpaid invoice was due.',
                      after: true,
                      groupEnabled: current.afterEnabled,
                      steps: current.after,
                      enabled: !_saving && current.enabled,
                      onGroup: (v) => _edit(current.copyWith(afterEnabled: v)),
                      onSteps: (v) => _edit(current.copyWith(after: v)),
                    ),
                    _PreviewCard(
                      settings: current,
                      currency: school.regional.currency,
                    ),
                    _AuditLine(
                      saved: saved,
                      isDefault: saved.updatedAt == null,
                      me: tenant.user.userId,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        TextButton(
                          onPressed: _saving || !dirty
                              ? null
                              : () => setState(() {
                                  _draft = null;
                                  _error = null;
                                }),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: _saving || !dirty
                              ? null
                              : () => _save(schoolId, saved, current),
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save changes'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _GeneralCard extends StatelessWidget {
  final FeeReminderSettings settings;
  final String timezone;
  final bool enabled;
  final ValueChanged<FeeReminderSettings> onChanged;

  const _GeneralCard({
    required this.settings,
    required this.timezone,
    required this.enabled,
    required this.onChanged,
  });

  Future<void> _pickTime(BuildContext context) async {
    final minutes = FeeReminderSettings.minutesOf(settings.deliveryTime) ?? 480;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    onChanged(settings.copyWith(deliveryTime: '$hh:$mm'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('General', style: theme.textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Send fee reminders'),
              subtitle: const Text(
                'Turn off to stop every reminder below for this school.',
              ),
              value: settings.enabled,
              onChanged: enabled
                  ? (v) => onChanged(settings.copyWith(enabled: v))
                  : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Delivery time'),
              subtitle: Text(
                '${settings.deliveryTime} in $timezone (the school\'s '
                'Regional setting). If a run is missed it is retried for '
                'the next 3 hours.',
              ),
              trailing: const Icon(Icons.schedule_outlined),
              enabled: enabled && settings.enabled,
              onTap: enabled && settings.enabled
                  ? () => _pickTime(context)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show the invoice amount'),
              subtitle: const Text(
                'The amount still to pay appears on the lock screen.',
              ),
              value: settings.includeAmount,
              onChanged: enabled && settings.enabled
                  ? (v) => onChanged(settings.copyWith(includeAmount: v))
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show the invoice number'),
              value: settings.includeInvoiceNumber,
              onChanged: enabled && settings.enabled
                  ? (v) => onChanged(settings.copyWith(includeInvoiceNumber: v))
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  final String title;
  final String caption;
  final bool after;
  final bool groupEnabled;
  final List<ReminderStep> steps;
  final bool enabled;
  final ValueChanged<bool> onGroup;
  final ValueChanged<List<ReminderStep>> onSteps;

  const _StepsCard({
    super.key,
    required this.title,
    required this.caption,
    required this.after,
    required this.groupEnabled,
    required this.steps,
    required this.enabled,
    required this.onGroup,
    required this.onSteps,
  });

  String _label(int days) {
    if (!after && days == 0) return 'On the due date';
    final unit = days == 1 ? 'day' : 'days';
    return after ? '$days $unit after' : '$days $unit before';
  }

  Future<void> _add(BuildContext context) async {
    final days = await showDialog<int>(
      context: context,
      builder: (context) => _AddDaysDialog(existing: steps, after: after),
    );
    if (days == null) return;
    final next = [...steps, ReminderStep(days)];
    next.sort((a, b) => after ? a.days - b.days : b.days - a.days);
    onSteps(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = enabled && groupEnabled;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title, style: theme.textTheme.titleMedium),
              subtitle: Text(caption),
              value: groupEnabled,
              onChanged: enabled ? onGroup : null,
            ),
            if (steps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  'No reminders in this list.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            for (final s in steps)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _label(s.days),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: active && s.enabled ? null : theme.disabledColor,
                      ),
                    ),
                  ),
                  Switch(
                    value: s.enabled,
                    onChanged: active
                        ? (v) => onSteps([
                            for (final o in steps)
                              o == s ? o.copyWith(enabled: v) : o,
                          ])
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Remove ${_label(s.days)}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: active
                        ? () => onSteps([
                            for (final o in steps)
                              if (o != s) o,
                          ])
                        : null,
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: active && steps.length < FeeReminderSettings.maxSteps
                    ? () => _add(context)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add a reminder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddDaysDialog extends StatefulWidget {
  final List<ReminderStep> existing;
  final bool after;
  const _AddDaysDialog({required this.existing, required this.after});

  @override
  State<_AddDaysDialog> createState() => _AddDaysDialogState();
}

class _AddDaysDialogState extends State<_AddDaysDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final days = int.tryParse(_controller.text.trim());
    final problem = FeeReminderSettings.checkDays(
      days,
      widget.existing,
      after: widget.after,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(days);
  }

  @override
  Widget build(BuildContext context) {
    final max = widget.after
        ? FeeReminderSettings.maxAfterDays
        : FeeReminderSettings.maxBeforeDays;
    return AlertDialog(
      title: Text(widget.after ? 'Add an overdue reminder' : 'Add a reminder'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: widget.after
              ? 'Days after the due date (1-$max)'
              : 'Days before the due date (0-$max)',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final FeeReminderSettings settings;
  final String currency;
  const _PreviewCard({required this.settings, required this.currency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = SchoolTime.formatDate(
      SchoolTime.today().add(const Duration(days: 3)),
    );
    final rows = <FeeReminderPreview>[];
    FeeReminderPreview make(bool after, int days) => FeeReminderPreview.build(
      afterDue: after,
      days: days,
      studentName: 'Asha Rao',
      invoiceNumber: 'INV-0042',
      dueDateText: due,
      balanceMinor: 150000,
      currency: currency,
      settings: settings,
    );
    if (settings.enabled) {
      if (settings.beforeEnabled) {
        for (final s in settings.before.where((s) => s.enabled)) {
          rows.add(make(false, s.days));
        }
      }
      if (settings.afterEnabled) {
        for (final s in settings.after.where((s) => s.enabled)) {
          rows.add(make(true, s.days));
        }
      }
    }
    // One example of each kind is enough to read the wording.
    final shown = <FeeReminderPreview>[];
    final kinds = <String>{};
    for (final r in rows) {
      if (kinds.add(r.title)) shown.add(r);
    }
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What parents will see', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Examples with a sample student and invoice. The real message '
              'uses the student, invoice and current balance.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (shown.isEmpty)
              Text(
                'No reminders will be sent with these settings.',
                style: theme.textTheme.bodyMedium,
              ),
            for (final p in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(p.title),
                  subtitle: Text(p.body),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AuditLine extends StatelessWidget {
  final FeeReminderSettings saved;
  final bool isDefault;
  final String me;
  const _AuditLine({
    required this.saved,
    required this.isDefault,
    required this.me,
  });

  @override
  Widget build(BuildContext context) {
    final at = saved.updatedAt;
    final text = isDefault || at == null
        ? 'Not saved yet: the standard reminders are in use.'
        : 'Last updated ${SchoolTime.formatInstant(at)} by '
              '${saved.updatedBy == me ? 'you' : 'another administrator'}.';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../domain/platform_ops_models.dart';
import '../../domain/platform_role.dart';
import '../../domain/school_overview.dart';
import '../providers/platform_ops_providers.dart';

/// Client-side checks mirroring the server (which always has the last word).
bool validCalendarDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s.trim());
  if (m == null) return false;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final t = DateTime.utc(y, mo, d);
  return t.year == y && t.month == mo && t.day == d;
}

/// A school's subscription: what it is, its dates in the school's own time
/// zone, and (owners) set / extend / renew / cancel / trial, with history.
class SchoolSubscriptionPanel extends ConsumerStatefulWidget {
  final SchoolOverview overview;
  final PlatformRole role;

  const SchoolSubscriptionPanel({
    super.key,
    required this.overview,
    required this.role,
  });

  @override
  ConsumerState<SchoolSubscriptionPanel> createState() =>
      _SchoolSubscriptionPanelState();
}

class _SchoolSubscriptionPanelState
    extends ConsumerState<SchoolSubscriptionPanel> {
  bool _history = false;

  Future<void> _open(String mode) async {
    final done = await showDialog<String>(
      context: context,
      builder: (_) => SubscriptionDialog(
        mode: mode,
        schoolId: widget.overview.id,
        schoolName: widget.overview.name,
        current: widget.overview.subscription,
      ),
    );
    if (done != null && mounted) context.showSnackBar(done);
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.overview;
    final s = o.subscription;
    final owner = widget.role == PlatformRole.owner;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Subscription', style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s == null)
                    Text(
                      'No subscription. This is a school from before subscriptions, so access is not limited by one.',
                      key: const ValueKey('sub-none'),
                      style: text.bodyMedium,
                    )
                  else ...[
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          key: const ValueKey('sub-status'),
                          label: Text(
                            OverviewSubscription.statusLabel(s.status),
                          ),
                          backgroundColor: s.blocking
                              ? scheme.errorContainer
                              : null,
                        ),
                        Text(
                          '${s.classification == 'TRIAL' ? 'Trial' : 'Paid'}'
                          '${s.planName == null ? '' : ' · ${s.planName}'}',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Valid ${s.startDate} to ${s.endDate} (school time zone ${o.timezone.isEmpty ? 'UTC' : o.timezone})',
                      key: const ValueKey('sub-dates'),
                    ),
                    if (s.gracePeriodDays > 0)
                      Text('Grace period: ${s.gracePeriodDays} days'),
                    if (s.status == 'NOT_STARTED')
                      Text(
                        'The school is paused until the start date.',
                        style: text.bodySmall,
                      ),
                    if (s.status == 'EXPIRED' || s.status == 'CANCELLED')
                      Text(
                        'The school is paused. Renew to switch it back on.',
                        style: text.bodySmall,
                      ),
                    if ((s.cancellationReason ?? '').isNotEmpty)
                      Text('Cancelled: ${s.cancellationReason}'),
                    if ((s.remarks ?? '').isNotEmpty)
                      Text('Remarks: ${s.remarks}'),
                    if ((s.internalNotes ?? '').isNotEmpty)
                      Text(
                        'Internal notes: ${s.internalNotes}',
                        style: text.bodySmall,
                      ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (owner && s == null) ...[
                        FilledButton(
                          key: const ValueKey('sub-set'),
                          onPressed: () => _open('set'),
                          child: const Text('Set subscription'),
                        ),
                        OutlinedButton(
                          key: const ValueKey('sub-trial'),
                          onPressed: () => _open('trial'),
                          child: const Text('Grant trial'),
                        ),
                      ],
                      if (owner && s != null) ...[
                        OutlinedButton(
                          key: const ValueKey('sub-change'),
                          onPressed: () => _open('set'),
                          child: const Text('Change'),
                        ),
                        if (s.status != 'CANCELLED')
                          OutlinedButton(
                            key: const ValueKey('sub-extend'),
                            onPressed: () => _open('extend'),
                            child: const Text('Extend'),
                          ),
                        FilledButton(
                          key: const ValueKey('sub-renew'),
                          onPressed: () => _open('renew'),
                          child: const Text('Renew'),
                        ),
                        if (s.status != 'CANCELLED')
                          TextButton(
                            key: const ValueKey('sub-cancel'),
                            onPressed: () => _open('cancel'),
                            child: const Text('Cancel subscription'),
                          ),
                        if (s.blocking)
                          OutlinedButton(
                            key: const ValueKey('sub-trial'),
                            onPressed: () => _open('trial'),
                            child: const Text('Grant trial'),
                          ),
                      ],
                      if (s != null)
                        TextButton(
                          key: const ValueKey('sub-history-toggle'),
                          onPressed: () => setState(() => _history = !_history),
                          child: Text(
                            _history ? 'Hide history' : 'Show history',
                          ),
                        ),
                    ],
                  ),
                  if (_history && s != null) _History(schoolId: o.id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _History extends ConsumerWidget {
  final String schoolId;

  const _History({required this.schoolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(subscriptionHistoryProvider(schoolId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Text(userMessageFor(e)),
      data: (list) => list.isEmpty
          ? const Text('No history yet.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in list)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '${formatInstant(e.at)} · ${e.label}'
                      '${e.toStatus == null ? '' : ' → ${OverviewSubscription.statusLabel(e.toStatus!)}'}'
                      ' · ${e.actor}${(e.reason ?? '').isEmpty ? '' : ' · ${e.reason}'}',
                      key: ValueKey('sub-history-${e.id}'),
                      style: text.bodySmall,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// One dialog for every subscription operation; only the fields that
/// operation needs are shown. Closes with a message once the server accepts.
class SubscriptionDialog extends ConsumerStatefulWidget {
  /// set | extend | renew | cancel | trial
  final String mode;
  final String schoolId;
  final String schoolName;
  final OverviewSubscription? current;

  const SubscriptionDialog({
    super.key,
    required this.mode,
    required this.schoolId,
    required this.schoolName,
    required this.current,
  });

  @override
  ConsumerState<SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends ConsumerState<SubscriptionDialog> {
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _grace = TextEditingController(text: '0');
  final _days = TextEditingController(text: '14');
  final _reason = TextEditingController();
  final _remarks = TextEditingController();
  final _notes = TextEditingController();
  String? _plan;
  String _class = 'PAID';
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    if (widget.mode == 'set' && c != null) {
      _start.text = c.startDate;
      _end.text = c.endDate;
      _grace.text = '${c.gracePeriodDays}';
      _class = c.classification;
      _remarks.text = c.remarks ?? '';
      _notes.text = c.internalNotes ?? '';
    }
    if (widget.mode == 'extend' && c != null) _end.text = c.endDate;
  }

  @override
  void dispose() {
    for (final c in [_start, _end, _grace, _days, _reason, _remarks, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _title => switch (widget.mode) {
    'set' =>
      widget.current == null ? 'Set subscription' : 'Change subscription',
    'extend' => 'Extend subscription',
    'renew' => 'Renew subscription',
    'cancel' => 'Cancel subscription',
    _ => 'Grant a trial',
  };

  bool get _needsReason =>
      widget.mode == 'extend' ||
      widget.mode == 'cancel' ||
      (widget.mode == 'set' && widget.current != null);

  String? _check() {
    final m = widget.mode;
    String? problem;
    if (m == 'set') {
      final g = int.tryParse(_grace.text.trim());
      if (_class == 'PAID' && _plan == null) {
        problem = 'Choose a plan.';
      } else if (!validCalendarDate(_start.text)) {
        problem = 'Enter a real start date (YYYY-MM-DD).';
      } else if (!validCalendarDate(_end.text)) {
        problem = 'Enter a real end date (YYYY-MM-DD).';
      } else if (_end.text.trim().compareTo(_start.text.trim()) < 0) {
        problem = 'The end date cannot be before the start date.';
      } else if (g == null || g < 0 || g > 90) {
        problem = 'Grace period must be 0 to 90 whole days.';
      }
    } else if (m == 'extend' || m == 'renew') {
      if (!validCalendarDate(_end.text)) {
        problem = 'Enter a real end date (YYYY-MM-DD).';
      } else if (m == 'renew' &&
          _start.text.trim().isNotEmpty &&
          !validCalendarDate(_start.text)) {
        problem = 'Enter a real start date (YYYY-MM-DD), or leave it empty.';
      }
    } else if (m == 'trial') {
      final d = int.tryParse(_days.text.trim());
      if (d == null || d < 1 || d > 90) {
        problem = 'A trial lasts 1 to 90 whole days.';
      }
    }
    if (problem == null && _needsReason && _reason.text.trim().length < 10) {
      problem = 'Give a reason of at least 10 characters.';
    }
    return problem;
  }

  Future<void> _save() async {
    final problem = _check();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() => _error = null);
    final ops = ref.read(platformOpsActionsProvider.notifier);
    final ok = await ops.subscription(
      widget.mode,
      widget.schoolId,
      planId: _plan,
      classification: widget.mode == 'set' ? _class : null,
      startDate:
          (widget.mode == 'set' || widget.mode == 'renew') &&
              _start.text.trim().isNotEmpty
          ? _start.text
          : null,
      endDate:
          widget.mode == 'set' ||
              widget.mode == 'extend' ||
              widget.mode == 'renew'
          ? _end.text
          : null,
      gracePeriodDays: widget.mode == 'set'
          ? int.tryParse(_grace.text.trim())
          : null,
      days: widget.mode == 'trial' ? int.tryParse(_days.text.trim()) : null,
      reason: _reason.text,
      remarks: widget.mode == 'set' || widget.mode == 'trial'
          ? _remarks.text
          : null,
      internalNotes: widget.mode == 'set' ? _notes.text : null,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, switch (widget.mode) {
        'cancel' => 'Subscription cancelled.',
        'trial' => 'Trial granted.',
        'extend' => 'Subscription extended.',
        'renew' => 'Subscription renewed.',
        _ => 'Subscription saved.',
      });
    } else {
      setState(
        () => _error = userMessageFor(
          ref.read(platformOpsActionsProvider).error!,
        ),
      );
    }
  }

  Future<void> _newPlan() async {
    final made = await showDialog<bool>(
      context: context,
      builder: (_) => const _PlanDialog(),
    );
    if (made == true && mounted) ref.invalidate(platformPlansProvider);
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final plans = [
      for (final p
          in ref.watch(platformPlansProvider).value ?? const <PlatformPlan>[])
        if (p.active) p,
    ];
    final m = widget.mode;
    final showPlan = m == 'set' || m == 'renew' || m == 'trial';
    return AlertDialog(
      title: Text('$_title · ${widget.schoolName}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (m == 'cancel')
                const Text(
                  'The school is paused straight away. Renew later to bring it back.',
                ),
              if (showPlan)
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('sub-plan'),
                        isExpanded: true,
                        value: plans.any((p) => p.id == _plan) ? _plan : null,
                        decoration: InputDecoration(
                          labelText: m == 'set' && _class == 'PAID'
                              ? 'Plan'
                              : 'Plan (optional)',
                        ),
                        items: [
                          for (final p in plans)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                '${p.name} · ${PlatformPlan.periodLabel(p.periodType)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(() => _plan = v),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('sub-new-plan'),
                      tooltip: 'New plan',
                      icon: const Icon(Icons.add),
                      onPressed: busy ? null : _newPlan,
                    ),
                  ],
                ),
              if (m == 'set')
                DropdownButtonFormField<String>(
                  key: const ValueKey('sub-class'),
                  value: _class,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: 'PAID', child: Text('Paid')),
                    DropdownMenuItem(value: 'TRIAL', child: Text('Trial')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => _class = v ?? _class),
                ),
              if (m == 'set' || m == 'renew')
                TextField(
                  key: const ValueKey('sub-start'),
                  controller: _start,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: m == 'renew'
                        ? 'Start date (optional, default: day after the current end)'
                        : 'Start date',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
              if (m == 'set' || m == 'extend' || m == 'renew')
                TextField(
                  key: const ValueKey('sub-end'),
                  controller: _end,
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: m == 'extend' ? 'New end date' : 'End date',
                    hintText: 'YYYY-MM-DD',
                  ),
                ),
              if (m == 'set')
                TextField(
                  key: const ValueKey('sub-grace'),
                  controller: _grace,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Grace period (days after the end date)',
                  ),
                ),
              if (m == 'trial')
                TextField(
                  key: const ValueKey('sub-days'),
                  controller: _days,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Trial length (days, starting today)',
                  ),
                ),
              if (m == 'set' || m == 'trial')
                TextField(
                  key: const ValueKey('sub-remarks'),
                  controller: _remarks,
                  enabled: !busy,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Remarks (optional)',
                  ),
                ),
              if (m == 'set')
                TextField(
                  key: const ValueKey('sub-notes'),
                  controller: _notes,
                  enabled: !busy,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    labelText: 'Internal notes (platform only)',
                  ),
                ),
              if (_needsReason || m == 'renew' || m == 'trial')
                TextField(
                  key: const ValueKey('sub-reason'),
                  controller: _reason,
                  enabled: !busy,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: _needsReason ? 'Reason' : 'Reason (optional)',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    _error!,
                    key: const ValueKey('sub-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          key: const ValueKey('sub-save'),
          onPressed: busy ? null : _save,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(m == 'cancel' ? 'Cancel subscription' : 'Save'),
        ),
      ],
    );
  }
}

class _PlanDialog extends ConsumerStatefulWidget {
  const _PlanDialog();

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  final _name = TextEditingController();
  String _period = 'ANNUAL';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _savePlan() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter the plan name.');
      return;
    }
    final ok = await ref
        .read(platformOpsActionsProvider.notifier)
        .savePlan(name: _name.text, periodType: _period);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(
        () => _error = userMessageFor(
          ref.read(platformOpsActionsProvider).error!,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    return AlertDialog(
      title: const Text('New plan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('plan-name'),
            controller: _name,
            enabled: !busy,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Plan name'),
          ),
          DropdownButtonFormField<String>(
            key: const ValueKey('plan-period'),
            value: _period,
            decoration: const InputDecoration(labelText: 'Period'),
            items: [
              for (final p in PlatformPlan.periodTypes)
                DropdownMenuItem(
                  value: p,
                  child: Text(PlatformPlan.periodLabel(p)),
                ),
            ],
            onChanged: busy
                ? null
                : (v) => setState(() => _period = v ?? _period),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('plan-save'),
          onPressed: busy ? null : _savePlan,
          child: const Text('Save plan'),
        ),
      ],
    );
  }
}

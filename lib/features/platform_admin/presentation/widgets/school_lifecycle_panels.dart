import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/features/feature_catalogue.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../../fees/domain/money.dart';
import '../../domain/platform_ops_models.dart';
import '../../domain/platform_role.dart';
import '../../domain/school_overview.dart';
import '../providers/platform_ops_providers.dart';
import 'billing_dialogs.dart';
import 'platform_dialogs.dart';

/// A titled card used by every lifecycle panel.
class _Panel extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Panel({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}

void _report(BuildContext context, WidgetRef ref, bool ok, String done) {
  if (!context.mounted) return;
  if (ok) {
    context.showSnackBar(done);
  } else {
    context.showSnackBar(
      userMessageFor(ref.read(platformOpsActionsProvider).error!),
      isError: true,
    );
  }
}

/// The school's lifecycle: activate, deactivate, suspend, reactivate, and (for a
/// CLOSED school) the two-owner recovery. Owners only; everyone else reads.
class SchoolStatusPanel extends ConsumerWidget {
  final SchoolOverview overview;
  final PlatformRole role;
  final String myUid;

  const SchoolStatusPanel({
    super.key,
    required this.overview,
    required this.role,
    this.myUid = '',
  });

  static String describe(SchoolOverview o) => switch (o.status) {
    'INACTIVE' =>
      'This school is inactive: it has not been activated yet. All of its users are paused.',
    'SUSPENDED' => 'This school is suspended. All of its users are paused.',
    'EXPIRED' =>
      'This school\'s subscription has expired. All of its users are paused.',
    'CLOSED' =>
      'This school is closed. All of its users are paused and its data is kept.',
    'ACTIVE' => 'This school is active.',
    _ => 'This school is ${o.status.toLowerCase()}.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = overview;
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final owner = role == PlatformRole.owner;
    final canRepair = owner || role == PlatformRole.support;
    final ops = ref.read(platformOpsActionsProvider.notifier);

    Future<void> go(
      SchoolStatusChoice to,
      String done, {
      String? reason,
      String? remarks,
      String? internalNotes,
      String? message,
    }) async {
      final ok = await ops.transition(
        o.id,
        to,
        reason: reason,
        remarks: remarks,
        internalNotes: internalNotes,
        message: message,
      );
      if (!context.mounted) return;
      _report(context, ref, ok, done);
    }

    Future<void> recover(String step, String done, {String? reason}) async {
      final ok = await ops.recovery(o.id, step, reason: reason);
      if (!context.mounted) return;
      _report(context, ref, ok, done);
    }

    final rec = o.recovery;
    final recOpen = rec != null && rec.isOpen;
    return _Panel(
      title: 'Access',
      children: [
        Text(
          describe(o),
          key: const ValueKey('school-state'),
          style: text.bodyMedium?.copyWith(
            color: o.isSuspended ? scheme.error : null,
          ),
        ),
        if (o.isSuspended && o.statusReason.isNotEmpty)
          Text('Reason: ${o.statusReason}', style: text.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            if (owner && o.status == 'ACTIVE') ...[
              OutlinedButton.icon(
                key: const ValueKey('school-suspend'),
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Suspend school'),
                onPressed: busy
                    ? null
                    : () async {
                        final reason = await showReasonDialog(
                          context,
                          title: 'Suspend ${o.name}?',
                          message:
                              'Everyone at this school (staff and parents) is signed out of their data '
                              'straight away until you reactivate it. Nothing is deleted.',
                          confirmLabel: 'Suspend',
                          destructive: true,
                        );
                        if (reason == null || !context.mounted) return;
                        await go(
                          SchoolStatusChoice.suspended,
                          'School suspended.',
                          reason: reason,
                        );
                      },
              ),
              OutlinedButton.icon(
                key: const ValueKey('school-deactivate'),
                icon: const Icon(Icons.toggle_off_outlined),
                label: const Text('Deactivate school'),
                onPressed: busy
                    ? null
                    : () async {
                        final reason = await showReasonDialog(
                          context,
                          title: 'Deactivate ${o.name}?',
                          message:
                              'The school goes back to inactive and everyone is paused until you activate it again.',
                          confirmLabel: 'Deactivate',
                          destructive: true,
                        );
                        if (reason == null || !context.mounted) return;
                        await go(
                          SchoolStatusChoice.inactive,
                          'School deactivated.',
                          reason: reason,
                        );
                      },
              ),
            ],
            if (owner && o.isSuspended && !o.isClosed)
              FilledButton.icon(
                key: ValueKey(
                  o.isInactive ? 'school-activate' : 'school-reactivate',
                ),
                icon: const Icon(Icons.play_circle_outline),
                label: Text(
                  o.isInactive ? 'Activate school' : 'Reactivate school',
                ),
                onPressed: busy
                    ? null
                    : () async {
                        final input = await showActivationDialog(
                          context,
                          schoolName: o.name,
                          reactivation: !o.isInactive,
                        );
                        if (input == null || !context.mounted) return;
                        await go(
                          SchoolStatusChoice.active,
                          o.isInactive
                              ? 'School activated.'
                              : 'School reactivated.',
                          remarks: input.remarks,
                          internalNotes: input.internalNotes,
                          message: input.message,
                        );
                      },
              ),
            if (canRepair && !o.isClosed)
              TextButton(
                key: const ValueKey('school-reapply'),
                onPressed: busy
                    ? null
                    : () async {
                        final ok = await ops.refreshAccess(o.id);
                        if (!context.mounted) return;
                        _report(
                          context,
                          ref,
                          ok,
                          'Applied to every user of the school.',
                        );
                      },
                child: const Text('Re-apply to all users'),
              ),
          ],
        ),
        if (o.isClosed && owner) ...[
          const SizedBox(height: AppSpacing.sm),
          if (recOpen)
            Text(
              'Recovery requested by ${rec.requestedByEmail}: ${rec.reason}',
              key: const ValueKey('recovery-info'),
              style: text.bodySmall,
            ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (!recOpen)
                OutlinedButton(
                  key: const ValueKey('recovery-request'),
                  onPressed: busy
                      ? null
                      : () async {
                          final reason = await showReasonDialog(
                            context,
                            title: 'Request recovery of ${o.name}?',
                            message:
                                'A different owner must approve. The school then returns to inactive '
                                'and still has to be activated.',
                            minLength: 15,
                            confirmLabel: 'Request recovery',
                          );
                          if (reason == null || !context.mounted) return;
                          await recover(
                            'request',
                            'Recovery requested.',
                            reason: reason,
                          );
                        },
                  child: const Text('Request recovery'),
                ),
              if (recOpen && rec.requestedBy != myUid)
                FilledButton(
                  key: const ValueKey('recovery-approve'),
                  onPressed: busy
                      ? null
                      : () =>
                            recover('approve', 'School recovered (inactive).'),
                  child: const Text('Approve recovery'),
                ),
              if (recOpen && rec.requestedBy == myUid)
                Text(
                  'Waiting for a different owner to approve.',
                  style: text.bodySmall,
                ),
              if (recOpen)
                OutlinedButton(
                  key: const ValueKey('recovery-cancel'),
                  onPressed: busy
                      ? null
                      : () => recover('cancel', 'Recovery request cancelled.'),
                  child: const Text('Cancel request'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The school's administrators, with reset (sign out + emailed link) and add.
class SchoolAdminsPanel extends ConsumerWidget {
  final SchoolOverview overview;
  final PlatformRole role;

  const SchoolAdminsPanel({
    super.key,
    required this.overview,
    required this.role,
  });

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final input = await showDialog<({String name, String email})>(
      context: context,
      builder: (_) => const _AddAdminDialog(),
    );
    if (input == null || !context.mounted) return;
    final sent = await ref
        .read(platformOpsActionsProvider.notifier)
        .addAdmin(schoolId: overview.id, name: input.name, email: input.email);
    if (!context.mounted) return;
    if (sent == null) {
      _report(context, ref, false, '');
    } else {
      context.showSnackBar(
        sent
            ? 'Added. A password-setup email is on its way.'
            : 'Added, but the email could not be sent. Use "Reset access".',
        isError: !sent,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = overview;
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final canReset = role == PlatformRole.owner || role == PlatformRole.support;
    return _Panel(
      title: 'School administrators',
      children: [
        if (o.admins.isEmpty) const Text('No school administrator found.'),
        for (final a in o.admins)
          ListTile(
            key: ValueKey('admin-${a.uid}'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(a.name.isEmpty ? a.email : a.name),
            subtitle: Text(
              a.status == 'ACTIVE'
                  ? a.email
                  : '${a.email} · ${a.status.toLowerCase()}',
            ),
            trailing: canReset
                ? TextButton(
                    key: ValueKey('reset-${a.uid}'),
                    onPressed: busy
                        ? null
                        : () async {
                            final yes = await confirm(
                              context,
                              title:
                                  'Reset access for ${a.name.isEmpty ? a.email : a.name}?',
                              message:
                                  'They are signed out everywhere and emailed a link to choose a new password.',
                              confirmLabel: 'Reset access',
                            );
                            if (!yes || !context.mounted) return;
                            final sent = await ref
                                .read(platformOpsActionsProvider.notifier)
                                .resetAdmin(schoolId: o.id, uid: a.uid);
                            if (!context.mounted) return;
                            if (sent == null) {
                              if (!context.mounted) return;
                              _report(context, ref, false, '');
                            } else {
                              context.showSnackBar(
                                sent
                                    ? 'Signed out. A reset link is on its way.'
                                    : 'Signed out, but the email could not be sent.',
                                isError: !sent,
                              );
                            }
                          },
                    child: const Text('Reset access'),
                  )
                : null,
          ),
        if (role == PlatformRole.owner)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('admin-add'),
              onPressed: busy ? null : () => _add(context, ref),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add administrator'),
            ),
          ),
      ],
    );
  }
}

/// Switches for the modules the platform controls (owner only).
class SchoolFeaturesPanel extends ConsumerStatefulWidget {
  final SchoolOverview overview;
  final PlatformRole role;

  const SchoolFeaturesPanel({
    super.key,
    required this.overview,
    required this.role,
  });

  @override
  ConsumerState<SchoolFeaturesPanel> createState() =>
      _SchoolFeaturesPanelState();
}

class _SchoolFeaturesPanelState extends ConsumerState<SchoolFeaturesPanel> {
  bool _history = false;

  Future<void> _flip(FeatureDef f, bool on) async {
    final o = widget.overview;
    final ops = ref.read(platformOpsActionsProvider.notifier);
    if (on) {
      final ok = await ops.setFeatures(o.id, {f.key: true});
      if (!mounted) return;
      _report(context, ref, ok, '${f.label} on.');
      return;
    }
    final dependants = [
      for (final d in dependantsOf(f.key))
        if (o.featureOn(d)) featureLabel(d),
    ];
    final reason = await showReasonDialog(
      context,
      title: 'Switch off ${f.label}?',
      message: dependants.isEmpty
          ? 'The school\'s users lose this module straight away. Nothing is deleted.'
          : 'This also switches off: ${dependants.join(', ')}. '
                'The school\'s users lose them straight away. Nothing is deleted.',
      confirmLabel: dependants.isEmpty ? 'Switch off' : 'Switch all off',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    final ok = await ops.setFeatures(
      o.id,
      {f.key: false},
      reason: reason,
      confirmDependants: dependants.isNotEmpty,
    );
    if (!mounted) return;
    _report(context, ref, ok, '${f.label} off.');
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.overview;
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final owner = widget.role == PlatformRole.owner;
    final text = Theme.of(context).textTheme;
    return _Panel(
      title: 'Modules',
      children: [
        for (final f in kFeatureCatalogue)
          Builder(
            builder: (_) {
              final on = o.featureOn(f.key);
              final missing = missingDependencies(o.features, f.key);
              final blocked = !on && missing.isNotEmpty;
              return SwitchListTile(
                key: ValueKey('feature-${f.key}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(f.label),
                subtitle: blocked
                    ? Text(
                        'Needs ${missing.map(featureLabel).join(', ')} switched on first.',
                        key: ValueKey('feature-needs-${f.key}'),
                      )
                    : null,
                value: on,
                onChanged: !owner || busy || blocked
                    ? null
                    : (v) => _flip(f, v),
              );
            },
          ),
        if (!owner)
          Text(
            'Only a platform owner can change modules.',
            style: text.bodySmall,
          ),
        TextButton(
          key: const ValueKey('features-history-toggle'),
          onPressed: () => setState(() => _history = !_history),
          child: Text(_history ? 'Hide history' : 'Show history'),
        ),
        if (_history) _FeatureHistory(schoolId: o.id),
      ],
    );
  }
}

class _FeatureHistory extends ConsumerWidget {
  final String schoolId;

  const _FeatureHistory({required this.schoolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ref
        .watch(featureHistoryProvider(schoolId))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(userMessageFor(e)),
          data: (list) => list.isEmpty
              ? const Text('No changes yet.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in list)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          '${formatInstant(e.at)} · ${featureLabel(e.feature)} '
                          '${e.to ? 'on' : 'off'}${e.cascade ? ' (with a module it depends on)' : ''}'
                          ' · ${e.actor}${(e.reason ?? '').isEmpty ? '' : ' · ${e.reason}'}',
                          key: ValueKey('feature-history-${e.id}'),
                          style: text.bodySmall,
                        ),
                      ),
                  ],
                ),
        );
  }
}

/// The module switches NEW schools start with. Existing schools are never
/// changed by this: each school keeps the copy it got when it was created.
class DefaultModulesDialog extends ConsumerStatefulWidget {
  const DefaultModulesDialog({super.key});

  @override
  ConsumerState<DefaultModulesDialog> createState() =>
      _DefaultModulesDialogState();
}

class _DefaultModulesDialogState extends ConsumerState<DefaultModulesDialog> {
  Map<String, bool>? _draft;
  String? _error;

  Future<void> _save() async {
    final ok = await ref
        .read(platformOpsActionsProvider.notifier)
        .setFeatureDefaults(_draft!);
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
    final loaded = ref.watch(featureDefaultsProvider);
    final draft = _draft ?? loaded.value;
    return AlertDialog(
      title: const Text('Default modules for new schools'),
      content: SizedBox(
        width: 460,
        child: draft == null
            ? (loaded.hasError
                  ? Text(userMessageFor(loaded.error!))
                  : const LinearProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Applies to schools created from now on. Existing schools keep what they have.',
                    ),
                    for (final f in kFeatureCatalogue)
                      Builder(
                        builder: (_) {
                          final on = featureUsable(draft, f.key);
                          final blocked =
                              !on &&
                              missingDependencies(draft, f.key).isNotEmpty;
                          return SwitchListTile(
                            key: ValueKey('default-${f.key}'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(f.label),
                            value: on,
                            onChanged: busy || blocked
                                ? null
                                : (v) => setState(() {
                                    final next = {...draft, f.key: v};
                                    if (!v) {
                                      for (final d in dependantsOf(f.key)) {
                                        next[d] = false;
                                      }
                                    }
                                    _draft = next;
                                  }),
                          );
                        },
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
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
          key: const ValueKey('defaults-save'),
          onPressed: busy || draft == null ? null : _save,
          child: const Text('Save defaults'),
        ),
      ],
    );
  }
}

/// Manual billing records for this school (owner only).
class SchoolBillingPanel extends ConsumerWidget {
  final SchoolOverview overview;

  const SchoolBillingPanel({super.key, required this.overview});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final today = dayKey(DateTime.now());
    return _Panel(
      title: 'Billing',
      children: [
        AsyncValueWidget(
          value: ref.watch(billingProvider(overview.id)),
          errorMessage: userMessageFor,
          onRetry: () => ref.invalidate(billingProvider(overview.id)),
          data: (b) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (b.owed.isEmpty)
                Text('Nothing is owed.', style: text.bodyMedium)
              else
                for (final e in b.owed.entries)
                  Text(
                    'Owed ${Money.format(e.value.dueMinor, currency: e.key)}'
                    '${e.value.overdueMinor > 0 ? ' · overdue ${Money.format(e.value.overdueMinor, currency: e.key)}' : ''}',
                    style: text.bodyMedium?.copyWith(
                      color: e.value.overdueMinor > 0
                          ? Theme.of(context).colorScheme.error
                          : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              const SizedBox(height: AppSpacing.xs),
              for (final r in b.records)
                BillingRecordTile(
                  record: r,
                  todayKey: today,
                  busy: busy,
                  showSchool: false,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('billing-add'),
            onPressed: busy
                ? null
                : () async {
                    final saved = await showDialog<bool>(
                      context: context,
                      builder: (_) => BillingRecordDialog(
                        schoolId: overview.id,
                        schoolName: overview.name,
                        defaultCurrency: overview.currency,
                      ),
                    );
                    if (saved == true && context.mounted) {
                      context.showSnackBar('Billing record added.');
                    }
                  },
            icon: const Icon(Icons.add),
            label: const Text('Add billing record'),
          ),
        ),
      ],
    );
  }
}

/// One billing record with its actions (mark paid, waive, void) while it is due.
class BillingRecordTile extends ConsumerWidget {
  final PlatformBillingRecord record;
  final String todayKey;
  final bool busy;
  final bool showSchool;

  const BillingRecordTile({
    super.key,
    required this.record,
    required this.todayKey,
    required this.busy,
    required this.showSchool,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = record;
    final overdue = r.isOverdueOn(todayKey);
    final scheme = Theme.of(context).colorScheme;
    Future<void> set(String status, {String? paidDate}) async {
      final ok = await ref
          .read(platformOpsActionsProvider.notifier)
          .setBilling(r.id, status, paidDate: paidDate);
      if (!context.mounted) return;
      _report(context, ref, ok, 'Marked ${status.toLowerCase()}.');
    }

    return ListTile(
      key: ValueKey('bill-${r.id}'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text('${showSchool ? '${r.schoolName} · ' : ''}${r.period}'),
      subtitle: Text(
        '${Money.format(r.amountMinor, currency: r.currency)} · '
        '${r.isDue
            ? 'due ${r.dueDate}'
            : r.status == 'PAID'
            ? 'paid ${r.paidDate ?? ''}'
            : r.status.toLowerCase()}'
        '${r.reference == null ? '' : ' · ${r.reference}'}',
        style: TextStyle(color: overdue ? scheme.error : null),
      ),
      trailing: r.isDue
          ? PopupMenuButton<String>(
              key: ValueKey('bill-menu-${r.id}'),
              enabled: !busy,
              onSelected: (v) async {
                if (v == 'paid') {
                  final d = await pickPaidDate(context);
                  if (d != null && context.mounted) {
                    await set('PAID', paidDate: d);
                  }
                } else {
                  final yes = await confirm(
                    context,
                    title: v == 'waive'
                        ? 'Waive this bill?'
                        : 'Void this bill?',
                    message: 'This cannot be changed afterwards.',
                    confirmLabel: v == 'waive' ? 'Waive' : 'Void',
                    destructive: true,
                  );
                  if (yes && context.mounted) {
                    await set(v == 'waive' ? 'WAIVED' : 'VOID');
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'paid', child: Text('Mark paid')),
                PopupMenuItem(value: 'waive', child: Text('Waive')),
                PopupMenuItem(value: 'void', child: Text('Void')),
              ],
            )
          : null,
    );
  }
}

/// The offboarding workflow: request (suspends the school), a DIFFERENT owner
/// approves, cancelling restores. Nothing is deleted by this workflow.
class SchoolOffboardingPanel extends ConsumerWidget {
  final SchoolOverview overview;
  final String myUid;

  const SchoolOffboardingPanel({
    super.key,
    required this.overview,
    required this.myUid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = overview;
    final off = o.offboarding;
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final text = Theme.of(context).textTheme;
    final open = off != null && off.isOpen;
    Future<void> step(String s, String done, {String? reason}) async {
      final ok = await ref
          .read(platformOpsActionsProvider.notifier)
          .offboarding(o.id, s, reason: reason);
      if (!context.mounted) return;
      _report(context, ref, ok, done);
    }

    return _Panel(
      title: 'Offboarding',
      children: [
        if (off == null || !open)
          Text(
            off != null && off.state == 'CANCELLED'
                ? 'The last offboarding was cancelled.'
                : 'Not offboarding. Starting it suspends the school; a second owner must approve. '
                      'Nothing is deleted automatically.',
            style: text.bodyMedium,
          )
        else ...[
          Text(
            off.state == 'APPROVED'
                ? 'Offboarding approved.'
                : 'Offboarding requested by ${off.requestedByEmail}.',
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          Text('Reason: ${off.reason}', style: text.bodySmall),
          if (off.graceUntil != null)
            Text(
              'Grace period until ${formatDisplayDate(off.graceUntil!)}.',
              style: text.bodySmall,
            ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            if (!open)
              OutlinedButton(
                key: const ValueKey('off-request'),
                onPressed: busy
                    ? null
                    : () async {
                        final reason = await showReasonDialog(
                          context,
                          title: 'Start offboarding ${o.name}?',
                          message:
                              'The school is suspended now and a 30-day grace period starts. A second owner must approve.',
                          minLength: 15,
                          confirmLabel: 'Start offboarding',
                          destructive: true,
                        );
                        if (reason != null && context.mounted) {
                          await step(
                            'request',
                            'Offboarding started.',
                            reason: reason,
                          );
                        }
                      },
                child: const Text('Start offboarding'),
              ),
            if (off != null &&
                off.state == 'REQUESTED' &&
                off.requestedBy != myUid)
              FilledButton(
                key: const ValueKey('off-approve'),
                onPressed: busy ? null : () => step('approve', 'Approved.'),
                child: const Text('Approve'),
              ),
            if (off != null &&
                off.state == 'REQUESTED' &&
                off.requestedBy == myUid)
              Text(
                'Waiting for a different owner to approve.',
                style: text.bodySmall,
              ),
            if (open)
              OutlinedButton(
                key: const ValueKey('off-cancel'),
                onPressed: busy
                    ? null
                    : () => step('cancel', 'Offboarding cancelled.'),
                child: const Text('Cancel offboarding'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Name and email of a new school administrator. Owns its controllers, so they
/// live exactly as long as the dialog (including its closing animation).
class _AddAdminDialog extends StatefulWidget {
  const _AddAdminDialog();

  @override
  State<_AddAdminDialog> createState() => _AddAdminDialogState();
}

class _AddAdminDialogState extends State<_AddAdminDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add an administrator'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const ValueKey('aa-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Enter their name' : null,
            ),
            TextFormField(
              key: const ValueKey('aa-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$',
                  ).hasMatch((v ?? '').trim())
                  ? null
                  : 'Enter a valid email address',
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
          key: const ValueKey('aa-save'),
          onPressed: () {
            if (_form.currentState?.validate() ?? false) {
              Navigator.pop(context, (name: _name.text, email: _email.text));
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

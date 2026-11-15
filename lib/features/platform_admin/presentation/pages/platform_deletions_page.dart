import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/error/empty_view.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/deletion_review.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_console_providers.dart';
import '../widgets/platform_scaffold.dart';

/// The account-deletion review queue (Google Play requirement). Reviewers see a
/// reference, the state, the requester's role and school NAME and the history:
/// never a name, email or phone. Only legal next steps are offered.
class PlatformDeletionsPage extends ConsumerStatefulWidget {
  const PlatformDeletionsPage({super.key});

  @override
  ConsumerState<PlatformDeletionsPage> createState() =>
      _PlatformDeletionsPageState();
}

class _PlatformDeletionsPageState extends ConsumerState<PlatformDeletionsPage> {
  bool _closed = false;

  Future<void> _decide(DeletionReviewItem item, DeletionDecision d) async {
    String? reasonCode;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(d.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d == DeletionDecision.approve
                    ? 'The account and its data will be deleted by the '
                          'processor. This cannot be undone once it runs.'
                    : 'Reference ${item.reference}',
              ),
              if (d == DeletionDecision.reject ||
                  d == DeletionDecision.requestAction) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('deletion-reason'),
                  value: reasonCode,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('No reason'),
                    ),
                    for (final e in deletionReasonLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setLocal(() => reasonCode = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('deletion-confirm'),
              style: d.isDestructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(d.label),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await ref
        .read(platformConsoleActionsProvider.notifier)
        .decideDeletion(
          reference: item.reference,
          decision: d,
          reasonCode: reasonCode,
        );
    if (!mounted) return;
    if (ok) {
      context.showSnackBar('Done: ${d.label.toLowerCase()}.');
    } else {
      context.showSnackBar(
        userMessageFor(ref.read(platformConsoleActionsProvider).error!),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(tenantContextProvider).value?.user.platformRole;
    final allowed =
        role == PlatformRole.owner || role == PlatformRole.compliance;
    return PlatformScaffold(
      title: 'Deletion requests',
      child: !allowed
          ? const EmptyView(
              icon: Icons.lock_outline,
              message: 'Only owners and compliance reviewers can see these.',
            )
          : PlatformBody(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: SegmentedButton<bool>(
                      key: const ValueKey('deletion-scope'),
                      segments: const [
                        ButtonSegment(value: false, label: Text('Open')),
                        ButtonSegment(value: true, label: Text('Closed')),
                      ],
                      selected: {_closed},
                      onSelectionChanged: (s) =>
                          setState(() => _closed = s.first),
                    ),
                  ),
                  Expanded(
                    child: AsyncValueWidget(
                      value: ref.watch(deletionRequestsProvider(_closed)),
                      errorMessage: userMessageFor,
                      onRetry: () =>
                          ref.invalidate(deletionRequestsProvider(_closed)),
                      data: (items) => items.isEmpty
                          ? EmptyView(
                              icon: Icons.inbox_outlined,
                              message: _closed
                                  ? 'No closed requests yet.'
                                  : 'No open deletion requests.',
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                ref.invalidate(
                                  deletionRequestsProvider(_closed),
                                );
                                await ref.read(
                                  deletionRequestsProvider(_closed).future,
                                );
                              },
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  0,
                                  AppSpacing.md,
                                  AppSpacing.lg,
                                ),
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (_, i) => _RequestCard(
                                  item: items[i],
                                  onDecide: _decide,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  final DeletionReviewItem item;
  final Future<void> Function(DeletionReviewItem, DeletionDecision) onDecide;

  const _RequestCard({required this.item, required this.onDecide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final busy = ref.watch(platformConsoleActionsProvider).isLoading;
    final who = [
      if (item.role != null) item.role!.toLowerCase().replaceAll('_', ' '),
      if (item.schoolName.isNotEmpty) item.schoolName,
      if (item.source != null) 'via ${item.source!.toLowerCase()}',
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SelectableText(
                  item.reference,
                  style: theme.textTheme.titleSmall,
                ),
                Chip(label: Text(deletionStatusLabel(item.status))),
              ],
            ),
            if (who.isNotEmpty) Text(who, style: theme.textTheme.bodyMedium),
            if (item.reason != null)
              Text(
                'Reason: ${deletionReasonLabels[item.reason] ?? item.reason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            Text(
              'Requested ${formatInstant(item.createdAt)}'
              '${item.updatedAt == null ? '' : ' · updated ${formatInstant(item.updatedAt)}'}',
              style: theme.textTheme.bodySmall,
            ),
            if (item.history.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  item.history
                      .map((h) => deletionStatusLabel(h.status))
                      .join('  →  '),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (item.decisions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final d in item.decisions)
                    d == DeletionDecision.approve
                        ? FilledButton(
                            key: ValueKey('decide-${item.reference}-${d.wire}'),
                            onPressed: busy ? null : () => onDecide(item, d),
                            child: Text(d.label),
                          )
                        : OutlinedButton(
                            key: ValueKey('decide-${item.reference}-${d.wire}'),
                            onPressed: busy ? null : () => onDecide(item, d),
                            child: Text(d.label),
                          ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

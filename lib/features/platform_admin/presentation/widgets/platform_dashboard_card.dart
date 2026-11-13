import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../domain/platform_ops_models.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_ops_providers.dart';

/// The platform at a glance: schools by status, people and activity, and the
/// things that need attention. Numbers are computed nightly (and on demand).
class PlatformDashboardCard extends ConsumerWidget {
  final PlatformRole role;

  const PlatformDashboardCard({super.key, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(platformStatsProvider);
    final busy = ref.watch(platformOpsActionsProvider).isLoading;
    final canRefresh = role != PlatformRole.viewer;
    final text = Theme.of(context).textTheme;
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text(userMessageFor(e), style: text.bodySmall),
      data: (s) {
        if (s == null) {
          return Card(
            key: const ValueKey('stats-empty'),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Dashboard numbers have not been computed yet. They update every night.',
                    ),
                  ),
                  if (canRefresh)
                    FilledButton(
                      key: const ValueKey('stats-refresh'),
                      onPressed: busy ? null : () => _refresh(context, ref),
                      child: const Text('Compute now'),
                    ),
                ],
              ),
            ),
          );
        }
        final stale = s.isStale(DateTime.now());
        final tiles = <(String, String, String?)>[
          (
            'Schools',
            '${s.schoolsTotal}',
            '${s.schoolsActive} active · ${s.schoolsSuspended} suspended',
          ),
          ('New schools', '${s.newSchools30d}', 'last 30 days'),
          ('Students', '${s.students}', '${s.branches} branches'),
          ('Staff', '${s.staff}', '${s.parents} parents'),
          ('Signed in today', '${s.active1d}', '${s.active7d} this week'),
          (
            'Active this month',
            '${s.active30d}',
            'of ${s.users} accounts${s.activityPartial ? ' (partial)' : ''}',
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Platform overview', style: text.titleMedium),
                ),
                if (canRefresh)
                  IconButton(
                    key: const ValueKey('stats-refresh'),
                    tooltip: 'Recompute now',
                    onPressed: busy ? null : () => _refresh(context, ref),
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            Text(
              'Updated ${formatInstant(s.computedAt)}',
              key: const ValueKey('stats-updated'),
              style: text.bodySmall?.copyWith(
                color: stale ? Theme.of(context).colorScheme.error : null,
              ),
            ),
            if (stale)
              Text(
                'These numbers are more than a day and a half old: the nightly job may not be running.',
                key: const ValueKey('stats-stale'),
                style: text.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 840
                    ? 6
                    : (c.maxWidth >= 520 ? 3 : 2);
                const gap = AppSpacing.sm;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final t in tiles)
                      SizedBox(
                        width: w,
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.$1, style: text.bodySmall),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(t.$2, style: text.headlineSmall),
                                ),
                                if (t.$3 != null)
                                  Text(t.$3!, style: text.bodySmall),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _Attention(stats: s, role: role),
          ],
        );
      },
    );
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final fresh = await ref
        .read(platformOpsActionsProvider.notifier)
        .refreshStats();
    if (!context.mounted) return;
    if (fresh == null) {
      context.showSnackBar(
        userMessageFor(ref.read(platformOpsActionsProvider).error!),
        isError: true,
      );
    } else {
      context.showSnackBar(
        fresh
            ? 'Numbers updated.'
            : 'Already up to date (refreshed in the last 5 minutes).',
      );
    }
  }
}

class _Attention extends StatelessWidget {
  final PlatformStats stats;
  final PlatformRole role;

  const _Attention({required this.stats, required this.role});

  @override
  Widget build(BuildContext context) {
    final owner = role == PlatformRole.owner;
    final reviewer = owner || role == PlatformRole.compliance;
    final items = <(String, int, String?)>[
      if (reviewer)
        (
          'deletion requests waiting for review',
          stats.openDeletionRequests,
          AppRoutes.platformDeletions,
        ),
      ('support sessions open right now', stats.activeSupportGrants, null),
      if (owner)
        (
          'schools being offboarded',
          stats.offboardingOpen,
          AppRoutes.platformSchools,
        ),
      if (owner)
        (
          'bills past their due date',
          stats.billingOverdue,
          AppRoutes.platformBilling,
        ),
    ].where((i) => i.$2 > 0).toList();
    final text = Theme.of(context).textTheme;
    if (items.isEmpty) {
      return Text(
        'Nothing needs attention.',
        key: const ValueKey('attention-none'),
        style: text.bodyMedium,
      );
    }
    return Card(
      key: const ValueKey('attention'),
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: Text('Needs attention', style: text.titleSmall),
          ),
          for (final i in items)
            ListTile(
              dense: true,
              title: Text('${i.$2} ${i.$1}'),
              trailing: i.$3 == null ? null : const Icon(Icons.chevron_right),
              onTap: i.$3 == null ? null : () => context.go(i.$3!),
            ),
        ],
      ),
    );
  }
}

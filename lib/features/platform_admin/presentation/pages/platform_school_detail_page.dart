import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/error_mapper.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/date_formatting.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/platform_role.dart';
import '../../domain/school_overview.dart';
import '../providers/platform_console_providers.dart';
import '../providers/support_session_providers.dart';
import '../widgets/platform_scaffold.dart';
import '../widgets/request_support_access_dialog.dart';
import '../widgets/school_lifecycle_panels.dart';

/// One school for Avail404: who runs it, how big it is, who currently has
/// support access, and what the platform did there. Metadata and counts only:
/// student, staff and finance records are reachable only through a support
/// session.
class PlatformSchoolDetailPage extends ConsumerWidget {
  final String schoolId;

  const PlatformSchoolDetailPage({super.key, required this.schoolId});

  Future<void> _startSession(
    BuildContext context,
    WidgetRef ref,
    SchoolOverview o,
  ) async {
    final started = await showDialog<bool>(
      context: context,
      builder: (_) =>
          RequestSupportAccessDialog(schoolId: o.id, schoolName: o.name),
    );
    if (started == true && context.mounted) context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(tenantContextProvider).value?.user.platformRole;
    final canSupport =
        role == PlatformRole.owner || role == PlatformRole.support;
    final session = ref.watch(supportSessionProvider);
    return PlatformScaffold(
      title: 'School',
      child: AsyncValueWidget(
        value: ref.watch(schoolOverviewProvider(schoolId)),
        errorMessage: userMessageFor,
        onRetry: () => ref.invalidate(schoolOverviewProvider(schoolId)),
        data: (o) {
          final text = Theme.of(context).textTheme;
          final sessionHere = session != null && session.schoolId == o.id;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(schoolOverviewProvider(schoolId));
              await ref.read(schoolOverviewProvider(schoolId).future);
            },
            child: PlatformBody(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Text(
                    o.name.isEmpty ? o.id : o.name,
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Chip(
                        label: Text(o.status.isEmpty ? 'Unknown' : o.status),
                      ),
                      if (o.code.isNotEmpty)
                        Chip(label: Text('Code ${o.code}')),
                      if (o.currency.isNotEmpty) Chip(label: Text(o.currency)),
                      if (o.timezone.isNotEmpty) Chip(label: Text(o.timezone)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    [
                      o.city,
                      o.state,
                      o.country,
                    ].where((e) => e.isNotEmpty).join(', '),
                    style: text.bodyMedium,
                  ),
                  if (o.email.isNotEmpty || o.phone.isNotEmpty)
                    Text(
                      [
                        o.email,
                        o.phone,
                      ].where((e) => e.isNotEmpty).join('  ·  '),
                      style: text.bodySmall,
                    ),
                  if (o.createdAt != null)
                    Text(
                      'Joined ${formatDisplayDate(o.createdAt!)}',
                      style: text.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  _Counts(overview: o),
                  const SizedBox(height: AppSpacing.md),
                  if (canSupport)
                    sessionHere
                        ? Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [
                              FilledButton.icon(
                                key: const ValueKey('school-open'),
                                icon: const Icon(Icons.visibility_outlined),
                                label: const Text(
                                  'Open the school (read-only)',
                                ),
                                onPressed: () =>
                                    context.go(AppRoutes.dashboard),
                              ),
                              OutlinedButton(
                                key: const ValueKey('school-end'),
                                onPressed: () => ref
                                    .read(
                                      platformConsoleActionsProvider.notifier,
                                    )
                                    .endSupportSession(),
                                child: const Text('End session'),
                              ),
                            ],
                          )
                        : FilledButton.icon(
                            key: const ValueKey('school-support'),
                            icon: const Icon(Icons.support_agent_outlined),
                            label: const Text('Start support session'),
                            onPressed: () => _startSession(context, ref, o),
                          )
                  else
                    Text(
                      'Your platform role cannot open school data.',
                      style: text.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  SchoolStatusPanel(
                    overview: o,
                    role: role ?? PlatformRole.viewer,
                  ),
                  SchoolAdminsPanel(
                    overview: o,
                    role: role ?? PlatformRole.viewer,
                  ),
                  SchoolFeaturesPanel(
                    overview: o,
                    role: role ?? PlatformRole.viewer,
                  ),
                  if (role == PlatformRole.owner) ...[
                    SchoolBillingPanel(overview: o),
                    SchoolOffboardingPanel(
                      overview: o,
                      myUid:
                          ref.watch(tenantContextProvider).value?.user.userId ??
                          '',
                    ),
                  ],
                  _Section(
                    title: 'Branches',
                    empty: 'No branches.',
                    children: [
                      for (final b in o.branches)
                        ListTile(
                          dense: true,
                          title: Text(b.name),
                          trailing: b.status == 'ACTIVE'
                              ? null
                              : Text(b.status.toLowerCase()),
                        ),
                    ],
                  ),
                  _Section(
                    title: 'Support access right now',
                    empty: 'Nobody has access.',
                    children: [
                      for (final g in o.activeGrants)
                        ListTile(
                          dense: true,
                          title: Text(
                            g.adminName.isEmpty ? g.adminEmail : g.adminName,
                          ),
                          subtitle: Text(
                            '${g.reason}\nUntil ${formatInstant(g.expiresAt)}',
                          ),
                          isThreeLine: true,
                          trailing: role == PlatformRole.owner
                              ? TextButton(
                                  onPressed: () async {
                                    final ok = await ref
                                        .read(
                                          platformConsoleActionsProvider
                                              .notifier,
                                        )
                                        .revokeGrant(
                                          schoolId: o.id,
                                          adminUid: g.adminUid,
                                        );
                                    ref.invalidate(
                                      schoolOverviewProvider(schoolId),
                                    );
                                    if (context.mounted) {
                                      context.showSnackBar(
                                        ok
                                            ? 'Access ended.'
                                            : 'Could not end access.',
                                        isError: !ok,
                                      );
                                    }
                                  },
                                  child: const Text('End'),
                                )
                              : null,
                        ),
                    ],
                  ),
                  _Section(
                    title: 'Recent platform activity',
                    empty: 'Nothing yet.',
                    children: [
                      for (final r in o.recentActions)
                        ListTile(
                          dense: true,
                          title: Text(_actionLabel(r.action)),
                          subtitle: Text(
                            [
                              r.actorEmail,
                              if (r.reason != null) r.reason!,
                            ].where((e) => e.isNotEmpty).join(' · '),
                          ),
                          trailing: Text(
                            formatInstant(r.at),
                            style: text.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _actionLabel(String action) {
  final t = action.toLowerCase().replaceAll('_', ' ');
  return t.isEmpty ? '' : t[0].toUpperCase() + t.substring(1);
}

class _Counts extends StatelessWidget {
  final SchoolOverview overview;

  const _Counts({required this.overview});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Branches', overview.branches.length),
      ('Students', overview.students),
      ('Staff', overview.staff),
      ('Parents', overview.parents),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 640 ? 4 : 2;
        const gap = AppSpacing.sm;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final i in items)
              SizedBox(
                width: w,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          i.$1,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '${i.$2}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String empty;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.empty,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Card(
            margin: EdgeInsets.zero,
            child: children.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(empty, style: text.bodyMedium),
                  )
                : Column(children: children),
          ),
        ],
      ),
    );
  }
}

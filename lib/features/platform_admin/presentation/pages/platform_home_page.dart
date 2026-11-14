import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/platform_role.dart';
import '../providers/platform_console_providers.dart';
import '../widgets/platform_dashboard_card.dart';
import '../widgets/platform_scaffold.dart';

/// Landing page of a platform administrator (Avail404). Shows the tools their
/// platform role allows; the server enforces the same limits.
class PlatformHomePage extends ConsumerWidget {
  const PlatformHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformScaffold(
      title: 'Platform',
      showBack: false,
      child: AsyncValueWidget(
        value: ref.watch(tenantContextProvider),
        data: (tenant) {
          final role = tenant?.user.platformRole;
          final tiles = <_Tile>[
            if (role != null)
              _Tile(
                key: const ValueKey('tile-platform-schools'),
                icon: Icons.school_outlined,
                title: 'Schools',
                subtitle: 'Directory, school overview and support access',
                route: AppRoutes.platformSchools,
              ),
            if (role == PlatformRole.owner || role == PlatformRole.compliance)
              _Tile(
                key: const ValueKey('tile-platform-deletions'),
                icon: Icons.delete_sweep_outlined,
                title: 'Deletion requests',
                subtitle: 'Review account-deletion requests',
                route: AppRoutes.platformDeletions,
              ),
            if (role == PlatformRole.owner || role == PlatformRole.compliance)
              _Tile(
                key: const ValueKey('tile-platform-audit'),
                icon: Icons.history,
                title: 'Audit log',
                subtitle: 'What platform administrators did',
                route: AppRoutes.platformAudit,
              ),
            if (role == PlatformRole.owner || role == PlatformRole.compliance)
              _Tile(
                key: const ValueKey('tile-platform-audit-trail'),
                icon: Icons.fact_check_outlined,
                title: 'Audit trail',
                subtitle: 'Everything that changed, across all schools',
                route: AppRoutes.platformAuditTrail,
              ),
            if (role != null)
              _Tile(
                key: const ValueKey('tile-platform-notices'),
                icon: Icons.campaign_outlined,
                title: 'Notices to schools',
                subtitle: 'Messages school administrators see in the app',
                route: AppRoutes.platformNotices,
              ),
            if (role == PlatformRole.owner)
              _Tile(
                key: const ValueKey('tile-platform-billing'),
                icon: Icons.receipt_long_outlined,
                title: 'Billing',
                subtitle: 'What schools owe Avail404',
                route: AppRoutes.platformBilling,
              ),
            if (role == PlatformRole.owner)
              _Tile(
                key: const ValueKey('tile-platform-availability'),
                icon: Icons.construction_outlined,
                title: 'App availability',
                subtitle: 'Maintenance mode and minimum app version',
                route: AppRoutes.platformAvailability,
              ),
            if (role == PlatformRole.owner)
              _Tile(
                key: const ValueKey('tile-platform-admins'),
                icon: Icons.admin_panel_settings_outlined,
                title: 'Platform administrators',
                subtitle: 'Add people, set roles, disable access',
                route: AppRoutes.platformAdmins,
              ),
            if (role == PlatformRole.owner || role == PlatformRole.support)
              _Tile(
                key: const ValueKey('tile-platform-branding'),
                icon: Icons.brush_outlined,
                title: 'Platform branding',
                subtitle: 'Default theme and presets for all schools',
                route: AppRoutes.platformBranding,
              ),
          ];
          final text = Theme.of(context).textTheme;
          return PlatformBody(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text(
                  'Welcome${tenant == null ? '' : ', ${tenant.user.name}'}',
                  style: text.headlineSmall,
                ),
                if (role != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      '${role.displayName}: ${role.description}',
                      style: text.bodyMedium,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                if (role != null) ...[
                  PlatformDashboardCard(role: role),
                  const SizedBox(height: AppSpacing.md),
                ],
                const _ActiveSessions(),
                if (tiles.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        'There are no tools for your role yet. More platform '
                        'tools will appear here as they are released.',
                      ),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth >= 640 ? 2 : 1;
                    const gap = AppSpacing.sm;
                    final w = (c.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final t in tiles) SizedBox(width: w, child: t),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  const _Tile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, size: 32, color: scheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Support sessions that are still open on the server (for example after a page
/// reload): resume one or end it.
class _ActiveSessions extends ConsumerWidget {
  const _ActiveSessions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grants = ref.watch(myGrantsProvider).value ?? const [];
    final now = DateTime.now();
    final active = [
      for (final g in grants)
        if (g.isActiveAt(now)) g,
    ];
    if (active.isEmpty) return const SizedBox.shrink();
    final names = {
      for (final s in ref.watch(platformSchoolsProvider).value ?? const [])
        s.id: s.name,
    };
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        key: const ValueKey('active-sessions'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Support sessions in progress', style: text.titleMedium),
              for (final g in active)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    (names[g.schoolId]?.isNotEmpty ?? false)
                        ? names[g.schoolId]!
                        : g.schoolId,
                  ),
                  subtitle: Text(
                    'Until ${TimeOfDay.fromDateTime(g.expiresAt!).format(context)}',
                  ),
                  trailing: Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      FilledButton(
                        key: ValueKey('resume-${g.schoolId}'),
                        onPressed: () {
                          ref
                              .read(platformConsoleActionsProvider.notifier)
                              .resumeSupportSession(
                                schoolId: g.schoolId,
                                schoolName: names[g.schoolId] ?? g.schoolId,
                                expiresAt: g.expiresAt!,
                              );
                          context.go(AppRoutes.dashboard);
                        },
                        child: const Text('Resume'),
                      ),
                      OutlinedButton(
                        key: ValueKey('end-${g.schoolId}'),
                        onPressed: () => ref
                            .read(platformConsoleRepositoryProvider)
                            .revokeSupportAccess(schoolId: g.schoolId),
                        child: const Text('End'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

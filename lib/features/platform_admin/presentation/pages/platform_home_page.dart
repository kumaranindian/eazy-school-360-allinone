import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/loading/async_value_widget.dart';
import '../../domain/platform_role.dart';
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

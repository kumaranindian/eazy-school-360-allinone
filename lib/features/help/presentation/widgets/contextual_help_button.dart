import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/tenant/tenant_context_provider.dart';
import '../../content/manual_content.dart';

/// The "?" in the top bar, on every screen: opens the guide for the screen the
/// user is on so nobody has to search the whole manual, or the manual's front
/// page when that screen has no guide of its own. Hidden on the manual itself.
class ContextualHelpButton extends ConsumerWidget {
  final String path;
  const ContextualHelpButton({super.key, required this.path});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(tenantContextProvider).value;
    if (tenant == null || path.startsWith(AppRoutes.help)) {
      return const SizedBox.shrink();
    }
    final guide = manualCatalog.forPath(path, tenant.can);
    return IconButton(
      icon: const Icon(Icons.help_outline),
      tooltip: guide == null ? 'Help & user manual' : 'Help: ${guide.title}',
      onPressed: () => context.go(
        guide == null ? AppRoutes.help : AppRoutes.helpGuidePath(guide.id),
      ),
    );
  }
}

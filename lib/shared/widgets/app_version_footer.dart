import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_environment.dart';
import '../../core/config/app_version.dart';
import '../../core/config/env_config_provider.dart';

/// One quiet line at the bottom of every screen: product, version/build and
/// — outside production — the environment, so a tester always knows which
/// build and backend they are looking at.
class AppVersionFooter extends ConsumerWidget {
  const AppVersionFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var env = '';
    try {
      final e = ref.watch(envConfigProvider).environment;
      if (e != AppEnvironment.prod) env = ' · ${e.name}';
    } catch (_) {
      // No environment resolved (e.g. isolated widget tests) — omit it.
    }
    final theme = Theme.of(context);
    return SizedBox(
      height: 24,
      child: Center(
        child: Text(
          'EazySchool 360 · $appVersionLabel$env',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

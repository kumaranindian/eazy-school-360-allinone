import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_environment.dart';
import '../../core/config/app_version.dart';
import '../../core/config/env_config_provider.dart';
import '../branding/school_brand_logo.dart';
import '../branding/school_branding.dart';

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
    final branding = ref.watch(schoolBrandingProvider);
    final branded = branding?.hasLogo ?? false;
    final line = '$appVersionLabel$env';
    return SizedBox(
      height: 24,
      child: Center(
        child: branded
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SchoolLogoImage(
                    url: branding!.logoUrl,
                    label: branding.name,
                    size: 16,
                    fallbackChild: SchoolInitialBadge(
                      name: branding.name,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: PoweredByEazySchool(suffix: line)),
                ],
              )
            : Text(
                'EazySchool 360 · $line',
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

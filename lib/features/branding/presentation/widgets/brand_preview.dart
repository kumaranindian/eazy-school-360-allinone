import 'package:flutter/material.dart';

import '../../../../core/branding/tenant_branding.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_theme.dart';

/// A small sample of the app drawn with [colors] — buttons, a chip, a module
/// tile, the navigation bar and the (fixed) status colours — so a school sees
/// what it is choosing before saving. Uses the real [AppTheme], so what shows
/// here is what every screen will get.
class BrandPreview extends StatelessWidget {
  final BrandColors colors;
  final BrandingAppearance appearance;

  const BrandPreview({
    super.key,
    required this.colors,
    required this.appearance,
  });

  @override
  Widget build(BuildContext context) {
    final dark = switch (appearance) {
      BrandingAppearance.dark => true,
      BrandingAppearance.light => false,
      BrandingAppearance.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final resolved = ResolvedTheme(
      schoolId: null,
      version: 0,
      colors: colors.isReadable ? colors : BrandColors.emerald,
      appearance: appearance,
      presetId: 'preview',
    );
    final data = dark ? AppTheme.dark(resolved) : AppTheme.light(resolved);
    return Semantics(
      label: 'Preview of the school theme',
      child: Theme(
        data: data,
        child: Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return Container(
              key: const ValueKey('brand-preview'),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: scheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: scheme.surface,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      'Your school',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              child: Icon(
                                Icons.groups_outlined,
                                color: scheme.primary,
                              ),
                            ),
                            title: const Text('Students'),
                            subtitle: const Text('Admissions and profiles'),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton(
                              onPressed: () {},
                              child: const Text('Save'),
                            ),
                            OutlinedButton(
                              onPressed: () {},
                              child: const Text('Cancel'),
                            ),
                            const Chip(label: Text('Class 5-A')),
                            _Status('Paid', AppColors.success),
                            _Status('Overdue', scheme.error),
                          ],
                        ),
                      ],
                    ),
                  ),
                  NavigationBar(
                    selectedIndex: 0,
                    height: 56,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.payments_outlined),
                        label: 'Fees',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.more_horiz),
                        label: 'More',
                      ),
                    ],
                    onDestinationSelected: (_) {},
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final String label;
  final Color color;
  const _Status(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

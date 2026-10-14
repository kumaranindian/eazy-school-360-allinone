import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/responsive.dart';
import '../branding/school_brand_logo.dart';
import '../branding/school_branding.dart';
import '../widgets/app_version_footer.dart';
import 'hero_scope.dart';

class NavDestination {
  final String label;
  final IconData icon;
  final IconData? selectedIcon;

  const NavDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
  });
}

/// Single navigation shell that adapts shape to the available width instead
/// of maintaining separate mobile/tablet/desktop screens:
///
/// - Mobile: `AppBar` + bottom navigation bar.
/// - Tablet: compact `NavigationRail` (icons only).
/// - Desktop: extended `NavigationRail` (icons + labels), sidebar-style.
///
/// Add a new top-level destination by extending [destinations] — the shell
/// itself doesn't need to change.
class AdaptiveScaffold extends StatelessWidget {
  final String title;
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final List<Widget>? actions;

  /// Optional hero shown above the page on top-level screens.
  final Widget? header;

  const AdaptiveScaffold({
    super.key,
    required this.title,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.actions,
    this.header,
  });

  /// The shell's top bar stays light (logo + product name) while inner
  /// screens use the navy bar from the theme, so the two read as layers.
  PreferredSizeWidget _shellBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      iconTheme: IconThemeData(color: scheme.onSurface),
      actionsIconTheme: IconThemeData(color: scheme.onSurface),
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      title: _BrandTitle(title),
      actions: actions,
    );
  }

  /// Every routed screen gets the version line under its content.
  Widget _withFooter(Widget content) => Column(
    children: [
      Expanded(child: content),
      const AppVersionFooter(),
    ],
  );

  Widget _withHeader(BuildContext context, {bool compact = false}) {
    final h = header;
    // Always provide the scope (active only while a hero shows) so a screen
    // can tell "I am the root screen" from "I was pushed".
    if (h == null) return HeroScope(active: false, child: body);
    return HeroScope(active: true, child: _heroColumn(h, compact));
  }

  Widget _heroColumn(Widget h, bool compact) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 16,
            compact ? 8 : 16,
            compact ? 8 : 16,
            0,
          ),
          child: h,
        ),
        Expanded(child: body),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, screenSize) {
        if (screenSize.isMobile) {
          // A bottom bar holds at most five comfortably. With more
          // destinations, the first four stay in the bar and the rest open
          // from a "More" entry, so nothing is lost and nothing is cramped.
          const maxInBar = 5;
          final needsMore = destinations.length > maxInBar;
          final inBar = needsMore
              ? destinations.take(maxInBar - 1).toList()
              : destinations;
          final overflow = needsMore
              ? destinations.skip(maxInBar - 1).toList()
              : const <NavDestination>[];
          final barSelected = needsMore && selectedIndex >= inBar.length
              ? inBar.length
              : selectedIndex;

          Future<void> openMore() async {
            final picked = await showModalBottomSheet<int>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.8,
              ),
              builder: (context) => SafeArea(
                // Scrolls: with many destinations the list is taller than a
                // phone, and an unreachable entry is an unusable one.
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < overflow.length; i++)
                      ListTile(
                        leading: Icon(
                          selectedIndex == inBar.length + i
                              ? (overflow[i].selectedIcon ?? overflow[i].icon)
                              : overflow[i].icon,
                        ),
                        title: Text(overflow[i].label),
                        selected: selectedIndex == inBar.length + i,
                        onTap: () =>
                            Navigator.of(context).pop(inBar.length + i),
                      ),
                  ],
                ),
              ),
            );
            if (picked != null) onDestinationSelected(picked);
          }

          return Scaffold(
            appBar: _shellBar(context),
            body: _withFooter(_withHeader(context, compact: true)),
            bottomNavigationBar: destinations.length > 1
                ? NavigationBar(
                    selectedIndex: barSelected,
                    onDestinationSelected: (index) {
                      if (needsMore && index == inBar.length) {
                        openMore();
                      } else {
                        onDestinationSelected(index);
                      }
                    },
                    destinations: [
                      for (final d in inBar)
                        NavigationDestination(
                          icon: Icon(d.icon),
                          selectedIcon: d.selectedIcon != null
                              ? Icon(d.selectedIcon)
                              : null,
                          label: d.label,
                        ),
                      if (needsMore)
                        const NavigationDestination(
                          icon: Icon(Icons.more_horiz),
                          label: 'More',
                        ),
                    ],
                  )
                : null,
          );
        }

        final isDesktop = screenSize.isDesktop;
        return Scaffold(
          appBar: _shellBar(context),
          body: Row(
            children: [
              // NavigationRail does not scroll; with many destinations on a
              // short window it would overflow. This makes it scrollable
              // (and still fills the height when there is room).
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        extended: isDesktop,
                        minExtendedWidth: 220,
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onDestinationSelected,
                        labelType: isDesktop
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        destinations: [
                          for (final d in destinations)
                            NavigationRailDestination(
                              icon: Icon(d.icon),
                              selectedIcon: d.selectedIcon != null
                                  ? Icon(d.selectedIcon)
                                  : null,
                              label: Text(d.label),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _ContentFrame(child: _withHeader(context))),
            ],
          ),
        );
      },
    );
  }
}

/// App-bar title: the school's logo and the EazySchool mark side by side,
/// then the school's name (or the product name before a school is known).
class _BrandTitle extends ConsumerWidget {
  final String title;
  const _BrandTitle(this.title);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(schoolBrandingProvider);
    final name = branding != null && branding.name.isNotEmpty
        ? branding.name
        : title;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SchoolAndProductMarks(size: 32),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Keeps page content to a readable measure on wide windows (tables and
/// forms stretched edge-to-edge on a 27" monitor are hard to scan) while
/// letting it use the full width on phones and tablets. Every routed page
/// sits inside the shell, so this one frame applies to all screens.
class _ContentFrame extends StatelessWidget {
  final Widget child;
  const _ContentFrame({required this.child});

  static const double maxWidth = 1360;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

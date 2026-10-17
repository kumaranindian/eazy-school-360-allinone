import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/responsive.dart';

/// The one primary action of a [SectionPage] (usually "Add ...").
class SectionAction {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const SectionAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
}

/// The frame every sub-page of a section (Settings → Classes, Fees →
/// Invoices, ...) sits in, so they share one structure instead of each page
/// inventing its own:
///
/// - a title and one-line description (sub-pages have no hero of their own),
/// - a way back to the parent when [parentRoute] is given,
/// - a [toolbar] slot for page context such as the academic-year picker,
/// - the single primary action: a header button on tablet and desktop, and a
///   floating button on a phone where the header has no room for it.
class SectionPage extends StatelessWidget {
  final String title;
  final String? description;

  /// Where the back button goes, e.g. `/settings`. Omit for a top-level page.
  final String? parentRoute;
  final String parentLabel;

  final SectionAction? primaryAction;
  final Widget? toolbar;
  final Widget child;

  const SectionPage({
    super.key,
    required this.title,
    required this.child,
    this.description,
    this.parentRoute,
    this.parentLabel = 'Settings',
    this.primaryAction,
    this.toolbar,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return ResponsiveBuilder(
      builder: (context, screenSize) {
        final wide = !screenSize.isMobile;
        final action = primaryAction;
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: action != null && !wide
              ? FloatingActionButton.extended(
                  onPressed: action.onPressed,
                  icon: Icon(action.icon),
                  label: Text(action.label),
                )
              : null,
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  12,
                  AppSpacing.md,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (parentRoute != null) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back to $parentLabel',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => context.go(parentRoute!),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: parentRoute != null ? 2 : 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(
                                title,
                                style: text.titleLarge,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (description != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  description!,
                                  style: text.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (action != null && wide) ...[
                      const SizedBox(width: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: action.onPressed,
                        icon: Icon(action.icon),
                        label: Text(action.label),
                      ),
                    ],
                  ],
                ),
              ),
              if (toolbar != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    12,
                    AppSpacing.md,
                    0,
                  ),
                  child: Align(alignment: Alignment.centerLeft, child: toolbar),
                ),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

/// A fixed-width control in a [SectionToolbar] (a dropdown needs a bounded
/// width to lay out). 240 fits a 320px phone with the page margins.
class ToolbarField extends StatelessWidget {
  final Widget child;
  final double width;

  const ToolbarField({super.key, required this.child, this.width = 240});

  @override
  Widget build(BuildContext context) => SizedBox(width: width, child: child);
}

/// The controls under a page title (year picker, class picker, ...). They sit
/// side by side when there is room and wrap onto the next line when there is
/// not, instead of overflowing a phone.
class SectionToolbar extends StatelessWidget {
  final List<Widget> children;

  const SectionToolbar({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm + 4,
    runSpacing: AppSpacing.sm + 4,
    children: children,
  );
}

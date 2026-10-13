import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/responsive.dart';

/// The controls that choose *what a page is about* (year, class, section,
/// date for a register) as opposed to narrowing a list.
///
/// On a tablet or desktop they are simply shown. On a phone they would eat
/// the whole first screen, so once the choice is [complete] they fold into a
/// one-line summary ("Class 5 · Section A · 12 Oct") that opens again with a
/// tap; while incomplete they stay open so the user can finish choosing.
class ScopeBar extends StatefulWidget {
  /// One line describing the current choice, shown when folded.
  final String summary;

  /// Whether everything needed has been chosen. Flipping to true folds the bar
  /// on a phone.
  final bool complete;

  /// The controls. Given whether the bar is narrow so they can fill the width.
  final Widget Function(BuildContext context, bool narrow) controlsBuilder;

  const ScopeBar({
    super.key,
    required this.summary,
    required this.complete,
    required this.controlsBuilder,
  });

  @override
  State<ScopeBar> createState() => _ScopeBarState();
}

class _ScopeBarState extends State<ScopeBar> {
  late bool _open = !widget.complete;

  @override
  void didUpdateWidget(ScopeBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.complete && widget.complete) _open = false;
    if (oldWidget.complete && !widget.complete) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, screenSize) {
        if (!screenSize.isMobile) {
          return widget.controlsBuilder(context, false);
        }
        final theme = Theme.of(context);
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.complete)
                InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.tune,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            widget.summary,
                            style: theme.textTheme.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(_open ? Icons.expand_less : Icons.expand_more),
                      ],
                    ),
                  ),
                ),
              if (_open || !widget.complete)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: widget.controlsBuilder(context, true),
                ),
            ],
          ),
        );
      },
    );
  }
}

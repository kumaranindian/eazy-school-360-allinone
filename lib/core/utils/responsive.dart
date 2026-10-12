import 'package:flutter/widgets.dart';

/// Breakpoint thresholds (logical pixels). Treat these as a starting point —
/// adjust per project if the design calls for different cutoffs, but keep
/// them centralized here rather than repeating magic numbers in widgets.
abstract final class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 1024;
}

enum ScreenSize { mobile, tablet, desktop }

extension ScreenSizeX on ScreenSize {
  bool get isMobile => this == ScreenSize.mobile;
  bool get isTablet => this == ScreenSize.tablet;
  bool get isDesktop => this == ScreenSize.desktop;
  bool get isTabletOrLarger => this != ScreenSize.mobile;
}

/// Resolves a [ScreenSize] from an available width. Prefer deriving width
/// from a [LayoutBuilder]'s constraints over [MediaQuery.size] so nested
/// panels/split-views are classified by the space they actually have, not
/// the whole window.
ScreenSize screenSizeForWidth(double width) {
  if (width < Breakpoints.mobile) return ScreenSize.mobile;
  if (width < Breakpoints.tablet) return ScreenSize.tablet;
  return ScreenSize.desktop;
}

/// Convenience builder that re-resolves [ScreenSize] on every relayout
/// (rotation, browser resize, split-view change) instead of caching a
/// stale value.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ScreenSize screenSize) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          builder(context, screenSizeForWidth(constraints.maxWidth)),
    );
  }
}

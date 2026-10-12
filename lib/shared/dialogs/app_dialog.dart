import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';

/// Shows [child] in a width that adapts to the available screen size:
/// near full-width on mobile, a bounded width on tablet/desktop — never a
/// fixed desktop-sized box forced onto a small screen, and never an
/// unbounded dialog that stretches edge-to-edge on a large monitor.
///
/// Content taller than the viewport scrolls instead of overflowing, which
/// also covers the "keyboard open" case for dialogs containing a form.
Future<T?> showAdaptiveAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) {
      final screenSize = screenSizeForWidth(MediaQuery.sizeOf(context).width);
      final maxWidth = switch (screenSize) {
        ScreenSize.mobile => double.infinity,
        ScreenSize.tablet => 480.0,
        ScreenSize.desktop => 560.0,
      };

      return Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: screenSize.isMobile ? 16 : 40,
          vertical: 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: builder(context),
          ),
        ),
      );
    },
  );
}

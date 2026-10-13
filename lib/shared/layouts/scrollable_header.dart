import 'package:flutter/material.dart';

/// A fixed header above a list that can never push the list off screen.
///
/// Filter and search headers sit above an `Expanded` list. On a short window
/// (phone in landscape) or at a large system text size they can grow taller
/// than the screen, which overflows the page and leaves no room for the list.
/// This caps the header at [maxFraction] of the available height and lets it
/// scroll inside that cap; when it fits, it is laid out exactly as before.
class ScrollableHeader extends StatelessWidget {
  final Widget child;
  final double maxFraction;

  const ScrollableHeader({
    super.key,
    required this.child,
    this.maxFraction = 0.5,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cap = constraints.hasBoundedHeight
            ? constraints.maxHeight * maxFraction
            : double.infinity;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: cap),
          child: SingleChildScrollView(child: child),
        );
      },
    );
  }
}

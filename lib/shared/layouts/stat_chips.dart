import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import 'status_chips.dart';

/// One figure in a [StatChipsBar].
class StatChip {
  final String label;

  /// Null while the count is still loading (shown as a placeholder).
  final int? count;

  /// Shown instead of [count] when the figure is not a whole number (an
  /// average, a percentage).
  final String? valueText;
  final bool selected;
  final VoidCallback? onTap;

  const StatChip({
    required this.label,
    required this.count,
    this.valueText,
    this.selected = false,
    this.onTap,
  });
}

/// A slim row of headline numbers that double as quick filters: tap one to
/// narrow the list below to it. The same compact pills as the staff
/// directories ([StatusChips]): 32px tall, scrolling sideways on a phone so it
/// never takes more than one line, wrapping on wider screens.
class StatChipsBar extends StatelessWidget {
  final List<StatChip> chips;

  const StatChipsBar({super.key, required this.chips});

  @override
  Widget build(BuildContext context) => ResponsiveBuilder(
    builder: (context, size) => StatusChips(chips: chips, layout: size),
  );
}

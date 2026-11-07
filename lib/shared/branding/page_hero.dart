import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Colours of the page heading, shared by [PageHero], [HeroPill] and any
/// control that sits on the heading (the staff branch selector).
abstract final class HeroColors {
  static Color background(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark
      ? Theme.of(c).colorScheme.surfaceContainerHigh
      : Theme.of(c).colorScheme.primaryContainer;
  static Color border(BuildContext c) =>
      Theme.of(c).colorScheme.primary.withValues(alpha: 0.18);
  static Color title(BuildContext c) => Theme.of(c).colorScheme.onSurface;
  static Color subtitle(BuildContext c) =>
      Theme.of(c).colorScheme.onSurfaceVariant;
  static Color accent(BuildContext c) => Theme.of(c).colorScheme.primary;

  /// A chip on the heading.
  static Color pill(BuildContext c) => Theme.of(c).colorScheme.surface;
}

/// A small label on the hero: the first is usually the highlighted one.
class HeroPill extends StatelessWidget {
  final String label;
  final bool filled;

  const HeroPill(this.label, {super.key, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled
            ? Theme.of(context).colorScheme.tertiary
            : HeroColors.pill(context),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: filled ? null : Border.all(color: HeroColors.border(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: filled
              ? Theme.of(context).colorScheme.onTertiary
              : HeroColors.title(context),
        ),
      ),
    );
  }
}

/// The signature header of every top-level screen: a short light-green
/// tinted strip with an icon tile, the title and a one-line subtitle on the
/// left, and the pills (school · branch, role, a branch selector...) on the
/// right. One compact design for every screen, so no screen spends its first
/// screenful on a banner. Pure presentation — no data, no actions of its own.
///
/// - **Tablet / desktop**: one row, about 78px tall.
/// - **Phone** ([compact]): the icon, title and subtitle in a slim row; pills
///   go below only when [pillsOnPhone] says they matter (a branch selector
///   does; a decorative school label does not).
class PageHero extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// A rounded tile at the start of the strip.
  final IconData? icon;
  final List<Widget> pills;

  /// A widget at the far end (the dashboard's school emblem).
  final Widget? trailing;

  /// The phone variant.
  final bool compact;
  final bool pillsOnPhone;

  const PageHero({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.pills = const [],
    this.trailing,
    this.compact = false,
    this.pillsOnPhone = false,
  });

  /// A rounded accent tile holding [icon].
  static Widget iconBadge(IconData icon, {double size = 44}) => Builder(
    builder: (context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: HeroColors.accent(context),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.55),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: text.titleLarge?.copyWith(
            color: HeroColors.title(context),
            fontSize: compact ? 20 : 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(
              color: HeroColors.subtitle(context),
              fontSize: 13,
            ),
          ),
      ],
    );
    final pillRow = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: compact ? WrapAlignment.start : WrapAlignment.end,
      children: pills,
    );

    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          iconBadge(icon!, size: compact ? 36 : 44),
          SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md),
        ],
        Expanded(child: heading),
        if (compact && trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          trailing!,
        ],
      ],
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 20,
        vertical: compact ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: HeroColors.background(context),
        border: Border.all(color: HeroColors.border(context)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                head,
                if (pillsOnPhone && pills.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  pillRow,
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  iconBadge(icon!, size: 44),
                  const SizedBox(width: AppSpacing.md),
                ],
                // The title block gets the larger share, so a one-line
                // subtitle stays on one line beside the pills.
                Expanded(flex: 3, child: heading),
                if (pills.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.md),
                  Flexible(flex: 2, child: pillRow),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  trailing!,
                ],
              ],
            ),
    );
  }
}

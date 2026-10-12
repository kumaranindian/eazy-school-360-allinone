import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

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
        color: filled ? AppColors.gold : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: filled ? AppColors.navy : Colors.white,
        ),
      ),
    );
  }
}

/// The signature header used by the dashboard and every top-level screen:
/// a navy → blue gradient card with a title, optional subtitle and pills,
/// and a trailing icon or mark. Pure presentation — no data, no actions.
class PageHero extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> pills;
  final Widget? trailing;

  /// Slim, title-only variant for phones, where vertical space is scarce.
  final bool compact;

  const PageHero({
    super.key,
    required this.title,
    this.subtitle,
    this.pills = const [],
    this.trailing,
    this.compact = false,
  });

  /// A rounded white-on-glass tile holding [icon], for [trailing].
  static Widget iconBadge(IconData icon, {double size = 44}) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Icon(icon, color: Colors.white, size: size * 0.55),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.all(compact ? 10 : AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (compact ? text.titleLarge : text.headlineSmall)
                      ?.copyWith(color: Colors.white),
                ),
                if (subtitle != null && !compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: const Color(0xFFD9EAFF),
                    ),
                  ),
                ],
                if (pills.isNotEmpty && !compact) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: pills,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../../core/theme/admin_dashboard_palette.dart';

/// Reusable building blocks of the School Admin dashboard. Pure presentation:
/// data and navigation are passed in. Colours come from
/// [AdminDashboardPalette] only.

/// The white rounded surface every dashboard block sits on.
class AdminCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const AdminCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final radius = BorderRadius.circular(AdminDashboardPalette.radius);
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      // The shadow sits OUTSIDE the white surface (a shadow painted on top of
      // it would grey the card).
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: p.shadow,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: p.card,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: p.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// "Quick Overview", "Quick Actions"... with an optional trailing widget.
class AdminSectionHeading extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const AdminSectionHeading(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: p.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (trailing != null) Flexible(child: trailing!),
      ],
    );
  }
}

/// A rounded square holding an icon on a soft tint of [color].
class AdminIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const AdminIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: p.tint(color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

/// The three headline numbers: icon, count, label. [value] is null while
/// loading (a skeleton) and [error] shows a dash with a retry on tap.
class AdminOverviewCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int? value;
  final bool loading;
  final bool error;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  const AdminOverviewCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.loading = false,
    this.error = false,
    this.onTap,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    final Widget number;
    if (loading) {
      number = _Skeleton(width: 48, height: 26, color: p.border);
    } else if (error) {
      number = Text(
        '–',
        style: text.headlineSmall?.copyWith(
          color: p.textSecondary,
          fontWeight: FontWeight.w800,
        ),
      );
    } else {
      number = FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          '${value ?? 0}',
          style: text.headlineSmall?.copyWith(
            color: p.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return AdminCard(
      onTap: error ? onRetry ?? onTap : onTap,
      semanticLabel: error
          ? '$label unavailable. Tap to retry.'
          : loading
          ? '$label loading'
          : '${value ?? 0} $label',
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminIconBadge(icon: icon, color: color, size: 36),
          const SizedBox(height: 10),
          number,
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  const _Skeleton({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
  );
}

/// A circular percentage gauge with the number in the middle.
class AdminProgressRing extends StatelessWidget {
  final double fraction; // 0-1
  final String centerText;
  final Color color;
  final double size;

  const AdminProgressRing({
    super.key,
    required this.fraction,
    required this.centerText,
    required this.color,
    this.size = 84,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              backgroundColor: p.border,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            centerText,
            style: text.titleMedium?.copyWith(
              color: p.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// A coloured dot, a label and a number: one line of a legend.
class AdminStatLine extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const AdminStatLine({
    super.key,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: p.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: text.bodyMedium?.copyWith(
              color: p.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One compact row of "Today at School".
class AdminActivityRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// A pending item: shows a count pill and a dot.
  final int? pending;
  final VoidCallback onTap;

  const AdminActivityRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.pending,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    final actionable = (pending ?? 0) > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              AdminIconBadge(icon: icon, color: color, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        color: p.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: actionable ? p.warning : p.textSecondary,
                        fontWeight: actionable
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionable)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: p.tint(p.warning),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$pending',
                    style: text.labelMedium?.copyWith(
                      color: p.warning,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Icon(Icons.chevron_right, color: p.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quick-action tile: tinted icon over a label, at least 48x48.
class AdminActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const AdminActionTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: p.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AdminIconBadge(icon: icon, color: color, size: 44),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The full-width "School Insights" banner.
class AdminInsightsBanner extends StatelessWidget {
  final VoidCallback onTap;
  const AdminInsightsBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'School Insights. Key performance, fee and attendance trends.',
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(AdminDashboardPalette.radius),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [p.primary, p.purple],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.insights_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'School Insights',
                            style: text.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Key performance, fee and attendance trends.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Powered by EazySchool 360" and the build, read from the app's version
/// config (never typed here).
class AdminFooter extends StatelessWidget {
  final String? schoolName;
  final String versionLabel;
  const AdminFooter({super.key, this.schoolName, required this.versionLabel});

  @override
  Widget build(BuildContext context) {
    final p = AdminDashboardPalette.of(context);
    final text = Theme.of(context).textTheme;
    final style = text.bodySmall?.copyWith(color: p.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          if (schoolName != null && schoolName!.isNotEmpty)
            Text(
              schoolName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style?.copyWith(fontWeight: FontWeight.w700),
            ),
          Text(
            'Powered by EazySchool 360',
            textAlign: TextAlign.center,
            style: style,
          ),
          Text(versionLabel, textAlign: TextAlign.center, style: style),
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Building blocks of the revamped home screens (parent and admin). Pure
/// presentation: no data, no navigation of their own — the dashboard feeds
/// them. All colours come from the theme or [AppColors] tokens so the same
/// widgets read well in light and dark.

/// The "Welcome, …" banner: navy → blue gradient with a painted school
/// building on the right, a role pill and an optional subtitle.
class WelcomeBanner extends StatelessWidget {
  final String name;
  final String? roleLabel;
  final String? subtitle;

  const WelcomeBanner({
    super.key,
    required this.name,
    this.roleLabel,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0B4FA8), AppColors.brandBlue],
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg + 4),
          ),
          child: Stack(
            children: [
              Positioned(
                right: 0,
                bottom: 0,
                top: 0,
                width: wide ? 260 : constraints.maxWidth * 0.46,
                child: const ExcludeSemantics(
                  child: CustomPaint(painter: _SchoolScenePainter()),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(wide ? AppSpacing.lg : AppSpacing.md),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: wide ? 112 : 104,
                    maxWidth: constraints.maxWidth * (wide ? 0.62 : 0.6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Welcome,',
                        style: text.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null) ...[
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
                      if (roleLabel != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            roleLabel!,
                            style: text.labelLarge?.copyWith(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A simple flat school building on a hill, with two clouds and trees —
/// drawn, so there is no asset to ship and it scales to any banner size.
class _SchoolScenePainter extends CustomPainter {
  const _SchoolScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Paint p(Color c) => Paint()..color = c;

    // Clouds.
    final cloud = p(Colors.white.withValues(alpha: 0.85));
    void drawCloud(double cx, double cy, double s) {
      canvas.drawCircle(Offset(cx, cy), 9 * s, cloud);
      canvas.drawCircle(Offset(cx + 11 * s, cy - 5 * s), 12 * s, cloud);
      canvas.drawCircle(Offset(cx + 24 * s, cy), 9 * s, cloud);
    }

    drawCloud(w * 0.12, h * 0.3, 1);
    drawCloud(w * 0.7, h * 0.16, 0.8);

    // Hill.
    final hill = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.82)
      ..quadraticBezierTo(w * 0.5, h * 0.66, w, h * 0.8)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(hill, p(const Color(0xFF3FAE4A)));

    // Trees.
    void tree(double x, double base, double s) {
      canvas.drawRect(
        Rect.fromLTWH(x - 2 * s, base - 10 * s, 4 * s, 12 * s),
        p(const Color(0xFF7A4B21)),
      );
      canvas.drawCircle(
        Offset(x, base - 18 * s),
        12 * s,
        p(const Color(0xFF2E8B3A)),
      );
    }

    tree(w * 0.1, h * 0.88, 1);
    tree(w * 0.93, h * 0.88, 0.9);

    // Building.
    final bw = w * 0.5;
    final bx = (w - bw) / 2 + w * 0.02;
    final by = h * 0.4;
    final bh = h * 0.46;
    canvas.drawRect(Rect.fromLTWH(bx, by, bw, bh), p(const Color(0xFFFFD27A)));
    // Roof.
    final roof = Path()
      ..moveTo(bx - 4, by)
      ..lineTo(bx + bw / 2, by - bh * 0.36)
      ..lineTo(bx + bw + 4, by)
      ..close();
    canvas.drawPath(roof, p(const Color(0xFFE5573B)));
    // Flag pole.
    canvas.drawRect(
      Rect.fromLTWH(bx + bw / 2 - 1, by - bh * 0.62, 2, bh * 0.28),
      p(Colors.white),
    );
    canvas.drawRect(
      Rect.fromLTWH(bx + bw / 2 + 1, by - bh * 0.62, 12, 8),
      p(AppColors.gold),
    );
    // Clock.
    canvas.drawCircle(Offset(bx + bw / 2, by - bh * 0.14), 7, p(Colors.white));
    // Door and windows.
    canvas.drawRect(
      Rect.fromLTWH(bx + bw / 2 - 9, by + bh - 24, 18, 24),
      p(const Color(0xFF5B3A1E)),
    );
    final win = p(const Color(0xFF7CC4FF));
    for (final dx in [0.12, 0.28, 0.62, 0.78]) {
      canvas.drawRect(
        Rect.fromLTWH(bx + bw * dx, by + bh * 0.22, bw * 0.1, bh * 0.26),
        win,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A section heading with an optional trailing widget ("This month · Nov").
class HomeSectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final IconData? icon;

  const HomeSectionTitle(this.title, {super.key, this.trailing, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: trailing!),
        ],
      ],
    );
  }
}

/// A rounded panel with a tinted border — the common surface of every home
/// card. [accent] tints the fill and border (a module's own colour).
class HomePanel extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  const HomePanel({
    super.key,
    required this.child,
    this.accent,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final a = accent;
    final fill = a == null
        ? scheme.surface
        : Color.alphaBlend(
            a.withValues(alpha: dark ? 0.16 : 0.08),
            scheme.surface,
          );
    final border = a == null
        ? scheme.outlineVariant
        : a.withValues(alpha: dark ? 0.55 : 0.4);
    return Material(
      color: gradient == null ? fill : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: gradient == null ? null : BoxDecoration(gradient: gradient),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A square-ish headline number: icon, big value, label ("128 Students").
class OverviewStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  const OverviewStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomePanel(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 24),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A circular percentage gauge with the number in the middle.
class ProgressRing extends StatelessWidget {
  final double fraction;
  final String label;
  final double size;
  final Color color;

  const ProgressRing({
    super.key,
    required this.fraction,
    required this.label,
    this.size = 64,
    this.color = AppColors.success,
  });

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.outlineVariant;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(fraction.clamp(0, 1), color, track),
        child: Center(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color track;
  _RingPainter(this.fraction, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, base..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      base..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// A small status pill ("All Paid ✓", "81%", "2 New").
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  const StatusPill(
    this.label, {
    super.key,
    this.color = AppColors.success,
    this.icon,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: dark ? 0.28 : 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: dark && !solid
                    ? Color.lerp(color, Colors.white, 0.5)
                    : fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 4),
            Icon(icon, size: 14, color: fg),
          ],
        ],
      ),
    );
  }
}

/// One tile of the Quick Actions grid: coloured icon over a short label, with
/// an optional count badge.
class QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  final int badgeCount;

  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomePanel(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: accent, size: 28),
              if (badgeCount > 0)
                Positioned(
                  right: -10,
                  top: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppRadius.pill),
                      ),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A responsive grid of [QuickActionTile]s: 4 columns on a phone (the mock),
/// more on wider screens. Rows are as tall as their tallest tile so larger
/// text never clips.
class QuickActionGrid extends StatelessWidget {
  final List<Widget> tiles;
  const QuickActionGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w >= 900 ? 8 : (w >= 600 ? 6 : (w >= 330 ? 4 : 3));
        return Column(
          children: [
            for (var i = 0; i < tiles.length; i += columns) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < columns; c++) ...[
                      if (c > 0) const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: i + c < tiles.length
                            ? tiles[i + c]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A full-width call-out strip (School Announcements, School Insights): icon,
/// title, subtitle, optional pill and chevron.
class PromoStrip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String? pill;
  final VoidCallback onTap;
  final bool filled;

  const PromoStrip({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.pill,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = filled ? Colors.white : null;
    return HomePanel(
      accent: filled ? null : accent,
      gradient: filled
          ? const LinearGradient(colors: [Color(0xFF3B4FD8), Color(0xFF6B4FD8)])
          : null,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: filled ? Colors.white : accent, size: 30),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: filled
                        ? Colors.white.withValues(alpha: 0.85)
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (pill != null) ...[
            const SizedBox(width: AppSpacing.sm),
            StatusPill(pill!, color: AppColors.error, solid: true),
          ],
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right, color: fg ?? theme.colorScheme.outline),
        ],
      ),
    );
  }
}

/// A titled list panel with divided rows ("Today at School").
class InfoRow {
  final IconData icon;
  final Color accent;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const InfoRow({
    required this.icon,
    required this.accent,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
}

class InfoPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? trailingText;
  final List<InfoRow> rows;

  const InfoPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.rows,
    this.trailingText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HomePanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (trailingText != null)
                Text(
                  trailingText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
            _InfoRowTile(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _InfoRowTile extends StatelessWidget {
  final InfoRow row;
  const _InfoRowTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: row.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: row.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(row.icon, color: row.accent, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm + 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.title, style: theme.textTheme.titleSmall),
                  if (row.subtitle != null)
                    Text(
                      row.subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (row.trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              row.trailing!,
            ],
            if (row.onTap != null && row.trailing is! StatusPill)
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

/// Lays [main] and [side] out as two columns on wide screens (desktop /
/// landscape tablet) and stacks them on a phone or portrait tablet.
class HomeColumns extends StatelessWidget {
  final List<Widget> main;
  final List<Widget> side;
  const HomeColumns({super.key, required this.main, required this.side});

  static Widget _stack(List<Widget> items) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.md),
        items[i],
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900 || side.isEmpty) {
          return _stack([...main, ...side]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: _stack(main)),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: _stack(side)),
          ],
        );
      },
    );
  }
}

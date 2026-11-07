import 'package:flutter/material.dart';

import 'brand_theme.dart';

/// Colours of the School Admin dashboard (light design).
///
/// Centralised here so widgets never repeat a hex value. In light mode the
/// dashboard uses the design's own palette; in dark mode it falls back to the
/// app's normal colour scheme (the dashboard does not force a light surface
/// on a dark device).
@immutable
class AdminDashboardPalette {
  final Color background;
  final Color card;
  final Color primary;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color success;
  final Color warning;
  final Color purple;
  final Color teal;
  final Color shadow;

  const AdminDashboardPalette({
    required this.background,
    required this.card,
    required this.primary,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.success,
    required this.warning,
    required this.purple,
    required this.teal,
    required this.shadow,
  });

  /// The design's light palette.
  static const AdminDashboardPalette light = AdminDashboardPalette(
    background: Color(0xFFF7F8F7),
    card: Color(0xFFFFFFFF),
    primary: Color(0xFF16856A),
    textPrimary: Color(0xFF17231F),
    textSecondary: Color(0xFF68756F),
    border: Color(0xFFE3E9E5),
    success: Color(0xFF23965B),
    warning: Color(0xFFD99532),
    purple: Color(0xFF527A69),
    teal: Color(0xFF2A9D8F),
    shadow: Color(0x1417231F),
  );

  /// The same roles drawn from the app's colour scheme (dark mode, and a
  /// school's own theme in light mode). Status colours stay fixed.
  factory AdminDashboardPalette.fromScheme(ColorScheme s) {
    final dark = s.brightness == Brightness.dark;
    return AdminDashboardPalette(
      background: dark ? s.surface : s.surfaceContainer,
      card: dark ? s.surfaceContainerHigh : s.surface,
      primary: s.primary,
      textPrimary: s.onSurface,
      textSecondary: s.onSurfaceVariant,
      border: s.outlineVariant,
      success: dark ? const Color(0xFF4ADE80) : light.success,
      warning: dark ? const Color(0xFFFBBF24) : light.warning,
      purple: dark ? const Color(0xFFA78BFA) : s.secondary,
      teal: dark
          ? const Color(0xFF2DD4BF)
          : Color.lerp(s.secondary, s.primary, 0.5)!,
      shadow: dark ? const Color(0x33000000) : const Color(0x1417231F),
    );
  }

  /// The design's light palette under the default theme; otherwise drawn from
  /// the school's colour scheme.
  static AdminDashboardPalette of(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark ||
        !BrandTheme.of(context).isDefault) {
      return AdminDashboardPalette.fromScheme(theme.colorScheme);
    }
    return light;
  }

  /// A soft tint of [c] for an icon background.
  Color tint(Color c) => c.withValues(alpha: 0.12);

  /// Corner radius and spacing shared by every dashboard card.
  static const double radius = 16;
  static const double gap = 16;
}

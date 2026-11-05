import 'package:flutter/material.dart';

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
    background: Color(0xFFF5F7FB),
    card: Color(0xFFFFFFFF),
    primary: Color(0xFF1976D2),
    textPrimary: Color(0xFF172B4D),
    textSecondary: Color(0xFF64748B),
    border: Color(0xFFE2E8F0),
    success: Color(0xFF16A34A),
    warning: Color(0xFFF59E0B),
    purple: Color(0xFF7C3AED),
    teal: Color(0xFF0D9488),
    shadow: Color(0x14172B4D),
  );

  /// The same roles drawn from the app's dark colour scheme.
  factory AdminDashboardPalette.fromScheme(ColorScheme s) =>
      AdminDashboardPalette(
        background: s.surface,
        card: s.surfaceContainerHigh,
        primary: s.primary,
        textPrimary: s.onSurface,
        textSecondary: s.onSurfaceVariant,
        border: s.outlineVariant,
        success: const Color(0xFF4ADE80),
        warning: const Color(0xFFFBBF24),
        purple: const Color(0xFFA78BFA),
        teal: const Color(0xFF2DD4BF),
        shadow: const Color(0x33000000),
      );

  static AdminDashboardPalette of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? AdminDashboardPalette.fromScheme(theme.colorScheme)
        : light;
  }

  /// A soft tint of [c] for an icon background.
  Color tint(Color c) => c.withValues(alpha: 0.12);

  /// Corner radius and spacing shared by every dashboard card.
  static const double radius = 16;
  static const double gap = 16;
}

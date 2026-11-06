import 'package:flutter/material.dart';

/// Design-token colour palette: a neutral light theme with a green/teal
/// accent. Widgets should reach for `Theme.of(context).colorScheme.*` or these
/// semantic constants — never raw `Colors.*` or hex values in feature code.
///
/// Blue is deliberately absent from the application palette. Brand artwork
/// (the EazySchool logo, school logos) keeps its own colours because it is an
/// image, not a theme colour.
abstract final class AppColors {
  /// Primary accent for interactive elements (buttons, selection, focus).
  static const Color accent = Color(0xFF16856A);

  /// Pressed / dark variant of the accent.
  static const Color accentDeep = Color(0xFF0F6B54);

  /// Primary text colour and the dark surface of hero panels.
  static const Color ink = Color(0xFF17231F);
  static const Color inkDeep = Color(0xFF0E1714);

  /// Warm accents used for highlights (snack-bar action, warnings).
  static const Color gold = Color(0xFFE0A030);
  static const Color orange = Color(0xFFD99532);

  // Interactive primary (white text on it is 4.9:1).
  static const Color primary = Color(0xFF16856A);
  static const Color primaryLight = Color(0xFF55BB9D);
  static const Color primaryDark = Color(0xFF0F6B54);
  static const Color primaryContainer = Color(0xFFE8F4EF);

  /// Secondary accent for supporting elements.
  static const Color secondary = Color(0xFF527A69);

  // Semantic
  static const Color success = Color(0xFF23965B);
  static const Color warning = Color(0xFFD99532);
  static const Color error = Color(0xFFD9534F);
  static const Color info = Color(0xFF527A69);

  // Light surfaces.
  static const Color lightBackground = Color(0xFFF7F8F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE3E9E5);
  static const Color lightTint = Color(0xFFE8F4EF);

  /// Secondary text, disabled surfaces and disabled text.
  static const Color textSecondary = Color(0xFF68756F);
  static const Color disabledBackground = Color(0xFFEEF1EF);
  static const Color disabledText = Color(0xFF98A39D);

  // Dark surfaces — deep green-black, matching the light theme's accent.
  static const Color darkBackground = Color(0xFF0E1714);
  static const Color darkSurface = Color(0xFF15211D);
  static const Color darkBorder = Color(0xFF2A3A34);
  static const Color darkTint = Color(0xFF1B2B25);

  /// Hero-panel gradient (dark green, subtle).
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [inkDeep, ink, Color(0xFF1E4A3D)],
    stops: [0, 0.6, 1],
  );
}

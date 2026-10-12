import 'package:flutter/material.dart';

/// Design-token color palette, taken from the EazySchool 360 logo: a bright
/// blue "E" and cap over deep navy, with a gold tassel and the green/orange
/// of the "360" ring as accents. Widgets should reach for
/// `Theme.of(context).colorScheme.*` or these semantic constants — never raw
/// `Colors.*` sprinkled through the UI.
abstract final class AppColors {
  // Brand (sampled from the logo artwork)
  /// Bright logo blue — gradients, illustrations, large accents.
  static const Color brandBlue = Color(0xFF0182F1);

  /// Deep logo blue — bottom of the "E" gradient.
  static const Color brandBlueDeep = Color(0xFF00459F);

  /// Logo wordmark navy — text, dark surfaces, app bar in dark panels.
  static const Color navy = Color(0xFF05224E);
  static const Color navyDeep = Color(0xFF031636);

  /// Tassel gold and the ring's orange.
  static const Color gold = Color(0xFFFEAF06);
  static const Color orange = Color(0xFFFE8B03);

  // Interactive primary: the brand blue darkened to meet 4.5:1 with white
  // text (the bright logo blue is 3.9:1), so buttons stay legible.
  static const Color primary = Color(0xFF0A6BD9);
  static const Color primaryLight = Color(0xFF4DA3FF);
  static const Color primaryDark = Color(0xFF00459F);
  static const Color primaryContainer = Color(0xFFD9EAFF);
  static const Color secondary = navy;

  // Semantic
  static const Color success = Color(0xFF1E8E3E);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFD32F2F);
  static const Color info = Color(0xFF0182F1);

  // Light surfaces — a faint blue tint, so white cards lift off the page.
  static const Color lightBackground = Color(0xFFF4F8FD);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFDDE6F2);
  static const Color lightTint = Color(0xFFEAF3FF);

  // Dark surfaces — navy, matching the dark logo lockup.
  static const Color darkBackground = Color(0xFF06142C);
  static const Color darkSurface = Color(0xFF0C2244);
  static const Color darkBorder = Color(0xFF213B63);
  static const Color darkTint = Color(0xFF12315E);

  /// The signature navy → blue gradient used on hero panels.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [navyDeep, navy, Color(0xFF0B4FA8)],
    stops: [0, 0.55, 1],
  );
}

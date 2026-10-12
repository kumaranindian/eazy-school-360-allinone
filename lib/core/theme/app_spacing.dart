/// Spacing scale (logical pixels). Use these instead of ad-hoc `SizedBox`/
/// `EdgeInsets` magic numbers so spacing stays visually consistent.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Border-radius scale.
abstract final class AppRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double pill = 999;
}

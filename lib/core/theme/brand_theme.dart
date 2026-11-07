import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'color_math.dart';

/// Tenant-aware tokens that `ColorScheme` has no slot for. Read with
/// [BrandTheme.of]; a screen never needs a raw colour or a tenant check.
///
/// The status colours are deliberately NOT tenant-controlled: a school cannot
/// turn an overdue marker green (see docs/tenant-theme.md).
@immutable
class BrandTheme extends ThemeExtension<BrandTheme> {
  /// Selected navigation item (label / icon).
  final Color selectedNav;

  /// A darker shade of the primary colour (pressed states, strong accents).
  final Color primaryDeep;

  /// Dark panel behind hero banners and its gradient.
  final LinearGradient heroGradient;

  /// True while the platform default colours are in force (no school theme).
  final bool isDefault;

  /// Status colours; the same for every school.
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  const BrandTheme({
    required this.selectedNav,
    required this.primaryDeep,
    required this.heroGradient,
    this.isDefault = false,
    this.success = AppColors.success,
    this.warning = AppColors.warning,
    this.danger = AppColors.error,
    this.info = AppColors.info,
  });

  static const BrandTheme defaults = BrandTheme(
    selectedNav: AppColors.primary,
    primaryDeep: AppColors.accentDeep,
    heroGradient: AppColors.heroGradient,
    isDefault: true,
  );

  static BrandTheme of(BuildContext context) =>
      Theme.of(context).extension<BrandTheme>() ?? defaults;

  @override
  BrandTheme copyWith({
    Color? selectedNav,
    Color? primaryDeep,
    LinearGradient? heroGradient,
  }) => BrandTheme(
    selectedNav: selectedNav ?? this.selectedNav,
    primaryDeep: primaryDeep ?? this.primaryDeep,
    heroGradient: heroGradient ?? this.heroGradient,
    isDefault: isDefault,
  );

  @override
  BrandTheme lerp(ThemeExtension<BrandTheme>? other, double t) {
    if (other is! BrandTheme) return this;
    return BrandTheme(
      selectedNav: Color.lerp(selectedNav, other.selectedNav, t)!,
      primaryDeep: Color.lerp(primaryDeep, other.primaryDeep, t)!,
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
      isDefault: t < 0.5 ? isDefault : other.isDefault,
    );
  }
}

/// Reads the school's colours at paint time.
extension BrandTone on BuildContext {
  /// Maps a legacy palette constant ([AppColors.accent], `gold`, …) to the
  /// school's equivalent so screens that still carry those constants (tile and
  /// category colours in static lists) follow the tenant theme. Status colours
  /// (success, warning, orange, error, info) and any other colour pass through
  /// unchanged, and under the default theme everything does, so the approved
  /// design is untouched.
  Color brandTone(Color c) {
    final brand = BrandTheme.of(this);
    if (brand.isDefault) return c;
    final s = Theme.of(this).colorScheme;
    if (c == AppColors.accent || c == AppColors.primary) return s.primary;
    if (c == AppColors.accentDeep || c == AppColors.primaryDark) {
      return brand.primaryDeep;
    }
    if (c == AppColors.primaryLight) {
      return ColorMath.mix(s.primary, Colors.white, 0.35);
    }
    if (c == AppColors.gold) return s.tertiary;
    if (c == AppColors.secondary) return s.secondary;
    if (c == AppColors.teal) return ColorMath.mix(s.secondary, s.primary, 0.5);
    if (c == AppColors.ink) return s.onSurface;
    if (c == AppColors.primaryContainer) return s.primaryContainer;
    return c;
  }

  /// Secondary text on a primary-coloured banner.
  Color get brandOnHeroMuted {
    if (BrandTheme.of(this).isDefault) return const Color(0xFFD5EEE5);
    return Theme.of(this).colorScheme.onPrimary.withValues(alpha: 0.85);
  }

  /// The hero panel gradient (dark, tinted with the school's primary).
  LinearGradient get brandHeroGradient => BrandTheme.of(this).heroGradient;
}

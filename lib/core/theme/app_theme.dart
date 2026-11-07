import 'package:flutter/material.dart';

import '../branding/tenant_branding.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';
import 'brand_theme.dart';
import 'color_math.dart';

/// Central theme factory. Screens should never construct `ThemeData` or
/// hardcode visual values directly — add a token here instead.
abstract final class AppTheme {
  /// The themes of the signed-in school ([theme]); null is the platform
  /// default (signed out, or between accounts).
  static ThemeData light([ResolvedTheme? theme]) =>
      _build(Brightness.light, theme?.colors ?? BrandColors.emerald);

  static ThemeData dark([ResolvedTheme? theme]) =>
      _build(Brightness.dark, theme?.colors ?? BrandColors.emerald);

  /// The scheme for [brand]. The default set reproduces the approved design
  /// exactly; any other set is derived from the school's seven colours.
  static ColorScheme _scheme(Brightness brightness, BrandColors brand) {
    if (brand != BrandColors.emerald) return _derived(brightness, brand);
    if (brightness == Brightness.light) {
      return const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.ink,
        secondary: AppColors.secondary,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.lightTint,
        onSecondaryContainer: AppColors.ink,
        tertiary: AppColors.gold,
        onTertiary: AppColors.ink,
        tertiaryContainer: Color(0xFFFBEFD6),
        onTertiaryContainer: Color(0xFF4A3300),
        error: AppColors.error,
        onError: Colors.white,
        errorContainer: Color(0xFFFBE9E8),
        onErrorContainer: Color(0xFF8C1D1D),
        surface: AppColors.lightSurface,
        onSurface: AppColors.ink,
        onSurfaceVariant: AppColors.textSecondary,
        outline: Color(0xFF8A9A93),
        outlineVariant: AppColors.lightBorder,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Color(0xFFFAFBFA),
        surfaceContainer: AppColors.lightBackground,
        surfaceContainerHigh: AppColors.lightTint,
        surfaceContainerHighest: Color(0xFFE6ECE8),
        inverseSurface: AppColors.ink,
        onInverseSurface: Colors.white,
        inversePrimary: AppColors.primaryLight,
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint: AppColors.primary,
      );
    }
    return const ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primaryLight,
      onPrimary: AppColors.inkDeep,
      primaryContainer: Color(0xFF14503F),
      onPrimaryContainer: Color(0xFFD5EEE5),
      secondary: Color(0xFFA9CDBE),
      onSecondary: AppColors.inkDeep,
      secondaryContainer: AppColors.darkTint,
      onSecondaryContainer: Color(0xFFD5EEE5),
      tertiary: AppColors.gold,
      onTertiary: AppColors.inkDeep,
      tertiaryContainer: Color(0xFF55400F),
      onTertiaryContainer: Color(0xFFFBEFD6),
      error: Color(0xFFFF8A80),
      onError: Color(0xFF3A0000),
      errorContainer: Color(0xFF5C2422),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: AppColors.darkSurface,
      onSurface: Color(0xFFE6EFEA),
      onSurfaceVariant: Color(0xFFA7B6AE),
      outline: Color(0xFF70867C),
      outlineVariant: AppColors.darkBorder,
      surfaceContainerLowest: AppColors.darkBackground,
      surfaceContainerLow: Color(0xFF111C18),
      surfaceContainer: AppColors.darkSurface,
      surfaceContainerHigh: AppColors.darkTint,
      surfaceContainerHighest: Color(0xFF254238),
      inverseSurface: Color(0xFFE6EFEA),
      onInverseSurface: AppColors.ink,
      inversePrimary: AppColors.primary,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: AppColors.primaryLight,
    );
  }

  static ColorScheme _derived(Brightness brightness, BrandColors c) {
    final isDark = brightness == Brightness.dark;
    if (!isDark) {
      final surface = c.surface;
      var variant = ColorMath.mix(c.text, surface, 0.35);
      if (ColorMath.contrast(variant, surface) < 4.5) variant = c.text;
      return ColorScheme(
        brightness: Brightness.light,
        primary: c.primary,
        onPrimary: ColorMath.onColor(c.primary),
        primaryContainer: ColorMath.mix(surface, c.primary, 0.12),
        onPrimaryContainer: c.text,
        secondary: c.secondary,
        onSecondary: ColorMath.onColor(c.secondary),
        secondaryContainer: ColorMath.mix(surface, c.secondary, 0.12),
        onSecondaryContainer: c.text,
        tertiary: c.accent,
        onTertiary: ColorMath.onColor(c.accent),
        tertiaryContainer: ColorMath.mix(surface, c.accent, 0.22),
        onTertiaryContainer: c.text,
        error: AppColors.error,
        onError: Colors.white,
        errorContainer: const Color(0xFFFBE9E8),
        onErrorContainer: const Color(0xFF8C1D1D),
        surface: surface,
        onSurface: c.text,
        onSurfaceVariant: variant,
        outline: ColorMath.mix(surface, c.text, 0.55),
        outlineVariant: ColorMath.mix(surface, c.text, 0.12),
        surfaceContainerLowest: surface,
        surfaceContainerLow: ColorMath.mix(surface, c.background, 0.5),
        surfaceContainer: c.background,
        surfaceContainerHigh: ColorMath.mix(surface, c.primary, 0.09),
        surfaceContainerHighest: ColorMath.mix(surface, c.primary, 0.15),
        inverseSurface: c.text,
        onInverseSurface: ColorMath.onColor(c.text),
        inversePrimary: ColorMath.mix(c.primary, Colors.white, 0.4),
        shadow: Colors.black,
        scrim: Colors.black,
        surfaceTint: c.primary,
      );
    }
    // Dark: neutral dark surfaces tinted a little toward the school's primary;
    // brand colours are lifted until they read on them.
    Color tinted(Color base) => ColorMath.mix(base, c.primary, 0.07);
    final bg = tinted(AppColors.darkBackground);
    final surface = tinted(AppColors.darkSurface);
    final primary = ColorMath.liftOn(c.primary, surface, 4.5);
    final secondary = ColorMath.liftOn(c.secondary, surface, 4.5);
    final accent = ColorMath.liftOn(c.accent, surface, 3);
    return ColorScheme(
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: ColorMath.onColor(primary),
      primaryContainer: ColorMath.mix(surface, c.primary, 0.35),
      onPrimaryContainer: const Color(0xFFEFEFEF),
      secondary: secondary,
      onSecondary: ColorMath.onColor(secondary),
      secondaryContainer: tinted(AppColors.darkTint),
      onSecondaryContainer: const Color(0xFFEFEFEF),
      tertiary: accent,
      onTertiary: ColorMath.onColor(accent),
      tertiaryContainer: ColorMath.mix(surface, c.accent, 0.3),
      onTertiaryContainer: const Color(0xFFEFEFEF),
      error: const Color(0xFFFF8A80),
      onError: const Color(0xFF3A0000),
      errorContainer: const Color(0xFF5C2422),
      onErrorContainer: const Color(0xFFFFDAD6),
      surface: surface,
      onSurface: const Color(0xFFE9ECEB),
      onSurfaceVariant: const Color(0xFFB0B8B5),
      outline: ColorMath.mix(const Color(0xFF70867C), primary, 0.2),
      outlineVariant: tinted(AppColors.darkBorder),
      surfaceContainerLowest: bg,
      surfaceContainerLow: ColorMath.mix(bg, surface, 0.5),
      surfaceContainer: surface,
      surfaceContainerHigh: tinted(AppColors.darkTint),
      surfaceContainerHighest: ColorMath.mix(surface, c.primary, 0.25),
      inverseSurface: const Color(0xFFE9ECEB),
      onInverseSurface: AppColors.ink,
      inversePrimary: c.primary,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: primary,
    );
  }

  static BrandTheme _brandTheme(
    Brightness brightness,
    BrandColors c,
    ColorScheme scheme,
  ) {
    if (c == BrandColors.emerald) {
      return brightness == Brightness.dark
          ? BrandTheme.defaults.copyWith(selectedNav: scheme.primary)
          : BrandTheme.defaults;
    }
    final dark = brightness == Brightness.dark;
    final deep = ColorMath.mix(c.primary, Colors.black, 0.25);
    final base = ColorMath.mix(Colors.black, c.primary, 0.12);
    return BrandTheme(
      selectedNav: dark ? scheme.primary : c.selectedNav,
      primaryDeep: deep,
      heroGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [base, ColorMath.mix(base, c.primary, 0.25), deep],
        stops: const [0, 0.6, 1],
      ),
    );
  }

  static ThemeData _build(Brightness brightness, BrandColors brand) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = _scheme(brightness, brand);
    final brandTheme = _brandTheme(brightness, brand, colorScheme);
    final isDefault = brand == BrandColors.emerald;

    // Everything below comes from the scheme, so a school's colours reach every
    // component. (For the default set the scheme equals the approved palette.)
    final background = isDark
        ? colorScheme.surfaceContainerLowest
        : colorScheme.surfaceContainer;
    final surface = colorScheme.surface;
    final border = colorScheme.outlineVariant;
    final tint = colorScheme.surfaceContainerHigh;

    final disabledBg = isDark
        ? tint
        : (isDefault
              ? AppColors.disabledBackground
              : ColorMath.mix(surface, colorScheme.onSurface, 0.07));
    final disabledFg = isDark
        ? colorScheme.outline
        : (isDefault
              ? AppColors.disabledText
              : ColorMath.mix(surface, colorScheme.onSurface, 0.45));
    final inkSurface = isDefault
        ? AppColors.ink
        : (isDark
              ? colorScheme.surfaceContainerHigh
              : colorScheme.inverseSurface);
    final onInk = ColorMath.onColor(inkSurface);
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    );
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [brandTheme],
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      visualDensity: VisualDensity.standard,
      // No slide between screens: the route progress bar marks the change.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const _NoTransitionsBuilder(),
        },
      ),
      textTheme: AppTypography.textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      // Inner screens (the ones that push their own AppBar) use the same
      // white header as the shell's top bar: dark text, a hairline border.
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: border)),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        actionsIconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: AppTypography.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: AppTypography.textTheme.labelLarge,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: buttonPadding,
          shape: buttonShape,
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: disabledFg,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: buttonPadding,
          shape: buttonShape,
          side: BorderSide(color: isDark ? colorScheme.outline : border),
          foregroundColor: colorScheme.primary,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          shape: buttonShape,
          foregroundColor: colorScheme.primary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tint,
        selectedColor: colorScheme.primaryContainer,
        side: BorderSide(color: border),
        labelStyle: TextStyle(color: colorScheme.onSurface),
        secondaryLabelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        dividerColor: border,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colorScheme.onSurfaceVariant,
        selectedColor: colorScheme.primary,
        selectedTileColor: tint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(tint),
        headingTextStyle: AppTypography.textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
        dataRowMinHeight: 48,
        dataRowMaxHeight: 56,
        dividerThickness: 1,
        dataRowColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? tint.withValues(alpha: 0.6)
              : states.contains(WidgetState.selected)
              ? colorScheme.primaryContainer
              : null,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: colorScheme.primaryContainer,
          selectedForegroundColor: colorScheme.onPrimaryContainer,
          side: BorderSide(color: isDark ? colorScheme.outline : border),
          shape: buttonShape,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: border),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: inkSurface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: TextStyle(color: onInk, fontSize: 12),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? disabledFg
              : s.contains(WidgetState.selected)
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? disabledBg
              : s.contains(WidgetState.selected)
              ? colorScheme.primary
              : null,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          colorScheme.outline.withValues(alpha: 0.5),
        ),
        radius: const Radius.circular(AppRadius.pill),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? brandTheme.selectedNav
                : colorScheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: TextStyle(
          color: brandTheme.selectedNav,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: tint,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? colorScheme.onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? colorScheme.primary : null,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: inkSurface,
        contentTextStyle: TextStyle(color: onInk),
        actionTextColor: colorScheme.tertiary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    );
  }
}

class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

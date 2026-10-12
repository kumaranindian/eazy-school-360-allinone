import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Central theme factory. Screens should never construct `ThemeData` or
/// hardcode visual values directly — add a token here instead.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme _scheme(Brightness brightness) {
    if (brightness == Brightness.light) {
      return const ColorScheme(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.navy,
        secondary: AppColors.navy,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.lightTint,
        onSecondaryContainer: AppColors.navy,
        tertiary: AppColors.gold,
        onTertiary: AppColors.navy,
        tertiaryContainer: Color(0xFFFFEFC7),
        onTertiaryContainer: Color(0xFF4A3000),
        error: AppColors.error,
        onError: Colors.white,
        errorContainer: Color(0xFFFDE7E7),
        onErrorContainer: Color(0xFF8C1D1D),
        surface: AppColors.lightSurface,
        onSurface: AppColors.navy,
        onSurfaceVariant: Color(0xFF4A5C78),
        outline: Color(0xFF8396B2),
        outlineVariant: AppColors.lightBorder,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Color(0xFFF8FBFE),
        surfaceContainer: AppColors.lightBackground,
        surfaceContainerHigh: AppColors.lightTint,
        surfaceContainerHighest: Color(0xFFE2EDFB),
        inverseSurface: AppColors.navy,
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
      onPrimary: AppColors.navyDeep,
      primaryContainer: Color(0xFF0B3F83),
      onPrimaryContainer: Color(0xFFD9EAFF),
      secondary: Color(0xFFB9D4F7),
      onSecondary: AppColors.navyDeep,
      secondaryContainer: AppColors.darkTint,
      onSecondaryContainer: Color(0xFFD9EAFF),
      tertiary: AppColors.gold,
      onTertiary: AppColors.navyDeep,
      tertiaryContainer: Color(0xFF5A3D00),
      onTertiaryContainer: Color(0xFFFFEFC7),
      error: Color(0xFFFF8A80),
      onError: Color(0xFF3A0000),
      errorContainer: Color(0xFF5C1A1A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: AppColors.darkSurface,
      onSurface: Color(0xFFE8F0FC),
      onSurfaceVariant: Color(0xFFA9BAD4),
      outline: Color(0xFF6C84A6),
      outlineVariant: AppColors.darkBorder,
      surfaceContainerLowest: AppColors.darkBackground,
      surfaceContainerLow: Color(0xFF0A1D3B),
      surfaceContainer: AppColors.darkSurface,
      surfaceContainerHigh: AppColors.darkTint,
      surfaceContainerHighest: Color(0xFF1A3D70),
      inverseSurface: Color(0xFFE8F0FC),
      onInverseSurface: AppColors.navy,
      inversePrimary: AppColors.primary,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: AppColors.primaryLight,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = _scheme(brightness);

    final background = isDark
        ? AppColors.darkBackground
        : AppColors.lightBackground;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final tint = isDark ? AppColors.darkTint : AppColors.lightTint;

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
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      visualDensity: VisualDensity.standard,
      textTheme: AppTypography.textTheme.apply(
        bodyColor: colorScheme.onSurface,
        displayColor: colorScheme.onSurface,
      ),
      // Inner screens (the ones that push their own AppBar) get the same
      // navy as the dashboard hero. The shell's own top bar overrides this
      // to stay light — see AdaptiveScaffold.
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkTint : AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: AppTypography.textTheme.titleLarge?.copyWith(
          color: Colors.white,
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
        fillColor: isDark ? AppColors.darkBackground : Colors.white,
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
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: AppTypography.textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: buttonPadding,
          shape: buttonShape,
          elevation: 0,
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
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
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      checkboxTheme: CheckboxThemeData(
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
                ? colorScheme.primary
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
          color: colorScheme.primary,
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
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: AppColors.gold,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, space: 1, thickness: 1),
    );
  }
}

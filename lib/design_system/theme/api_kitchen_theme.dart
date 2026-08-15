import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_typography.dart';
import 'package:flutter/material.dart';

class ApiKitchenTheme {
  const ApiKitchenTheme._();

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.infoAlt,
      onSecondary: Colors.white,
      tertiary: AppColors.warning,
      onTertiary: AppColors.textPrimary,
      error: AppColors.dangerAlt,
      onError: Colors.white,
      surface: AppColors.adminSurface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.adminSurfaceMuted,
      outline: AppColors.neutral,
      outlineVariant: AppColors.adminBorder,
    );
    return _base(scheme, AppColors.adminBackground);
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.accent,
      onPrimary: AppColors.staffText,
      secondary: AppColors.info,
      onSecondary: AppColors.staffBackground,
      tertiary: AppColors.warning,
      onTertiary: AppColors.staffBackground,
      error: AppColors.danger,
      onError: AppColors.staffBackground,
      surface: AppColors.staffSurface,
      onSurface: AppColors.staffText,
      surfaceContainerHighest: AppColors.staffCard,
      outline: AppColors.staffMuted,
      outlineVariant: AppColors.staffBorder,
    );
    return _base(scheme, AppColors.staffBackground);
  }

  static ThemeData staffDark() {
    return dark().copyWith(
      scaffoldBackgroundColor: AppColors.staffBackground,
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.staffNav,
        indicatorColor: AppColors.staffSurface,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.staffMuted,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.staffMuted,
            size: 22,
          ),
        ),
      ),
    );
  }

  static ThemeData _base(ColorScheme scheme, Color scaffoldBackground) {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBackground,
      visualDensity: VisualDensity.standard,
      textTheme: AppTypography.textTheme(scheme.onSurface),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        minWidth: 88,
        minExtendedWidth: 244,
      ),
    );
  }
}

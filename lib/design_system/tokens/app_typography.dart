import 'package:flutter/material.dart';

class AppTypography {
  const AppTypography._();

  /// [textColor] is the primary on-surface color for the active scheme
  /// (light or dark). [secondaryColor]/[mutedColor] default to opacity
  /// steps of [textColor] so body/label text stays legible on both the
  /// light admin surfaces and the dark staff/kitchen surfaces instead of
  /// hardcoding light-mode-only colors.
  static TextTheme textTheme(
    Color textColor, {
    Color? secondaryColor,
    Color? mutedColor,
  }) {
    final secondary = secondaryColor ?? textColor.withValues(alpha: 0.72);
    final muted = mutedColor ?? textColor.withValues(alpha: 0.56);
    return TextTheme(
      headlineMedium: TextStyle(
        color: textColor,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineSmall: TextStyle(
        color: textColor,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      titleLarge: TextStyle(
        color: textColor,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      titleSmall: TextStyle(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      bodyMedium: TextStyle(
        color: secondary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      bodySmall: TextStyle(
        color: muted,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      labelLarge: TextStyle(
        color: textColor,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
      labelMedium: TextStyle(
        color: secondary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }
}

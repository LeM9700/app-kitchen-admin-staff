import 'package:flutter/material.dart';

import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';

/// Per-scheme knobs for the neumorphic surface system: the tenant-brandable
/// accent color, the base color depth shadows are derived from for this
/// scheme (admin vs. staff/kitchen have different surfaces), and the
/// default intensity screens fall back to when no
/// `NeumorphicIntensityScope` is present.
///
/// Registered on [ThemeData.extensions] by `ApiKitchenTheme._base` and read
/// via `Theme.of(context).extension<NeumorphicThemeExtension>()`.
class NeumorphicThemeExtension
    extends ThemeExtension<NeumorphicThemeExtension> {
  const NeumorphicThemeExtension({
    required this.accentColor,
    required this.surfaceBase,
    this.defaultIntensity = NeumorphicIntensity.full,
  });

  final Color accentColor;
  final Color surfaceBase;
  final NeumorphicIntensity defaultIntensity;

  @override
  NeumorphicThemeExtension copyWith({
    Color? accentColor,
    Color? surfaceBase,
    NeumorphicIntensity? defaultIntensity,
  }) {
    return NeumorphicThemeExtension(
      accentColor: accentColor ?? this.accentColor,
      surfaceBase: surfaceBase ?? this.surfaceBase,
      defaultIntensity: defaultIntensity ?? this.defaultIntensity,
    );
  }

  @override
  NeumorphicThemeExtension lerp(
    ThemeExtension<NeumorphicThemeExtension>? other,
    double t,
  ) {
    if (other is! NeumorphicThemeExtension) {
      return this;
    }
    return NeumorphicThemeExtension(
      accentColor: Color.lerp(accentColor, other.accentColor, t) ??
          accentColor,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t) ??
          surfaceBase,
      defaultIntensity: t < 0.5 ? defaultIntensity : other.defaultIntensity,
    );
  }
}

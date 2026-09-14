import 'package:flutter/material.dart';

/// How much neumorphic depth a surface should carry.
///
/// Real-time/time-critical screens (kitchen, orders board, checkout,
/// dashboard) default to [flat] or [subtle] so soft shadows never compete
/// with fast reading of live status/countdown text. Back-office screens
/// default to [full].
enum NeumorphicIntensity { flat, subtle, full }

/// Derives a believable dual-shadow (highlight + shadow) pair from a single
/// surface color, so the same formula produces correct-looking depth on
/// both light admin surfaces (e.g. [AppColors.adminSurface]) and dark
/// staff/kitchen surfaces (e.g. [AppColors.staffCard]) without hardcoding
/// per-theme shadow colors.
class NeumorphicShadows {
  const NeumorphicShadows._();

  /// Extruded/"raised" look — the resting and hovered state of a card.
  static List<BoxShadow> raised(
    Color surfaceBase, {
    double blur = 12,
    double offset = 5,
    double intensity = 1.0,
  }) {
    if (intensity <= 0) {
      return const [];
    }
    final hsl = HSLColor.fromColor(surfaceBase);
    final isDark = hsl.lightness < 0.5;
    final highlight = hsl
        .withLightness(
          (hsl.lightness + (isDark ? 0.10 : 0.06)).clamp(0.0, 1.0),
        )
        .toColor()
        .withValues(alpha: (isDark ? 0.05 : 0.85) * intensity);
    final shadow = hsl
        .withLightness(
          (hsl.lightness - (isDark ? 0.06 : 0.10)).clamp(0.0, 1.0),
        )
        .toColor()
        .withValues(alpha: (isDark ? 0.5 : 0.14) * intensity);
    return [
      BoxShadow(
        color: highlight,
        offset: Offset(-offset * 0.7, -offset * 0.7),
        blurRadius: blur * 0.8,
      ),
      BoxShadow(
        color: shadow,
        offset: Offset(offset, offset * 1.15),
        blurRadius: blur,
      ),
    ];
  }

  /// Approximates a "pressed"/inset surface. Flutter's [BoxShadow] has no
  /// true CSS `inset` equivalent (it always paints outside the box), so
  /// this fakes the effect the way most neumorphic CSS recipes do: the
  /// light/dark shadow positions are swapped relative to [raised] and kept
  /// tight/low-blur, which reads as "pushed in" rather than "popped out"
  /// when combined with a slightly darkened fill (see [pressedFill]).
  static List<BoxShadow> inset(
    Color surfaceBase, {
    double intensity = 1.0,
  }) {
    if (intensity <= 0) {
      return const [];
    }
    final hsl = HSLColor.fromColor(surfaceBase);
    final isDark = hsl.lightness < 0.5;
    final highlight = hsl
        .withLightness(
          (hsl.lightness + (isDark ? 0.08 : 0.05)).clamp(0.0, 1.0),
        )
        .toColor()
        .withValues(alpha: (isDark ? 0.04 : 0.6) * intensity);
    final shadow = hsl
        .withLightness(
          (hsl.lightness - (isDark ? 0.05 : 0.08)).clamp(0.0, 1.0),
        )
        .toColor()
        .withValues(alpha: (isDark ? 0.4 : 0.12) * intensity);
    return [
      BoxShadow(
        color: shadow,
        offset: const Offset(-2, -2),
        blurRadius: 4,
        spreadRadius: -1,
      ),
      BoxShadow(
        color: highlight,
        offset: const Offset(2, 2),
        blurRadius: 4,
        spreadRadius: -1,
      ),
    ];
  }

  /// Slightly darkened fill to pair with [inset] so a pressed surface also
  /// reads as "recessed" through color, not shadow alone.
  static Color pressedFill(Color surfaceBase) {
    final hsl = HSLColor.fromColor(surfaceBase);
    final isDark = hsl.lightness < 0.5;
    return hsl
        .withLightness(
          (hsl.lightness + (isDark ? 0.02 : -0.025)).clamp(0.0, 1.0),
        )
        .toColor();
  }
}

/// Named depth presets built on [NeumorphicShadows]. [flat] is the current
/// (pre-redesign) look — an empty shadow list — kept as the default for
/// contexts that opt out of depth entirely (see `NeumorphicIntensityScope`
/// in `ds_card.dart`).
class AppElevation {
  const AppElevation._();

  static const flat = <BoxShadow>[];

  static List<BoxShadow> raisedSm(Color surfaceBase, {double intensity = 1}) =>
      NeumorphicShadows.raised(
        surfaceBase,
        blur: 8,
        offset: 3,
        intensity: intensity,
      );

  static List<BoxShadow> raisedMd(Color surfaceBase, {double intensity = 1}) =>
      NeumorphicShadows.raised(
        surfaceBase,
        blur: 14,
        offset: 5,
        intensity: intensity,
      );

  static List<BoxShadow> raisedLg(Color surfaceBase, {double intensity = 1}) =>
      NeumorphicShadows.raised(
        surfaceBase,
        blur: 22,
        offset: 8,
        intensity: intensity,
      );

  static List<BoxShadow> pressed(Color surfaceBase, {double intensity = 1}) =>
      NeumorphicShadows.inset(surfaceBase, intensity: intensity);
}

/// Semantic alert "glow" rings — distinct from [AppElevation]'s decorative
/// depth. These mark urgency/state transitions (e.g. a late kitchen ticket,
/// an order becoming ready) and must never be softened away by the
/// neumorphic pass, so they live in their own token family.
class AppGlow {
  const AppGlow._();

  static List<BoxShadow> urgent(Color color, {double spread = 2}) => [
        BoxShadow(
          color: color.withValues(alpha: 0.28),
          spreadRadius: spread,
        ),
      ];

  static List<BoxShadow> ready(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.24),
          blurRadius: 16,
          spreadRadius: 2,
        ),
      ];
}

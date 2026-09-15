import 'package:flutter/material.dart';

import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';

/// Scopes the neumorphic depth every [DsCard] below it should use, so
/// real-time screens (kitchen/orders/checkout/dashboard) can attenuate
/// depth once at the route/scaffold level instead of relying on every call
/// site to remember to pass `intensity: NeumorphicIntensity.flat`.
class NeumorphicIntensityScope extends InheritedWidget {
  const NeumorphicIntensityScope({
    required this.intensity,
    required super.child,
    super.key,
  });

  final NeumorphicIntensity intensity;

  static NeumorphicIntensity? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<NeumorphicIntensityScope>()
        ?.intensity;
  }

  @override
  bool updateShouldNotify(NeumorphicIntensityScope oldWidget) =>
      intensity != oldWidget.intensity;
}

class DsCard extends StatefulWidget {
  const DsCard({
    required this.child,
    this.padding = AppSpacing.card,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppRadius.xl,
    this.width,
    this.height,
    this.onTap,
    this.intensity = NeumorphicIntensity.full,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  /// Depth level for this card. Overridden by an ancestor
  /// [NeumorphicIntensityScope] when present, so a screen can attenuate
  /// depth for every card beneath it in one place.
  final NeumorphicIntensity intensity;

  @override
  State<DsCard> createState() => _DsCardState();
}

class _DsCardState extends State<DsCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (widget.onTap == null || _pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final intensity =
        NeumorphicIntensityScope.maybeOf(context) ?? widget.intensity;
    final surfaceBase = widget.backgroundColor ?? scheme.surface;

    var fill = surfaceBase;
    List<BoxShadow> shadow;
    if (intensity == NeumorphicIntensity.flat) {
      shadow = AppElevation.flat;
    } else {
      final depthIntensity =
          intensity == NeumorphicIntensity.subtle ? 0.5 : 1.0;
      if (_pressed) {
        shadow = AppElevation.pressed(surfaceBase, intensity: depthIntensity);
        fill = NeumorphicShadows.pressedFill(surfaceBase);
      } else {
        shadow = AppElevation.raisedMd(surfaceBase, intensity: depthIntensity);
      }
    }

    final content = AnimatedContainer(
      duration: Duration(milliseconds: _pressed ? 90 : 180),
      curve: _pressed ? Curves.easeOut : Curves.easeInOut,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: widget.borderColor ?? scheme.outlineVariant),
        boxShadow: shadow,
      ),
      // A transparent Material sits directly against the child (not just
      // around the whole card) so descendants that need a Material
      // ancestor for their own ink/background (ListTile, Chip, ...) have
      // one with no colored decoration in between — the same guarantee
      // the Card widget this replaces gave for free.
      child: Material(
        type: MaterialType.transparency,
        child: widget.child,
      ),
    );

    if (widget.onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        // The shadow/fill transition above is the press feedback; a default
        // Material ripple on top of it would fight the soft-shadow look.
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: content,
      ),
    );
  }
}

class StaffDsCard extends StatelessWidget {
  const StaffDsCard({
    required this.child,
    this.padding = AppSpacing.cardCompact,
    this.onTap,
    this.intensity = NeumorphicIntensity.full,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final NeumorphicIntensity intensity;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      backgroundColor: AppColors.staffCard,
      borderColor: AppColors.staffBorder,
      borderRadius: AppRadius.lg,
      padding: padding,
      onTap: onTap,
      intensity: intensity,
      child: child,
    );
  }
}

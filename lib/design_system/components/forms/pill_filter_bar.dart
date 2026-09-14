import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:flutter/material.dart';

class PillFilterOption<T> {
  const PillFilterOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

class PillFilterBar<T> extends StatelessWidget {
  const PillFilterBar({
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<PillFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final option in options)
          _PillFilterButton<T>(
            option: option,
            selected: option.value == selected,
            onSelected: onSelected,
          ),
      ],
    );
  }
}

class _PillFilterButton<T> extends StatelessWidget {
  const _PillFilterButton({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  final PillFilterOption<T> option;
  final bool selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.textSecondary;
    final fillBase =
        selected ? AppColors.adminSidebar : AppColors.adminSurfaceMuted;
    final intensity =
        NeumorphicIntensityScope.maybeOf(context) ?? NeumorphicIntensity.full;
    // Selected reads as "pressed in" (active filter), unselected stays
    // flat — same press/depth language as DsCard, attenuated together
    // with it on real-time screens via NeumorphicIntensityScope.
    final hasDepth = selected && intensity != NeumorphicIntensity.flat;
    final depthIntensity = intensity == NeumorphicIntensity.subtle ? 0.5 : 1.0;
    final fill = hasDepth ? NeumorphicShadows.pressedFill(fillBase) : fillBase;
    final shadow = hasDepth
        ? AppElevation.pressed(fillBase, intensity: depthIntensity)
        : AppElevation.flat;

    return Tooltip(
      message: option.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: shadow,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: () => onSelected(option.value),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (option.icon != null) ...[
                      Icon(option.icon, size: 16, color: foreground),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Text(
                      option.label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

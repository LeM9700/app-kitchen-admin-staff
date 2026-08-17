import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:flutter/material.dart';

class KitchenStatusHeader extends StatelessWidget {
  const KitchenStatusHeader({
    required this.totalWaiting,
    required this.totalPreparing,
    required this.totalNew,
    super.key,
  });

  final int totalWaiting;
  final int totalPreparing;
  final int totalNew;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final counters = [
                _KitchenHeaderCounter(
                  value: totalWaiting,
                  label: 'EN ATTENTE',
                  color: AppColors.infoAlt,
                ),
                _KitchenHeaderCounter(
                  value: totalPreparing,
                  label: 'EN PRÉPARATION',
                  color: AppColors.warning,
                ),
                _KitchenHeaderCounter(
                  value: totalNew,
                  label: 'NOUVELLES',
                  color: AppColors.success,
                ),
              ];

              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CUISINE',
                      style: KitchenTypography.headerTitle(context),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: counters),
                  ],
                );
              }

              return Row(
                children: [
                  Text(
                    'CUISINE',
                    style: KitchenTypography.headerTitle(context),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: counters,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _KitchenHeaderCounter extends StatelessWidget {
  const _KitchenHeaderCounter({
    required this.value,
    required this.label,
    required this.color,
  });

  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : AppColors.textPrimary;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          '$value $label',
          style: KitchenTypography.headerCounter(context).copyWith(
            color: foreground,
          ),
        ),
      ),
    );
  }
}

import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter/material.dart';

class KitchenStatusUi {
  const KitchenStatusUi({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  static KitchenStatusUi from(KitchenTicketState state) {
    return switch (state) {
      KitchenTicketState.awaitingConfirmation => const KitchenStatusUi(
          label: 'EN ATTENTE DE CONFIRMATION',
          color: AppColors.infoAlt,
          icon: Icons.lock_outline,
        ),
      KitchenTicketState.readyToStart => const KitchenStatusUi(
          label: 'À COMMENCER',
          color: AppColors.neutral,
          icon: Icons.play_arrow_outlined,
        ),
      KitchenTicketState.preparing => const KitchenStatusUi(
          label: 'EN PRÉPARATION',
          color: AppColors.warning,
          icon: Icons.local_fire_department_outlined,
        ),
      KitchenTicketState.ready => const KitchenStatusUi(
          label: 'PRÊTE',
          color: AppColors.success,
          icon: Icons.check_circle_outline,
        ),
    };
  }

  Color foregroundColor() {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : AppColors.textPrimary;
  }
}

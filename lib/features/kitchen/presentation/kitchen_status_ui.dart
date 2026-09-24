import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_visuals.dart';
import 'package:flutter/material.dart';

class KitchenStatusUi {
  const KitchenStatusUi({
    required this.label,
    required this.color,
    required this.background,
    required this.icon,
    required this.tone,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData icon;
  final KitchenTone tone;

  static KitchenStatusUi from(KitchenTicketState state) {
    final tone = switch (state) {
      KitchenTicketState.awaitingConfirmation => KitchenTone.awaiting,
      KitchenTicketState.readyToStart => KitchenTone.readyToStart,
      KitchenTicketState.preparing => KitchenTone.preparing,
      KitchenTicketState.ready => KitchenTone.ready,
    };

    return switch (state) {
      KitchenTicketState.awaitingConfirmation => KitchenStatusUi(
          label: 'EN ATTENTE DE CONFIRMATION',
          color: KitchenVisuals.statusColor(tone),
          background: KitchenVisuals.statusBackground(tone),
          icon: Icons.lock_outline,
          tone: tone,
        ),
      KitchenTicketState.readyToStart => KitchenStatusUi(
          label: 'À COMMENCER',
          color: KitchenVisuals.statusColor(tone),
          background: KitchenVisuals.statusBackground(tone),
          icon: Icons.play_arrow_outlined,
          tone: tone,
        ),
      KitchenTicketState.preparing => KitchenStatusUi(
          label: 'EN PRÉPARATION',
          color: KitchenVisuals.statusColor(tone),
          background: KitchenVisuals.statusBackground(tone),
          icon: Icons.local_fire_department_outlined,
          tone: tone,
        ),
      KitchenTicketState.ready => KitchenStatusUi(
          label: 'PRÊTE',
          color: KitchenVisuals.statusColor(tone),
          background: KitchenVisuals.statusBackground(tone),
          icon: Icons.check_circle_outline,
          tone: tone,
        ),
    };
  }

  Color foregroundColor() {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : AppColors.textPrimary;
  }
}

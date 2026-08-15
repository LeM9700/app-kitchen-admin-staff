import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

class OrderStatusUi {
  const OrderStatusUi({
    required this.label,
    required this.foreground,
    required this.background,
    required this.icon,
    required this.tone,
    required this.emphasis,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData icon;
  final StatusTone tone;
  final bool emphasis;

  static OrderStatusUi from(String status) {
    return switch (status) {
      'pending' => const OrderStatusUi(
          label: 'En attente',
          foreground: AppColors.warning,
          background: AppColors.warningBg,
          icon: Icons.schedule_outlined,
          tone: StatusTone.warning,
          emphasis: true,
        ),
      'queued' => const OrderStatusUi(
          label: 'En file',
          foreground: AppColors.infoAlt,
          background: AppColors.infoBg,
          icon: Icons.playlist_add_check_outlined,
          tone: StatusTone.info,
          emphasis: true,
        ),
      'confirmed' => const OrderStatusUi(
          label: 'Confirmee',
          foreground: AppColors.info,
          background: AppColors.infoBg,
          icon: Icons.verified_outlined,
          tone: StatusTone.info,
          emphasis: false,
        ),
      'preparing' => const OrderStatusUi(
          label: 'Preparation',
          foreground: AppColors.warning,
          background: AppColors.warningBg,
          icon: Icons.restaurant_outlined,
          tone: StatusTone.warning,
          emphasis: true,
        ),
      'ready' => const OrderStatusUi(
          label: 'Prete',
          foreground: AppColors.success,
          background: AppColors.successBg,
          icon: Icons.task_alt_outlined,
          tone: StatusTone.success,
          emphasis: true,
        ),
      'out_for_delivery' => const OrderStatusUi(
          label: 'En livraison',
          foreground: AppColors.infoAlt,
          background: AppColors.infoBg,
          icon: Icons.delivery_dining_outlined,
          tone: StatusTone.info,
          emphasis: false,
        ),
      'delivered' => const OrderStatusUi(
          label: 'Livree',
          foreground: AppColors.success,
          background: AppColors.successBg,
          icon: Icons.done_all_outlined,
          tone: StatusTone.success,
          emphasis: false,
        ),
      'cancelled' => const OrderStatusUi(
          label: 'Annulee',
          foreground: AppColors.dangerAlt,
          background: AppColors.dangerBg,
          icon: Icons.cancel_outlined,
          tone: StatusTone.danger,
          emphasis: true,
        ),
      'paid' => const OrderStatusUi(
          label: 'Payee',
          foreground: AppColors.success,
          background: AppColors.successBg,
          icon: Icons.payments_outlined,
          tone: StatusTone.success,
          emphasis: false,
        ),
      'refunded' => const OrderStatusUi(
          label: 'Remboursee',
          foreground: AppColors.neutral,
          background: AppColors.neutralBg,
          icon: Icons.undo_outlined,
          tone: StatusTone.neutral,
          emphasis: false,
        ),
      'partially_refunded' => const OrderStatusUi(
          label: 'Remb. partiel',
          foreground: AppColors.warning,
          background: AppColors.warningBg,
          icon: Icons.call_split_outlined,
          tone: StatusTone.warning,
          emphasis: false,
        ),
      'failed' => const OrderStatusUi(
          label: 'Echec',
          foreground: AppColors.dangerAlt,
          background: AppColors.dangerBg,
          icon: Icons.error_outline,
          tone: StatusTone.danger,
          emphasis: true,
        ),
      _ => OrderStatusUi(
          label: status,
          foreground: AppColors.neutral,
          background: AppColors.neutralBg,
          icon: Icons.circle_outlined,
          tone: StatusTone.neutral,
          emphasis: false,
        ),
    };
  }
}

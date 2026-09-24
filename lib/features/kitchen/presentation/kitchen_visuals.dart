import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:flutter/material.dart';

class KitchenVisuals {
  const KitchenVisuals._();

  static const boardBackground = Color(0xFFF2EEE6);
  static const headerSurface = Color(0xFFFAF7F0);
  static const ticketSurface = Color(0xFFFFFCF4);
  static const ticketHeaderSurface = Color(0xFFF7F1E8);
  static const recessedSurface = Color(0xFFEDE6DA);
  static const warmBorder = Color(0xFFE0D6C8);
  static const strongBorder = Color(0xFF7B6F62);
  static const graphite = Color(0xFF24211D);
  static const mutedText = Color(0xFF6C6358);
  static const focusBorder = Color(0xFF7A5130);

  static List<BoxShadow> ticketShadow({required bool focused}) {
    return [
      BoxShadow(
        color: Colors.white.withValues(alpha: focused ? 0.95 : 0.7),
        offset: const Offset(-1.5, -1.5),
        blurRadius: focused ? 7 : 5,
      ),
      BoxShadow(
        color: const Color(0xFF8F8171).withValues(
          alpha: focused ? 0.28 : 0.18,
        ),
        offset: Offset(0, focused ? 7 : 4),
        blurRadius: focused ? 16 : 10,
      ),
    ];
  }

  static Color statusColor(KitchenTone tone) {
    return switch (tone) {
      KitchenTone.awaiting => const Color(0xFF49677E),
      KitchenTone.readyToStart => const Color(0xFF6B6259),
      KitchenTone.preparing => const Color(0xFFA96417),
      KitchenTone.ready => const Color(0xFF24774D),
    };
  }

  static Color statusBackground(KitchenTone tone) {
    return switch (tone) {
      KitchenTone.awaiting => AppColors.infoBg,
      KitchenTone.readyToStart => AppColors.neutralBg,
      KitchenTone.preparing => AppColors.warningSoftBg,
      KitchenTone.ready => AppColors.successBg,
    };
  }
}

enum KitchenTone {
  awaiting,
  readyToStart,
  preparing,
  ready,
}

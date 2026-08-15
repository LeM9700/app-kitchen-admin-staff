import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:flutter/material.dart';

enum StatusTone { success, warning, danger, info, neutral }

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    required this.label,
    required this.tone,
    this.icon,
    this.compact = false,
    super.key,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = StatusBadgeColors.fromTone(tone);
    final foreground = Theme.of(context).brightness == Brightness.dark
        ? colors.darkForeground
        : colors.foreground;
    final background = Theme.of(context).brightness == Brightness.dark
        ? colors.darkBackground
        : colors.background;

    return Semantics(
      label: label,
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 26 : 30),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 11,
          vertical: compact ? 5 : 7,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon == null)
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: foreground,
                  borderRadius: BorderRadius.circular(4),
                ),
              )
            else
              Icon(icon, size: compact ? 14 : 16, color: foreground),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: compact ? 9 : 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusBadgeColors {
  const StatusBadgeColors({
    required this.foreground,
    required this.background,
    required this.darkForeground,
    required this.darkBackground,
  });

  final Color foreground;
  final Color background;
  final Color darkForeground;
  final Color darkBackground;

  static StatusBadgeColors fromTone(StatusTone tone) {
    return switch (tone) {
      StatusTone.success => const StatusBadgeColors(
          foreground: AppColors.success,
          background: AppColors.successBg,
          darkForeground: AppColors.success,
          darkBackground: AppColors.successDarkBg,
        ),
      StatusTone.warning => const StatusBadgeColors(
          foreground: AppColors.warning,
          background: AppColors.warningBg,
          darkForeground: AppColors.warning,
          darkBackground: Color(0xFF211C12),
        ),
      StatusTone.danger => const StatusBadgeColors(
          foreground: AppColors.danger,
          background: AppColors.dangerBg,
          darkForeground: AppColors.danger,
          darkBackground: Color(0xFF2C1418),
        ),
      StatusTone.info => const StatusBadgeColors(
          foreground: AppColors.infoAlt,
          background: AppColors.infoBg,
          darkForeground: AppColors.info,
          darkBackground: Color(0xFF0F1A29),
        ),
      StatusTone.neutral => const StatusBadgeColors(
          foreground: AppColors.neutral,
          background: AppColors.neutralBg,
          darkForeground: AppColors.staffMuted,
          darkBackground: AppColors.staffSurface,
        ),
    };
  }
}

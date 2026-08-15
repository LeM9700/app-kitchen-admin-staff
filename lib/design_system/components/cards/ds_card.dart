import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:flutter/material.dart';

class DsCard extends StatelessWidget {
  const DsCard({
    required this.child,
    this.padding = AppSpacing.card,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppRadius.xl,
    this.width,
    this.height,
    this.onTap,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? scheme.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor ?? scheme.outlineVariant),
      ),
      child: child,
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
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
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      backgroundColor: AppColors.staffCard,
      borderColor: AppColors.staffBorder,
      borderRadius: AppRadius.lg,
      padding: padding,
      onTap: onTap,
      child: child,
    );
  }
}

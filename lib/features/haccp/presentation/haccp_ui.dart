import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:flutter/material.dart';

enum HaccpTone { ok, warning, danger, neutral, info }

class HaccpToneStyle {
  const HaccpToneStyle({
    required this.foreground,
    required this.background,
    required this.icon,
  });

  final Color foreground;
  final Color background;
  final IconData icon;
}

HaccpToneStyle haccpToneStyle(HaccpTone tone) {
  return switch (tone) {
    HaccpTone.ok => const HaccpToneStyle(
        foreground: AppColors.success,
        background: AppColors.successBg,
        icon: Icons.check_circle_outline,
      ),
    HaccpTone.warning => const HaccpToneStyle(
        foreground: AppColors.warning,
        background: AppColors.warningBg,
        icon: Icons.schedule_outlined,
      ),
    HaccpTone.danger => const HaccpToneStyle(
        foreground: AppColors.dangerAlt,
        background: AppColors.dangerBg,
        icon: Icons.report_problem_outlined,
      ),
    HaccpTone.info => const HaccpToneStyle(
        foreground: AppColors.infoAlt,
        background: AppColors.infoBg,
        icon: Icons.info_outline,
      ),
    HaccpTone.neutral => const HaccpToneStyle(
        foreground: AppColors.neutral,
        background: AppColors.neutralBg,
        icon: Icons.radio_button_unchecked,
      ),
  };
}

HaccpTone haccpToneForCompliance(bool isCompliant) {
  return isCompliant ? HaccpTone.ok : HaccpTone.danger;
}

HaccpTone haccpToneForStatus(String status) {
  return switch (status) {
    'complete' || 'closed' => HaccpTone.ok,
    'incomplete_validated' || 'in_progress' => HaccpTone.warning,
    'open' => HaccpTone.danger,
    'not_started' => HaccpTone.neutral,
    _ => HaccpTone.info,
  };
}

String haccpStatusLabel(String status) {
  return switch (status) {
    'not_started' => 'A faire',
    'in_progress' => 'En cours',
    'complete' => 'Cloture',
    'incomplete_validated' => 'Cloture avec reserves',
    'open' => 'Ouverte',
    'closed' => 'Cloturee',
    _ => status,
  };
}

String haccpFriendlyError(Object error, String context) {
  final text = error.toString().toLowerCase();
  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('connection')) {
    return '$context. Verifiez la connexion ou enregistrez localement si l action le permet.';
  }
  if (text.contains('403') || text.contains('forbidden')) {
    return '$context. Permission insuffisante.';
  }
  if (text.contains('401') || text.contains('unauthorized')) {
    return '$context. Session expiree.';
  }
  return context;
}

class HaccpStatusPill extends StatelessWidget {
  const HaccpStatusPill({
    required this.label,
    required this.tone,
    this.compact = false,
    super.key,
  });

  final String label;
  final HaccpTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: style.foreground.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: compact ? 13 : 15, color: style.foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: style.foreground,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class HaccpActionCard extends StatelessWidget {
  const HaccpActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tone,
    this.trailing,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final HaccpTone tone;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    return DsCard(
      borderRadius: AppRadius.md,
      borderColor: style.foreground.withValues(alpha: 0.22),
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: style.foreground, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class HaccpInfoBanner extends StatelessWidget {
  const HaccpInfoBanner({
    required this.icon,
    required this.title,
    required this.message,
    required this.tone,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final HaccpTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: style.foreground.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: style.foreground, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: style.foreground,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: style.foreground.withValues(alpha: 0.9),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

class HaccpEmptyState extends StatelessWidget {
  const HaccpEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HaccpErrorState extends StatelessWidget {
  const HaccpErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.dangerAlt,
              size: 44,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class HaccpSkeletonList extends StatelessWidget {
  const HaccpSkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemBuilder: (_, index) => DsCard(
        borderRadius: AppRadius.md,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.adminSurfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: double.infinity,
                    color: AppColors.adminSurfaceMuted,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 10,
                    width: 160,
                    color: AppColors.adminSurfaceMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemCount: 4,
    );
  }
}

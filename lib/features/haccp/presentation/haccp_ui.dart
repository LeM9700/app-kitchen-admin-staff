import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:flutter/material.dart';

enum HaccpTone { ok, warning, danger, neutral, info }

class HaccpPalette {
  const HaccpPalette._();

  static const background = Color(0xFFF4F2EE);
  static const surface = Color(0xFFFFFCF7);
  static const surfaceWarm = Color(0xFFF8F3EA);
  static const graphite = Color(0xFF252525);
  static const graphiteSoft = Color(0xFF67625B);
  static const border = Color(0xFFE1D9CC);
}

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
    'not_started' => 'À faire',
    'in_progress' => 'En cours',
    'complete' => 'Clôturé',
    'incomplete_validated' => 'Clôturé avec réserves',
    'open' => 'Ouverte',
    'closed' => 'Clôturée',
    _ => status,
  };
}

String haccpFriendlyError(Object error, String context) {
  final text = error.toString().toLowerCase();
  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('connection')) {
    return '$context. Vérifiez la connexion ou enregistrez localement si l’action le permet.';
  }
  if (text.contains('403') || text.contains('forbidden')) {
    return '$context. Permission insuffisante.';
  }
  if (text.contains('401') || text.contains('unauthorized')) {
    return '$context. Session expirée.';
  }
  return context;
}

class HaccpPageHeader extends StatelessWidget {
  const HaccpPageHeader({
    required this.title,
    required this.subtitle,
    this.icon = Icons.verified_outlined,
    this.trailing,
    this.children = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      backgroundColor: HaccpPalette.surface,
      borderColor: HaccpPalette.border,
      borderRadius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: HaccpPalette.surfaceWarm,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: HaccpPalette.border),
                ),
                child: Icon(icon, color: HaccpPalette.graphite, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: HaccpPalette.graphite,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: HaccpPalette.graphiteSoft,
                        fontSize: 12,
                        height: 1.35,
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
          if (children.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ],
      ),
    );
  }
}

class HaccpSection extends StatelessWidget {
  const HaccpSection({
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.action,
    this.tone = HaccpTone.neutral,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? action;
  final HaccpTone tone;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    return DsCard(
      backgroundColor: HaccpPalette.surface,
      borderColor: HaccpPalette.border,
      borderRadius: AppRadius.lg,
      padding: EdgeInsets.zero,
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: style.background,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, color: style.foreground, size: 18),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: HaccpPalette.graphite,
                            ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: HaccpPalette.graphiteSoft,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
          const Divider(height: 1, color: HaccpPalette.border),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: child,
          ),
        ],
      ),
    );
  }
}

class HaccpStatusBadge extends StatelessWidget {
  const HaccpStatusBadge({
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
    return HaccpStatusPill(label: label, tone: tone, compact: compact);
  }
}

class HaccpSyncStatus extends StatelessWidget {
  const HaccpSyncStatus({
    required this.isOnline,
    required this.pendingCount,
    this.failedCount = 0,
    this.onSync,
    this.showWhenSynced = false,
    super.key,
  });

  final bool isOnline;
  final int pendingCount;

  /// Actions en file dont au moins une tentative de synchronisation a echoue.
  final int failedCount;
  final VoidCallback? onSync;

  /// Affiche aussi l'état Synchronisé (sinon le widget disparait).
  final bool showWhenSynced;

  @override
  Widget build(BuildContext context) {
    final synced = isOnline && pendingCount == 0;
    if (synced && !showWhenSynced) return const SizedBox.shrink();

    final tone = failedCount > 0
        ? HaccpTone.danger
        : !isOnline
            ? HaccpTone.warning
            : pendingCount > 0
                ? HaccpTone.info
                : HaccpTone.ok;
    final style = haccpToneStyle(tone);
    final IconData icon = failedCount > 0
        ? Icons.sync_problem_outlined
        : !isOnline
            ? Icons.wifi_off
            : pendingCount > 0
                ? Icons.cloud_upload_outlined
                : Icons.cloud_done_outlined;
    final String title;
    final String? detail;
    if (failedCount > 0) {
      title = 'Erreur de synchronisation';
      detail = '$failedCount action(s) à renvoyer — enregistrées localement';
    } else if (!isOnline) {
      title = 'Enregistré localement';
      detail = pendingCount > 0
          ? 'Hors ligne — $pendingCount action(s) en attente de synchronisation'
          : 'Hors ligne — les saisies seront envoyées au retour du réseau';
    } else if (pendingCount > 0) {
      title = 'Enregistré localement';
      detail = 'Synchronisation en attente — $pendingCount action(s)';
    } else {
      title = 'Synchronisé';
      detail = null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: style.background,
        border: Border(
          bottom: BorderSide(color: style.foreground.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: style.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: style.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: TextStyle(
                      color: style.foreground.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (isOnline && pendingCount > 0 && onSync != null)
            TextButton.icon(
              onPressed: onSync,
              icon: const Icon(Icons.cloud_sync_outlined, size: 18),
              label: const Text('Synchroniser'),
              style: TextButton.styleFrom(
                foregroundColor: style.foreground,
                minimumSize: const Size(48, 44),
              ),
            ),
        ],
      ),
    );
  }
}

class HaccpTaskCard extends StatelessWidget {
  const HaccpTaskCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
    this.statusLabel,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final HaccpTone tone;
  final String? statusLabel;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    return DsCard(
      backgroundColor: HaccpPalette.surfaceWarm,
      borderColor: style.foreground.withValues(alpha: 0.18),
      borderRadius: AppRadius.md,
      padding: const EdgeInsets.all(AppSpacing.sm),
      intensity: NeumorphicIntensity.subtle,
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
            child: Icon(icon, color: style.foreground, size: 21),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: HaccpPalette.graphite,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: HaccpPalette.graphiteSoft,
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          if (trailing != null)
            trailing!
          else if (statusLabel != null)
            HaccpStatusBadge(label: statusLabel!, tone: tone, compact: true),
        ],
      ),
    );
  }
}

class HaccpMeasurementCard extends StatelessWidget {
  const HaccpMeasurementCard({
    required this.title,
    required this.primaryValue,
    required this.subtitle,
    required this.icon,
    required this.tone,
    this.onTap,
    this.actionIcon = Icons.add_circle_outline,
    super.key,
  });

  final String title;
  final String primaryValue;
  final String subtitle;
  final IconData icon;
  final HaccpTone tone;
  final VoidCallback? onTap;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    return DsCard(
      backgroundColor: HaccpPalette.surfaceWarm,
      borderColor: style.foreground.withValues(alpha: 0.18),
      borderRadius: AppRadius.md,
      padding: const EdgeInsets.all(AppSpacing.sm),
      intensity: NeumorphicIntensity.subtle,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: style.foreground, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: HaccpPalette.graphite,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: HaccpPalette.graphiteSoft,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                primaryValue,
                style: TextStyle(
                  color: style.foreground,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              if (onTap != null) Icon(actionIcon, color: style.foreground),
            ],
          ),
        ],
      ),
    );
  }
}

class HaccpMeasurementInput extends StatelessWidget {
  const HaccpMeasurementInput({
    required this.controller,
    required this.label,
    required this.suffix,
    this.autofocus = false,
    this.onChanged,
    this.validator,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: HaccpPalette.surface,
      ),
    );
  }
}

class HaccpNonConformityCard extends StatelessWidget {
  const HaccpNonConformityCard({
    required this.description,
    required this.sourceLabel,
    required this.statusLabel,
    required this.createdLabel,
    required this.tone,
    this.correctiveAction,
    this.expanded = false,
    this.onTap,
    this.actions,
    super.key,
  });

  final String description;
  final String sourceLabel;
  final String statusLabel;
  final String createdLabel;
  final HaccpTone tone;
  final String? correctiveAction;
  final bool expanded;
  final VoidCallback? onTap;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    return DsCard(
      backgroundColor: HaccpPalette.surface,
      borderColor: style.foreground.withValues(alpha: 0.25),
      borderRadius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      intensity: NeumorphicIntensity.subtle,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HaccpStatusBadge(label: statusLabel, tone: tone, compact: true),
              const SizedBox(width: AppSpacing.xs),
              HaccpStatusBadge(
                label: sourceLabel,
                tone: HaccpTone.neutral,
                compact: true,
              ),
              const Spacer(),
              Text(
                createdLabel,
                style: const TextStyle(
                  color: HaccpPalette.graphiteSoft,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: HaccpPalette.graphiteSoft,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            description,
            style: const TextStyle(
              color: HaccpPalette.graphite,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            correctiveAction == null || correctiveAction!.isEmpty
                ? 'Action corrective requise'
                : correctiveAction!,
            style: TextStyle(
              color: correctiveAction == null || correctiveAction!.isEmpty
                  ? AppColors.dangerAlt
                  : HaccpPalette.graphiteSoft,
              fontSize: 12,
              fontWeight: correctiveAction == null || correctiveAction!.isEmpty
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
          if (expanded && actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1, color: HaccpPalette.border),
            const SizedBox(height: AppSpacing.sm),
            HaccpActionBar(children: actions!),
          ],
        ],
      ),
    );
  }
}

class HaccpDeadlineCard extends StatelessWidget {
  const HaccpDeadlineCard({
    required this.title,
    required this.deadlineLabel,
    required this.subtitle,
    required this.tone,
    this.onTap,
    super.key,
  });

  final String title;
  final String deadlineLabel;
  final String subtitle;
  final HaccpTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HaccpTaskCard(
      title: title,
      subtitle: subtitle,
      icon: Icons.event_available_outlined,
      tone: tone,
      trailing: HaccpStatusBadge(label: deadlineLabel, tone: tone),
      onTap: onTap,
    );
  }
}

class HaccpActionBar extends StatelessWidget {
  const HaccpActionBar({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.xs),
                children[i],
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(child: children[i]),
            ],
          ],
        );
      },
    );
  }
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
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class HaccpSkeletonList extends StatelessWidget {
  const HaccpSkeletonList({this.itemCount = 4, super.key});

  final int itemCount;

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
      itemCount: itemCount,
    );
  }
}

class HaccpSkeleton extends StatelessWidget {
  const HaccpSkeleton({this.itemCount = 4, super.key});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return HaccpSkeletonList(itemCount: itemCount);
  }
}

/// Carte de progression d'une session : "6 / 9 contrôles terminés".
class HaccpProgressCard extends StatelessWidget {
  const HaccpProgressCard({
    required this.title,
    required this.statusLabel,
    required this.tone,
    required this.done,
    required this.total,
    this.chips = const [],
    super.key,
  });

  final String title;
  final String statusLabel;
  final HaccpTone tone;
  final int done;
  final int total;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final style = haccpToneStyle(tone);
    final value = total == 0 ? 1.0 : (done / total).clamp(0.0, 1.0);
    return DsCard(
      backgroundColor: HaccpPalette.surface,
      borderColor: HaccpPalette.border,
      borderRadius: AppRadius.lg,
      padding: const EdgeInsets.all(AppSpacing.md),
      intensity: NeumorphicIntensity.subtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: HaccpPalette.graphite,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              HaccpStatusBadge(label: statusLabel, tone: tone),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$done / $total',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: HaccpPalette.graphite,
                  ),
                ),
                const TextSpan(
                  text: '  contrôles terminés',
                  style: TextStyle(
                    fontSize: 13,
                    color: HaccpPalette.graphiteSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 10,
              color: style.foreground,
              backgroundColor: style.foreground.withValues(alpha: 0.14),
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: chips,
            ),
          ],
        ],
      ),
    );
  }
}

/// Petit libelle de groupe ("À FAIRE", "TERMINÉS") au-dessus d'une liste.
class HaccpGroupLabel extends StatelessWidget {
  const HaccpGroupLabel({
    required this.label,
    this.count,
    this.tone,
    super.key,
  });

  final String label;
  final int? count;
  final HaccpTone? tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == null
        ? HaccpPalette.graphiteSoft
        : haccpToneStyle(tone!).foreground;
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xs,
        bottom: AppSpacing.xs,
        left: 2,
      ),
      child: Text(
        count == null ? label : '$label ($count)',
        style: TextStyle(
          color: color,
          fontSize: 11,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Conteneur de page HACCP : fond gris chaud, contenu centre, largeur bornee.
class HaccpPageBody extends StatelessWidget {
  const HaccpPageBody({required this.child, this.maxWidth = 980, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: HaccpPalette.background,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// Squelette compact pour l'interieur d'une section (hors ListView).
class HaccpInlineSkeleton extends StatelessWidget {
  const HaccpInlineSkeleton({this.rows = 2, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          Container(
            height: 58,
            decoration: BoxDecoration(
              color: HaccpPalette.surfaceWarm,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: HaccpPalette.border),
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.adminSurfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 10,
                        width: double.infinity,
                        color: AppColors.adminSurfaceMuted,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 8,
                        width: 120,
                        color: AppColors.adminSurfaceMuted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Message d'erreur compact pour l'interieur d'une section.
class HaccpInlineError extends StatelessWidget {
  const HaccpInlineError({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return HaccpInfoBanner(
      icon: Icons.error_outline,
      title: 'Chargement impossible',
      message: message,
      tone: HaccpTone.danger,
    );
  }
}

/// Message d'etat vide compact pour l'interieur d'une section.
class HaccpInlineEmpty extends StatelessWidget {
  const HaccpInlineEmpty({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Text(
        message,
        style: const TextStyle(color: HaccpPalette.graphiteSoft, fontSize: 13),
      ),
    );
  }
}

import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:flutter/material.dart';

enum AppFeedbackKind {
  loading,
  success,
  error,
  empty,
  offline,
  forbidden,
  noResults,
}

class AppFeedback extends StatelessWidget {
  const AppFeedback({
    required this.kind,
    required this.title,
    this.message,
    this.onRetry,
    super.key,
  });

  final AppFeedbackKind kind;
  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final icon = switch (kind) {
      AppFeedbackKind.loading => Icons.hourglass_empty_outlined,
      AppFeedbackKind.success => Icons.check_circle_outline,
      AppFeedbackKind.error => Icons.error_outline,
      AppFeedbackKind.empty => Icons.inbox_outlined,
      AppFeedbackKind.offline => Icons.wifi_off_outlined,
      AppFeedbackKind.forbidden => Icons.lock_outline,
      AppFeedbackKind.noResults => Icons.search_off_outlined,
    };

    final color = switch (kind) {
      AppFeedbackKind.success => Theme.of(context).colorScheme.primary,
      AppFeedbackKind.error => Theme.of(context).colorScheme.error,
      AppFeedbackKind.offline => Theme.of(context).colorScheme.tertiary,
      AppFeedbackKind.forbidden => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.outline,
    };

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: DsCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind == AppFeedbackKind.loading)
                const SizedBox.square(
                  dimension: 44,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                Icon(icon, color: color, size: 44),
              const SizedBox(height: AppSpacing.sm),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reessayer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

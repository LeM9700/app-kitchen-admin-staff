import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_connection.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:flutter/material.dart';

class KitchenStatusHeader extends StatelessWidget {
  const KitchenStatusHeader({
    required this.totalWaiting,
    required this.totalPreparing,
    required this.totalNew,
    this.connection,
    super.key,
  });

  final int totalWaiting;
  final int totalPreparing;
  final int totalNew;
  final KitchenConnectionState? connection;

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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...counters,
                        if (connection != null)
                          _KitchenConnectionChip(connection: connection!),
                      ],
                    ),
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
                  if (connection != null) ...[
                    const SizedBox(width: 12),
                    _KitchenConnectionChip(connection: connection!),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _KitchenConnectionChip extends StatelessWidget {
  const _KitchenConnectionChip({required this.connection});

  final KitchenConnectionState connection;

  @override
  Widget build(BuildContext context) {
    final colors = _connectionColors(connection.status);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(colors.icon, size: 16, color: colors.foreground),
            const SizedBox(width: 6),
            Text(
              _connectionShortLabel(connection),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KitchenTypography.headerCounter(context).copyWith(
                color: colors.foreground,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

_ConnectionColors _connectionColors(KitchenConnectionStatus status) {
  return switch (status) {
    KitchenConnectionStatus.online => const _ConnectionColors(
        background: AppColors.successBg,
        border: AppColors.success,
        foreground: AppColors.textPrimary,
        icon: Icons.wifi_outlined,
      ),
    KitchenConnectionStatus.reconnecting => const _ConnectionColors(
        background: AppColors.warningSoftBg,
        border: AppColors.warning,
        foreground: AppColors.textPrimary,
        icon: Icons.sync_outlined,
      ),
    KitchenConnectionStatus.offline => const _ConnectionColors(
        background: AppColors.dangerBg,
        border: AppColors.danger,
        foreground: AppColors.dangerAlt,
        icon: Icons.wifi_off_outlined,
      ),
  };
}

String _connectionShortLabel(KitchenConnectionState connection) {
  final base = switch (connection.status) {
    KitchenConnectionStatus.online => 'ONLINE',
    KitchenConnectionStatus.reconnecting => 'RECONNEXION',
    KitchenConnectionStatus.offline => 'HORS CONNEXION',
  };
  if (connection.pendingActions <= 0) {
    return base;
  }
  return '$base ${connection.pendingActions}';
}

class _ConnectionColors {
  const _ConnectionColors({
    required this.background,
    required this.border,
    required this.foreground,
    required this.icon,
  });

  final Color background;
  final Color border;
  final Color foreground;
  final IconData icon;
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

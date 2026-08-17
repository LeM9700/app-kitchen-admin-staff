import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_connection.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:flutter/material.dart';

class KitchenOfflineBanner extends StatelessWidget {
  const KitchenOfflineBanner({
    required this.connection,
    super.key,
  });

  final KitchenConnectionState connection;

  @override
  Widget build(BuildContext context) {
    return switch (connection.status) {
      KitchenConnectionStatus.online => const SizedBox.shrink(),
      KitchenConnectionStatus.reconnecting => _KitchenConnectionBanner(
          icon: Icons.sync_outlined,
          label: _connectionLabel(connection),
          background: AppColors.warningSoftBg,
          foreground: AppColors.textPrimary,
          border: AppColors.warning,
        ),
      KitchenConnectionStatus.offline => _KitchenConnectionBanner(
          icon: Icons.wifi_off_outlined,
          label: _connectionLabel(connection),
          background: AppColors.dangerBg,
          foreground: AppColors.dangerAlt,
          border: AppColors.danger,
        ),
    };
  }
}

class _KitchenConnectionBanner extends StatelessWidget {
  const _KitchenConnectionBanner({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KitchenTypography.meta(context).copyWith(
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _connectionLabel(KitchenConnectionState connection) {
  final base = switch (connection.status) {
    KitchenConnectionStatus.online => 'ONLINE',
    KitchenConnectionStatus.reconnecting => 'RECONNEXION',
    KitchenConnectionStatus.offline => 'HORS CONNEXION',
  };

  final pending = connection.pendingActions;
  if (pending <= 0) {
    return base;
  }

  final suffix = pending == 1 ? 'ACTION EN ATTENTE' : 'ACTIONS EN ATTENTE';
  return '$base · $pending $suffix';
}

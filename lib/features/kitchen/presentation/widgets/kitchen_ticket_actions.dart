import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_hold_to_reopen_action.dart';
import 'package:flutter/material.dart';

class KitchenTicketActions extends StatelessWidget {
  const KitchenTicketActions({
    required this.ticket,
    required this.profile,
    required this.actionsState,
    this.onStart,
    this.onReady,
    this.onReopen,
    this.compact = false,
    super.key,
  });

  final KitchenTicketViewModel ticket;
  final KitchenScreenProfile profile;
  final KitchenActionsState actionsState;
  final VoidCallback? onStart;
  final VoidCallback? onReady;
  final VoidCallback? onReopen;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (ticket.state == KitchenTicketState.ready || ticket.stationReady) {
      final label =
          ticket.state == KitchenTicketState.ready ? '✓ PRÊTE' : '✓ POSTE PRÊT';

      if (_reopenGestureEnabled) {
        final key = kitchenReopenStationActionKey(ticket.order.id, profile);
        return KitchenHoldToReopenAction(
          label: label,
          busy: actionsState.isActionBusy(key),
          onHoldComplete: onReopen ?? () {},
          compact: compact,
        );
      }

      return _ActionStateLabel(label: label, compact: compact);
    }

    if (!_directActionsEnabled || ticket.isLocked) {
      return const SizedBox.shrink();
    }

    if (ticket.canStart) {
      final key = kitchenStartOrderActionKey(ticket.order.id);
      return _KitchenActionButton(
        label: 'COMMENCER',
        icon: Icons.play_arrow_rounded,
        busy: actionsState.isActionBusy(key),
        onPressed: onStart,
        compact: compact,
      );
    }

    if (ticket.canMarkReady) {
      final key = kitchenReadyStationActionKey(ticket.order.id, profile);
      return _KitchenActionButton(
        label: 'PRÊTE',
        icon: Icons.check_rounded,
        busy: actionsState.isActionBusy(key),
        onPressed: onReady,
        compact: compact,
      );
    }

    return const SizedBox.shrink();
  }

  bool get _directActionsEnabled {
    return profile.interactionMode == KitchenInteractionMode.touch;
  }

  bool get _reopenGestureEnabled {
    return _directActionsEnabled &&
        (profile.mode == KitchenScreenMode.kitchen ||
            profile.mode == KitchenScreenMode.counter);
  }
}

class _KitchenActionButton extends StatelessWidget {
  const _KitchenActionButton({
    required this.label,
    required this.icon,
    required this.busy,
    required this.onPressed,
    required this.compact,
  });

  final String label;
  final IconData icon;
  final bool busy;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = compact ? 48.0 : 54.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        compact ? 8 : 10,
        compact ? 12 : 16,
        compact ? 8 : 10,
      ),
      child: SizedBox(
        height: height,
        child: FilledButton.icon(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            minimumSize: Size.fromHeight(height),
            textStyle: KitchenTypography.meta(context).copyWith(
              fontSize: compact ? 12 : 14,
            ),
            disabledBackgroundColor:
                scheme.primaryContainer.withValues(alpha: 0.72),
            disabledForegroundColor: scheme.onPrimaryContainer,
          ),
          icon: busy
              ? SizedBox.square(
                  dimension: compact ? 17 : 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onPrimaryContainer,
                  ),
                )
              : Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}

class _ActionStateLabel extends StatelessWidget {
  const _ActionStateLabel({
    required this.label,
    required this.compact,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 16,
        compact ? 8 : 10,
        compact ? 12 : 16,
        compact ? 8 : 10,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.primary),
        ),
        child: SizedBox(
          height: compact ? 42 : 48,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KitchenTypography.meta(context).copyWith(
                color: scheme.onPrimaryContainer,
                fontSize: compact ? 12 : 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_status_ui.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ready_transition.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_actions.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_header.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_items.dart';
import 'package:flutter/material.dart';

class KitchenTicket extends StatelessWidget {
  const KitchenTicket({
    required this.ticket,
    required this.focused,
    this.profile = const KitchenScreenProfile(
      mode: KitchenScreenMode.kitchen,
      station: 'kitchen',
    ),
    this.actionsState = const KitchenActionsState(),
    this.onTap,
    this.onStart,
    this.onReady,
    this.compact = false,
    super.key,
  });

  final KitchenTicketViewModel ticket;
  final bool focused;
  final KitchenScreenProfile profile;
  final KitchenActionsState actionsState;
  final VoidCallback? onTap;
  final VoidCallback? onStart;
  final VoidCallback? onReady;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusUi = KitchenStatusUi.from(ticket.state);
    final borderColor = focused ? scheme.primary : scheme.outlineVariant;
    final borderWidth = focused ? 3.0 : 1.0;
    final surface = focused
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.08),
            scheme.surface,
          )
        : scheme.surface;

    return KitchenReadyTransition(
      active: ticket.state == KitchenTicketState.ready,
      child: Material(
        color: surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: BorderSide(color: borderColor, width: borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _KitchenTapRegion(
              onTap: onTap,
              child: KitchenTicketHeader(ticket: ticket, compact: compact),
            ),
            Expanded(
              child: _KitchenTapRegion(
                onTap: onTap,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: ticket.isLocked
                            ? statusUi.color
                            : Colors.transparent,
                        width: ticket.isLocked ? 4 : 0,
                      ),
                    ),
                  ),
                  child: KitchenTicketItems(
                    items: ticket.visibleItems,
                    compact: compact,
                  ),
                ),
              ),
            ),
            KitchenTicketActions(
              ticket: ticket,
              profile: profile,
              actionsState: actionsState,
              compact: compact,
              onStart: onStart,
              onReady: onReady,
            ),
            _KitchenTapRegion(
              onTap: onTap,
              child: _KitchenTicketMeta(ticket: ticket),
            ),
          ],
        ),
      ),
    );
  }
}

class _KitchenTapRegion extends StatelessWidget {
  const _KitchenTapRegion({
    required this.child,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return child;
    }

    return InkWell(
      onTap: onTap,
      child: child,
    );
  }
}

class _KitchenTicketMeta extends StatelessWidget {
  const _KitchenTicketMeta({required this.ticket});

  final KitchenTicketViewModel ticket;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tableNumber = ticket.order.tableNumber?.trim();
    final label = tableNumber != null && tableNumber.isNotEmpty
        ? 'TABLE $tableNumber'
        : humanOrderType(ticket.order.orderType).toUpperCase();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KitchenTypography.meta(context).copyWith(
              color: scheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
    );
  }
}

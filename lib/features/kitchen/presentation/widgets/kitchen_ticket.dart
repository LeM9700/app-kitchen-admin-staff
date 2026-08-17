import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_status_ui.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_header.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket_items.dart';
import 'package:flutter/material.dart';

class KitchenTicket extends StatelessWidget {
  const KitchenTicket({
    required this.ticket,
    required this.focused,
    this.onTap,
    this.compact = false,
    super.key,
  });

  final KitchenTicketViewModel ticket;
  final bool focused;
  final VoidCallback? onTap;
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

    return Material(
      color: surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitchenTicketHeader(ticket: ticket, compact: compact),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color:
                          ticket.isLocked ? statusUi.color : Colors.transparent,
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
            _KitchenTicketMeta(ticket: ticket),
          ],
        ),
      ),
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

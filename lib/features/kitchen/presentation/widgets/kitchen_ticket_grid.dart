import 'dart:math' as math;

import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_layout_policy.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_ticket.dart';
import 'package:flutter/material.dart';

class KitchenTicketGrid extends StatelessWidget {
  const KitchenTicketGrid({
    required this.tickets,
    required this.profile,
    required this.policy,
    required this.focusedOrderId,
    required this.actionsState,
    required this.prepTimeNormalMinutes,
    required this.onTicketTap,
    required this.onStart,
    required this.onReady,
    super.key,
  });

  final List<KitchenTicketViewModel> tickets;
  final KitchenScreenProfile profile;
  final KitchenLayoutPolicy policy;
  final int? focusedOrderId;
  final KitchenActionsState actionsState;
  final int prepTimeNormalMinutes;
  final ValueChanged<KitchenTicketViewModel> onTicketTap;
  final ValueChanged<KitchenTicketViewModel> onStart;
  final ValueChanged<KitchenTicketViewModel> onReady;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = math.min(
          policy.columns,
          math.max(1, tickets.length),
        );
        final rows = math.min(
          policy.rows,
          math.max(1, (tickets.length / columns).ceil()),
        );
        final availableWidth = constraints.maxWidth - policy.padding.horizontal;
        final availableHeight = constraints.maxHeight - policy.padding.vertical;
        final tileWidth =
            (availableWidth - (columns - 1) * policy.gap) / columns;
        final tileHeight = (availableHeight - (rows - 1) * policy.gap) / rows;
        final aspectRatio = tileHeight <= 0 ? 1.0 : tileWidth / tileHeight;

        return GridView.builder(
          key: const Key('kitchen-ticket-grid'),
          padding: policy.padding,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: policy.gap,
            mainAxisSpacing: policy.gap,
            childAspectRatio: aspectRatio.clamp(0.65, 2.2),
          ),
          itemCount: tickets.length,
          itemBuilder: (context, index) {
            final ticket = tickets[index];

            return KitchenTicket(
              key: ValueKey('kitchen-ticket-${ticket.order.id}'),
              ticket: ticket,
              focused: ticket.order.id == focusedOrderId,
              profile: profile,
              actionsState: actionsState,
              prepTimeNormalMinutes: prepTimeNormalMinutes,
              compact: policy.compact,
              onTap: () => onTicketTap(ticket),
              onStart: () => onStart(ticket),
              onReady: () => onReady(ticket),
            );
          },
        );
      },
    );
  }
}

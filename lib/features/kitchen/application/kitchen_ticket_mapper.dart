import 'package:app_admin_staff/features/kitchen/application/kitchen_time.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';

KitchenTicketViewModel mapOrderToKitchenTicket({
  required OrderDetail order,
  required KitchenScreenProfile profile,
}) {
  final visibleItems = _visibleItemsForProfile(order, profile);
  final state = _ticketStateForStatus(order.status);

  return KitchenTicketViewModel(
    order: order,
    state: state,
    visibleItems: visibleItems,
    confirmedAt: resolveConfirmedAt(order),
    isLocked: state == KitchenTicketState.awaitingConfirmation,
    canStart: state == KitchenTicketState.readyToStart,
    canMarkReady: state == KitchenTicketState.preparing,
    stationReady: _stationReady(
      order: order,
      profile: profile,
      visibleItems: visibleItems,
    ),
  );
}

List<OrderItem> _visibleItemsForProfile(
  OrderDetail order,
  KitchenScreenProfile profile,
) {
  if (profile.mode == KitchenScreenMode.service) {
    return order.items.toList();
  }

  return order.items
      .where((item) => item.preparationStation == profile.station)
      .toList();
}

KitchenTicketState _ticketStateForStatus(String status) {
  switch (status) {
    case 'pending':
    case 'queued':
      return KitchenTicketState.awaitingConfirmation;
    case 'confirmed':
      return KitchenTicketState.readyToStart;
    case 'preparing':
      return KitchenTicketState.preparing;
    case 'ready':
      return KitchenTicketState.ready;
    default:
      throw ArgumentError.value(
        status,
        'order.status',
        'Unsupported KDS order status',
      );
  }
}

bool _stationReady({
  required OrderDetail order,
  required KitchenScreenProfile profile,
  required List<OrderItem> visibleItems,
}) {
  if (profile.mode == KitchenScreenMode.service) {
    return order.items.isNotEmpty &&
        order.items.every((item) => item.preparationStatus == 'ready');
  }

  if (visibleItems.isEmpty) {
    return false;
  }

  final summary = _stationSummaryFor(order, profile.station);
  if (summary != null) {
    return summary.allReady;
  }

  return visibleItems.every((item) => item.preparationStatus == 'ready');
}

OrderStationSummary? _stationSummaryFor(OrderDetail order, String station) {
  for (final summary in order.stationSummary) {
    if (summary.station == station) {
      return summary;
    }
  }

  return null;
}

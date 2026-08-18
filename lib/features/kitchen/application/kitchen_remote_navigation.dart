import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';

class KitchenRemoteNavigationState {
  const KitchenRemoteNavigationState({
    required this.currentTicket,
    required this.currentQueueIndex,
    required this.canGoPrevious,
    required this.canGoNext,
  });

  final KitchenTicketViewModel? currentTicket;
  final int currentQueueIndex;
  final bool canGoPrevious;
  final bool canGoNext;
}

KitchenTicketViewModel? resolveRemoteCurrentTicket(
  KitchenQueueState state,
) {
  final focusedOrderId = state.focusedOrderId;
  if (focusedOrderId != null) {
    for (final ticket in state.currentPageTickets) {
      if (ticket.order.id == focusedOrderId) {
        return ticket;
      }
    }
  }

  if (state.currentPageTickets.isEmpty) {
    return null;
  }

  return state.currentPageTickets.first;
}

KitchenRemoteNavigationState resolveRemoteNavigationState(
  KitchenQueueState state,
) {
  final currentTicket = resolveRemoteCurrentTicket(state);
  final currentIndex = currentTicket == null
      ? -1
      : state.tickets.indexWhere(
          (ticket) => ticket.order.id == currentTicket.order.id,
        );

  return KitchenRemoteNavigationState(
    currentTicket: currentTicket,
    currentQueueIndex: currentIndex,
    canGoPrevious: currentIndex > 0,
    canGoNext: currentIndex >= 0 && currentIndex < state.tickets.length - 1,
  );
}

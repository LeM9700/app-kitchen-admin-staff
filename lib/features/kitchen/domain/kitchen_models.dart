import 'package:app_admin_staff/features/orders/data/orders_repository.dart';

enum KitchenTicketState {
  awaitingConfirmation,
  readyToStart,
  preparing,
  ready,
}

enum KitchenScreenMode {
  kitchen,
  counter,
  service,
}

enum KitchenInteractionMode {
  wall,
  touch,
  remote,
}

class KitchenScreenProfile {
  const KitchenScreenProfile({
    required this.mode,
    required this.station,
    this.ticketsPerPage = 4,
    this.interactionMode = KitchenInteractionMode.wall,
  });

  final KitchenScreenMode mode;
  final String station;
  final int ticketsPerPage;
  final KitchenInteractionMode interactionMode;
}

class KitchenTicketViewModel {
  const KitchenTicketViewModel({
    required this.order,
    required this.state,
    required this.visibleItems,
    required this.confirmedAt,
    required this.isLocked,
    required this.canStart,
    required this.canMarkReady,
    required this.stationReady,
  });

  final OrderDetail order;
  final KitchenTicketState state;
  final List<OrderItem> visibleItems;
  final DateTime? confirmedAt;

  final bool isLocked;
  final bool canStart;
  final bool canMarkReady;
  final bool stationReady;
}

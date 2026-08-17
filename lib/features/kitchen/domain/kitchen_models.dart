import 'package:app_admin_staff/features/orders/data/orders_repository.dart';

const _unset = Object();

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
  }) : assert(ticketsPerPage > 0);

  final KitchenScreenMode mode;
  final String station;
  final int ticketsPerPage;
  final KitchenInteractionMode interactionMode;

  KitchenScreenProfile copyWith({
    KitchenScreenMode? mode,
    String? station,
    int? ticketsPerPage,
    KitchenInteractionMode? interactionMode,
  }) {
    return KitchenScreenProfile(
      mode: mode ?? this.mode,
      station: station ?? this.station,
      ticketsPerPage: ticketsPerPage ?? this.ticketsPerPage,
      interactionMode: interactionMode ?? this.interactionMode,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is KitchenScreenProfile &&
            other.mode == mode &&
            other.station == station &&
            other.ticketsPerPage == ticketsPerPage &&
            other.interactionMode == interactionMode;
  }

  @override
  int get hashCode {
    return Object.hash(mode, station, ticketsPerPage, interactionMode);
  }
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

class KitchenQueueState {
  const KitchenQueueState({
    required this.profile,
    required this.tickets,
    required this.pages,
    required this.currentPage,
    required this.currentPageTickets,
    required this.focusedOrderId,
    required this.queueChangedWhileBrowsing,
    required this.totalWaiting,
    required this.totalPreparing,
    required this.totalNew,
  });

  final KitchenScreenProfile profile;

  /// Full FIFO queue after KDS mapping.
  final List<KitchenTicketViewModel> tickets;

  /// Live pagination built from [tickets].
  final List<List<KitchenTicketViewModel>> pages;

  final int currentPage;

  /// Tickets currently displayed.
  /// On secondary pages this can be a temporary snapshot.
  final List<KitchenTicketViewModel> currentPageTickets;

  final int? focusedOrderId;

  final bool queueChangedWhileBrowsing;

  final int totalWaiting;
  final int totalPreparing;
  final int totalNew;

  int get totalPages => pages.length;

  int get remainingItems {
    final consumedItems = (currentPage + 1) * profile.ticketsPerPage;
    if (consumedItems >= tickets.length) {
      return 0;
    }
    return tickets.length - consumedItems;
  }

  KitchenQueueState copyWith({
    KitchenScreenProfile? profile,
    List<KitchenTicketViewModel>? tickets,
    List<List<KitchenTicketViewModel>>? pages,
    int? currentPage,
    List<KitchenTicketViewModel>? currentPageTickets,
    Object? focusedOrderId = _unset,
    bool? queueChangedWhileBrowsing,
    int? totalWaiting,
    int? totalPreparing,
    int? totalNew,
  }) {
    return KitchenQueueState(
      profile: profile ?? this.profile,
      tickets: tickets ?? this.tickets,
      pages: pages ?? this.pages,
      currentPage: currentPage ?? this.currentPage,
      currentPageTickets: currentPageTickets ?? this.currentPageTickets,
      focusedOrderId: focusedOrderId == _unset
          ? this.focusedOrderId
          : focusedOrderId as int?,
      queueChangedWhileBrowsing:
          queueChangedWhileBrowsing ?? this.queueChangedWhileBrowsing,
      totalWaiting: totalWaiting ?? this.totalWaiting,
      totalPreparing: totalPreparing ?? this.totalPreparing,
      totalNew: totalNew ?? this.totalNew,
    );
  }
}

int countKitchenWaitingTickets(Iterable<KitchenTicketViewModel> tickets) {
  return tickets.where((ticket) {
    return ticket.state == KitchenTicketState.awaitingConfirmation ||
        ticket.state == KitchenTicketState.readyToStart;
  }).length;
}

int countKitchenPreparingTickets(Iterable<KitchenTicketViewModel> tickets) {
  return tickets.where((ticket) => ticket.order.status == 'preparing').length;
}

int countKitchenNewTickets(Iterable<KitchenTicketViewModel> tickets) {
  return tickets.where((ticket) {
    return ticket.order.status == 'pending' || ticket.order.status == 'queued';
  }).length;
}

import 'package:app_admin_staff/core/config/env.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_pagination.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_loader.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_remote_navigation.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_screen_presets.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final initialKitchenScreenProfile = kitchenScreenPresetFor(
  mode: KitchenScreenMode.kitchen,
  ticketsPerPage: 4,
  interactionMode: _initialKitchenInteractionMode(),
);

final kitchenScreenProfileProvider =
    NotifierProvider<KitchenScreenProfileController, KitchenScreenProfile>(
  KitchenScreenProfileController.new,
);

class KitchenScreenProfileController extends Notifier<KitchenScreenProfile> {
  @override
  KitchenScreenProfile build() {
    return initialKitchenScreenProfile;
  }

  void setProfile(KitchenScreenProfile profile) {
    state = profile;
  }
}

final kitchenQueueProvider =
    AsyncNotifierProvider<KitchenQueueController, KitchenQueueState>(
  KitchenQueueController.new,
);

class KitchenQueueController extends AsyncNotifier<KitchenQueueState> {
  int _currentPage = 0;
  int? _focusedOrderId;
  int? _snapshotPage;
  List<KitchenTicketViewModel>? _secondaryPageSnapshot;
  KitchenScreenProfile? _lastProfile;

  @override
  Future<KitchenQueueState> build() async {
    final profile = ref.watch(kitchenScreenProfileProvider);
    final repository = ref.watch(ordersRepositoryProvider);
    _resetForProfileChange(profile);

    final summaries = await ref.watch(activeOrdersProvider.future);
    final tickets = await loadKitchenTickets(
      summaries: summaries,
      loadDetail: repository.getOrder,
      profile: profile,
    );

    return _composeState(
      tickets: tickets,
      profile: profile,
    );
  }

  void nextPage() {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    goToPage(current.currentPage + 1);
  }

  void previousPage() {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    goToPage(current.currentPage - 1);
  }

  void goToPage(int page) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final targetPage = _boundedPage(page, current.pages.length);
    if (targetPage == current.currentPage) {
      return;
    }

    _currentPage = targetPage;
    if (targetPage == 0) {
      _clearSecondarySnapshot();
    } else {
      _snapshotPage = targetPage;
      _secondaryPageSnapshot = _ticketsForPage(
        current.pages,
        targetPage,
      );
    }

    state = AsyncValue.data(
      _composeState(
        tickets: current.tickets,
        profile: current.profile,
      ),
    );
  }

  void focusOrder(int orderId) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    final existsOnCurrentPage = current.currentPageTickets.any(
      (ticket) => ticket.order.id == orderId,
    );
    if (!existsOnCurrentPage) {
      return;
    }

    _focusedOrderId = orderId;
    state = AsyncValue.data(current.copyWith(focusedOrderId: orderId));
  }

  void clearFocus() {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }

    _focusedOrderId = null;
    state = AsyncValue.data(current.copyWith(focusedOrderId: null));
  }

  bool focusNextOrder() {
    return _focusAdjacentOrder(1);
  }

  bool focusPreviousOrder() {
    return _focusAdjacentOrder(-1);
  }

  bool _focusAdjacentOrder(int offset) {
    final current = state.valueOrNull;
    if (current == null) {
      return false;
    }

    final navigation = resolveRemoteNavigationState(current);
    final currentIndex = navigation.currentQueueIndex;
    if (currentIndex < 0) {
      return false;
    }

    final targetIndex = currentIndex + offset;
    if (targetIndex < 0 || targetIndex >= current.tickets.length) {
      return false;
    }

    final target = current.tickets[targetIndex];
    final targetPage = targetIndex ~/ current.profile.ticketsPerPage;
    _currentPage = targetPage;

    final targetVisibleInSnapshot = current.currentPage == targetPage &&
        current.currentPageTickets.any(
          (ticket) => ticket.order.id == target.order.id,
        );
    if (targetPage == 0) {
      _clearSecondarySnapshot();
    } else if (!targetVisibleInSnapshot) {
      _snapshotPage = targetPage;
      _secondaryPageSnapshot = _ticketsForPage(current.pages, targetPage);
    }

    _focusedOrderId = target.order.id;
    state = AsyncValue.data(
      _composeState(
        tickets: current.tickets,
        profile: current.profile,
      ),
    );
    return state.valueOrNull?.focusedOrderId == target.order.id;
  }

  Future<void> refresh({bool preserveCurrentOnError = false}) async {
    final previous = state.valueOrNull;
    ref.invalidate(activeOrdersProvider);
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      if (preserveCurrentOnError && previous != null) {
        state = AsyncValue.data(previous);
      }
      rethrow;
    }
  }

  void setProfile(KitchenScreenProfile profile) {
    _clearBrowsingState();
    ref.read(kitchenScreenProfileProvider.notifier).setProfile(profile);
  }

  void _resetForProfileChange(KitchenScreenProfile profile) {
    final previousProfile = _lastProfile;
    _lastProfile = profile;
    if (previousProfile == null || previousProfile == profile) {
      return;
    }

    _clearBrowsingState();
  }

  KitchenQueueState _composeState({
    required List<KitchenTicketViewModel> tickets,
    required KitchenScreenProfile profile,
  }) {
    final pages = paginateKitchenItems(
      tickets,
      perPage: profile.ticketsPerPage,
    );
    _currentPage = _boundedPage(_currentPage, pages.length);

    final livePageTickets = _ticketsForPage(pages, _currentPage);
    late final List<KitchenTicketViewModel> currentPageTickets;
    late final bool queueChangedWhileBrowsing;

    if (_currentPage == 0) {
      _clearSecondarySnapshot();
      currentPageTickets = livePageTickets;
      queueChangedWhileBrowsing = false;
    } else {
      if (_snapshotPage != _currentPage || _secondaryPageSnapshot == null) {
        _snapshotPage = _currentPage;
        _secondaryPageSnapshot = livePageTickets;
      }

      final snapshot = _secondaryPageSnapshot!;
      currentPageTickets = snapshot;
      queueChangedWhileBrowsing = !_hasSameOrderIds(
        snapshot,
        livePageTickets,
      );
    }

    _clearFocusIfMissingFrom(currentPageTickets);

    return KitchenQueueState(
      profile: profile,
      tickets: tickets,
      pages: pages,
      currentPage: _currentPage,
      currentPageTickets: currentPageTickets,
      focusedOrderId: _focusedOrderId,
      queueChangedWhileBrowsing: queueChangedWhileBrowsing,
      totalWaiting: countKitchenWaitingTickets(tickets),
      totalPreparing: countKitchenPreparingTickets(tickets),
      totalNew: countKitchenNewTickets(tickets),
    );
  }

  void _clearBrowsingState() {
    _currentPage = 0;
    _focusedOrderId = null;
    _clearSecondarySnapshot();
  }

  void _clearSecondarySnapshot() {
    _snapshotPage = null;
    _secondaryPageSnapshot = null;
  }

  void _clearFocusIfMissingFrom(List<KitchenTicketViewModel> tickets) {
    final focusedOrderId = _focusedOrderId;
    if (focusedOrderId == null) {
      return;
    }

    final stillVisible = tickets.any(
      (ticket) => ticket.order.id == focusedOrderId,
    );
    if (!stillVisible) {
      _focusedOrderId = null;
    }
  }
}

int _boundedPage(int page, int totalPages) {
  if (totalPages <= 0 || page < 0) {
    return 0;
  }

  final lastPage = totalPages - 1;
  if (page > lastPage) {
    return lastPage;
  }

  return page;
}

List<KitchenTicketViewModel> _ticketsForPage(
  List<List<KitchenTicketViewModel>> pages,
  int page,
) {
  if (page < 0 || page >= pages.length) {
    return const [];
  }

  return List<KitchenTicketViewModel>.of(
    pages[page],
    growable: false,
  );
}

bool _hasSameOrderIds(
  List<KitchenTicketViewModel> left,
  List<KitchenTicketViewModel> right,
) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    if (left[index].order.id != right[index].order.id) {
      return false;
    }
  }

  return true;
}

KitchenInteractionMode _initialKitchenInteractionMode() {
  switch (Env.kdsInteractionMode.trim().toLowerCase()) {
    case 'touch':
      return KitchenInteractionMode.touch;
    case 'remote':
      return KitchenInteractionMode.remote;
    default:
      return KitchenInteractionMode.wall;
  }
}

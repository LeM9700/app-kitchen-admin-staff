import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_remote_navigation.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  test('navigation remote traverse la FIFO sans boucler', () async {
    final repository = TestKitchenRepository()..setOrders(kitchenIds(101, 106));
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenQueueProvider.notifier);

    var state = _currentState(container);
    var navigation = resolveRemoteNavigationState(state);
    expect(navigation.currentTicket!.order.id, 101);
    expect(navigation.canGoPrevious, isFalse);
    expect(navigation.canGoNext, isTrue);

    expect(controller.focusNextOrder(), isTrue);
    expect(_remoteOrderId(container), 102);
    expect(_currentState(container).currentPage, 0);

    expect(controller.focusNextOrder(), isTrue);
    expect(_remoteOrderId(container), 103);

    expect(controller.focusNextOrder(), isTrue);
    expect(_remoteOrderId(container), 104);

    expect(controller.focusNextOrder(), isTrue);
    state = _currentState(container);
    expect(_remoteOrderId(container), 105);
    expect(state.currentPage, 1);
    expect(_visibleOrderIds(state), [105, 106]);

    expect(controller.focusPreviousOrder(), isTrue);
    state = _currentState(container);
    expect(_remoteOrderId(container), 104);
    expect(state.currentPage, 0);

    expect(controller.focusNextOrder(), isTrue);
    expect(controller.focusNextOrder(), isTrue);
    state = _currentState(container);
    navigation = resolveRemoteNavigationState(state);
    expect(navigation.currentTicket!.order.id, 106);
    expect(navigation.canGoNext, isFalse);
    expect(controller.focusNextOrder(), isFalse);
    expect(_remoteOrderId(container), 106);
  });
}

KitchenQueueState _currentState(ProviderContainer container) {
  return container.read(kitchenQueueProvider).valueOrNull!;
}

int _remoteOrderId(ProviderContainer container) {
  return resolveRemoteCurrentTicket(_currentState(container))!.order.id;
}

List<int> _visibleOrderIds(KitchenQueueState state) {
  return state.currentPageTickets.map((ticket) => ticket.order.id).toList();
}

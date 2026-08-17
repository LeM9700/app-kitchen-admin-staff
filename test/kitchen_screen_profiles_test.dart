import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_screen_presets.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  test('demo presets define kitchen, counter, and service stations', () {
    expect(kitchenWallPreset.mode, KitchenScreenMode.kitchen);
    expect(kitchenWallPreset.station, 'kitchen');
    expect(kitchenWallPreset.interactionMode, KitchenInteractionMode.wall);

    expect(kitchenTouchPreset.mode, KitchenScreenMode.kitchen);
    expect(kitchenTouchPreset.station, 'kitchen');
    expect(kitchenTouchPreset.interactionMode, KitchenInteractionMode.touch);

    expect(counterWallPreset.mode, KitchenScreenMode.counter);
    expect(counterWallPreset.station, 'counter');
    expect(counterTouchPreset.mode, KitchenScreenMode.counter);
    expect(counterTouchPreset.station, 'counter');

    expect(serviceWallPreset.mode, KitchenScreenMode.service);
    expect(serviceWallPreset.station, 'service');
    expect(serviceTouchPreset.mode, KitchenScreenMode.service);
    expect(serviceTouchPreset.station, 'service');
  });

  test('profile change remaps tickets and resets browsing state', () async {
    final repository = TestKitchenRepository()..setOrders(kitchenIds(101, 105));
    repository.details = {
      for (final id in kitchenIds(101, 105)) id: _mixedStationOrder(id),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenQueueProvider.notifier);
    controller.goToPage(1);
    controller.focusOrder(105);

    controller.setProfile(counterWallPreset);
    final counterState = await container.read(kitchenQueueProvider.future);

    expect(counterState.profile.mode, KitchenScreenMode.counter);
    expect(counterState.profile.station, 'counter');
    expect(counterState.currentPage, 0);
    expect(counterState.focusedOrderId, isNull);
    expect(counterState.queueChangedWhileBrowsing, isFalse);
    expect(
      counterState.currentPageTickets.first.visibleItems.map(
        (item) => item.productName,
      ),
      ['Coca'],
    );

    controller.setProfile(serviceWallPreset);
    final serviceState = await container.read(kitchenQueueProvider.future);

    expect(serviceState.profile.mode, KitchenScreenMode.service);
    expect(serviceState.currentPage, 0);
    expect(serviceState.focusedOrderId, isNull);
    expect(
      serviceState.currentPageTickets.first.visibleItems.map(
        (item) => item.productName,
      ),
      ['Burger', 'Coca'],
    );
  });

  testWidgets('selector switches counter then service profile', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'pending'});
    repository.details = {101: _mixedStationOrder(101, status: 'pending')};
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    expect(find.text('CUISINE'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsOneWidget);
    expect(find.textContaining('COCA'), findsNothing);

    await tester.tap(find.byKey(const Key('kitchen-screen-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kitchen-profile-mode-counter')));
    await tester.pumpAndSettle();

    expect(find.text('COMPTOIR'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsNothing);
    expect(find.textContaining('COCA'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kitchen-screen-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('kitchen-profile-mode-service')));
    await tester.pumpAndSettle();

    expect(find.text('SERVICE'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsOneWidget);
    expect(find.textContaining('COCA'), findsOneWidget);
  });
}

OrderDetail _mixedStationOrder(int id, {String status = 'preparing'}) {
  return testKitchenOrder(
    id: id,
    status: status,
    orderType: 'pickup',
    tableNumber: null,
    confirmedAt: status == 'pending' || status == 'queued'
        ? null
        : DateTime.utc(2026, 8, 17, 10, id - 100),
    items: [
      testKitchenItem(
        id: id * 10,
        productName: 'Burger',
        preparationStatus: status == 'ready' ? 'ready' : 'preparing',
        preparationStation: 'kitchen',
      ),
      testKitchenItem(
        id: id * 10 + 1,
        productName: 'Coca',
        preparationStatus: status == 'ready' ? 'ready' : 'preparing',
        preparationStation: 'counter',
      ),
    ],
  );
}

import 'package:app_admin_staff/features/kitchen/application/kitchen_ticket_mapper.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_screen_presets.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_station_status.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  final confirmedAt = DateTime.now().subtract(const Duration(minutes: 6));

  test('counter profile shows only counter station items', () {
    final ticket = mapOrderToKitchenTicket(
      order: _serviceOrder(status: 'preparing'),
      profile: counterWallPreset,
    );

    expect(ticket.visibleItems.map((item) => item.productName), ['Coca']);
    expect(ticket.canStart, isFalse);
    expect(ticket.canMarkReady, isTrue);
  });

  testWidgets('service profile shows every item without preparation actions', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final ticket = testKitchenTicket(
      status: 'preparing',
      confirmedAt: confirmedAt,
      items: _serviceItems(),
      profile: serviceTouchPreset,
    );

    await pumpKitchenTicket(
      tester,
      ticket,
      profile: serviceTouchPreset,
      size: const Size(760, 640),
    );

    expect(find.textContaining('BURGER'), findsOneWidget);
    expect(find.text('DOUBLE'), findsOneWidget);
    expect(find.text('+ Cheddar'), findsOneWidget);
    expect(find.textContaining('FRITES'), findsOneWidget);
    expect(find.textContaining('COCA'), findsOneWidget);
    expect(find.text('COMMENCER'), findsNothing);
    expect(find.text('PRÊTE'), findsNothing);
  });

  testWidgets('service displays station summary states compactly', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final partialTicket = testKitchenTicket(
      status: 'preparing',
      confirmedAt: confirmedAt,
      items: _serviceItems(),
      stationSummary: const [
        OrderStationSummary(
          station: 'kitchen',
          totalItems: 2,
          readyItems: 2,
          allReady: true,
        ),
        OrderStationSummary(
          station: 'counter',
          totalItems: 1,
          readyItems: 0,
          allReady: false,
        ),
      ],
      profile: serviceWallPreset,
    );

    await pumpKitchenTicket(
      tester,
      partialTicket,
      profile: serviceWallPreset,
      size: const Size(760, 640),
    );

    expect(find.text('CUISINE ✓ PRÊT'), findsOneWidget);
    expect(find.text('COMPTOIR EN COURS'), findsOneWidget);

    final readyTicket = testKitchenTicket(
      status: 'preparing',
      confirmedAt: confirmedAt,
      items: _serviceItems(),
      stationSummary: const [
        OrderStationSummary(
          station: 'kitchen',
          totalItems: 2,
          readyItems: 2,
          allReady: true,
        ),
        OrderStationSummary(
          station: 'counter',
          totalItems: 1,
          readyItems: 1,
          allReady: true,
        ),
      ],
      profile: serviceWallPreset,
    );

    await pumpKitchenTicket(
      tester,
      readyTicket,
      profile: serviceWallPreset,
      size: const Size(760, 640),
    );

    expect(find.text('CUISINE ✓ PRÊT'), findsOneWidget);
    expect(find.text('COMPTOIR ✓ PRÊT'), findsOneWidget);
  });

  testWidgets('pending service order stays visible and locked', (tester) async {
    addTearDown(tester.view.reset);
    final ticket = testKitchenTicket(
      status: 'pending',
      confirmedAt: null,
      items: _serviceItems(),
      profile: serviceTouchPreset,
    );

    await pumpKitchenTicket(
      tester,
      ticket,
      profile: serviceTouchPreset,
      size: const Size(760, 640),
    );

    expect(find.text('EN ATTENTE DE CONFIRMATION'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsOneWidget);
    expect(find.textContaining('COCA'), findsOneWidget);
    expect(find.text('COMMENCER'), findsNothing);
    expect(find.text('PRÊTE'), findsNothing);
  });

  test('fallback counts lines not quantities — all ready', () {
    final order = testKitchenOrder(
      status: 'preparing',
      orderType: 'dine_in',
      confirmedAt: DateTime.utc(2026, 8, 17, 10),
      items: [
        testKitchenItem(
          id: 10,
          quantity: 2,
          productName: 'Burger',
          preparationStatus: 'ready',
          preparationStation: 'kitchen',
        ),
        testKitchenItem(
          id: 11,
          productName: 'Frites',
          preparationStatus: 'ready',
          preparationStation: 'kitchen',
        ),
      ],
    );
    final statuses = kitchenStationStatusesForOrder(order);
    expect(statuses.length, 1);
    expect(statuses.first.station, 'kitchen');
    expect(statuses.first.totalItems, 2);
    expect(statuses.first.readyItems, 2);
    expect(statuses.first.allReady, isTrue);
  });

  test('fallback counts lines not quantities — partial ready', () {
    final order = testKitchenOrder(
      status: 'preparing',
      orderType: 'dine_in',
      confirmedAt: DateTime.utc(2026, 8, 17, 10),
      items: [
        testKitchenItem(
          id: 12,
          quantity: 2,
          productName: 'Burger',
          preparationStatus: 'ready',
          preparationStation: 'kitchen',
        ),
        testKitchenItem(
          id: 13,
          productName: 'Frites',
          preparationStatus: 'preparing',
          preparationStation: 'kitchen',
        ),
      ],
    );
    final statuses = kitchenStationStatusesForOrder(order);
    expect(statuses.length, 1);
    expect(statuses.first.station, 'kitchen');
    expect(statuses.first.totalItems, 2);
    expect(statuses.first.readyItems, 1);
    expect(statuses.first.allReady, isFalse);
  });

  test('station status falls back to order items when summary is absent', () {
    final order = _serviceOrder(status: 'preparing');
    final ticket = mapOrderToKitchenTicket(
      order: order,
      profile: serviceWallPreset,
    );
    final statuses = kitchenStationStatusesForOrder(order);

    expect(ticket.visibleItems.map((item) => item.productName), [
      'Burger',
      'Frites',
      'Coca',
    ]);
    expect(ticket.canStart, isFalse);
    expect(ticket.canMarkReady, isFalse);
    expect(statuses.map((status) => status.station), ['kitchen', 'counter']);
    expect(statuses.map((status) => status.totalItems), [2, 1]);
    expect(statuses.map((status) => status.allReady), [true, false]);
  });
}

OrderDetail _serviceOrder({required String status}) {
  return testKitchenOrder(
    status: status,
    orderType: 'dine_in',
    tableNumber: '08',
    confirmedAt: status == 'pending' || status == 'queued'
        ? null
        : DateTime.utc(2026, 8, 17, 10),
    items: _serviceItems(),
  );
}

List<OrderItem> _serviceItems() {
  return [
    testKitchenItem(
      id: 1,
      quantity: 2,
      productName: 'Burger',
      variantName: 'Double',
      extras: [testKitchenExtra(name: 'Cheddar')],
      preparationStatus: 'ready',
      preparationStation: 'kitchen',
    ),
    testKitchenItem(
      id: 2,
      productName: 'Frites',
      preparationStatus: 'ready',
      preparationStation: 'kitchen',
    ),
    testKitchenItem(
      id: 3,
      quantity: 2,
      productName: 'Coca',
      preparationStatus: 'preparing',
      preparationStation: 'counter',
    ),
  ];
}

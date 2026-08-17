import 'package:app_admin_staff/features/kitchen/application/kitchen_ticket_mapper.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const kitchenProfile = KitchenScreenProfile(
    mode: KitchenScreenMode.kitchen,
    station: 'kitchen',
  );

  test('maps pending orders as locked awaiting confirmation tickets', () {
    final ticket = mapOrderToKitchenTicket(
      order: _order(status: 'pending'),
      profile: kitchenProfile,
    );

    expect(ticket.state, KitchenTicketState.awaitingConfirmation);
    expect(ticket.isLocked, isTrue);
    expect(ticket.canStart, isFalse);
    expect(ticket.canMarkReady, isFalse);
  });

  test('maps queued orders as awaiting confirmation tickets', () {
    final ticket = mapOrderToKitchenTicket(
      order: _order(status: 'queued'),
      profile: kitchenProfile,
    );

    expect(ticket.state, KitchenTicketState.awaitingConfirmation);
  });

  test('maps confirmed orders as startable tickets', () {
    final ticket = mapOrderToKitchenTicket(
      order: _order(
        status: 'confirmed',
        items: [
          _item(id: 1, station: 'kitchen'),
        ],
      ),
      profile: kitchenProfile,
    );

    expect(ticket.state, KitchenTicketState.readyToStart);
    expect(ticket.isLocked, isFalse);
    expect(ticket.canStart, isTrue);
    expect(ticket.canMarkReady, isFalse);
  });

  test('maps preparing orders as ready-action tickets', () {
    final ticket = mapOrderToKitchenTicket(
      order: _order(
        status: 'preparing',
        items: [
          _item(id: 1, station: 'kitchen', preparationStatus: 'preparing'),
        ],
      ),
      profile: kitchenProfile,
    );

    expect(ticket.state, KitchenTicketState.preparing);
    expect(ticket.isLocked, isFalse);
    expect(ticket.canStart, isFalse);
    expect(ticket.canMarkReady, isTrue);
  });

  test('maps ready orders with no actions', () {
    final ticket = mapOrderToKitchenTicket(
      order: _order(status: 'ready'),
      profile: kitchenProfile,
    );

    expect(ticket.state, KitchenTicketState.ready);
    expect(ticket.isLocked, isFalse);
    expect(ticket.canStart, isFalse);
    expect(ticket.canMarkReady, isFalse);
  });

  test('filters visible items by screen profile station', () {
    final order = _order(
      items: [
        _item(id: 1, productName: 'Burger', station: 'kitchen'),
        _item(id: 2, productName: 'Coca', station: 'counter'),
      ],
    );

    final kitchenTicket = mapOrderToKitchenTicket(
      order: order,
      profile: kitchenProfile,
    );
    final counterTicket = mapOrderToKitchenTicket(
      order: order,
      profile: const KitchenScreenProfile(
        mode: KitchenScreenMode.counter,
        station: 'counter',
      ),
    );
    final serviceTicket = mapOrderToKitchenTicket(
      order: order,
      profile: const KitchenScreenProfile(
        mode: KitchenScreenMode.service,
        station: 'service',
      ),
    );

    expect(
      kitchenTicket.visibleItems.map((item) => item.productName),
      ['Burger'],
    );
    expect(counterTicket.visibleItems.map((item) => item.productName), [
      'Coca',
    ]);
    expect(serviceTicket.visibleItems.map((item) => item.productName), [
      'Burger',
      'Coca',
    ]);
  });

  test('resolves stationReady from station summary when present', () {
    final ticket = mapOrderToKitchenTicket(
      order: _order(
        items: [
          _item(id: 1, station: 'kitchen', preparationStatus: 'preparing'),
        ],
        stationSummary: const [
          OrderStationSummary(
            station: 'kitchen',
            totalItems: 1,
            readyItems: 1,
            allReady: true,
          ),
        ],
      ),
      profile: kitchenProfile,
    );

    expect(ticket.stationReady, isTrue);
  });

  test('falls back to visible items for stationReady without station summary',
      () {
    final ticket = mapOrderToKitchenTicket(
      order: _order(
        items: [
          _item(id: 1, station: 'kitchen', preparationStatus: 'ready'),
          _item(id: 2, station: 'counter', preparationStatus: 'preparing'),
        ],
      ),
      profile: kitchenProfile,
    );

    expect(ticket.stationReady, isTrue);
  });

  test('service stationReady represents the full order readiness', () {
    final ticket = mapOrderToKitchenTicket(
      order: _order(
        items: [
          _item(id: 1, station: 'kitchen', preparationStatus: 'ready'),
          _item(id: 2, station: 'counter', preparationStatus: 'ready'),
        ],
      ),
      profile: const KitchenScreenProfile(
        mode: KitchenScreenMode.service,
        station: 'service',
      ),
    );

    expect(ticket.stationReady, isTrue);
  });

  test('does not allow ready action when current station is already ready', () {
    final ticket = mapOrderToKitchenTicket(
      order: _order(
        status: 'preparing',
        items: [
          _item(
            id: 1,
            productName: 'Burger',
            station: 'kitchen',
            preparationStatus: 'ready',
          ),
          _item(
            id: 2,
            productName: 'Coca',
            station: 'counter',
            preparationStatus: 'preparing',
          ),
        ],
        stationSummary: const [
          OrderStationSummary(
            station: 'kitchen',
            totalItems: 1,
            readyItems: 1,
            allReady: true,
          ),
          OrderStationSummary(
            station: 'counter',
            totalItems: 1,
            readyItems: 0,
            allReady: false,
          ),
        ],
      ),
      profile: kitchenProfile,
    );

    expect(ticket.stationReady, isTrue);
    expect(ticket.canMarkReady, isFalse);
  });

  test('does not expose preparation actions when profile has no station items',
      () {
    final confirmedTicket = mapOrderToKitchenTicket(
      order: _order(
        status: 'confirmed',
        items: [
          _item(id: 1, productName: 'Coca', station: 'counter'),
        ],
      ),
      profile: kitchenProfile,
    );
    final preparingTicket = mapOrderToKitchenTicket(
      order: _order(
        status: 'preparing',
        items: [
          _item(
            id: 1,
            productName: 'Coca',
            station: 'counter',
            preparationStatus: 'preparing',
          ),
        ],
      ),
      profile: kitchenProfile,
    );

    expect(confirmedTicket.visibleItems, isEmpty);
    expect(confirmedTicket.canStart, isFalse);
    expect(confirmedTicket.canMarkReady, isFalse);
    expect(preparingTicket.visibleItems, isEmpty);
    expect(preparingTicket.canStart, isFalse);
    expect(preparingTicket.canMarkReady, isFalse);
  });

  test('service mode never exposes kitchen preparation actions', () {
    const serviceProfile = KitchenScreenProfile(
      mode: KitchenScreenMode.service,
      station: 'service',
    );
    final confirmedTicket = mapOrderToKitchenTicket(
      order: _order(
        status: 'confirmed',
        items: [
          _item(id: 1, station: 'kitchen'),
          _item(id: 2, station: 'counter'),
        ],
      ),
      profile: serviceProfile,
    );
    final preparingTicket = mapOrderToKitchenTicket(
      order: _order(
        status: 'preparing',
        items: [
          _item(id: 1, station: 'kitchen', preparationStatus: 'preparing'),
          _item(id: 2, station: 'counter', preparationStatus: 'preparing'),
        ],
      ),
      profile: serviceProfile,
    );

    expect(confirmedTicket.visibleItems.length, 2);
    expect(confirmedTicket.canStart, isFalse);
    expect(confirmedTicket.canMarkReady, isFalse);
    expect(preparingTicket.visibleItems.length, 2);
    expect(preparingTicket.canStart, isFalse);
    expect(preparingTicket.canMarkReady, isFalse);
  });

  test('uses confirmedAt resolved from status history', () {
    final confirmedAt = DateTime.utc(2026, 8, 17, 10, 5);
    final ticket = mapOrderToKitchenTicket(
      order: _order(
        statusHistory: [
          OrderStatusHistory(
            status: 'confirmed',
            authority: 'staff',
            createdAt: confirmedAt,
          ),
        ],
      ),
      profile: kitchenProfile,
    );

    expect(ticket.confirmedAt, confirmedAt);
  });

  test('throws for non-KDS statuses instead of guessing behavior', () {
    expect(
      () => mapOrderToKitchenTicket(
        order: _order(status: 'cancelled'),
        profile: kitchenProfile,
      ),
      throwsArgumentError,
    );
  });
}

OrderDetail _order({
  String status = 'preparing',
  List<OrderItem> items = const [],
  List<OrderStationSummary> stationSummary = const [],
  List<OrderStatusHistory> statusHistory = const [],
}) {
  return OrderDetail(
    id: 101,
    orderType: 'pickup',
    status: status,
    paymentStatus: 'paid',
    source: 'customer',
    total: 18,
    deliveryFee: 0,
    items: items,
    stationSummary: stationSummary,
    statusHistory: statusHistory,
  );
}

OrderItem _item({
  required int id,
  required String station,
  String preparationStatus = 'pending',
  String? productName,
}) {
  return OrderItem(
    id: id,
    productId: id,
    quantity: 1,
    unitPrice: 1,
    total: 1,
    extras: const [],
    preparationStatus: preparationStatus,
    preparationStation: station,
    productName: productName,
  );
}

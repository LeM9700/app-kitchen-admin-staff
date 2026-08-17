import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_loader.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = KitchenScreenProfile(
    mode: KitchenScreenMode.kitchen,
    station: 'kitchen',
  );

  test('keeps FIFO order when detail loads complete out of order', () async {
    final tickets = await loadKitchenTickets(
      summaries: [
        _summary(
          id: 103,
          createdAt: DateTime.utc(2026, 8, 17, 10, 3),
        ),
        _summary(
          id: 101,
          createdAt: DateTime.utc(2026, 8, 17, 10, 1),
        ),
        _summary(
          id: 102,
          createdAt: DateTime.utc(2026, 8, 17, 10, 2),
        ),
      ],
      loadDetail: (orderId) async {
        final delay = switch (orderId) {
          101 => 30,
          102 => 10,
          _ => 1,
        };
        await Future<void>.delayed(Duration(milliseconds: delay));
        return _detail(id: orderId);
      },
      profile: profile,
    );

    expect(tickets.map((ticket) => ticket.order.id), [101, 102, 103]);
  });

  test('excludes a detail that became cancelled between list and detail',
      () async {
    final tickets = await loadKitchenTickets(
      summaries: [
        _summary(id: 101, status: 'pending'),
        _summary(id: 102, status: 'pending'),
      ],
      loadDetail: (orderId) async {
        if (orderId == 101) {
          return _detail(id: orderId, status: 'cancelled');
        }
        return _detail(id: orderId);
      },
      profile: profile,
    );

    expect(tickets.map((ticket) => ticket.order.id), [102]);
  });

  test('propagates a real loadDetail exception', () async {
    expect(
      loadKitchenTickets(
        summaries: [
          _summary(id: 101),
        ],
        loadDetail: (_) => throw StateError('network down'),
        profile: profile,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('maps details with the provided kitchen profile', () async {
    final tickets = await loadKitchenTickets(
      summaries: [
        _summary(id: 101, status: 'confirmed'),
      ],
      loadDetail: (orderId) async {
        return _detail(
          id: orderId,
          status: 'confirmed',
          items: [
            _item(id: 1, station: 'kitchen', productName: 'Pizza'),
            _item(id: 2, station: 'counter', productName: 'Soda'),
          ],
        );
      },
      profile: profile,
    );

    final ticket = tickets.single;
    expect(ticket.state, KitchenTicketState.readyToStart);
    expect(ticket.visibleItems.map((item) => item.productName), ['Pizza']);
    expect(ticket.canStart, isTrue);
  });
}

OrderSummary _summary({
  required int id,
  String status = 'preparing',
  DateTime? createdAt,
}) {
  return OrderSummary(
    id: id,
    orderType: 'pickup',
    status: status,
    paymentStatus: 'paid',
    source: 'customer',
    total: 18,
    deliveryFee: 0,
    createdAt: createdAt,
  );
}

OrderDetail _detail({
  required int id,
  String status = 'preparing',
  List<OrderItem> items = const [],
}) {
  return OrderDetail(
    id: id,
    orderType: 'pickup',
    status: status,
    paymentStatus: 'paid',
    source: 'customer',
    total: 18,
    deliveryFee: 0,
    items: items,
    stationSummary: const [],
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

import 'package:app_admin_staff/features/kitchen/application/kitchen_queue.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a strict FIFO queue regardless of KDS status', () {
    final queue = buildKitchenQueue([
      _summary(
        id: 104,
        status: 'ready',
        createdAt: DateTime.utc(2026, 8, 17, 10, 4),
      ),
      _summary(
        id: 101,
        status: 'preparing',
        createdAt: DateTime.utc(2026, 8, 17, 10, 1),
      ),
      _summary(
        id: 103,
        status: 'pending',
        createdAt: DateTime.utc(2026, 8, 17, 10, 3),
      ),
      _summary(
        id: 102,
        status: 'confirmed',
        createdAt: DateTime.utc(2026, 8, 17, 10, 2),
      ),
    ]);

    expect(queue.map((order) => order.id), [101, 102, 103, 104]);
  });

  test('excludes statuses outside the KDS lifecycle', () {
    final filtered = filterOrdersForKds([
      _summary(id: 1, status: 'pending'),
      _summary(id: 2, status: 'cancelled'),
      _summary(id: 3, status: 'delivered'),
      _summary(id: 4, status: 'out_for_delivery'),
      _summary(id: 5, status: 'refunded'),
      _summary(id: 6, status: 'ready'),
    ]);

    expect(filtered.map((order) => order.id), [1, 6]);
  });

  test('places orders without createdAt after dated orders', () {
    final sorted = sortKitchenOrdersFifo([
      _summary(id: 3),
      _summary(id: 2, createdAt: DateTime.utc(2026, 8, 17, 10, 2)),
      _summary(id: 1, createdAt: DateTime.utc(2026, 8, 17, 10, 1)),
    ]);

    expect(sorted.map((order) => order.id), [1, 2, 3]);
  });

  test('sorts equal createdAt values by id ascending', () {
    final createdAt = DateTime.utc(2026, 8, 17, 10, 1);
    final sorted = sortKitchenOrdersFifo([
      _summary(id: 12, createdAt: createdAt),
      _summary(id: 10, createdAt: createdAt),
      _summary(id: 11, createdAt: createdAt),
    ]);

    expect(sorted.map((order) => order.id), [10, 11, 12]);
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

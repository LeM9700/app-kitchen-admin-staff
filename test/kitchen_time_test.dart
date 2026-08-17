import 'package:app_admin_staff/features/kitchen/application/kitchen_time.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves confirmedAt from unordered status history', () {
    final confirmedAt = DateTime.utc(2026, 8, 17, 10, 5);
    final order = _order(
      statusHistory: [
        OrderStatusHistory(
          status: 'preparing',
          authority: 'staff',
          createdAt: DateTime.utc(2026, 8, 17, 10, 8),
        ),
        OrderStatusHistory(
          status: 'confirmed',
          authority: 'staff',
          createdAt: confirmedAt,
        ),
        OrderStatusHistory(
          status: 'pending',
          authority: 'system',
          createdAt: DateTime.utc(2026, 8, 17, 10),
        ),
      ],
    );

    expect(resolveConfirmedAt(order), confirmedAt);
  });

  test('uses first chronological confirmation when several exist', () {
    final firstConfirmedAt = DateTime.utc(2026, 8, 17, 10, 5);
    final order = _order(
      statusHistory: [
        OrderStatusHistory(
          status: 'confirmed',
          authority: 'staff',
          createdAt: DateTime.utc(2026, 8, 17, 10, 6),
        ),
        OrderStatusHistory(
          status: 'confirmed',
          authority: 'staff',
          createdAt: firstConfirmedAt,
        ),
      ],
    );

    expect(resolveConfirmedAt(order), firstConfirmedAt);
  });

  test('returns null when no confirmation exists', () {
    final order = _order(
      statusHistory: [
        OrderStatusHistory(
          status: 'pending',
          authority: 'system',
          createdAt: DateTime.utc(2026, 8, 17, 10),
        ),
      ],
    );

    expect(resolveConfirmedAt(order), isNull);
  });

  test('elapsed starts from confirmation timestamp', () {
    final order = _order(
      statusHistory: [
        OrderStatusHistory(
          status: 'confirmed',
          authority: 'staff',
          createdAt: DateTime.utc(2026, 8, 17, 10, 5),
        ),
      ],
    );

    expect(
      preparationElapsed(
        order: order,
        now: DateTime.utc(2026, 8, 17, 10, 7, 30),
      ),
      const Duration(minutes: 2, seconds: 30),
    );
  });

  test('elapsed is zero when now is before confirmation', () {
    final order = _order(
      statusHistory: [
        OrderStatusHistory(
          status: 'confirmed',
          authority: 'staff',
          createdAt: DateTime.utc(2026, 8, 17, 10, 5),
        ),
      ],
    );

    expect(
      preparationElapsed(
        order: order,
        now: DateTime.utc(2026, 8, 17, 10, 4, 59),
      ),
      Duration.zero,
    );
  });
}

OrderDetail _order({
  List<OrderStatusHistory> statusHistory = const [],
}) {
  return OrderDetail(
    id: 101,
    orderType: 'pickup',
    status: 'preparing',
    paymentStatus: 'paid',
    source: 'customer',
    total: 18,
    deliveryFee: 0,
    items: const [],
    stationSummary: const [],
    statusHistory: statusHistory,
  );
}

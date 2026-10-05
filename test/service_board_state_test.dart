import 'package:app_admin_staff/features/orders/application/service_board_state.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves service transitions from order type and status', () {
    expect(
      resolveServiceNextStatus(_summary(orderType: 'dine_in')),
      serviceDeliveredStatus,
    );
    expect(
      resolveServiceNextStatus(_summary(orderType: 'pickup')),
      serviceDeliveredStatus,
    );
    expect(
      resolveServiceNextStatus(_summary(orderType: 'delivery')),
      serviceDeliveryStatus,
    );
    expect(
      resolveServiceNextStatus(
        _summary(orderType: 'delivery', status: serviceDeliveryStatus),
      ),
      serviceDeliveredStatus,
    );
  });

  test('service board excludes KDS statuses', () {
    final state = ServiceBoardState.build(
      orders: [
        _summary(id: 1, status: 'pending'),
        _summary(id: 2, status: 'queued'),
        _summary(id: 3, status: 'confirmed'),
        _summary(id: 4, status: 'preparing'),
        _summary(id: 5, status: 'ready'),
        _summary(id: 6, status: 'out_for_delivery'),
      ],
      now: DateTime(2026, 9, 23, 12),
    );

    expect(state.all.map((order) => order.order.id), [5, 6]);
  });

  test('filters by order type, late state, search query, and establishment',
      () {
    final now = DateTime(2026, 9, 23, 12);
    final state = ServiceBoardState.build(
      orders: [
        _summary(
          id: 10,
          orderType: 'dine_in',
          tableNumber: '12',
          createdAt: now.subtract(const Duration(minutes: 35)),
          establishmentId: 1,
        ),
        _summary(
          id: 11,
          orderType: 'pickup',
          customerName: 'Malik B.',
          establishmentId: 1,
        ),
        _summary(
          id: 12,
          orderType: 'delivery',
          customerName: 'Nora',
          establishmentId: 2,
        ),
      ],
      filter: ServiceFilter.late,
      query: 'table 12',
      establishmentId: 1,
      now: now,
    );

    expect(state.total, 2);
    expect(state.lateCount, 1);
    expect(state.ready.single.order.id, 10);
    expect(state.counts[ServiceFilter.dineIn], 1);
    expect(state.counts[ServiceFilter.pickup], 1);
    expect(state.counts[ServiceFilter.delivery], 0);
  });

  group('estimated delivery time', () {
    final now = DateTime(2026, 10, 3, 19, 30);

    test('a delivery is late only once its estimate has passed', () {
      final created = now.subtract(const Duration(minutes: 50));
      // 50 min after creation would be late with the fixed threshold, but the
      // estimate (recomputed at departure) says 10 more minutes.
      final onTime = _summary(
        orderType: 'delivery',
        createdAt: created,
        estimatedDeliveryAt: now.add(const Duration(minutes: 10)),
      );
      final overdue = _summary(
        orderType: 'delivery',
        createdAt: created,
        estimatedDeliveryAt: now.subtract(const Duration(minutes: 1)),
      );

      expect(isLateForService(onTime, now: now), isFalse);
      expect(isLateForService(overdue, now: now), isTrue);
    });

    test('falls back to the 30 minute threshold without estimate', () {
      final created = now.subtract(const Duration(minutes: 31));

      expect(
        isLateForService(
          _summary(orderType: 'delivery', createdAt: created),
          now: now,
        ),
        isTrue,
      );
      // The estimate does not apply to counter or table orders.
      expect(
        isLateForService(
          _summary(
            createdAt: created,
            estimatedDeliveryAt: now.add(const Duration(hours: 1)),
          ),
          now: now,
        ),
        isTrue,
      );
    });

    test('readable label before and after the estimate', () {
      OrderSummary at(int minutes) => _summary(
            orderType: 'delivery',
            estimatedDeliveryAt: now.add(Duration(minutes: minutes)),
          );

      expect(deliveryEstimateLabel(at(12), now: now),
          'Prevue 19:42 (dans 12 min)',);
      expect(deliveryEstimateLabel(at(95), now: now),
          'Prevue 21:05 (dans 1 h 35)',);
      expect(deliveryEstimateLabel(at(-8), now: now),
          'En retard de 8 min (prevue 19:22)',);
      expect(
          deliveryEstimateLabel(at(0), now: now), 'Prevue 19:30 (imminente)',);
      expect(
        deliveryEstimateLabel(_summary(orderType: 'delivery'), now: now),
        isNull,
      );
      expect(
        deliveryEstimateLabel(
          _summary(estimatedDeliveryAt: now.add(const Duration(minutes: 5))),
          now: now,
        ),
        isNull,
      );
    });
  });
}

OrderSummary _summary({
  int id = 1,
  String orderType = 'dine_in',
  String status = serviceReadyStatus,
  String paymentStatus = 'paid',
  String source = 'customer',
  double total = 12,
  double deliveryFee = 0,
  String? tableNumber,
  String? customerName,
  int? establishmentId,
  DateTime? createdAt,
  DateTime? estimatedDeliveryAt,
}) {
  return OrderSummary(
    id: id,
    orderType: orderType,
    status: status,
    paymentStatus: paymentStatus,
    source: source,
    total: total,
    deliveryFee: deliveryFee,
    tableNumber: tableNumber,
    customerName: customerName,
    establishmentId: establishmentId,
    createdAt: createdAt,
    estimatedDeliveryAt: estimatedDeliveryAt,
  );
}

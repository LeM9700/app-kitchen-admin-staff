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
  );
}

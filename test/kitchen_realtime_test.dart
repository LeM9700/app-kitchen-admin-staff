import 'package:app_admin_staff/core/realtime/notification_bus.dart';
import 'package:app_admin_staff/core/realtime/realtime_connector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('notification exposes order_id from realtime data', () {
    final notification = RealtimeNotification.fromJson(
      const {
        'type': 'notification',
        'event': 'order.ready',
        'data': {'order_id': '42'},
      },
    );

    expect(notification.orderId, 42);
  });

  test('order notification targets active orders and the concerned detail', () {
    final invalidation = resolveOrderRealtimeInvalidation(
      const RealtimeNotification(
        type: 'notification',
        event: 'order.ready',
        data: {'order_id': 42},
      ),
    );

    expect(invalidation.invalidateActiveOrders, isTrue);
    expect(invalidation.orderId, 42);
  });

  test('order notification without order_id keeps active orders fallback', () {
    final invalidation = resolveOrderRealtimeInvalidation(
      const RealtimeNotification(
        type: 'notification',
        event: 'order.ready',
      ),
    );

    expect(invalidation.invalidateActiveOrders, isTrue);
    expect(invalidation.orderId, isNull);
  });

  test('non order notification does not invalidate order providers', () {
    final invalidation = resolveOrderRealtimeInvalidation(
      const RealtimeNotification(
        type: 'notification',
        event: 'stock.low_alert',
      ),
    );

    expect(invalidation.invalidateActiveOrders, isFalse);
    expect(invalidation.orderId, isNull);
  });
}

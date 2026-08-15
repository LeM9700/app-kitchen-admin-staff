import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('queued action round trip keeps endpoint and payload', () {
    final action = QueuedAction(
      id: '1',
      feature: 'orders',
      label: 'Commande #1',
      endpoint: '/orders/1/status',
      method: 'PATCH',
      payload: const {'status': 'ready'},
      createdAt: DateTime.parse('2026-07-21T10:00:00Z'),
      idempotencyKey: 'same-key',
    );

    final restored = QueuedAction.fromJson(action.toJson());

    expect(restored.endpoint, '/orders/1/status');
    expect(restored.payload['status'], 'ready');
    expect(restored.idempotencyKey, 'same-key');
  });

  test('queued action keeps same idempotency key across retries', () {
    final action = QueuedAction(
      id: '1',
      feature: 'orders',
      label: 'Commande #1',
      endpoint: '/orders/manual',
      method: 'POST',
      payload: const {'items': []},
      createdAt: DateTime.parse('2026-07-21T10:00:00Z'),
      idempotencyKey: 'manual-fixed',
    );

    final retried = action.copyWith(retryCount: 1, lastError: 'timeout');

    expect(retried.idempotencyKey, action.idempotencyKey);
    expect(retried.retryCount, 1);
  });
}

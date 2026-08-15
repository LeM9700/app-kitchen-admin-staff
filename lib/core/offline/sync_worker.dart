import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  return SyncWorker(
    ref.watch(apiClientProvider),
    ref.read(syncQueueProvider.notifier),
  );
});

class SyncWorker {
  const SyncWorker(this._apiClient, this._queue);

  final ApiClient _apiClient;
  final SyncQueue _queue;

  Future<void> flush(List<QueuedAction> actions) async {
    for (final action in actions.reversed) {
      try {
        final method = action.method.toUpperCase();
        if (method == 'POST') {
          await _apiClient.post(
            action.endpoint,
            data: action.payload,
            idempotencyKey: action.idempotencyKey,
          );
        } else if (method == 'PUT') {
          await _apiClient.put(
            action.endpoint,
            data: action.payload,
            idempotencyKey: action.idempotencyKey,
          );
        } else if (method == 'DELETE') {
          await _apiClient.delete(
            action.endpoint,
            data: action.payload,
            idempotencyKey: action.idempotencyKey,
          );
        } else {
          await _apiClient.patch(
            action.endpoint,
            data: action.payload,
            idempotencyKey: action.idempotencyKey,
          );
        }
        _queue.remove(action.id);
      } catch (error) {
        _queue.markFailed(action.id, error.toString());
      }
    }
  }
}

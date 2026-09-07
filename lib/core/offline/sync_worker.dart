import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final syncWorkerProvider = Provider<SyncWorker>((ref) {
  return SyncWorker(
    ref.watch(apiClientProvider),
    ref.read(syncQueueProvider.notifier),
    ref,
  );
});

class SyncWorker {
  const SyncWorker(this._apiClient, this._queue, this._ref);

  final ApiClient _apiClient;
  final SyncQueue _queue;
  final Ref _ref;

  /// Replays [actions] against the API.
  ///
  /// [🔒 SÉCURITÉ] Before sending anything, each action's tenant/user is
  /// compared against whoever is signed in *right now* — read fresh on
  /// every call, never cached — so an action queued under tenant A can
  /// never be replayed under a tenant B (or a different user) session.
  /// Mismatched actions are marked [QueuedAction.blockReason] and are never
  /// sent to the API.
  Future<void> flush(List<QueuedAction> actions) async {
    final session = _ref.read(sessionControllerProvider).valueOrNull;
    final currentTenantSlug = session?.tenantSlug;
    final currentUserId = session?.user?.id;
    if (currentTenantSlug == null || currentUserId == null) {
      // No authenticated session: nothing can be safely replayed.
      return;
    }

    for (final action in actions.reversed) {
      if (!action.matchesIdentity(
        tenantSlug: currentTenantSlug,
        userId: currentUserId,
      )) {
        _queue.markBlocked(
          action.id,
          action.hasKnownIdentity
              ? 'tenant_or_user_mismatch'
              : 'unknown_origin',
        );
        continue;
      }

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

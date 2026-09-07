import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final syncWorkerProvider = Provider<SyncWorker>((ref) => SyncWorker(ref));

class SyncWorker {
  const SyncWorker(this._ref);

  final Ref _ref;

  /// Replays [actions] against the API.
  ///
  /// [🔒 SÉCURITÉ] The API client, the queue notifier and the signed-in
  /// identity are all re-read fresh from [_ref] on every call — never
  /// captured once and cached — because [SyncQueue] rebuilds (a brand new
  /// notifier instance, bound to the new identity's own storage partition)
  /// whenever the signed-in tenant/user changes. Holding on to a stale
  /// queue instance across a tenant switch would let this worker write to
  /// state nobody is looking at, or worse, to the wrong partition.
  ///
  /// Each action's tenant/user is also compared against whoever is signed
  /// in *right now* before anything is sent: with [SyncQueue] partitioned
  /// per identity this should never actually mismatch, but the check is
  /// cheap defense-in-depth against races (e.g. [actions] was snapshotted
  /// just before a tenant switch). A mismatched action is simply skipped —
  /// never sent, never touched — since it cannot belong to the identity
  /// this worker is currently allowed to act on.
  Future<void> flush(List<QueuedAction> actions) async {
    final session = _ref.read(sessionControllerProvider).valueOrNull;
    final currentTenantSlug = session?.tenantSlug;
    final currentUserId = session?.user?.id;
    if (currentTenantSlug == null || currentUserId == null) {
      // No authenticated session: nothing can be safely replayed.
      return;
    }

    final apiClient = _ref.read(apiClientProvider);
    final queue = _ref.read(syncQueueProvider.notifier);

    for (final action in actions.reversed) {
      if (!action.matchesIdentity(
        tenantSlug: currentTenantSlug,
        userId: currentUserId,
      )) {
        continue;
      }

      try {
        final method = action.method.toUpperCase();
        if (method == 'POST') {
          await apiClient.post(
            action.endpoint,
            data: action.payload,
            idempotencyKey: action.idempotencyKey,
          );
        } else if (method == 'PUT') {
          await apiClient.put(
            action.endpoint,
            data: action.payload,
            idempotencyKey: action.idempotencyKey,
          );
        } else if (method == 'DELETE') {
          await apiClient.delete(
            action.endpoint,
            data: action.payload,
            idempotencyKey: action.idempotencyKey,
          );
        } else {
          await apiClient.patch(
            action.endpoint,
            data: action.payload,
            idempotencyKey: action.idempotencyKey,
          );
        }
        queue.remove(action.id);
      } catch (error) {
        queue.markFailed(action.id, error.toString());
      }
    }
  }
}

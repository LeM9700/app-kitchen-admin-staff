import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/realtime/websocket_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum KitchenConnectionStatus {
  online,
  reconnecting,
  offline,
}

class KitchenConnectionState {
  const KitchenConnectionState({
    required this.status,
    required this.pendingActions,
  });

  final KitchenConnectionStatus status;
  final int pendingActions;
}

final kitchenPendingActionsProvider = Provider<int>((ref) {
  return pendingSyncCountForFeature(ref.watch(syncQueueProvider), 'kitchen');
});

final kitchenConnectionStateProvider = Provider<KitchenConnectionState>((ref) {
  final online = ref.watch(onlineStatusProvider).valueOrNull ?? true;
  final realtimeStatus =
      ref.watch(realtimeConnectionStatusProvider).valueOrNull;
  final pendingActions = ref.watch(kitchenPendingActionsProvider);

  final status = _kitchenConnectionStatus(
    online: online,
    realtimeStatus: realtimeStatus,
  );

  return KitchenConnectionState(
    status: status,
    pendingActions: pendingActions,
  );
});

KitchenConnectionStatus resolveKitchenConnectionStatus({
  required bool online,
  required RealtimeConnectionStatus? realtimeStatus,
}) {
  return _kitchenConnectionStatus(
    online: online,
    realtimeStatus: realtimeStatus,
  );
}

KitchenConnectionStatus _kitchenConnectionStatus({
  required bool online,
  required RealtimeConnectionStatus? realtimeStatus,
}) {
  if (!online) {
    return KitchenConnectionStatus.offline;
  }

  if (realtimeStatus == null ||
      realtimeStatus == RealtimeConnectionStatus.connected) {
    return KitchenConnectionStatus.online;
  }

  return KitchenConnectionStatus.reconnecting;
}

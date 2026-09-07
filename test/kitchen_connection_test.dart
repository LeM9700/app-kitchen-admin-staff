import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/realtime/websocket_client.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_connection.dart';
import 'package:app_admin_staff/features/kitchen/presentation/widgets/kitchen_offline_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  test('resolves online, reconnecting, and offline states', () {
    expect(
      resolveKitchenConnectionStatus(
        online: true,
        realtimeStatus: RealtimeConnectionStatus.connected,
      ),
      KitchenConnectionStatus.online,
    );
    expect(
      resolveKitchenConnectionStatus(
        online: true,
        realtimeStatus: RealtimeConnectionStatus.reconnecting,
      ),
      KitchenConnectionStatus.reconnecting,
    );
    expect(
      resolveKitchenConnectionStatus(
        online: false,
        realtimeStatus: RealtimeConnectionStatus.connected,
      ),
      KitchenConnectionStatus.offline,
    );
  });

  test('pendingActions counts only kitchen sync actions', () {
    final container = ProviderContainer(
      overrides: [
        syncQueueProvider.overrideWith(
          () => _SeededSyncQueue([
            _queuedAction(id: '1', feature: 'kitchen'),
            _queuedAction(id: '2', feature: 'orders'),
            _queuedAction(id: '3', feature: 'kitchen'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(kitchenPendingActionsProvider), 2);
  });

  test('provider combines connectivity, realtime, and pending actions',
      () async {
    final container = ProviderContainer(
      overrides: [
        onlineStatusProvider.overrideWith((ref) => Stream.value(false)),
        realtimeConnectionStatusProvider.overrideWith(
          (ref) => Stream.value(RealtimeConnectionStatus.connected),
        ),
        syncQueueProvider.overrideWith(
          () => _SeededSyncQueue([
            _queuedAction(id: '1', feature: 'kitchen'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(onlineStatusProvider.future);
    await container.read(realtimeConnectionStatusProvider.future);

    final state = container.read(kitchenConnectionStateProvider);
    expect(state.status, KitchenConnectionStatus.offline);
    expect(state.pendingActions, 1);
  });

  testWidgets('online hides banner and offline shows pending actions',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KitchenOfflineBanner(
          connection: KitchenConnectionState(
            status: KitchenConnectionStatus.online,
            pendingActions: 0,
          ),
        ),
      ),
    );
    expect(find.textContaining('HORS CONNEXION'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(
        home: KitchenOfflineBanner(
          connection: KitchenConnectionState(
            status: KitchenConnectionStatus.offline,
            pendingActions: 2,
          ),
        ),
      ),
    );
    expect(find.text('HORS CONNEXION · 2 ACTIONS EN ATTENTE'), findsOneWidget);
  });

  testWidgets('tickets remain visible when the KDS is offline', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final container = createKitchenContainer(
      repository,
      overrides: [
        onlineStatusProvider.overrideWith((ref) => Stream.value(false)),
        realtimeConnectionStatusProvider.overrideWith(
          (ref) => Stream.value(RealtimeConnectionStatus.connected),
        ),
        syncQueueProvider.overrideWith(
          () => _SeededSyncQueue([
            _queuedAction(id: '1', feature: 'kitchen'),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    expect(find.text('#101'), findsOneWidget);
    expect(find.text('HORS CONNEXION · 1 ACTION EN ATTENTE'), findsOneWidget);
  });
}

class _SeededSyncQueue extends SyncQueue {
  _SeededSyncQueue(this.actions);

  final List<QueuedAction> actions;

  @override
  List<QueuedAction> build() => actions;
}

QueuedAction _queuedAction({
  required String id,
  required String feature,
}) {
  return QueuedAction(
    id: id,
    feature: feature,
    label: 'Action $id',
    endpoint: '/test/$id',
    method: 'PATCH',
    payload: const {},
    createdAt: DateTime.utc(2026, 8, 17, 10),
  );
}

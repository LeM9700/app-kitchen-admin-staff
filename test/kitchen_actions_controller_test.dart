import 'dart:async';

import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_actions_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_ticket_mapper.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  const kitchenProfile = KitchenScreenProfile(
    mode: KitchenScreenMode.kitchen,
    station: 'kitchen',
    interactionMode: KitchenInteractionMode.touch,
  );

  test('startOrder appelle updateStatus preparing', () async {
    final repository = TestKitchenRepository()
      ..setOrders(
        [101],
        statuses: {101: 'confirmed'},
      );
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container
        .read(kitchenActionsProvider.notifier)
        .startOrder(orderId: 101);

    expect(repository.statusUpdates.length, 1);
    expect(repository.statusUpdates.single.orderId, 101);
    expect(repository.statusUpdates.single.status, 'preparing');
  });

  test('busy est true pendant action puis nettoye', () async {
    final repository = TestKitchenRepository()
      ..setOrders(
        [101],
        statuses: {101: 'confirmed'},
      )
      ..updateStatusGate = Completer<void>();
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final future = container
        .read(kitchenActionsProvider.notifier)
        .startOrder(orderId: 101);
    await Future<void>.delayed(Duration.zero);

    final key = kitchenStartOrderActionKey(101);
    expect(container.read(kitchenActionsProvider).isActionBusy(key), isTrue);
    expect(container.read(kitchenActionsProvider).isOrderBusy(101), isTrue);

    repository.updateStatusGate!.complete();
    await future;

    expect(container.read(kitchenActionsProvider).isActionBusy(key), isFalse);
    expect(container.read(kitchenActionsProvider).isOrderBusy(101), isFalse);
  });

  test('double start simultane n envoie qu un appel', () async {
    final repository = TestKitchenRepository()
      ..setOrders(
        [101],
        statuses: {101: 'confirmed'},
      )
      ..updateStatusGate = Completer<void>();
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenActionsProvider.notifier);
    final first = controller.startOrder(orderId: 101);
    await Future<void>.delayed(Duration.zero);
    final second = controller.startOrder(orderId: 101);
    await Future<void>.delayed(Duration.zero);

    expect(repository.statusUpdates.length, 1);

    repository.updateStatusGate!.complete();
    await Future.wait([first, second]);
  });

  test('erreur start conserve la queue courante', () async {
    final repository = TestKitchenRepository()
      ..setOrders(
        [101],
        statuses: {101: 'confirmed'},
      )
      ..updateStatusError = StateError('boom');
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    final initial = await container.read(kitchenQueueProvider.future);
    expect(initial.currentPageTickets.map((ticket) => ticket.order.id), [101]);

    await container
        .read(kitchenActionsProvider.notifier)
        .startOrder(orderId: 101);

    final queue = container.read(kitchenQueueProvider).valueOrNull!;
    expect(queue.currentPageTickets.map((ticket) => ticket.order.id), [101]);
    expect(
      container.read(kitchenActionsProvider).lastError,
      'Impossible de mettre a jour la commande.',
    );
  });

  test('startOrder met en file kitchen uniquement sur erreur reseau', () async {
    final repository = TestKitchenRepository()
      ..setOrders(
        [101],
        statuses: {101: 'confirmed'},
      )
      ..updateStatusError = const NetworkException(message: 'offline');
    final container = createKitchenContainer(
      repository,
      overrides: [syncQueueProvider.overrideWith(_TestSyncQueue.new)],
    );
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container
        .read(kitchenActionsProvider.notifier)
        .startOrder(orderId: 101);

    final queued = container.read(syncQueueProvider);
    expect(queued, hasLength(1));
    expect(queued.single.feature, 'kitchen');
    expect(queued.single.endpoint, '/orders/101/status');
    expect(queued.single.payload, {'status': 'preparing'});
    expect(
      container.read(kitchenActionsProvider).lastError,
      'Action mise en file offline.',
    );
  });

  test('startOrder ne met pas en file une erreur metier', () async {
    final repository = TestKitchenRepository()
      ..setOrders(
        [101],
        statuses: {101: 'confirmed'},
      )
      ..updateStatusError = const ForbiddenException(message: 'Forbidden');
    final container = createKitchenContainer(
      repository,
      overrides: [syncQueueProvider.overrideWith(_TestSyncQueue.new)],
    );
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container
        .read(kitchenActionsProvider.notifier)
        .startOrder(orderId: 101);

    expect(container.read(syncQueueProvider), isEmpty);
    expect(container.read(kitchenActionsProvider).lastError, 'Forbidden');
  });

  test('markStationReady ne touche que visibleItems non ready', () async {
    final repository = TestKitchenRepository()..setOrders([101]);
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'preparing',
        items: [
          testKitchenItem(id: 1, preparationStatus: 'ready'),
          testKitchenItem(id: 2, preparationStatus: 'preparing'),
          testKitchenItem(
            id: 3,
            productName: 'Coca',
            preparationStatus: 'preparing',
            preparationStation: 'counter',
          ),
        ],
      ),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).markStationReady(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    expect(
      repository.preparationUpdates.map((update) => update.itemId),
      [2],
    );
    expect(repository.statusUpdates, isEmpty);
  });

  test('station kitchen prete mais counter non prete garde preparing',
      () async {
    final repository = TestKitchenRepository()..setOrders([101]);
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'preparing',
        items: [
          testKitchenItem(id: 1, preparationStatus: 'preparing'),
          testKitchenItem(
            id: 2,
            productName: 'Coca',
            preparationStatus: 'preparing',
            preparationStation: 'counter',
          ),
        ],
      ),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).markStationReady(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    expect(repository.preparationUpdates.length, 1);
    expect(repository.statusUpdates, isEmpty);
    expect(repository.details[101]!.status, 'preparing');
  });

  test('toutes stations ready met la commande globale ready', () async {
    final repository = TestKitchenRepository()..setOrders([101]);
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'preparing',
        items: [
          testKitchenItem(id: 1, preparationStatus: 'preparing'),
          testKitchenItem(
            id: 2,
            productName: 'Coca',
            preparationStatus: 'ready',
            preparationStation: 'counter',
          ),
        ],
      ),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).markStationReady(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    expect(repository.preparationUpdates.length, 1);
    expect(repository.statusUpdates.map((update) => update.status), ['ready']);
    expect(repository.details[101]!.status, 'ready');
  });

  test('service mode refuse markStationReady proprement', () async {
    const serviceProfile = KitchenScreenProfile(
      mode: KitchenScreenMode.service,
      station: 'service',
      interactionMode: KitchenInteractionMode.touch,
    );
    final repository = TestKitchenRepository()..setOrders([101]);
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).markStationReady(
          ticket: _ticket(repository, serviceProfile),
          profile: serviceProfile,
        );

    expect(repository.preparationUpdates, isEmpty);
    expect(repository.statusUpdates, isEmpty);
    expect(
      container.read(kitchenActionsProvider).lastError,
      'Action indisponible sur cet ecran.',
    );
  });

  test('busy est nettoye apres erreur ready', () async {
    final repository = TestKitchenRepository()
      ..setOrders([101])
      ..updateItemPreparationError = StateError('boom');
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).markStationReady(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    final key = kitchenReadyStationActionKey(101, kitchenProfile);
    expect(container.read(kitchenActionsProvider).isActionBusy(key), isFalse);
    expect(
      container.read(kitchenActionsProvider).lastError,
      'Impossible de mettre a jour la commande.',
    );
  });

  test('markStationReady met les PATCH restants en file si le reseau tombe',
      () async {
    final repository = TestKitchenRepository()..setOrders([101]);
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'preparing',
        items: [
          testKitchenItem(id: 1, preparationStatus: 'preparing'),
          testKitchenItem(id: 2, preparationStatus: 'preparing'),
        ],
      ),
    };
    repository.updateItemPreparationError =
        const NetworkException(message: 'offline');
    final container = createKitchenContainer(
      repository,
      overrides: [syncQueueProvider.overrideWith(_TestSyncQueue.new)],
    );
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).markStationReady(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    final queued = container.read(syncQueueProvider);
    expect(queued.map((action) => action.feature), ['kitchen', 'kitchen']);
    expect(
      queued.map((action) => action.endpoint).toSet(),
      {
        '/orders/101/items/1/preparation',
        '/orders/101/items/2/preparation',
      },
    );
    expect(
      repository.details[101]!.items.map((item) => item.preparationStatus),
      ['preparing', 'preparing'],
    );
  });

  test('conflit 409 affiche un message court et rafraichit sans error board',
      () async {
    final repository = TestKitchenRepository()
      ..setOrders(
        [101],
        statuses: {101: 'confirmed'},
      )
      ..updateStatusError = const ConflictException(
        message: 'state changed',
        statusCode: 409,
      );
    final container = createKitchenContainer(
      repository,
      overrides: [syncQueueProvider.overrideWith(_TestSyncQueue.new)],
    );
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container
        .read(kitchenActionsProvider.notifier)
        .startOrder(orderId: 101);

    expect(container.read(syncQueueProvider), isEmpty);
    expect(
      container.read(kitchenActionsProvider).lastError,
      'DEJA MISE A JOUR',
    );
    expect(container.read(kitchenQueueProvider).hasValue, isTrue);
    expect(
      container
          .read(kitchenQueueProvider)
          .valueOrNull!
          .currentPageTickets
          .map((ticket) => ticket.order.id),
      [101],
    );
    expect(repository.listCalls, greaterThan(1));
  });
}

KitchenTicketViewModel _ticket(
  TestKitchenRepository repository,
  KitchenScreenProfile profile,
) {
  return mapOrderToKitchenTicket(
    order: repository.details[101]!,
    profile: profile,
  );
}

class _TestSyncQueue extends SyncQueue {
  @override
  List<QueuedAction> build() => const [];

  @override
  void add({
    required String feature,
    required String label,
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    String? idempotencyKey,
    String? lastError,
  }) {
    state = [
      QueuedAction(
        id: (state.length + 1).toString(),
        feature: feature,
        label: label,
        endpoint: endpoint,
        method: method,
        payload: payload,
        createdAt: DateTime.utc(2026, 8, 17, 10, state.length),
        idempotencyKey: idempotencyKey,
        lastError: lastError,
      ),
      ...state,
    ];
  }
}

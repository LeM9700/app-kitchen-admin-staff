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

  test('markStationReady utilise UNE requete bulk et plus de N PATCH item',
      () async {
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

    expect(repository.stationPreparationUpdates.length, 1);
    expect(repository.stationPreparationUpdates.single.station, 'kitchen');
    expect(repository.stationPreparationUpdates.single.status, 'ready');
    // LOT 12 : plus de N PATCH item ni de second PATCH updateStatus ready.
    expect(repository.preparationUpdates, isEmpty);
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

    expect(repository.stationPreparationUpdates.length, 1);
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

    expect(repository.stationPreparationUpdates.length, 1);
    // La synchronisation globale (preparing -> ready) est faite par le
    // backend, jamais par un second PATCH /orders/{id}/status cote client.
    expect(repository.statusUpdates, isEmpty);
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

    expect(repository.stationPreparationUpdates, isEmpty);
    expect(repository.statusUpdates, isEmpty);
    expect(
      container.read(kitchenActionsProvider).lastError,
      'Action indisponible sur cet ecran.',
    );
  });

  test('busy est nettoye apres erreur ready', () async {
    final repository = TestKitchenRepository()
      ..setOrders([101])
      ..updateStationPreparationError = StateError('boom');
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

  test('markStationReady met UNE action bulk en file si le reseau tombe',
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
    repository.updateStationPreparationError =
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
    expect(queued.map((action) => action.feature), ['kitchen']);
    expect(queued.single.endpoint, '/orders/101/stations/kitchen/preparation');
    expect(queued.single.payload, {'status': 'ready'});
    expect(
      repository.details[101]!.items.map((item) => item.preparationStatus),
      ['preparing', 'preparing'],
    );
  });

  test('reopenStation appelle bulk preparing', () async {
    final repository = TestKitchenRepository()..setOrders([101]);
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'ready',
        items: [testKitchenItem(id: 1, preparationStatus: 'ready')],
      ),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).reopenStation(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    expect(repository.stationPreparationUpdates.length, 1);
    expect(repository.stationPreparationUpdates.single.station, 'kitchen');
    expect(repository.stationPreparationUpdates.single.status, 'preparing');
    expect(repository.details[101]!.status, 'preparing');
  });

  test('reopenStation refuse sur ecran service', () async {
    const serviceProfile = KitchenScreenProfile(
      mode: KitchenScreenMode.service,
      station: 'service',
      interactionMode: KitchenInteractionMode.touch,
    );
    final repository = TestKitchenRepository()..setOrders([101]);
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'ready',
        items: [testKitchenItem(id: 1, preparationStatus: 'ready')],
      ),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).reopenStation(
          ticket: _ticket(repository, serviceProfile),
          profile: serviceProfile,
        );

    expect(repository.stationPreparationUpdates, isEmpty);
    expect(
      container.read(kitchenActionsProvider).lastError,
      'Action indisponible sur cet ecran.',
    );
  });

  test('reopenStation refuse quand la station n est pas prete', () async {
    final repository = TestKitchenRepository()..setOrders([101]);
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'preparing',
        items: [testKitchenItem(id: 1, preparationStatus: 'preparing')],
      ),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).reopenStation(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    expect(repository.stationPreparationUpdates, isEmpty);
  });

  test('double reopen simultane n envoie qu un appel', () async {
    final repository = TestKitchenRepository()
      ..setOrders([101])
      ..updateStationPreparationGate = Completer<void>();
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'ready',
        items: [testKitchenItem(id: 1, preparationStatus: 'ready')],
      ),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenActionsProvider.notifier);
    final ticket = _ticket(repository, kitchenProfile);
    final first = controller.reopenStation(
      ticket: ticket,
      profile: kitchenProfile,
    );
    await Future<void>.delayed(Duration.zero);
    final second = controller.reopenStation(
      ticket: ticket,
      profile: kitchenProfile,
    );
    await Future<void>.delayed(Duration.zero);

    expect(repository.stationPreparationUpdates.length, 1);

    repository.updateStationPreparationGate!.complete();
    await Future.wait([first, second]);
  });

  test('busy reopen est nettoye apres succes', () async {
    final repository = TestKitchenRepository()..setOrders([101]);
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'ready',
        items: [testKitchenItem(id: 1, preparationStatus: 'ready')],
      ),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).reopenStation(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    final key = kitchenReopenStationActionKey(101, kitchenProfile);
    expect(container.read(kitchenActionsProvider).isActionBusy(key), isFalse);
    expect(
      container.read(kitchenActionsProvider).lastError,
      'POSTE REPASSE EN PREPARATION',
    );
  });

  test('busy reopen est nettoye apres erreur', () async {
    final repository = TestKitchenRepository()
      ..setOrders([101])
      ..updateStationPreparationError = StateError('boom');
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'ready',
        items: [testKitchenItem(id: 1, preparationStatus: 'ready')],
      ),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).reopenStation(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    final key = kitchenReopenStationActionKey(101, kitchenProfile);
    expect(container.read(kitchenActionsProvider).isActionBusy(key), isFalse);
    expect(
      container.read(kitchenActionsProvider).lastError,
      'Impossible de mettre a jour la commande.',
    );
  });

  test('reopenStation met une action bulk preparing en file hors ligne',
      () async {
    final repository = TestKitchenRepository()
      ..setOrders([101])
      ..updateStationPreparationError = const NetworkException(
        message: 'offline',
      );
    repository.details = {
      101: testKitchenOrder(
        id: 101,
        status: 'ready',
        items: [testKitchenItem(id: 1, preparationStatus: 'ready')],
      ),
    };
    final container = createKitchenContainer(
      repository,
      overrides: [syncQueueProvider.overrideWith(_TestSyncQueue.new)],
    );
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    await container.read(kitchenActionsProvider.notifier).reopenStation(
          ticket: _ticket(repository, kitchenProfile),
          profile: kitchenProfile,
        );

    final queued = container.read(syncQueueProvider);
    expect(queued.map((action) => action.feature), ['kitchen']);
    expect(queued.single.endpoint, '/orders/101/stations/kitchen/preparation');
    expect(queued.single.payload, {
      'status': 'preparing',
      'note': 'Reouverture du poste depuis le KDS',
    });
    // Pas d'optimistic update mensonger : l'etat local reste "ready" tant
    // que le serveur n'a pas confirme.
    expect(repository.details[101]!.status, 'ready');
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

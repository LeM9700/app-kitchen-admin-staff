import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  testWidgets('4 tickets sont affichés en page 0 et le ticket 5 est absent',
      (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders(kitchenIds(101, 105));
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    expect(find.text('#101'), findsOneWidget);
    expect(find.text('#102'), findsOneWidget);
    expect(find.text('#103'), findsOneWidget);
    expect(find.text('#104'), findsOneWidget);
    expect(find.text('#105'), findsNothing);
  });

  testWidgets('nextPage affiche le ticket 5', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders(kitchenIds(101, 105));
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);
    await tester.tap(find.byKey(const Key('kitchen-next-page')));
    await tester.pump();

    expect(find.text('#105'), findsOneWidget);
    expect(find.text('#101'), findsNothing);
  });

  testWidgets('le header affiche les compteurs de queue', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders(
        kitchenIds(101, 105),
        statuses: {
          101: 'pending',
          102: 'queued',
          103: 'confirmed',
          104: 'preparing',
          105: 'ready',
        },
      );
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    expect(find.text('3 EN ATTENTE'), findsOneWidget);
    expect(find.text('1 EN PRÉPARATION'), findsOneWidget);
    expect(find.text('2 NOUVELLES'), findsOneWidget);
  });

  testWidgets('empty state fonctionne', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders(const []);
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    expect(find.text('AUCUNE COMMANDE EN COURS'), findsOneWidget);
  });

  testWidgets('error state expose réessayer et relance le chargement',
      (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..listError = StateError('boom')
      ..setOrders([101]);
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    expect(find.text('CHARGEMENT CUISINE IMPOSSIBLE'), findsOneWidget);
    expect(find.text('RÉESSAYER'), findsOneWidget);

    repository.listError = null;
    await tester.tap(find.text('RÉESSAYER'));
    for (var index = 0; index < 4; index++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('#101'), findsOneWidget);
    expect(repository.listCalls, greaterThan(1));
  });

  testWidgets('tap ticket applique le focus via le controller', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders(kitchenIds(101, 104));
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);
    await tester.tap(find.byKey(const ValueKey('kitchen-ticket-102')));
    await tester.pump();

    final state = container.read(kitchenQueueProvider).valueOrNull!;
    expect(state.focusedOrderId, 102);
  });

  testWidgets('interactionMode wall ne montre pas les actions tactiles',
      (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders(
        [101],
        statuses: {101: 'confirmed'},
      );
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    expect(find.text('COMMENCER'), findsNothing);
    expect(find.text('PRÊTE'), findsNothing);
  });

  testWidgets('tap COMMENCER appelle la mutation sans focus incorrect',
      (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders(
        [101],
        statuses: {101: 'confirmed'},
      );
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    container.read(kitchenScreenProfileProvider.notifier).setProfile(
          testKitchenProfile.copyWith(
            interactionMode: KitchenInteractionMode.touch,
          ),
        );

    await pumpKitchenPage(tester, container);
    await tester.tap(find.text('COMMENCER'));
    await _pumpAction(tester);

    expect(repository.statusUpdates.map((update) => update.status), [
      'preparing',
    ]);
    expect(
      container.read(kitchenQueueProvider).valueOrNull!.focusedOrderId,
      isNull,
    );
  });

  testWidgets('tap PRÊTE appelle la mutation sans focus incorrect',
      (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    container.read(kitchenScreenProfileProvider.notifier).setProfile(
          testKitchenProfile.copyWith(
            interactionMode: KitchenInteractionMode.touch,
          ),
        );

    await pumpKitchenPage(tester, container);
    await tester.tap(find.text('PRÊTE'));
    await _pumpAction(tester);

    expect(repository.stationPreparationUpdates.length, 1);
    expect(repository.stationPreparationUpdates.single.station, 'kitchen');
    expect(repository.stationPreparationUpdates.single.status, 'ready');
    // LOT 12 : plus de PATCH item ni de second PATCH statut global cote client.
    expect(repository.preparationUpdates, isEmpty);
    expect(repository.statusUpdates, isEmpty);
    expect(
      container.read(kitchenQueueProvider).valueOrNull!.focusedOrderId,
      isNull,
    );
  });
}

Future<void> _pumpAction(WidgetTester tester) async {
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

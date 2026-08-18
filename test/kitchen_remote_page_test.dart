import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_connection.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_remote_controller.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_remote_session.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_remote_page.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  testWidgets('aucun ecran associe affiche le choix de demonstration', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository();
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('AUCUN ÉCRAN ASSOCIÉ'), findsOneWidget);
    expect(find.text('MODE DÉMONSTRATION'), findsOneWidget);
    expect(find.text('Cuisine principale'), findsOneWidget);
    expect(find.text('Comptoir'), findsOneWidget);
    expect(find.text('Service'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('association cuisine verrouille le nom ecran et le ticket', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    repository.details = {
      101: _remoteKitchenOrder(status: 'preparing'),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    _connect(container, 'kitchen-main');

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('ÉCRAN ASSOCIÉ'), findsOneWidget);
    expect(find.text('CUISINE PRINCIPALE'), findsOneWidget);
    expect(find.byKey(const Key('kitchen-screen-selector')), findsNothing);
    expect(find.textContaining('BURGER CLASSIC'), findsOneWidget);
    expect(find.text('DOUBLE'), findsOneWidget);
    expect(find.text('+ Cheddar'), findsOneWidget);
    expect(find.textContaining('FRITES'), findsOneWidget);
    expect(find.textContaining('06:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cuisine confirmed affiche COMMENCER', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'confirmed'});
    repository.details = {
      101: _remoteKitchenOrder(status: 'confirmed'),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    _connect(container, 'kitchen-main');

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('COMMENCER'), findsOneWidget);
  });

  testWidgets('cuisine preparing affiche PRETE', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    repository.details = {
      101: _remoteKitchenOrder(status: 'preparing'),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    _connect(container, 'kitchen-main');

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('PRÊTE'), findsOneWidget);
  });

  testWidgets('service affiche les stations sans actions production', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    repository.details = {
      101: _remoteServiceOrder(),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    _connect(container, 'service-main');

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('SERVICE'), findsOneWidget);
    expect(find.textContaining('BURGER CLASSIC'), findsOneWidget);
    expect(find.textContaining('COCA'), findsOneWidget);
    expect(find.text('CUISINE ✓ PRÊT'), findsOneWidget);
    expect(find.text('COMPTOIR EN COURS'), findsOneWidget);
    expect(find.text('COMMENCER'), findsNothing);
    expect(find.text('PRÊTE'), findsNothing);
  });

  testWidgets('etat offline et actions en attente visibles', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    repository.details = {
      101: _remoteKitchenOrder(status: 'preparing'),
    };
    final container = createKitchenContainer(
      repository,
      overrides: [
        kitchenConnectionStateProvider.overrideWithValue(
          const KitchenConnectionState(
            status: KitchenConnectionStatus.offline,
            pendingActions: 2,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    _connect(container, 'kitchen-main');

    await pumpKitchenRemotePage(tester, container);

    expect(find.textContaining('HORS CONNEXION'), findsWidgets);
    expect(find.textContaining('2 ACTIONS EN ATTENTE'), findsWidgets);
  });

  testWidgets('queueChangedWhileBrowsing affiche la file mise a jour', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders(kitchenIds(101, 109));
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    _connect(container, 'kitchen-main');

    await pumpKitchenRemotePage(tester, container);
    final remoteContainer = _remoteContainer(tester);
    final controller = remoteContainer.read(kitchenQueueProvider.notifier);
    controller.goToPage(1);
    controller.focusOrder(105);
    await tester.pump();

    repository.setOrders(kitchenIds(102, 109));
    await controller.refresh();
    await tester.pumpAndSettle();

    expect(find.text('FILE MISE À JOUR'), findsOneWidget);
    expect(find.text('#105'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kitchen-remote-return-live')));
    await tester.pumpAndSettle();

    expect(find.text('#102'), findsOneWidget);
    expect(find.text('FILE MISE À JOUR'), findsNothing);
  });

  testWidgets('dissocier retourne a l ecran d association', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    _connect(container, 'kitchen-main');

    await pumpKitchenRemotePage(tester, container);

    await tester.tap(find.byKey(const Key('kitchen-remote-disconnect')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('kitchen-remote-disconnect-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text('AUCUN ÉCRAN ASSOCIÉ'), findsOneWidget);
  });
}

Future<void> pumpKitchenRemotePage(
  WidgetTester tester,
  ProviderContainer container, {
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(body: KitchenRemotePage()),
      ),
    ),
  );

  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ProviderContainer _remoteContainer(WidgetTester tester) {
  final context = tester.element(find.byKey(const Key('kitchen-remote-board')));
  return ProviderScope.containerOf(context, listen: false);
}

void _connect(ProviderContainer container, String screenId) {
  final screen = demoKitchenScreens.firstWhere(
    (candidate) => candidate.id == screenId,
  );
  container.read(kitchenRemoteSessionProvider.notifier).connectToScreen(screen);
}

OrderDetail _remoteKitchenOrder({required String status}) {
  return testKitchenOrder(
    id: 101,
    status: status,
    orderType: 'dine_in',
    tableNumber: '08',
    confirmedAt: status == 'pending' || status == 'queued'
        ? null
        : DateTime.now().subtract(const Duration(minutes: 6, seconds: 5)),
    items: [
      testKitchenItem(
        id: 1,
        quantity: 2,
        productName: 'Burger Classic',
        variantName: 'Double',
        extras: [testKitchenExtra(name: 'Cheddar')],
        preparationStatus: status == 'ready' ? 'ready' : 'preparing',
        preparationStation: 'kitchen',
      ),
      testKitchenItem(
        id: 2,
        productName: 'Frites',
        preparationStatus: status == 'ready' ? 'ready' : 'preparing',
        preparationStation: 'kitchen',
      ),
    ],
  );
}

OrderDetail _remoteServiceOrder() {
  return testKitchenOrder(
    id: 101,
    status: 'preparing',
    orderType: 'dine_in',
    tableNumber: '08',
    confirmedAt: DateTime.now().subtract(
      const Duration(minutes: 6, seconds: 5),
    ),
    items: [
      testKitchenItem(
        id: 1,
        quantity: 2,
        productName: 'Burger Classic',
        variantName: 'Double',
        extras: [testKitchenExtra(name: 'Cheddar')],
        preparationStatus: 'ready',
        preparationStation: 'kitchen',
      ),
      testKitchenItem(
        id: 2,
        productName: 'Frites',
        preparationStatus: 'ready',
        preparationStation: 'kitchen',
      ),
      testKitchenItem(
        id: 3,
        productName: 'Coca',
        preparationStatus: 'preparing',
        preparationStation: 'counter',
      ),
    ],
    stationSummary: const [
      OrderStationSummary(
        station: 'kitchen',
        totalItems: 2,
        readyItems: 2,
        allReady: true,
      ),
      OrderStationSummary(
        station: 'counter',
        totalItems: 1,
        readyItems: 0,
        allReady: false,
      ),
    ],
  );
}

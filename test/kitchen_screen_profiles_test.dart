import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_screen_presets.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  test('demo presets define kitchen, counter, and service stations', () {
    expect(kitchenWallPreset.mode, KitchenScreenMode.kitchen);
    expect(kitchenWallPreset.station, 'kitchen');
    expect(kitchenWallPreset.interactionMode, KitchenInteractionMode.wall);

    expect(kitchenTouchPreset.mode, KitchenScreenMode.kitchen);
    expect(kitchenTouchPreset.station, 'kitchen');
    expect(kitchenTouchPreset.interactionMode, KitchenInteractionMode.touch);

    expect(counterWallPreset.mode, KitchenScreenMode.counter);
    expect(counterWallPreset.station, 'counter');
    expect(counterTouchPreset.mode, KitchenScreenMode.counter);
    expect(counterTouchPreset.station, 'counter');

    expect(serviceWallPreset.mode, KitchenScreenMode.service);
    expect(serviceWallPreset.station, 'service');
    expect(serviceTouchPreset.mode, KitchenScreenMode.service);
    expect(serviceTouchPreset.station, 'service');
  });

  test('profile change remaps tickets and resets browsing state', () async {
    final repository = TestKitchenRepository()..setOrders(kitchenIds(101, 105));
    repository.details = {
      for (final id in kitchenIds(101, 105)) id: _mixedStationOrder(id),
    };
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenQueueProvider.notifier);
    controller.goToPage(1);
    controller.focusOrder(105);

    controller.setProfile(counterWallPreset);
    final counterState = await container.read(kitchenQueueProvider.future);

    expect(counterState.profile.mode, KitchenScreenMode.counter);
    expect(counterState.profile.station, 'counter');
    expect(counterState.currentPage, 0);
    expect(counterState.focusedOrderId, isNull);
    expect(counterState.queueChangedWhileBrowsing, isFalse);
    expect(
      counterState.currentPageTickets.first.visibleItems.map(
        (item) => item.productName,
      ),
      ['Coca'],
    );

    controller.setProfile(serviceWallPreset);
    final serviceState = await container.read(kitchenQueueProvider.future);

    expect(serviceState.profile.mode, KitchenScreenMode.service);
    expect(serviceState.currentPage, 0);
    expect(serviceState.focusedOrderId, isNull);
    expect(
      serviceState.currentPageTickets.first.visibleItems.map(
        (item) => item.productName,
      ),
      ['Burger', 'Coca'],
    );
  });

  testWidgets(
      'selector backend affiche les ecrans actifs et applique leur profil',
      (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'pending'});
    repository.details = {101: _mixedStationOrder(101, status: 'pending')};
    final kdsRepository = _FakeKdsScreensRepository()
      ..screens = [
        _kdsScreen(id: 1, name: 'Cuisine principale'),
        _kdsScreen(
          id: 2,
          name: 'Comptoir terrasse',
          mode: 'counter',
          station: 'counter',
        ),
      ];
    final container = createKitchenContainer(
      repository,
      overrides: [kdsRepositoryProvider.overrideWithValue(kdsRepository)],
    );
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    // Avant toute sélection: fallback sur le libellé de mode local.
    expect(find.text('CUISINE'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsOneWidget);
    expect(find.textContaining('COCA'), findsNothing);

    await tester.tap(find.byKey(const Key('kitchen-screen-selector')));
    await tester.pumpAndSettle();

    // Les deux écrans backend actifs apparaissent, aucun preset générique
    // fictif (CUISINE/COMPTOIR/SERVICE) n'est présent dans ce flow normal.
    expect(find.text('Cuisine principale'), findsOneWidget);
    expect(find.text('Comptoir terrasse'), findsOneWidget);
    expect(find.byKey(const Key('kitchen-profile-mode-counter')), findsNothing);
    expect(find.byKey(const Key('kitchen-profile-mode-service')), findsNothing);
    expect(kdsRepository.includeInactiveCaptured, isFalse);

    await tester.tap(find.text('Comptoir terrasse'));
    await tester.pumpAndSettle();

    expect(find.text('COMPTOIR TERRASSE'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsNothing);
    expect(find.textContaining('COCA'), findsOneWidget);
    expect(
      container.read(kitchenSelectedScreenProvider)?.name,
      'Comptoir terrasse',
    );

    await tester.tap(find.byKey(const Key('kitchen-screen-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuisine principale'));
    await tester.pumpAndSettle();

    expect(find.text('CUISINE PRINCIPALE'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsOneWidget);
    expect(find.textContaining('COCA'), findsNothing);
  });

  testWidgets('ecran isActive false absent du selector', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final kdsRepository = _FakeKdsScreensRepository()
      ..screens = [
        _kdsScreen(id: 1, name: 'Cuisine principale'),
        _kdsScreen(id: 2, name: 'Ecran desactive', isActive: false),
      ];
    final container = createKitchenContainer(
      repository,
      overrides: [kdsRepositoryProvider.overrideWithValue(kdsRepository)],
    );
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);
    await tester.tap(find.byKey(const Key('kitchen-screen-selector')));
    await tester.pumpAndSettle();

    expect(find.text('Cuisine principale'), findsOneWidget);
    expect(find.text('Ecran desactive'), findsNothing);
  });

  testWidgets(
      'echec de chargement affiche le message et ne perturbe pas le board',
      (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final kdsRepository = _FakeKdsScreensRepository()
      ..listError = StateError('boom');
    final container = createKitchenContainer(
      repository,
      overrides: [kdsRepositoryProvider.overrideWithValue(kdsRepository)],
    );
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    expect(find.text('CUISINE'), findsOneWidget);
    expect(find.text('#101'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kitchen-screen-selector')));
    await tester.pumpAndSettle();

    expect(find.text('Impossible de charger les écrans'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Le board déjà affiché reste fonctionnel: pas de crash, aucun
    // changement de profil ni d'écran sélectionné côté providers.
    expect(container.read(kitchenSelectedScreenProvider), isNull);
    expect(
      container.read(kitchenScreenProfileProvider).mode,
      KitchenScreenMode.kitchen,
    );
    expect(find.text('#101'), findsOneWidget);
  });
}

OrderDetail _mixedStationOrder(int id, {String status = 'preparing'}) {
  return testKitchenOrder(
    id: id,
    status: status,
    orderType: 'pickup',
    tableNumber: null,
    confirmedAt: status == 'pending' || status == 'queued'
        ? null
        : DateTime.utc(2026, 8, 17, 10, id - 100),
    items: [
      testKitchenItem(
        id: id * 10,
        productName: 'Burger',
        preparationStatus: status == 'ready' ? 'ready' : 'preparing',
        preparationStation: 'kitchen',
      ),
      testKitchenItem(
        id: id * 10 + 1,
        productName: 'Coca',
        preparationStatus: status == 'ready' ? 'ready' : 'preparing',
        preparationStation: 'counter',
      ),
    ],
  );
}

KdsScreen _kdsScreen({
  required int id,
  required String name,
  String mode = 'kitchen',
  String station = 'kitchen',
  String interactionMode = 'wall',
  int ticketsPerPage = 4,
  bool isActive = true,
}) {
  return KdsScreen(
    id: id,
    name: name,
    screenKey: 'screen-$id',
    mode: mode,
    station: station,
    interactionMode: interactionMode,
    ticketsPerPage: ticketsPerPage,
    isActive: isActive,
  );
}

/// Fake KDS repository focused on `listScreens()`, used to drive the board's
/// screen selector without hitting the network. Mirrors the real backend's
/// `include_inactive` filtering behavior so widget tests can verify the
/// selector only ever sees `isActive == true` screens by default.
class _FakeKdsScreensRepository extends KdsRepository {
  _FakeKdsScreensRepository() : super(_unusedClient());

  List<KdsScreen> screens = const [];
  Object? listError;
  bool includeInactiveCaptured = false;

  @override
  Future<List<KdsScreen>> listScreens({bool includeInactive = false}) async {
    includeInactiveCaptured = includeInactive;
    final error = listError;
    if (error != null) {
      throw error;
    }
    if (includeInactive) {
      return screens;
    }
    return [
      for (final screen in screens)
        if (screen.isActive) screen,
    ];
  }
}

ApiClient _unusedClient() {
  return ApiClient(
    Dio(BaseOptions(baseUrl: 'http://api.test')),
    _MemoryTokenStore(),
  );
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore() : super(const FlutterSecureStorage());
}

import 'package:app_admin_staff/app/operational_fullscreen.dart';
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
        _kdsScreen(id: 3, name: 'Cuisine secondaire'),
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

    // Seuls les écrans backend actifs du mode Cuisine apparaissent, aucun
    // preset générique fictif (CUISINE/COMPTOIR/SERVICE) n'est présent.
    expect(find.text('Cuisine principale'), findsOneWidget);
    expect(find.text('Cuisine secondaire'), findsOneWidget);
    expect(find.text('Comptoir terrasse'), findsNothing);
    expect(find.byKey(const Key('kitchen-profile-mode-counter')), findsNothing);
    expect(find.byKey(const Key('kitchen-profile-mode-service')), findsNothing);
    expect(kdsRepository.includeInactiveCaptured, isFalse);

    await tester.tap(find.text('Cuisine secondaire'));
    await tester.pumpAndSettle();

    expect(find.text('CUISINE SECONDAIRE'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsOneWidget);
    expect(find.textContaining('COCA'), findsNothing);
    expect(
      container.read(kitchenSelectedScreenProvider)?.name,
      'Cuisine secondaire',
    );

    await tester.tap(find.byKey(const Key('kitchen-screen-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuisine principale'));
    await tester.pumpAndSettle();

    expect(find.text('CUISINE PRINCIPALE'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsOneWidget);
    expect(find.textContaining('COCA'), findsNothing);
  });

  testWidgets('page Comptoir filtre les ecrans et tickets counter',
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

    await pumpKitchenPage(
      tester,
      container,
      screenMode: KitchenScreenMode.counter,
    );

    expect(find.text('COMPTOIR'), findsOneWidget);
    expect(find.textContaining('BURGER'), findsNothing);
    expect(find.textContaining('COCA'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kitchen-screen-selector')));
    await tester.pumpAndSettle();

    expect(find.text('Cuisine principale'), findsNothing);
    expect(find.text('Comptoir terrasse'), findsOneWidget);

    await tester.tap(find.text('Comptoir terrasse'));
    await tester.pumpAndSettle();

    expect(find.text('COMPTOIR TERRASSE'), findsOneWidget);
    expect(
      container
          .read(kitchenSelectedScreenProviderFor(KitchenScreenMode.counter))
          ?.name,
      'Comptoir terrasse',
    );
    expect(container.read(kitchenSelectedScreenProvider), isNull);
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

  testWidgets('bouton QR Cuisine ouvre un code remote chiffre', (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final kdsRepository = _FakeKdsScreensRepository()
      ..screens = [_kdsScreen(id: 7, name: 'Cuisine principale')]
      ..pairingCode = KdsPairingCode(
        screenId: 7,
        code: '482731',
        pairingPayload: 'encrypted-pairing-payload',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
    final container = createKitchenContainer(
      repository,
      overrides: [kdsRepositoryProvider.overrideWithValue(kdsRepository)],
    );
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);
    await tester.tap(find.byKey(const Key('kitchen-remote-pairing-action')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(kdsRepository.generatedScreenId, 7);
    expect(find.byKey(const Key('kds-pairing-qr')), findsOneWidget);
    expect(find.text('482 731'), findsOneWidget);
    expect(
      container.read(kitchenSelectedScreenProvider)?.name,
      'Cuisine principale',
    );
  });

  testWidgets('bouton QR refuse un ecran selectionne non remote',
      (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final kdsRepository = _FakeKdsScreensRepository()
      ..screens = [
        _kdsScreen(
          id: 8,
          name: 'Cuisine sans remote',
          remoteEnabled: false,
        ),
      ];
    final container = createKitchenContainer(
      repository,
      overrides: [kdsRepositoryProvider.overrideWithValue(kdsRepository)],
    );
    addTearDown(container.dispose);
    container.read(kitchenSelectedScreenProvider.notifier).state =
        kdsRepository.screens.single;

    await pumpKitchenPage(tester, container);
    await tester.tap(find.byKey(const Key('kitchen-remote-pairing-action')));
    await tester.pump();

    expect(kdsRepository.generateCalls, 0);
    expect(find.text('REMOTE DÉSACTIVÉ POUR CET ÉCRAN'), findsOneWidget);
    expect(find.byKey(const Key('kds-pairing-qr')), findsNothing);
  });

  testWidgets('bouton QR Comptoir genere pour un ecran counter',
      (tester) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final kdsRepository = _FakeKdsScreensRepository()
      ..screens = [
        _kdsScreen(id: 7, name: 'Cuisine principale'),
        _kdsScreen(
          id: 9,
          name: 'Comptoir terrasse',
          mode: 'counter',
          station: 'counter',
        ),
      ]
      ..pairingCode = KdsPairingCode(
        screenId: 9,
        code: '928304',
        pairingPayload: 'encrypted-counter-payload',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
    final container = createKitchenContainer(
      repository,
      overrides: [kdsRepositoryProvider.overrideWithValue(kdsRepository)],
    );
    addTearDown(container.dispose);

    await pumpKitchenPage(
      tester,
      container,
      screenMode: KitchenScreenMode.counter,
    );
    await tester.tap(find.byKey(const Key('kitchen-remote-pairing-action')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(kdsRepository.generatedScreenId, 9);
    expect(find.byKey(const Key('kds-pairing-qr')), findsOneWidget);
    expect(find.text('928 304'), findsOneWidget);
    expect(
      container
          .read(kitchenSelectedScreenProviderFor(KitchenScreenMode.counter))
          ?.name,
      'Comptoir terrasse',
    );
  });

  testWidgets('scanner remote visible sur Cuisine mobile seulement', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container, size: const Size(390, 844));

    expect(find.byKey(const Key('kitchen-remote-scan-action')), findsOneWidget);

    await pumpKitchenPage(tester, container, size: const Size(1024, 768));

    expect(find.byKey(const Key('kitchen-remote-scan-action')), findsNothing);
  });

  testWidgets('scanner remote visible sur Comptoir mobile seulement', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(
      tester,
      container,
      size: const Size(390, 844),
      screenMode: KitchenScreenMode.counter,
    );

    expect(find.byKey(const Key('kitchen-remote-scan-action')), findsOneWidget);

    await pumpKitchenPage(
      tester,
      container,
      size: const Size(1024, 768),
      screenMode: KitchenScreenMode.counter,
    );

    expect(find.byKey(const Key('kitchen-remote-scan-action')), findsNothing);
  });

  testWidgets('bouton plein ecran Cuisine bascule l etat global', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(tester, container);

    expect(find.byKey(const Key('kitchen-fullscreen-action')), findsOneWidget);
    expect(container.read(operationalFullscreenProvider), isFalse);

    await tester.tap(find.byKey(const Key('kitchen-fullscreen-action')));
    await tester.pump();

    expect(container.read(operationalFullscreenProvider), isTrue);
    expect(find.byIcon(Icons.fullscreen_exit_outlined), findsOneWidget);

    await tester.tap(find.byKey(const Key('kitchen-fullscreen-action')));
    await tester.pump();

    expect(container.read(operationalFullscreenProvider), isFalse);
  });

  testWidgets('bouton plein ecran Comptoir bascule l etat global', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final repository = TestKitchenRepository()..setOrders([101]);
    final container = createKitchenContainer(repository);
    addTearDown(container.dispose);

    await pumpKitchenPage(
      tester,
      container,
      screenMode: KitchenScreenMode.counter,
    );

    expect(find.byKey(const Key('kitchen-fullscreen-action')), findsOneWidget);
    expect(container.read(operationalFullscreenProvider), isFalse);

    await tester.tap(find.byKey(const Key('kitchen-fullscreen-action')));
    await tester.pump();

    expect(container.read(operationalFullscreenProvider), isTrue);
    expect(find.byIcon(Icons.fullscreen_exit_outlined), findsOneWidget);
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
  bool remoteEnabled = true,
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
    remoteEnabled: remoteEnabled,
  );
}

/// Fake KDS repository focused on `listScreens()`, used to drive the board's
/// screen selector without hitting the network. Mirrors the real backend's
/// `include_inactive` filtering behavior so widget tests can verify the
/// selector only ever sees `isActive == true` screens by default.
class _FakeKdsScreensRepository extends KdsRepository {
  _FakeKdsScreensRepository() : super(_unusedClient());

  List<KdsScreen> screens = const [];
  KdsPairingCode? pairingCode;
  Object? listError;
  bool includeInactiveCaptured = false;
  int generateCalls = 0;
  int? generatedScreenId;

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

  @override
  Future<KdsPairingCode> generatePairingCode({required int screenId}) async {
    generateCalls += 1;
    generatedScreenId = screenId;
    final code = pairingCode;
    if (code == null) {
      throw StateError('missing pairing code');
    }
    return code;
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

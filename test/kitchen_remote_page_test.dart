import 'dart:async';

import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_connection.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:app_admin_staff/features/kitchen/data/kitchen_remote_session_store.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_remote_page.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'kitchen_board_test_support.dart';

void main() {
  testWidgets('aucun ecran associe affiche le formulaire code', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final orders = TestKitchenRepository();
    final kdsStore = TestRemoteSessionStore();
    final kdsRepository = TestKdsRepository();
    final container = createKitchenContainer(
      orders,
      overrides: remoteKdsOverrides(kdsStore, kdsRepository),
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('AUCUN ÉCRAN ASSOCIÉ'), findsOneWidget);
    expect(
      find.text('ENTREZ LE CODE AFFICHÉ SUR L’ÉCRAN KDS'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('kitchen-remote-pairing-code')),
      findsOneWidget,
    );
    expect(find.text('ASSOCIER'), findsOneWidget);
    expect(find.text('MODE DÉMONSTRATION'), findsNothing);
    expect(find.text('Cuisine principale'), findsNothing);
    expect(find.text('Comptoir'), findsNothing);
    expect(find.text('Service'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('code 5 chiffres garde le bouton disabled', (tester) async {
    addTearDown(tester.view.reset);
    final container = createKitchenContainer(
      TestKitchenRepository(),
      overrides: remoteKdsOverrides(
        TestRemoteSessionStore(),
        TestKdsRepository(),
      ),
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);
    await tester.enterText(
      find.byKey(const Key('kitchen-remote-pairing-code')),
      '12345',
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('kitchen-remote-pair-submit')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('code 6 chiffres active le bouton', (tester) async {
    addTearDown(tester.view.reset);
    final container = createKitchenContainer(
      TestKitchenRepository(),
      overrides: remoteKdsOverrides(
        TestRemoteSessionStore(),
        TestKdsRepository(),
      ),
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);
    await tester.enterText(
      find.byKey(const Key('kitchen-remote-pairing-code')),
      '004281',
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const Key('kitchen-remote-pair-submit')),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('pairing affiche un spinner et desactive le bouton', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final pairGate = Completer<KdsPairResult>();
    final kdsRepository = TestKdsRepository()..pairGate = pairGate;
    final container = createKitchenContainer(
      TestKitchenRepository(),
      overrides: remoteKdsOverrides(
        TestRemoteSessionStore(),
        kdsRepository,
      ),
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);
    await tester.enterText(
      find.byKey(const Key('kitchen-remote-pairing-code')),
      '004281',
    );
    await tester.pump();
    await _tapPairSubmit(tester);
    await tester.pump();

    expect(kdsRepository.pairCodes, ['004281']);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('kitchen-remote-pair-submit')),
    );
    expect(button.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pairGate.complete(
      _pairResult(screen: _kdsScreen(name: 'Cuisine principale')),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('pair succes affiche le vrai nom ecran backend', (tester) async {
    addTearDown(tester.view.reset);
    final orders = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    orders.details = {
      101: _remoteKitchenOrder(status: 'preparing'),
    };
    final kdsRepository = TestKdsRepository()
      ..pairResult = _pairResult(
        screen: _kdsScreen(name: 'Cuisine secondaire'),
      );
    final container = createKitchenContainer(
      orders,
      overrides: remoteKdsOverrides(
        TestRemoteSessionStore(),
        kdsRepository,
      ),
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);
    await tester.enterText(
      find.byKey(const Key('kitchen-remote-pairing-code')),
      '004281',
    );
    await tester.pump();
    await _tapPairSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('ÉCRAN ASSOCIÉ'), findsOneWidget);
    expect(find.text('CUISINE SECONDAIRE'), findsOneWidget);
    expect(find.byKey(const Key('kitchen-screen-selector')), findsNothing);
    expect(find.textContaining('BURGER CLASSIC'), findsOneWidget);
    expect(kdsRepository.pairCodes, ['004281']);
  });

  testWidgets('pair invalid affiche CODE INVALIDE', (tester) async {
    addTearDown(tester.view.reset);
    final kdsRepository = TestKdsRepository()
      ..pairError = const BusinessException(
        message: 'invalid',
        code: 'PAIRING_CODE_INVALID',
        statusCode: 400,
      );
    final kdsStore = TestRemoteSessionStore();
    final container = createKitchenContainer(
      TestKitchenRepository(),
      overrides: remoteKdsOverrides(kdsStore, kdsRepository),
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);
    await tester.enterText(
      find.byKey(const Key('kitchen-remote-pairing-code')),
      '004281',
    );
    await tester.pump();
    await _tapPairSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('CODE INVALIDE'), findsOneWidget);
    expect(kdsStore.token, isNull);
  });

  testWidgets('pair expired affiche CODE EXPIRE', (tester) async {
    addTearDown(tester.view.reset);
    final kdsRepository = TestKdsRepository()
      ..pairError = const BusinessException(
        message: 'expired',
        code: 'PAIRING_CODE_EXPIRED',
        statusCode: 400,
      );
    final container = createKitchenContainer(
      TestKitchenRepository(),
      overrides: remoteKdsOverrides(
        TestRemoteSessionStore(),
        kdsRepository,
      ),
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);
    await tester.enterText(
      find.byKey(const Key('kitchen-remote-pairing-code')),
      '004281',
    );
    await tester.pump();
    await _tapPairSubmit(tester);
    await tester.pumpAndSettle();

    expect(find.text('CODE EXPIRÉ'), findsOneWidget);
  });

  testWidgets('token restaure valide affiche ecran associe', (tester) async {
    addTearDown(tester.view.reset);
    final orders = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    orders.details = {
      101: _remoteKitchenOrder(status: 'preparing'),
    };
    final container = createKitchenContainer(
      orders,
      overrides: remoteKdsOverrides(
        TestRemoteSessionStore('stored-token'),
        TestKdsRepository()
          ..statusResult = _remoteStatus(
            screen: _kdsScreen(name: 'Cuisine principale'),
          ),
      ),
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('ÉCRAN ASSOCIÉ'), findsOneWidget);
    expect(find.text('CUISINE PRINCIPALE'), findsOneWidget);
    expect(find.textContaining('BURGER CLASSIC'), findsOneWidget);
  });

  testWidgets('token invalide revient au formulaire pairing', (tester) async {
    addTearDown(tester.view.reset);
    final kdsStore = TestRemoteSessionStore('bad-token');
    final container = createKitchenContainer(
      TestKitchenRepository(),
      overrides: remoteKdsOverrides(
        kdsStore,
        TestKdsRepository()
          ..statusError = const UnauthorizedException(
            message: 'invalid',
            code: 'KDS_SESSION_INVALID',
            statusCode: 401,
          ),
      ),
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('SESSION INVALIDE'), findsOneWidget);
    expect(find.text('AUCUN ÉCRAN ASSOCIÉ'), findsOneWidget);
    expect(kdsStore.token, isNull);
  });

  testWidgets('cuisine confirmed affiche COMMENCER', (tester) async {
    addTearDown(tester.view.reset);
    final orders = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'confirmed'});
    orders.details = {
      101: _remoteKitchenOrder(status: 'confirmed'),
    };
    final container = connectedRemoteContainer(orders);
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('COMMENCER'), findsOneWidget);
  });

  testWidgets('cuisine preparing affiche PRETE', (tester) async {
    addTearDown(tester.view.reset);
    final orders = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    orders.details = {
      101: _remoteKitchenOrder(status: 'preparing'),
    };
    final container = connectedRemoteContainer(orders);
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);

    expect(find.text('PRÊTE'), findsOneWidget);
  });

  testWidgets('service affiche les stations sans actions production', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final orders = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    orders.details = {
      101: _remoteServiceOrder(),
    };
    final container = connectedRemoteContainer(
      orders,
      screen: _kdsScreen(name: 'Service', mode: 'service', station: 'service'),
    );
    addTearDown(container.dispose);

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
    final orders = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    orders.details = {
      101: _remoteKitchenOrder(status: 'preparing'),
    };
    final container = connectedRemoteContainer(
      orders,
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

    await pumpKitchenRemotePage(tester, container);

    expect(find.textContaining('HORS CONNEXION'), findsWidgets);
    expect(find.textContaining('2 ACTIONS EN ATTENTE'), findsWidgets);
  });

  testWidgets('queueChangedWhileBrowsing affiche la file mise a jour', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final orders = TestKitchenRepository()..setOrders(kitchenIds(101, 109));
    final container = connectedRemoteContainer(orders);
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);
    final remoteContainer = _remoteContainer(tester);
    final controller = remoteContainer.read(kitchenQueueProvider.notifier);
    controller.goToPage(1);
    controller.focusOrder(105);
    await tester.pump();

    orders.setOrders(kitchenIds(102, 109));
    await controller.refresh();
    await tester.pumpAndSettle();

    expect(find.text('FILE MISE À JOUR'), findsOneWidget);
    expect(find.text('#105'), findsOneWidget);

    await tester.tap(find.byKey(const Key('kitchen-remote-return-live')));
    await tester.pumpAndSettle();

    expect(find.text('#102'), findsOneWidget);
    expect(find.text('FILE MISE À JOUR'), findsNothing);
  });

  testWidgets('dissocier revoque et retourne au formulaire pairing', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    final orders = TestKitchenRepository()
      ..setOrders([101], statuses: {101: 'preparing'});
    final kdsStore = TestRemoteSessionStore('stored-token');
    final kdsRepository = TestKdsRepository()..statusResult = _remoteStatus();
    final container = connectedRemoteContainer(
      orders,
      kdsStore: kdsStore,
      kdsRepository: kdsRepository,
    );
    addTearDown(container.dispose);

    await pumpKitchenRemotePage(tester, container);

    await tester.tap(find.byKey(const Key('kitchen-remote-disconnect')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('kitchen-remote-disconnect-confirm')),
    );
    await tester.pumpAndSettle();

    expect(kdsRepository.revokedTokens, ['stored-token']);
    expect(kdsStore.token, isNull);
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

  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

ProviderContainer connectedRemoteContainer(
  TestKitchenRepository orders, {
  KdsScreen? screen,
  TestRemoteSessionStore? kdsStore,
  TestKdsRepository? kdsRepository,
  List<Override> overrides = const [],
}) {
  final store = kdsStore ?? TestRemoteSessionStore('stored-token');
  final repository = kdsRepository ??
      (TestKdsRepository()
        ..statusResult = _remoteStatus(
          screen: screen ?? _kdsScreen(name: 'Cuisine principale'),
        ));
  return createKitchenContainer(
    orders,
    overrides: [
      ...remoteKdsOverrides(store, repository),
      ...overrides,
    ],
  );
}

Future<void> _tapPairSubmit(WidgetTester tester) async {
  final button = find.byKey(const Key('kitchen-remote-pair-submit'));
  final label = find.text('ASSOCIER');
  await tester.ensureVisible(button);
  await tester.tap(label);
}

List<Override> remoteKdsOverrides(
  TestRemoteSessionStore store,
  TestKdsRepository repository,
) {
  return [
    kitchenRemoteSessionStoreProvider.overrideWithValue(store),
    kdsRepositoryProvider.overrideWithValue(repository),
  ];
}

ProviderContainer _remoteContainer(WidgetTester tester) {
  final context = tester.element(find.byKey(const Key('kitchen-remote-board')));
  return ProviderScope.containerOf(context, listen: false);
}

KdsPairResult _pairResult({required KdsScreen screen}) {
  return KdsPairResult(
    sessionToken: 'paired-token',
    expiresAt: DateTime.utc(2026, 8, 18, 22),
    screen: screen,
  );
}

KdsRemoteSessionStatus _remoteStatus({KdsScreen? screen}) {
  return KdsRemoteSessionStatus(
    id: 44,
    screenId: 12,
    pairedByUserId: 7,
    deviceLabel: 'Kitchen Remote',
    createdAt: DateTime.utc(2026, 8, 18, 10),
    lastSeenAt: DateTime.utc(2026, 8, 18, 10, 5),
    expiresAt: DateTime.utc(2026, 8, 18, 22),
    screen: screen ?? _kdsScreen(name: 'Cuisine principale'),
  );
}

KdsScreen _kdsScreen({
  int id = 12,
  String name = 'Cuisine principale',
  String screenKey = 'kitchen-main',
  String mode = 'kitchen',
  String station = 'kitchen',
  String interactionMode = 'wall',
  int ticketsPerPage = 4,
}) {
  return KdsScreen(
    id: id,
    name: name,
    screenKey: screenKey,
    mode: mode,
    station: station,
    interactionMode: interactionMode,
    ticketsPerPage: ticketsPerPage,
    isActive: true,
  );
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

class TestKdsRepository extends KdsRepository {
  TestKdsRepository() : super(_unusedClient());

  KdsPairResult? pairResult;
  Object? pairError;
  Completer<KdsPairResult>? pairGate;
  KdsRemoteSessionStatus? statusResult;
  Object? statusError;
  Object? revokeError;

  final List<String> pairCodes = [];
  final List<String?> deviceLabels = [];
  final List<String> sessionTokens = [];
  final List<String> revokedTokens = [];

  @override
  Future<List<KdsScreen>> listScreens({bool includeInactive = false}) async =>
      const [];

  @override
  Future<KdsPairResult> pair({
    required String code,
    String? deviceLabel,
  }) async {
    pairCodes.add(code);
    deviceLabels.add(deviceLabel);
    final error = pairError;
    if (error != null) {
      throw error;
    }
    final gate = pairGate;
    if (gate != null) {
      return gate.future;
    }
    return pairResult ??
        _pairResult(screen: _kdsScreen(name: 'Cuisine principale'));
  }

  @override
  Future<KdsRemoteSessionStatus> getRemoteSession({
    required String sessionToken,
  }) async {
    sessionTokens.add(sessionToken);
    final error = statusError;
    if (error != null) {
      throw error;
    }
    return statusResult ?? _remoteStatus();
  }

  @override
  Future<void> revokeRemoteSession({required String sessionToken}) async {
    revokedTokens.add(sessionToken);
    final error = revokeError;
    if (error != null) {
      throw error;
    }
  }
}

class TestRemoteSessionStore extends KitchenRemoteSessionStore {
  TestRemoteSessionStore([this.token]) : super(const FlutterSecureStorage());

  String? token;

  @override
  Future<void> saveToken(String token) async {
    this.token = token;
  }

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> clearToken() async {
    token = null;
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

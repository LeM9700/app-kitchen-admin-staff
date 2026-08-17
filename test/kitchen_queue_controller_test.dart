import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_queue_controller.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial state is page 0 with five tickets', () async {
    final api = _OrdersApi()..setOrders(_ids(101, 105));
    final container = _container(api);
    addTearDown(container.dispose);

    final state = await container.read(kitchenQueueProvider.future);

    expect(state.currentPage, 0);
    expect(_visibleOrderIds(state), [101, 102, 103, 104]);
    expect(state.totalPages, 2);
    expect(state.remainingItems, 1);
  });

  test('nextPage displays the fifth ticket', () async {
    final api = _OrdersApi()..setOrders(_ids(101, 105));
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    container.read(kitchenQueueProvider.notifier).nextPage();

    final state = _currentState(container);
    expect(state.currentPage, 1);
    expect(_visibleOrderIds(state), [105]);
  });

  test('previousPage returns to page 0', () async {
    final api = _OrdersApi()..setOrders(_ids(101, 105));
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenQueueProvider.notifier);
    controller.nextPage();
    controller.previousPage();

    final state = _currentState(container);
    expect(state.currentPage, 0);
    expect(_visibleOrderIds(state), [101, 102, 103, 104]);
  });

  test('valid focus works on a visible order', () async {
    final api = _OrdersApi()..setOrders(_ids(101, 105));
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    container.read(kitchenQueueProvider.notifier).focusOrder(101);

    expect(_currentState(container).focusedOrderId, 101);
  });

  test('focus ignores an order absent from the current page', () async {
    final api = _OrdersApi()..setOrders(_ids(101, 105));
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenQueueProvider.notifier);
    controller.focusOrder(101);
    controller.focusOrder(105);

    expect(_currentState(container).focusedOrderId, 101);
  });

  test('page 0 recompacts live after removal', () async {
    final api = _OrdersApi()..setOrders(_ids(101, 105));
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    api.setOrders(_ids(102, 105));
    await container.read(kitchenQueueProvider.notifier).refresh();

    final state = _currentState(container);
    expect(state.currentPage, 0);
    expect(_visibleOrderIds(state), [102, 103, 104, 105]);
    expect(state.queueChangedWhileBrowsing, isFalse);
  });

  test('secondary page stays stable when the live queue changes', () async {
    final api = _OrdersApi()..setOrders(_ids(101, 109));
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenQueueProvider.notifier);
    controller.goToPage(1);
    expect(_visibleOrderIds(_currentState(container)), [105, 106, 107, 108]);

    api.setOrders(_ids(102, 109));
    await controller.refresh();

    final state = _currentState(container);
    expect(state.currentPage, 1);
    expect(_visibleOrderIds(state), [105, 106, 107, 108]);
    expect(_pageOrderIds(state, 1), [106, 107, 108, 109]);
    expect(state.queueChangedWhileBrowsing, isTrue);
  });

  test('returning to page 0 clears secondary snapshot and flag', () async {
    final api = _OrdersApi()..setOrders(_ids(101, 109));
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenQueueProvider.notifier);
    controller.goToPage(1);
    api.setOrders(_ids(102, 109));
    await controller.refresh();
    controller.goToPage(0);

    final state = _currentState(container);
    expect(state.currentPage, 0);
    expect(_visibleOrderIds(state), [102, 103, 104, 105]);
    expect(state.queueChangedWhileBrowsing, isFalse);
  });

  test('secondary to secondary navigation takes a fresh live snapshot',
      () async {
    final api = _OrdersApi()..setOrders(_ids(101, 113));
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenQueueProvider.notifier);
    controller.goToPage(1);
    api.setOrders(_ids(102, 113));
    await controller.refresh();
    controller.goToPage(2);

    final state = _currentState(container);
    expect(state.currentPage, 2);
    expect(_visibleOrderIds(state), [110, 111, 112, 113]);
    expect(state.queueChangedWhileBrowsing, isFalse);
  });

  test('header counters distinguish waiting, preparing, and new tickets',
      () async {
    final api = _OrdersApi()
      ..setOrders(
        _ids(101, 105),
        statuses: {
          101: 'pending',
          102: 'queued',
          103: 'confirmed',
          104: 'preparing',
          105: 'ready',
        },
      );
    final container = _container(api);
    addTearDown(container.dispose);

    final state = await container.read(kitchenQueueProvider.future);

    expect(state.totalWaiting, 3);
    expect(state.totalPreparing, 1);
    expect(state.totalNew, 2);
  });

  test('profile change resets page, focus, snapshot, and remaps tickets',
      () async {
    final api = _OrdersApi()..setOrders(_ids(101, 105), includeCounter: true);
    final container = _container(api);
    addTearDown(container.dispose);
    await container.read(kitchenQueueProvider.future);

    final controller = container.read(kitchenQueueProvider.notifier);
    controller.goToPage(1);
    controller.focusOrder(105);

    controller.setProfile(
      const KitchenScreenProfile(
        mode: KitchenScreenMode.counter,
        station: 'counter',
        ticketsPerPage: 4,
        interactionMode: KitchenInteractionMode.wall,
      ),
    );
    final state = await container.read(kitchenQueueProvider.future);

    expect(state.profile.station, 'counter');
    expect(state.currentPage, 0);
    expect(state.focusedOrderId, isNull);
    expect(state.queueChangedWhileBrowsing, isFalse);
    expect(_visibleOrderIds(state), [101, 102, 103, 104]);
    expect(
      state.currentPageTickets.first.visibleItems.map(
        (item) => item.preparationStation,
      ),
      ['counter'],
    );
  });
}

ProviderContainer _container(_OrdersApi api) {
  final tokenStore = _MemoryTokenStore(
    const StoredTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      tenantSlug: 'pizza',
      sessionId: 1,
    ),
  );
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _FakeAdapter(api.handle);
  final apiClient = ApiClient(dio, tokenStore);

  return ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokenStore),
      apiClientProvider.overrideWithValue(apiClient),
      ordersRepositoryProvider.overrideWithValue(OrdersRepository(apiClient)),
    ],
  );
}

KitchenQueueState _currentState(ProviderContainer container) {
  return container.read(kitchenQueueProvider).valueOrNull!;
}

List<int> _visibleOrderIds(KitchenQueueState state) {
  return state.currentPageTickets.map((ticket) => ticket.order.id).toList();
}

List<int> _pageOrderIds(KitchenQueueState state, int page) {
  return state.pages[page].map((ticket) => ticket.order.id).toList();
}

List<int> _ids(int start, int end) {
  return [for (var id = start; id <= end; id++) id];
}

class _OrdersApi {
  List<Map<String, dynamic>> summaries = [];
  Map<int, Map<String, dynamic>> details = {};

  void setOrders(
    List<int> ids, {
    Map<int, String> statuses = const {},
    bool includeCounter = false,
  }) {
    summaries = [
      for (final id in ids)
        _summaryJson(
          id,
          status: statuses[id] ?? 'preparing',
        ),
    ];
    details = {
      for (final id in ids)
        id: _detailJson(
          id,
          status: statuses[id] ?? 'preparing',
          includeCounter: includeCounter,
        ),
    };
  }

  FutureOr<ResponseBody> handle(RequestOptions options) {
    if (options.method == 'GET' && options.path == ApiEndpoints.orders) {
      return _jsonResponse({
        'items': summaries,
        'total': summaries.length,
        'page': 1,
        'page_size': 100,
      });
    }

    if (options.method == 'GET' && options.path.startsWith('/orders/')) {
      final orderId = int.parse(options.path.split('/').last);
      final detail = details[orderId];
      if (detail == null) {
        return _jsonResponse(
          {'detail': 'Not found'},
          statusCode: 404,
        );
      }

      return _jsonResponse(detail);
    }

    return _jsonResponse(
      {'detail': 'Unexpected ${options.method} ${options.path}'},
      statusCode: 500,
    );
  }
}

Map<String, dynamic> _summaryJson(
  int id, {
  required String status,
}) {
  return {
    'id': id,
    'order_type': 'pickup',
    'status': status,
    'payment_status': 'paid',
    'source': 'customer',
    'total': 18,
    'delivery_fee': 0,
    'created_at': DateTime.utc(2026, 8, 17, 10, id - 100).toIso8601String(),
  };
}

Map<String, dynamic> _detailJson(
  int id, {
  required String status,
  required bool includeCounter,
}) {
  final preparationStatus = status == 'ready' ? 'ready' : 'preparing';
  return {
    ..._summaryJson(id, status: status),
    'items': [
      _itemJson(
        id: id * 10,
        station: 'kitchen',
        preparationStatus: preparationStatus,
      ),
      if (includeCounter)
        _itemJson(
          id: id * 10 + 1,
          station: 'counter',
          preparationStatus: preparationStatus,
        ),
    ],
    'station_summary': [],
    'status_history': [
      {
        'status': 'confirmed',
        'authority': 'staff',
        'created_at': DateTime.utc(2026, 8, 17, 10, id - 100).toIso8601String(),
      },
    ],
  };
}

Map<String, dynamic> _itemJson({
  required int id,
  required String station,
  required String preparationStatus,
}) {
  return {
    'id': id,
    'product_id': id,
    'quantity': 1,
    'unit_price': 1,
    'total': 1,
    'extras': [],
    'preparation_status': preparationStatus,
    'preparation_station': station,
    'product_name': '$station item',
  };
}

ResponseBody _jsonResponse(
  Map<String, dynamic> body, {
  int statusCode = 200,
}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore(this.tokens) : super(const FlutterSecureStorage());

  StoredTokens? tokens;

  @override
  Future<StoredTokens?> read() async => tokens;

  @override
  Future<String?> readAccessToken() async => tokens?.accessToken;

  @override
  Future<String?> readRefreshToken() async => tokens?.refreshToken;

  @override
  Future<String?> readTenantSlug() async => tokens?.tenantSlug;

  @override
  Future<void> write(StoredTokens tokens) async {
    this.tokens = tokens;
  }

  @override
  Future<void> clear() async {
    tokens = null;
  }
}

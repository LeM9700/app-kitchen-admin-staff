import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/dashboard/data/dashboard_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardRepository', () {
    test('liveStats hits admin/stats/live and parses the response', () async {
      late RequestOptions seen;
      final repository = DashboardRepository(
        _client((options) {
          seen = options;
          return _jsonResponse({
            'orders_last_24h': 12,
            'revenue_last_24h': '340.50',
            'avg_order_value_24h': '28.37',
            'pending_orders': 3,
            'computed_at': '2026-08-24T10:00:00Z',
          });
        }),
      );

      final stats = await repository.liveStats();

      expect(seen.path, ApiEndpoints.adminStatsLive);
      expect(stats.ordersLast24h, 12);
      expect(stats.revenueLast24h, 340.50);
      expect(stats.avgOrderValue24h, 28.37);
      expect(stats.pendingOrders, 3);
      expect(stats.computedAt, isNotNull);
    });

    test('summary hits admin/stats/summary and parses nested live + last_day',
        () async {
      late RequestOptions seen;
      final repository = DashboardRepository(
        _client((options) {
          seen = options;
          return _jsonResponse({
            'live': {
              'orders_last_24h': 5,
              'revenue_last_24h': '100.0',
              'avg_order_value_24h': '20.0',
              'pending_orders': 1,
            },
            'last_day': {
              'revenue': '99.5',
              'order_count': 4,
              'avg_basket': '24.87',
            },
          });
        }),
      );

      final summary = await repository.summary();

      expect(seen.path, ApiEndpoints.adminStatsSummary);
      expect(summary.live.ordersLast24h, 5);
      expect(summary.lastDayRevenue, 99.5);
      expect(summary.lastDayOrders, 4);
      expect(summary.lastDayAvgBasket, 24.87);
    });

    test('summary tolerates a missing last_day block', () async {
      final repository = DashboardRepository(
        _client(
          (_) => _jsonResponse({
            'live': {
              'orders_last_24h': 0,
              'revenue_last_24h': '0',
              'avg_order_value_24h': '0',
              'pending_orders': 0,
            },
          }),
        ),
      );

      final summary = await repository.summary();

      expect(summary.lastDayRevenue, isNull);
      expect(summary.lastDayOrders, isNull);
      expect(summary.lastDayAvgBasket, isNull);
    });

    test('daily hits admin/stats/daily and parses the list', () async {
      late RequestOptions seen;
      final repository = DashboardRepository(
        _client((options) {
          seen = options;
          return _jsonResponse([
            {
              'date': '2026-08-23',
              'revenue': '150.0',
              'order_count': 6,
              'avg_basket': '25.0',
            },
          ]);
        }),
      );

      final daily = await repository.daily();

      expect(seen.path, ApiEndpoints.adminStatsDaily);
      expect(daily, hasLength(1));
      expect(daily.first.date, '2026-08-23');
      expect(daily.first.orderCount, 6);
    });

    test('monthly hits admin/stats/monthly and parses the list', () async {
      late RequestOptions seen;
      final repository = DashboardRepository(
        _client((options) {
          seen = options;
          return _jsonResponse([
            {
              'year': '2026',
              'month': '08',
              'total_orders': 210,
              'total_revenue': '5400.0',
              'avg_order_value': '25.71',
            },
          ]);
        }),
      );

      final monthly = await repository.monthly();

      expect(seen.path, ApiEndpoints.adminStatsMonthly);
      expect(monthly, hasLength(1));
      expect(monthly.first.year, '2026');
      expect(monthly.first.totalOrders, 210);
    });

    test(
        'topProducts hits admin/stats/top-products with days/limit query params',
        () async {
      late RequestOptions seen;
      final repository = DashboardRepository(
        _client((options) {
          seen = options;
          return _jsonResponse([
            {
              'product_id': 7,
              'product_name': 'Margherita',
              'quantity': 42,
              'revenue': '588.0',
            },
          ]);
        }),
      );

      final top = await repository.topProducts(days: 14, limit: 5);

      expect(seen.path, ApiEndpoints.adminStatsTopProducts);
      expect(seen.queryParameters['days'], 14);
      expect(seen.queryParameters['limit'], 5);
      expect(top, hasLength(1));
      expect(top.first.productName, 'Margherita');
      expect(top.first.revenue, 588.0);
    });

    test('daily returns an empty list when the API sends null', () async {
      final repository = DashboardRepository(
        _client((_) => _jsonResponse(null)),
      );

      final daily = await repository.daily();

      expect(daily, isEmpty);
    });
  });
}

ApiClient _client(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _FakeAdapter(handler);
  return ApiClient(dio, _MemoryTokenStore());
}

ResponseBody _jsonResponse(
  Object? body, {
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
  _MemoryTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> readAccessToken() async => 'access';

  @override
  Future<String?> readRefreshToken() async => 'refresh';

  @override
  Future<String?> readTenantSlug() async => 'pizza';
}

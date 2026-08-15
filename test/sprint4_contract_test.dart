import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/catalog/data/catalog_repository.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('establishment context parses backend route and current selection',
      () async {
    late RequestOptions seenOptions;
    final repository = EstablishmentRepository(
      _client(
        (options) {
          seenOptions = options;
          return _jsonResponse([
            {
              'id': 1,
              'name': 'Centre',
              'timezone': 'Europe/Paris',
              'is_active': true,
            },
            {
              'id': 2,
              'name': 'Nord',
              'timezone': 'Europe/Paris',
              'is_active': true,
            },
          ]);
        },
      ),
    );

    final establishments = await repository.listEstablishments();

    expect(seenOptions.path, ApiEndpoints.tenantEstablishments);
    expect(establishments.map((item) => item.name), ['Centre', 'Nord']);

    final container = ProviderContainer(
      overrides: [
        availableEstablishmentsProvider.overrideWith(
          (ref) async => establishments,
        ),
      ],
    );
    addTearDown(container.dispose);

    expect((await container.read(currentEstablishmentProvider.future))?.id, 1);
    container.read(selectedEstablishmentIdProvider.notifier).state = 2;
    expect((await container.read(currentEstablishmentProvider.future))?.id, 2);
  });

  test('catalog repository uses real list filters and availability override',
      () async {
    final seen = <RequestOptions>[];
    final repository = CatalogRepository(
      _client(
        (options) {
          seen.add(options);
          if (options.path.endsWith('/availability-override')) {
            return _jsonResponse({'ok': true});
          }
          return _jsonResponse({
            'items': [
              {
                'id': 11,
                'name': 'Margherita',
                'base_price': 11.5,
                'is_active': true,
                'effective_preparation_station': 'kitchen',
                'availability': {'available': true},
              },
            ],
            'total': 1,
            'page': 1,
            'page_size': 100,
            'pages': 1,
          });
        },
      ),
    );

    final products = await repository.listProducts(
      pageSize: 100,
      query: 'marg',
      categoryId: 1,
    );
    await repository.setAvailabilityOverride(
      productId: 11,
      available: false,
      reason: 'Rupture mozzarella',
    );

    expect(seen.first.path, ApiEndpoints.catalogProducts);
    expect(seen.first.queryParameters['q'], 'marg');
    expect(seen.first.queryParameters['category_id'], 1);
    expect(products.single.name, 'Margherita');
    expect(seen.last.path, ApiEndpoints.productAvailabilityOverride(11));
    expect((seen.last.data as Map)['available'], false);
    expect((seen.last.data as Map)['reason'], 'Rupture mozzarella');
  });

  test('stock repository uses search, low filter and adjustment request route',
      () async {
    final seen = <RequestOptions>[];
    final repository = StockRepository(
      _client(
        (options) {
          seen.add(options);
          if (options.path == ApiEndpoints.stockAdjustmentRequests) {
            return _jsonResponse(
              {
                'id': 4,
                'ingredient_id': 2,
                'quantity_delta': -1.5,
                'reason': 'inventory',
                'status': 'pending',
                'requested_by_user_id': 10,
                'is_large_adjustment': false,
              },
              statusCode: 201,
            );
          }
          return _jsonResponse({
            'items': [
              {
                'id': 2,
                'name': 'Mozzarella',
                'unit': 'kg',
                'current_qty': 3,
                'alert_threshold': 5,
                'is_below_threshold': true,
              },
            ],
            'total': 1,
            'page': 1,
            'page_size': 100,
            'pages': 1,
          });
        },
      ),
    );

    final ingredients = await repository.listIngredients(
      pageSize: 100,
      search: 'moz',
      belowThreshold: true,
    );
    final request = await repository.createAdjustmentRequest(
      ingredientId: 2,
      quantityDelta: -1.5,
      reason: 'inventory',
      note: 'Comptage',
    );

    expect(seen.first.queryParameters['search'], 'moz');
    expect(seen.first.queryParameters['below_threshold'], true);
    expect(ingredients.single.isBelowThreshold, isTrue);
    expect(seen.last.path, ApiEndpoints.stockAdjustmentRequests);
    expect(request.status, 'pending');
  });

  test('payments repository uses status filter and refund contract', () async {
    final seen = <RequestOptions>[];
    final repository = PaymentsRepository(
      _client(
        (options) {
          seen.add(options);
          if (options.path.endsWith('/refund')) {
            return _jsonResponse({
              'id': 9,
              'order_id': 142,
              'amount': 1200,
              'status': 'succeeded',
              'created_at': '2026-08-10T12:00:00Z',
              'reason': 'Client',
            });
          }
          return _jsonResponse({
            'items': [
              {
                'id': 1,
                'order_id': 142,
                'provider': 'stripe',
                'amount': 36.5,
                'currency': 'eur',
                'status': 'paid',
                'refunded_amount_cents': 0,
                'created_at': '2026-08-10T12:00:00Z',
              },
            ],
            'total': 1,
            'page': 1,
            'page_size': 50,
            'pages': 1,
          });
        },
      ),
    );

    final payments = await repository.listPayments(status: 'paid');
    final refund = await repository.refund(
      orderId: 142,
      amountCents: 1200,
      reason: 'Client',
    );

    expect(seen.first.queryParameters['status'], 'paid');
    expect(payments.single.orderId, 142);
    expect(seen.last.path, ApiEndpoints.paymentRefund(142));
    expect((seen.last.data as Map)['amount'], 1200);
    expect(refund.amount, 1200);
  });

  test('settings repository patches preparation and closure routes', () async {
    final seen = <RequestOptions>[];
    final repository = TenantRepository(
      _client(
        (options) {
          seen.add(options);
          return _jsonResponse({
            'id': 1,
            'is_temporarily_closed': false,
            'default_closure_message': 'Ferme',
            'prep_time_normal_minutes': 20,
            'prep_time_peak_minutes': 35,
            'peak_orders_threshold': 8,
            'auto_calc_prep_time': true,
            'overhead_per_order_minutes': 3,
            'timezone': 'Europe/Paris',
            'large_stock_adjustment_threshold': 25,
            'print_enabled': true,
            'print_config': {},
          });
        },
      ),
      _MemoryTokenStore(),
    );

    final config = await repository.updatePreparationSettings(
      normalMinutes: 20,
      peakMinutes: 35,
      peakOrdersThreshold: 8,
      overheadPerOrderMinutes: 3,
      autoCalcPrepTime: true,
    );
    await repository.toggleClosure(closed: true, message: 'Rush pause');

    expect(seen.first.path, ApiEndpoints.tenantConfig);
    expect((seen.first.data as Map)['prep_time_peak_minutes'], 35);
    expect(config.prepTimePeakMinutes, 35);
    expect(seen.last.path, ApiEndpoints.tenantToggleClosure);
    expect((seen.last.data as Map)['is_temporarily_closed'], true);
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
  Object body, {
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

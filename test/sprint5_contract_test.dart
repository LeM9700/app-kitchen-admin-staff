import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/core/config/env.dart';
import 'package:app_admin_staff/core/config/stripe_connect_callbacks.dart';
import 'package:app_admin_staff/core/realtime/notification_bus.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/loyalty/data/loyalty_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/promotions/data/promotions_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('promotions list uses real admin filters and parses product fields',
      () async {
    late RequestOptions seen;
    final repository = PromotionsRepository(
      _client((options) {
        seen = options;
        return _jsonResponse({
          'items': [
            {
              'id': 1,
              'code': 'WELCOME20',
              'discount_type': 'percent',
              'discount_value': 20,
              'min_order_amount': 25,
              'starts_at': '2026-08-01T00:00:00Z',
              'ends_at': '2026-09-01T00:00:00Z',
              'is_active': true,
              'is_public': true,
              'is_stackable': true,
              'first_order_only': true,
              'email_verified_required': true,
              'max_uses': 100,
              'max_uses_per_user': 1,
              'current_uses': 12,
              'usage_count': 12,
              'unique_users': 11,
              'remaining_uses': 88,
              'revenue_gross': 400,
              'revenue_net': 360,
              'discount_total': 40,
              'targets': {
                'category_ids': [1],
                'product_ids': [2],
              },
            },
          ],
          'total': 1,
          'page': 1,
          'page_size': 20,
          'pages': 1,
        });
      }),
    );

    final items = await repository.listAdmin(
      pageSize: 20,
      code: 'wel',
      isActive: true,
    );

    expect(seen.path, ApiEndpoints.promotionsAdmin);
    expect(seen.queryParameters['code'], 'wel');
    expect(seen.queryParameters['is_active'], true);
    expect(items.single.maxUses, 100);
    expect(items.single.firstOrderOnly, isTrue);
    expect(items.single.hasTargets, isTrue);
    expect(items.single.revenueNet, 360);
  });

  test('promotion create, update and toggle send only real backend fields',
      () async {
    final seen = <RequestOptions>[];
    final repository = PromotionsRepository(
      _client((options) {
        seen.add(options);
        return _jsonResponse({
          'id': 1,
          'code': 'WELCOME20',
          'discount_type': 'percent',
          'discount_value': 20,
          'min_order_amount': 25,
          'is_active': true,
          'is_public': true,
        });
      }),
    );

    await repository.create(
      code: 'welcome20',
      discountType: 'percent',
      discountValue: 20,
      minOrderAmount: 25,
      isPublic: false,
      isStackable: true,
      firstOrderOnly: true,
      emailVerifiedRequired: true,
      maxUses: 100,
      maxUsesPerUser: 1,
      startsAt: DateTime.utc(2026, 8),
      endsAt: DateTime.utc(2026, 9),
    );
    await repository.update(
      promoId: 1,
      code: 'WELCOME20',
      discountType: 'fixed',
      discountValue: 5,
      minOrderAmount: 30,
      isPublic: true,
      isStackable: false,
      firstOrderOnly: false,
      emailVerifiedRequired: false,
      maxUses: 200,
      maxUsesPerUser: 2,
    );
    await repository.toggle(1, false);

    expect(seen[0].path, ApiEndpoints.promotions);
    expect((seen[0].data as Map)['first_order_only'], true);
    expect((seen[0].data as Map)['email_verified_required'], true);
    expect((seen[0].data as Map)['starts_at'], contains('2026-08-01'));
    expect(seen[1].path, ApiEndpoints.promotion(1));
    expect((seen[1].data as Map)['max_uses_per_user'], 2);
    expect(seen[2].path, ApiEndpoints.promotionToggle(1));
    expect((seen[2].data as Map)['is_active'], false);
  });

  test('promotion permission denied is surfaced as AppException', () async {
    final repository = PromotionsRepository(
      _client((options) {
        return _jsonResponse(
          {'code': 'FORBIDDEN', 'detail': 'Acces refuse'},
          statusCode: 403,
        );
      }),
    );

    await expectLater(
      repository.create(
        code: 'PIZZA10',
        discountType: 'percent',
        discountValue: 10,
      ),
      throwsA(isA<AppException>()),
    );
  });

  test('loyalty config, rules and rewards use the audited endpoints', () async {
    final seen = <RequestOptions>[];
    final repository = LoyaltyRepository(
      _client((options) {
        seen.add(options);
        if (options.path == ApiEndpoints.loyaltyConfig) {
          return _jsonResponse({
            'id': 1,
            'base_ratio': '1.5',
            'points_expiry_days': 365,
            'points_to_euro_rate': '0.02',
            'max_cumulative_multiplier': '3.0',
            'is_active': true,
            'updated_at': '2026-08-01T00:00:00Z',
          });
        }
        if (options.path == ApiEndpoints.loyaltyRules) {
          return _jsonResponse([
            {
              'id': 1,
              'name': 'Premier achat',
              'rule_type': 'first_order',
              'category_id': null,
              'multiplier': '2',
              'priority': 1,
              'is_active': true,
              'created_at': '2026-08-01T00:00:00Z',
            },
          ]);
        }
        return _jsonResponse([
          {
            'id': 1,
            'name': '5 EUR',
            'reward_type': 'discount_euros',
            'points_required': 250,
            'discount_amount': '5',
            'product_id': null,
            'is_active': true,
            'created_at': '2026-08-01T00:00:00Z',
            'can_redeem': false,
            'missing_points': 20,
          },
        ]);
      }),
    );

    final config = await repository.updateConfig(
      baseRatio: 1.5,
      pointsExpiryDays: 365,
      pointsToEuroRate: 0.02,
      maxCumulativeMultiplier: 3,
      isActive: true,
    );
    final rules = await repository.rules();
    final rewards = await repository.rewards();

    expect(seen[0].path, ApiEndpoints.loyaltyConfig);
    expect((seen[0].data as Map)['points_expiry_days'], 365);
    expect(seen[1].path, ApiEndpoints.loyaltyRules);
    expect(seen[2].path, ApiEndpoints.loyaltyRewards);
    expect(config.baseRatio, 1.5);
    expect(rules.single.ruleType, 'first_order');
    expect(rewards.single.pointsRequired, 250);
  });

  test('delivery create and update require GeoJSON and do not send is_active',
      () async {
    final seen = <RequestOptions>[];
    final repository = DeliveryRepository(
      _client((options) {
        seen.add(options);
        return _jsonResponse({
          'id': 1,
          'name': 'Centre',
          'fee': 3.5,
          'min_order_amount': 18,
          'estimated_minutes': 25,
          'is_active': true,
        });
      }),
      _MemoryTokenStore(),
    );
    const draft = DeliveryZoneDraft(
      name: 'Centre',
      fee: 3.5,
      minOrderAmount: 18,
      estimatedMinutes: 25,
      polygon: {
        'type': 'Polygon',
        'coordinates': [
          [
            [2.0, 48.0],
            [2.1, 48.0],
            [2.1, 48.1],
            [2.0, 48.0],
          ],
        ],
      },
    );

    await repository.createZone(draft);
    await repository.updateZone(1, draft);

    expect(seen[0].path, ApiEndpoints.deliveryZones);
    expect((seen[0].data as Map).containsKey('polygon'), isTrue);
    expect((seen[0].data as Map).containsKey('is_active'), isFalse);
    expect(seen[1].path, ApiEndpoints.deliveryZone(1));
    expect((seen[1].data as Map).containsKey('is_active'), isFalse);
  });

  test('delivery zone parses optional GeoJSON presence', () {
    final exposed = DeliveryZone.fromJson({
      'id': 1,
      'name': 'Centre',
      'fee': 3.5,
      'min_order_amount': 18,
      'estimated_minutes': 25,
      'is_active': true,
      'polygon': {'type': 'Polygon', 'coordinates': []},
    });
    final hidden = DeliveryZone.fromJson({
      'id': 2,
      'name': 'Nord',
      'fee': 4.5,
      'min_order_amount': 22,
      'estimated_minutes': 35,
      'is_active': false,
    });

    expect(exposed.hasGeoJson, isTrue);
    expect(hidden.hasGeoJson, isFalse);
    expect(hidden.isActive, isFalse);
  });

  test('Stripe Connect callbacks are configurable and reject example.com prod',
      () {
    const valid = StripeConnectCallbackConfig(
      environment: 'production',
      returnUrl: 'https://admin.apikitchen.test/stripe/connect/return',
      refreshUrl: 'https://admin.apikitchen.test/stripe/connect/refresh',
    );
    const invalid = StripeConnectCallbackConfig(
      environment: 'production',
      returnUrl: 'https://example.com/stripe/return',
      refreshUrl: 'https://admin.apikitchen.test/stripe/connect/refresh',
    );

    expect(valid.validated().returnUrl, contains('/stripe/connect/return'));
    expect(invalid.validated, throwsStateError);
    expect(
      StripeConnectCallbackConfig.fromEnvironment().returnUrl,
      isNot(contains('example.com')),
    );
    expect(
      () => Env.validateStartupConfig(stripeConnectCallbacks: invalid),
      throwsStateError,
    );
  });

  test('Connect onboarding posts configured return and refresh URLs', () async {
    late RequestOptions seen;
    final repository = PaymentsRepository(
      _client((options) {
        seen = options;
        return _jsonResponse({
          'url': 'https://connect.stripe.test/onboarding',
          'stripe_account_id': 'acct_123',
        });
      }),
    );

    await repository.startConnectOnboarding(
      returnUrl: 'https://admin.apikitchen.test/stripe/connect/return',
      refreshUrl: 'https://admin.apikitchen.test/stripe/connect/refresh',
    );

    expect(seen.path, ApiEndpoints.connectOnboarding);
    expect((seen.data as Map)['return_url'], contains('/return'));
    expect((seen.data as Map)['refresh_url'], contains('/refresh'));
  });

  test('realtime router supports audited events and sanitizes security data',
      () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final bus = container.read(notificationBusProvider.notifier);
    expect(container.read(notificationBusProvider), isEmpty);

    bus.route({'type': 'notification', 'event': 'unknown.event'});
    expect(container.read(notificationBusProvider), isEmpty);

    bus.route({
      'type': 'notification',
      'event': 'loyalty.points_expiring',
      'title': 'Points',
      'data': {'token': 'secret-token', 'points': 20},
    });
    bus.route({
      'type': 'notification',
      'event': 'security_alert',
      'title': 'Bearer abc.def',
      'body': 'token=abc',
      'data': {'api_key': 'sk_test', 'tenant_slug': 'pizza'},
    });
    bus.route({'type': 'notification', 'event': 'allergen_update'});

    final notifications = container.read(notificationBusProvider);
    expect(notifications, hasLength(3));
    expect(notifications[0].event, 'allergen_update');
    expect(notifications[1].title, 'Alerte securite');
    expect(notifications[1].body, isNull);
    expect(notifications[1].data['api_key'], '[redacted]');
    expect(notifications[2].data['token'], '[redacted]');
  });

  test('notification bus deduplicates notification ids', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final bus = container.read(notificationBusProvider.notifier);

    final payload = {
      'type': 'notification',
      'event': 'order.ready',
      'title': 'Commande prete',
      'data': {'order_id': 7, 'notification_id': 'notif-7'},
    };

    bus.route(payload);
    bus.route(payload);

    final notifications = container.read(notificationBusProvider);
    expect(notifications, hasLength(1));
    expect(notifications.single.notificationId, 'notif-7');
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

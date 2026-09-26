import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/loyalty/data/loyalty_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('searchStaffCustomers appelle la recherche staff masquee', () async {
    RequestOptions? request;
    final repo = LoyaltyRepository(
      _client((options) {
        request = options;
        expect(options.method, 'GET');
        expect(options.path, ApiEndpoints.loyaltyStaffCustomerSearch);
        return _jsonResponse({
          'items': [_customerJson()],
        });
      }),
    );

    final customers = await repo.searchStaffCustomers('0600');

    expect(request?.queryParameters['q'], '0600');
    expect(request?.queryParameters['limit'], 10);
    expect(customers.single.fullName, 'Ada Lovelace');
    expect(customers.single.maskedPhone, '+33******0000');
  });

  test('identifyQr envoie uniquement le token QR', () async {
    RequestOptions? request;
    final repo = LoyaltyRepository(
      _client((options) {
        request = options;
        expect(options.method, 'POST');
        expect(options.path, ApiEndpoints.loyaltyStaffIdentifyQr);
        return _jsonResponse(_walletJson());
      }),
    );

    final wallet = await repo.identifyQr('signed.qr.token');

    expect(request?.data, {'token': 'signed.qr.token'});
    expect(wallet.customer.availablePoints, 140);
    expect(wallet.rewards.single.name, 'Pizza offerte');
  });

  test('createStaffCustomer cree le client caisse sans email obligatoire',
      () async {
    RequestOptions? request;
    final repo = LoyaltyRepository(
      _client((options) {
        request = options;
        expect(options.method, 'POST');
        expect(options.path, ApiEndpoints.loyaltyStaffCustomers);
        return _jsonResponse(_walletJson());
      }),
    );

    await repo.createStaffCustomer(
      phone: '0600000000',
      firstName: 'Ada',
      lastName: 'Lovelace',
    );

    expect(request?.data, {
      'phone': '0600000000',
      'first_name': 'Ada',
      'last_name': 'Lovelace',
    });
  });

  test('audit lit le journal admin filtre sur les actions fidelite', () async {
    RequestOptions? request;
    final repo = LoyaltyRepository(
      _client((options) {
        request = options;
        expect(options.method, 'GET');
        expect(options.path, ApiEndpoints.adminCustomerAudit);
        return _jsonResponse({
          'items': [
            {
              'id': 3,
              'actor_user_id': 9,
              'actor_email': 'staff@example.com',
              'action': 'loyalty_staff_reward_applied',
              'target_type': 'customer',
              'target_id': '42',
              'metadata_json': {
                'customer_id': 42,
                'order_id': 88,
                'loyalty_identification_method': 'qr',
                'loyalty_oral_confirmed': true,
              },
              'created_at': '2026-09-26T10:00:00Z',
            },
          ],
          'total': 1,
          'page': 1,
          'page_size': 20,
          'pages': 1,
        });
      }),
    );

    final entries = await repo.audit();

    expect(request?.queryParameters['loyalty_only'], isTrue);
    expect(request?.queryParameters['page_size'], 20);
    expect(entries.single.action, 'loyalty_staff_reward_applied');
    expect(entries.single.metadata['loyalty_identification_method'], 'qr');
    expect(entries.single.actorEmail, 'staff@example.com');
  });
}

Map<String, dynamic> _walletJson() {
  return {
    'customer': _customerJson(),
    'rewards': [
      {
        'id': 7,
        'name': 'Pizza offerte',
        'reward_type': 'free_product',
        'points_required': 100,
        'discount_amount': null,
        'product_id': 3,
        'is_active': true,
      },
    ],
  };
}

Map<String, dynamic> _customerJson() {
  return {
    'id': 42,
    'full_name': 'Ada Lovelace',
    'masked_phone': '+33******0000',
    'phone_last4': '0000',
    'points': 140,
    'available_points': 140,
    'phone_verified': true,
    'pending_profile_completion': false,
  };
}

ApiClient _client(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _FakeAdapter(handler);
  return ApiClient(dio, _MemoryTokenStore());
}

ResponseBody _jsonResponse(Object? body, {int statusCode = 200}) {
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

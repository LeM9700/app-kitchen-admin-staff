import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concurrent 401 responses share one refresh request and retry once',
      () async {
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    var refreshCalls = 0;
    var protectedCalls = 0;
    final tokenStore = _MemoryTokenStore(
      const StoredTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        tenantSlug: 'pizza-test',
        sessionId: 1,
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    dio.httpClientAdapter = _FakeAdapter((options) async {
      if (options.path == ApiEndpoints.authRefresh) {
        refreshCalls++;
        if (!refreshStarted.isCompleted) {
          refreshStarted.complete();
        }
        await releaseRefresh.future;
        return _jsonResponse({
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
          'session_id': 2,
        });
      }

      protectedCalls++;
      if (options.headers['Authorization'] == 'Bearer old-access') {
        return _jsonResponse({'code': 'UNAUTHORIZED'}, statusCode: 401);
      }
      return _jsonResponse({'ok': true});
    });
    final client = ApiClient(dio, tokenStore);

    final requests = [
      client.get('/protected'),
      client.get('/protected'),
      client.get('/protected'),
    ];
    await refreshStarted.future;
    releaseRefresh.complete();

    final responses = await Future.wait(requests);

    expect(responses, hasLength(3));
    expect(responses.every((response) => response.data['ok'] == true), isTrue);
    expect(refreshCalls, 1);
    expect(protectedCalls, 6);
    expect(tokenStore.tokens?.accessToken, 'new-access');
    expect(tokenStore.tokens?.refreshToken, 'new-refresh');
    expect(tokenStore.tokens?.sessionId, 2);
  });

  test('refresh failure clears tokens and notifies session invalidation',
      () async {
    var invalidations = 0;
    final tokenStore = _MemoryTokenStore(
      const StoredTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        tenantSlug: 'pizza-test',
        sessionId: 1,
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    dio.httpClientAdapter = _FakeAdapter((options) {
      if (options.path == ApiEndpoints.authRefresh) {
        return _jsonResponse({'code': 'INVALID_TOKEN'}, statusCode: 401);
      }
      return _jsonResponse({'code': 'UNAUTHORIZED'}, statusCode: 401);
    });
    final client = ApiClient(
      dio,
      tokenStore,
      onSessionExpired: () {
        invalidations++;
      },
    );

    await expectLater(client.get('/protected'), throwsA(isA<AppException>()));

    expect(tokenStore.tokens, isNull);
    expect(invalidations, 1);
  });

  test('retry is attempted only once after refresh', () async {
    var refreshCalls = 0;
    var protectedCalls = 0;
    final tokenStore = _MemoryTokenStore(
      const StoredTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        tenantSlug: 'pizza-test',
        sessionId: 1,
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    dio.httpClientAdapter = _FakeAdapter((options) {
      if (options.path == ApiEndpoints.authRefresh) {
        refreshCalls++;
        return _jsonResponse({
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
          'session_id': 2,
        });
      }
      protectedCalls++;
      return _jsonResponse({'code': 'UNAUTHORIZED'}, statusCode: 401);
    });
    final client = ApiClient(dio, tokenStore);

    await expectLater(client.get('/protected'), throwsA(isA<AppException>()));

    expect(refreshCalls, 1);
    expect(protectedCalls, 2);
  });

  test('request id and idempotency key are sent per request', () async {
    late Map<String, dynamic> seenHeaders;
    final tokenStore = _MemoryTokenStore(
      const StoredTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        tenantSlug: 'pizza-test',
        sessionId: 1,
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    dio.httpClientAdapter = _FakeAdapter((options) {
      seenHeaders = Map<String, dynamic>.from(options.headers);
      return _jsonResponse({'ok': true});
    });
    final client = ApiClient(dio, tokenStore);

    await client.post(
      '/orders/manual',
      data: const {},
      idempotencyKey: 'manual-1',
    );

    expect(seenHeaders['Authorization'], 'Bearer access');
    expect(seenHeaders['Idempotency-Key'], 'manual-1');
    expect(seenHeaders['X-Request-ID'], isNotNull);
    expect(seenHeaders.containsKey('X-Tenant-Slug'), isFalse);
  });
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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/auth/data/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bootstrap without tokens is unauthenticated', () async {
    final container = _container(
      _MemoryTokenStore(null),
      _FakeAdapter(
        (_) => _jsonResponse({'unexpected': true}),
      ),
    );
    addTearDown(container.dispose);

    final state = await container.read(sessionControllerProvider.future);

    expect(state.status, SessionStatus.unauthenticated);
  });

  test('bootstrap with valid token hydrates /auth/me', () async {
    final store = _MemoryTokenStore(
      StoredTokens(
        accessToken: _jwt({'sub': 1, 'role': 'admin', 'tenant_slug': 'pizza'}),
        refreshToken: 'refresh',
        tenantSlug: 'pizza',
        sessionId: 7,
      ),
    );
    final container = _container(
      store,
      _FakeAdapter((options) {
        expect(options.path, ApiEndpoints.authMe);
        return _jsonResponse({
          'id': 1,
          'email': 'admin@test.com',
          'full_name': 'Admin',
          'phone': null,
          'role': 'admin',
          'permissions': null,
          'is_active': true,
          'email_verified': true,
          'must_change_password': false,
        });
      }),
    );
    addTearDown(container.dispose);

    final state = await container.read(sessionControllerProvider.future);

    expect(state.status, SessionStatus.authenticated);
    expect(state.user?.email, 'admin@test.com');
    expect(state.sessionId, 7);
  });

  test('bootstrap maps PASSWORD_CHANGE_REQUIRED to mustChangePassword',
      () async {
    final store = _MemoryTokenStore(
      StoredTokens(
        accessToken: _jwt({
          'sub': 2,
          'email': 'staff@test.com',
          'role': 'staff',
          'tenant_slug': 'pizza',
          'must_change_password': true,
        }),
        refreshToken: 'refresh',
        tenantSlug: 'pizza',
        sessionId: 8,
      ),
    );
    final container = _container(
      store,
      _FakeAdapter((_) {
        return _jsonResponse(
          {
            'code': 'PASSWORD_CHANGE_REQUIRED',
            'detail': 'Change password',
          },
          statusCode: 403,
        );
      }),
    );
    addTearDown(container.dispose);

    final state = await container.read(sessionControllerProvider.future);

    expect(state.status, SessionStatus.mustChangePassword);
    expect(state.user?.mustChangePassword, isTrue);
  });

  test('login maps MFA_REQUIRED to mfaRequired', () async {
    final store = _MemoryTokenStore(null);
    final container = _container(
      store,
      _FakeAdapter((_) {
        return _jsonResponse(
          {'code': 'MFA_REQUIRED', 'detail': 'MFA code required'},
          statusCode: 401,
        );
      }),
    );
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.future);

    await container.read(sessionControllerProvider.notifier).login(
          tenantSlug: 'pizza',
          email: 'admin@test.com',
          password: 'Secret1!',
        );

    final state = container.read(sessionControllerProvider).valueOrNull;
    expect(state?.status, SessionStatus.mfaRequired);
    expect(state?.mfaChallenge?.password, 'Secret1!');
  });

  test('submitMfa keeps challenge on INVALID_MFA_CODE', () async {
    var calls = 0;
    final store = _MemoryTokenStore(null);
    final container = _container(
      store,
      _FakeAdapter((_) {
        calls++;
        return _jsonResponse(
          {
            'code': calls == 1 ? 'MFA_REQUIRED' : 'INVALID_MFA_CODE',
            'detail': calls == 1 ? 'MFA code required' : 'Invalid MFA code',
          },
          statusCode: 401,
        );
      }),
    );
    addTearDown(container.dispose);
    await container.read(sessionControllerProvider.future);

    await container.read(sessionControllerProvider.notifier).login(
          tenantSlug: 'pizza',
          email: 'admin@test.com',
          password: 'Secret1!',
        );
    await container
        .read(sessionControllerProvider.notifier)
        .submitMfa('000000');

    final state = container.read(sessionControllerProvider).valueOrNull;
    expect(state?.status, SessionStatus.mfaRequired);
    expect(state?.error, contains('Invalid'));
  });

  test('bootstrap becomes sessionExpired when refresh is invalid', () async {
    final store = _MemoryTokenStore(
      StoredTokens(
        accessToken: _jwt({'sub': 1, 'role': 'admin', 'tenant_slug': 'pizza'}),
        refreshToken: 'bad-refresh',
        tenantSlug: 'pizza',
        sessionId: 1,
      ),
    );
    final container = _container(
      store,
      _FakeAdapter((options) {
        return _jsonResponse(
          {'code': 'UNAUTHORIZED', 'detail': options.path},
          statusCode: 401,
        );
      }),
    );
    addTearDown(container.dispose);

    final state = await container.read(sessionControllerProvider.future);

    expect(state.status, SessionStatus.sessionExpired);
    expect(store.tokens, isNull);
  });
}

ProviderContainer _container(
  _MemoryTokenStore tokenStore,
  HttpClientAdapter adapter,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = adapter;
  final apiClient = ApiClient(dio, tokenStore);
  return ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokenStore),
      apiClientProvider.overrideWithValue(apiClient),
      authRepositoryProvider.overrideWithValue(AuthRepository(apiClient)),
    ],
  );
}

String _jwt(Map<String, dynamic> payload) {
  String encode(Map<String, dynamic> value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${encode({'alg': 'none'})}.${encode(payload)}.sig';
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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('list screens parse correctement la reponse backend', () async {
    late RequestOptions seenOptions;
    final repository = _repository((options) {
      seenOptions = options;
      return _jsonResponse([
        _screenJson(
          id: 12,
          name: 'Cuisine principale',
          screenKey: 'kitchen-main',
          mode: 'kitchen',
          station: 'hot',
          interactionMode: 'wall',
          ticketsPerPage: 6,
        ),
      ]);
    });

    final screens = await repository.listScreens();

    expect(seenOptions.path, ApiEndpoints.kdsScreens);
    expect(screens.single.id, 12);
    expect(screens.single.name, 'Cuisine principale');
    expect(screens.single.screenKey, 'kitchen-main');
    expect(screens.single.station, 'hot');
    expect(screens.single.ticketsPerPage, 6);
  });

  test('pair envoie le code string avec zeros initiaux et parse le token',
      () async {
    late Map<String, dynamic> body;
    final repository = _repository((options) {
      body = Map<String, dynamic>.from(options.data as Map);
      return _jsonResponse({
        'session_token': 'remote-token',
        'expires_at': '2026-08-18T16:00:00Z',
        'screen': _screenJson(id: 12, name: 'Cuisine principale'),
      });
    });

    final result = await repository.pair(
      code: '004281',
      deviceLabel: 'Kitchen Remote',
    );

    expect(body['code'], '004281');
    expect(body['device_label'], 'Kitchen Remote');
    expect(result.sessionToken, 'remote-token');
    expect(result.screen.id, 12);
  });

  test('get remote session envoie X-KDS-Session sans query token', () async {
    late RequestOptions seenOptions;
    final repository = _repository((options) {
      seenOptions = options;
      return _jsonResponse({
        'id': 44,
        'screen_id': 12,
        'paired_by_user_id': 7,
        'device_label': 'Kitchen Remote',
        'created_at': '2026-08-18T10:00:00Z',
        'last_seen_at': '2026-08-18T10:05:00Z',
        'expires_at': '2026-08-18T22:00:00Z',
        'screen': _screenJson(id: 12, name: 'Comptoir', mode: 'counter'),
      });
    });

    final status = await repository.getRemoteSession(
      sessionToken: 'secret-token',
    );

    expect(seenOptions.path, ApiEndpoints.kdsRemoteSession);
    expect(seenOptions.headers['X-KDS-Session'], 'secret-token');
    expect(seenOptions.queryParameters.values, isNot(contains('secret-token')));
    expect(seenOptions.uri.toString(), isNot(contains('secret-token')));
    expect(status.id, 44);
    expect(status.screen.name, 'Comptoir');
  });

  test('revoke envoie X-KDS-Session sans query token', () async {
    late RequestOptions seenOptions;
    final repository = _repository((options) {
      seenOptions = options;
      return _jsonResponse({'revoked': true});
    });

    await repository.revokeRemoteSession(sessionToken: 'secret-token');

    expect(seenOptions.path, ApiEndpoints.kdsRemoteSessionRevoke);
    expect(seenOptions.headers['X-KDS-Session'], 'secret-token');
    expect(seenOptions.queryParameters.values, isNot(contains('secret-token')));
    expect(seenOptions.uri.toString(), isNot(contains('secret-token')));
  });
}

KdsRepository _repository(
  FutureOr<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _FakeAdapter(handler);
  return KdsRepository(
    ApiClient(
      dio,
      _MemoryTokenStore(),
    ),
  );
}

Map<String, dynamic> _screenJson({
  int id = 1,
  String name = 'Cuisine',
  String screenKey = 'kitchen',
  String mode = 'kitchen',
  String station = 'kitchen',
  String interactionMode = 'wall',
  int ticketsPerPage = 4,
  bool isActive = true,
}) {
  return {
    'id': id,
    'name': name,
    'screen_key': screenKey,
    'mode': mode,
    'station': station,
    'interaction_mode': interactionMode,
    'tickets_per_page': ticketsPerPage,
    'is_active': isActive,
  };
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

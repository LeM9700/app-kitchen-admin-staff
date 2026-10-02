import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/delivery/presentation/delivery_map.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reponse HTTP simulee avec un statut explicite.
class FakeResponse {
  const FakeResponse(this.status, this.body);

  final int status;
  final Object? body;
}

/// Faux backend : repond aux routes declarees, enregistre toutes les requetes, et echoue
/// bruyamment sur une route inattendue (jamais de requete silencieuse).
class FakeBackend {
  final requests = <RequestOptions>[];
  final _routes = <String, Object? Function(RequestOptions)>{};

  void on(
    String method,
    String path,
    Object? Function(RequestOptions) responder,
  ) {
    _routes['$method $path'] = responder;
  }

  void onJson(String method, String path, Object? body, {int status = 200}) {
    on(method, path, (_) => FakeResponse(status, body));
  }

  List<RequestOptions> where(String method, String path) =>
      requests.where((r) => r.method == method && r.path == path).toList();

  Map<String, dynamic> bodyOf(RequestOptions options) =>
      Map<String, dynamic>.from(options.data as Map);

  ApiClient client() {
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
    dio.httpClientAdapter = _Adapter(this);
    return ApiClient(dio, MemoryTokenStore());
  }

  ResponseBody _handle(RequestOptions options) {
    requests.add(options);
    final responder = _routes['${options.method} ${options.path}'];
    if (responder == null) {
      throw StateError('requete inattendue ${options.method} ${options.path}');
    }
    final result = responder(options);
    final response =
        result is FakeResponse ? result : FakeResponse(200, result);
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this._backend);

  final FakeBackend _backend;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      _backend._handle(options);

  @override
  void close({bool force = false}) {}
}

class MemoryTokenStore extends TokenStore {
  MemoryTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> readAccessToken() async => 'access';

  @override
  Future<String?> readRefreshToken() async => 'refresh';

  @override
  Future<String?> readTenantSlug() async => 'pizza';
}

class FakeSession extends SessionController {
  FakeSession(this.role);

  final String role;

  @override
  Future<SessionState> build() async {
    return SessionState.authenticated(
      user: StaffUser(
        id: 1,
        email: '$role@test.com',
        role: role,
        tenantSlug: 'pizza',
        permissions: null,
        mustChangePassword: false,
      ),
      tenantSlug: 'pizza',
      sessionId: 1,
    );
  }
}

// ------------------------------------------------------------------ donnees

const belgrade = {'latitude': 44.7866, 'longitude': 20.4489};

Map<String, dynamic> establishmentJson({
  int id = 1,
  String name = 'Centre',
  bool withLocation = true,
}) {
  return {
    'id': id,
    'name': name,
    'timezone': 'Europe/Belgrade',
    'is_active': true,
    if (withLocation) ...belgrade,
  };
}

/// Carre ferme de ~2 km de cote autour de Belgrade, en GeoJSON [lng, lat].
Map<String, dynamic> squareGeoJson() {
  const lat = 44.7866;
  const lng = 20.4489;
  const d = 0.01;
  return {
    'type': 'Polygon',
    'coordinates': [
      [
        [lng - d, lat - d],
        [lng + d, lat - d],
        [lng + d, lat + d],
        [lng - d, lat + d],
        [lng - d, lat - d],
      ],
    ],
  };
}

Map<String, dynamic> zoneJson({
  required int id,
  required String name,
  bool isActive = true,
  String shapeKind = 'circle',
  Map<String, dynamic>? shapeParams,
  List<Map<String, dynamic>> rules = const [],
  int? establishmentId = 1,
}) {
  return {
    'id': id,
    'name': name,
    'establishment_id': establishmentId,
    'fee': 3.5,
    'min_order_amount': 15.0,
    'estimated_minutes': 30,
    'is_active': isActive,
    'polygon': squareGeoJson(),
    'shape_kind': shapeKind,
    'shape_params': shapeParams ??
        (shapeKind == 'circle'
            ? {'center_lat': 44.7866, 'center_lng': 20.4489, 'radius_m': 2500}
            : null),
    'area_km2': 4.0,
    'rules': rules,
  };
}

/// Backend avec les routes de la page Livraison deja declarees.
FakeBackend deliveryBackend({
  List<Map<String, dynamic>> zones = const [],
  List<Map<String, dynamic>>? establishments,
  bool deliveryEnabled = true,
  int settingsVersion = 1,
}) {
  final backend = FakeBackend()
    ..onJson('GET', '/delivery/zones/manage', zones)
    ..onJson('GET', '/delivery/settings', {
      'internal_enabled': deliveryEnabled,
      'version': settingsVersion,
    })
    ..onJson(
      'GET',
      '/tenant/establishments',
      establishments ?? [establishmentJson()],
    );
  return backend;
}

/// Couche de tuiles factice qui remplit la carte : sans elle la carte n'a aucune zone cliquable.
const fakeTileLayer =
    ColoredBox(color: Color(0xFFEEEEEE), child: SizedBox.expand());

List<Override> deliveryOverrides(
  FakeBackend backend, {
  String role = 'admin',
}) =>
    [
      apiClientProvider.overrideWithValue(backend.client()),
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      sessionControllerProvider.overrideWith(() => FakeSession(role)),
      deliveryTileLayerProvider.overrideWithValue(fakeTileLayer),
    ];

/// Tape au centre d'une carte (flutter_map attend la fin du delai de double-tap).
Future<void> tapMapAt(
  WidgetTester tester,
  Finder map, {
  Offset offset = Offset.zero,
}) async {
  await tester.tapAt(tester.getCenter(map) + offset);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

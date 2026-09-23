import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/delivery/presentation/delivery_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const _validGeoJson = '{"type":"Polygon","coordinates":[[[2.3,48.8],'
    '[2.4,48.8],[2.4,48.9],[2.3,48.9],[2.3,48.8]]]}';

void main() {
  group('DeliveryPage — editeur de zone', () {
    testWidgets('creation avec polygone GeoJSON valide envoie le POST attendu',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.deliveryZones) {
          return _jsonResponse(<Object?>[]);
        }
        if (options.method == 'POST' &&
            options.path == ApiEndpoints.deliveryZones) {
          return _jsonResponse(_zoneJson(id: 1, name: 'Centre-ville'));
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path}',
        );
      });

      await _pumpDeliveryPage(tester, api);

      await tester.tap(find.text('Nouvelle zone'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Nom').hitTestable(),
        'Centre-ville',
      );
      await tester.enterText(find.byType(TextField).at(1), '3.5');
      await tester.enterText(find.byType(TextField).at(2), '15');
      await tester.enterText(find.byType(TextField).at(3), '30');
      await tester.enterText(find.byType(TextField).at(4), _validGeoJson);

      await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
      await tester.pumpAndSettle();

      final created = requests
          .where(
            (r) => r.method == 'POST' && r.path == ApiEndpoints.deliveryZones,
          )
          .toList();
      expect(created, hasLength(1));
      final body = created.single.data as Map;
      expect(body['name'], 'Centre-ville');
      expect(body['fee'], 3.5);
      expect(body['min_order_amount'], 15.0);
      expect(body['estimated_minutes'], 30);
      expect(body['polygon']['type'], 'Polygon');
      expect(body.containsKey('is_active'), isFalse);
      expect(find.text('Zone creee'), findsOneWidget);
    });

    testWidgets(
        'polygone GeoJSON manquant ou invalide bloque la creation cote client',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.deliveryZones) {
          return _jsonResponse(<Object?>[]);
        }
        throw StateError(
          'une zone sans polygone valide ne doit jamais etre postee '
          '(${options.method} ${options.path})',
        );
      });

      await _pumpDeliveryPage(tester, api);

      await tester.tap(find.text('Nouvelle zone'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Zone test');
      await tester.enterText(find.byType(TextField).at(1), '3.5');
      await tester.enterText(find.byType(TextField).at(2), '15');
      await tester.enterText(find.byType(TextField).at(3), '30');
      // Ni GeoJSON valide, ni meme un JSON parsable.
      await tester.enterText(find.byType(TextField).at(4), 'pas du json');

      await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
      await tester.pumpAndSettle();

      expect(find.text('Polygone GeoJSON obligatoire'), findsOneWidget);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    });

    testWidgets('modification envoie un PUT sans champ is_active',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.deliveryZones) {
          return _jsonResponse([_zoneJson(id: 7, name: 'Nord')]);
        }
        if (options.method == 'PUT' &&
            options.path == ApiEndpoints.deliveryZone(7)) {
          return _jsonResponse(_zoneJson(id: 7, name: 'Nord etendu'));
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path}',
        );
      });

      await _pumpDeliveryPage(tester, api);

      await tester.tap(find.byTooltip('Modifier'));
      await tester.pumpAndSettle();

      expect(find.text('Modifier Nord'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Nord etendu');
      await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
      await tester.pumpAndSettle();

      final updated = requests
          .where(
            (r) => r.method == 'PUT' && r.path == ApiEndpoints.deliveryZone(7),
          )
          .toList();
      expect(updated, hasLength(1));
      expect(updated.single.data['name'], 'Nord etendu');
      expect((updated.single.data as Map).containsKey('is_active'), isFalse);
      expect(find.text('Zone mise a jour'), findsOneWidget);
    });
  });
}

// ─── Helpers ────────────────────────────────────────────────────────────────

Future<void> _pumpDeliveryPage(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(_MemoryTokenStore()),
        sessionControllerProvider.overrideWith(_AdminSessionController.new),
      ],
      child: const MaterialApp(home: Scaffold(body: DeliveryPage())),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _zoneJson({
  required int id,
  required String name,
  bool isActive = true,
}) {
  return {
    'id': id,
    'name': name,
    'fee': 3.5,
    'min_order_amount': 15.0,
    'estimated_minutes': 30,
    'is_active': isActive,
    'polygon': jsonDecode(_validGeoJson),
  };
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

class _AdminSessionController extends SessionController {
  @override
  Future<SessionState> build() async {
    return const SessionState.authenticated(
      user: StaffUser(
        id: 1,
        email: 'admin@test.com',
        role: 'admin',
        tenantSlug: 'pizza',
        permissions: null,
        mustChangePassword: false,
      ),
      tenantSlug: 'pizza',
      sessionId: 1,
    );
  }
}

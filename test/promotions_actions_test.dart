import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/promotions/presentation/promotions_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PromotionsPage — actions admin', () {
    testWidgets('desactiver via le Switch appelle toggle(false) et confirme',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.promotionsAdmin) {
          return _jsonResponse(_paginatedPromotions());
        }
        if (options.method == 'POST' &&
            options.path == ApiEndpoints.promotionToggle(11)) {
          return _jsonResponse(_promoJson(id: 11, isActive: false));
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path}',
        );
      });

      await _pumpPromotionsPage(tester, api);

      expect(find.byType(Switch), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final toggles = requests
          .where((r) => r.path == ApiEndpoints.promotionToggle(11))
          .toList();
      expect(toggles, hasLength(1));
      expect(toggles.single.data['is_active'], isFalse);
      expect(find.text('Promotion desactivee'), findsOneWidget);
    });

    testWidgets('supprimer exige une confirmation avant le DELETE',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.promotionsAdmin) {
          return _jsonResponse(_paginatedPromotions());
        }
        if (options.method == 'DELETE' &&
            options.path == ApiEndpoints.promotion(11)) {
          return _jsonResponse(null);
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path}',
        );
      });

      await _pumpPromotionsPage(tester, api);

      // Annuler ne doit rien supprimer.
      await tester.tap(find.byTooltip('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer WELCOME10 ?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method == 'DELETE'), isEmpty);

      // Confirmer supprime bien.
      await tester.tap(find.byTooltip('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.pumpAndSettle();

      final deletes = requests
          .where((r) =>
              r.method == 'DELETE' && r.path == ApiEndpoints.promotion(11))
          .toList();
      expect(deletes, hasLength(1));
      expect(find.text('Promotion supprimee'), findsOneWidget);
    });
  });
}

// ─── Helpers ────────────────────────────────────────────────────────────────

Future<void> _pumpPromotionsPage(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(_AdminSessionController.new),
      ],
      child: const MaterialApp(home: Scaffold(body: PromotionsPage())),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _promoJson({required int id, required bool isActive}) {
  return {
    'id': id,
    'code': 'WELCOME10',
    'description': '10% de reduction',
    'discount_type': 'percentage',
    'discount_value': 10.0,
    'min_order_amount': 0.0,
    'is_active': isActive,
    'is_public': true,
    'is_stackable': false,
    'first_order_only': false,
    'email_verified_required': false,
    'usage_count': 3,
    'unique_users': 3,
    'current_uses': 3,
    'max_uses': null,
    'max_uses_per_user': null,
    'remaining_uses': null,
    'starts_at': null,
    'ends_at': null,
    'revenue_gross': 0.0,
    'revenue_net': 0.0,
    'discount_total': 0.0,
    'targets': <String, Object?>{},
  };
}

Map<String, dynamic> _paginatedPromotions() {
  return {
    'items': [_promoJson(id: 11, isActive: true)],
    'total': 1,
    'page': 1,
    'page_size': 100,
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
    return SessionState.authenticated(
      user: const StaffUser(
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

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/loyalty/presentation/loyalty_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoyaltyPage — actions admin', () {
    testWidgets(
        'desactiver le programme via la config envoie le PATCH attendu',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.loyaltyConfig) {
          return _jsonResponse(_configJson(isActive: true));
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.loyaltyStats) {
          return _jsonResponse(_statsJson());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.loyaltyRules) {
          return _jsonResponse(<Object?>[]);
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.loyaltyRewards) {
          return _jsonResponse(<Object?>[]);
        }
        if (options.method == 'PATCH' &&
            options.path == ApiEndpoints.loyaltyConfig) {
          return _jsonResponse(_configJson(isActive: false));
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path}',
        );
      });

      await _pumpLoyaltyPage(tester, api);

      await tester.tap(find.byTooltip('Configurer'));
      await tester.pumpAndSettle();

      expect(find.text('Configuration fidelite'), findsOneWidget);

      await tester.tap(find.text('Programme actif'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Points par euro'),
        '2',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
      await tester.pumpAndSettle();

      final patches = requests
          .where((r) =>
              r.method == 'PATCH' && r.path == ApiEndpoints.loyaltyConfig)
          .toList();
      expect(patches, hasLength(1));
      expect(patches.single.data['is_active'], isFalse);
      expect(patches.single.data['base_ratio'], 2.0);
      expect(find.text('Configuration mise a jour'), findsOneWidget);
    });

    testWidgets('desactiver une recompense appelle updateReward(isActive: false)',
        (tester) async {
      final requests = <RequestOptions>[];
      final api = _client((options) {
        requests.add(options);
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.loyaltyConfig) {
          return _jsonResponse(_configJson(isActive: true));
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.loyaltyStats) {
          return _jsonResponse(_statsJson());
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.loyaltyRules) {
          return _jsonResponse(<Object?>[]);
        }
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.loyaltyRewards) {
          return _jsonResponse([_rewardJson(id: 5, isActive: true)]);
        }
        if (options.method == 'PATCH' &&
            options.path == ApiEndpoints.loyaltyReward(5)) {
          return _jsonResponse(_rewardJson(id: 5, isActive: false));
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path}',
        );
      });

      await _pumpLoyaltyPage(tester, api);

      expect(find.byType(Switch), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      // Laisse le refetch de loyaltyRewardsProvider (declenche par
      // l'invalidate post-toggle) purger son timer dio interne avant la fin
      // du test, sinon flutter_test le signale comme timer residuel.
      await tester.pump(const Duration(milliseconds: 300));

      final patches = requests
          .where((r) =>
              r.method == 'PATCH' &&
              r.path == ApiEndpoints.loyaltyReward(5))
          .toList();
      expect(patches, hasLength(1));
      expect(patches.single.data['is_active'], isFalse);
    });
  });
}

// ─── Helpers ────────────────────────────────────────────────────────────────

Future<void> _pumpLoyaltyPage(WidgetTester tester, ApiClient api) async {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        sessionControllerProvider.overrideWith(_AdminSessionController.new),
      ],
      child: const MaterialApp(home: Scaffold(body: LoyaltyPage())),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _configJson({required bool isActive}) {
  return {
    'id': 1,
    'base_ratio': 1.0,
    'points_expiry_days': 365,
    'points_to_euro_rate': 0.01,
    'max_cumulative_multiplier': 3.0,
    'is_active': isActive,
  };
}

Map<String, dynamic> _statsJson() {
  return {
    'member_count': 120,
    'active_member_count': 80,
    'points_distributed': 5000,
    'points_redeemed': 1200,
    'points_expired': 100,
    'circulating_balance': 3700,
    'redemption_rate': 0.24,
  };
}

Map<String, dynamic> _rewardJson({required int id, required bool isActive}) {
  return {
    'id': id,
    'name': 'Cafe offert',
    'reward_type': 'product',
    'points_required': 100,
    'discount_amount': null,
    'product_id': 3,
    'is_active': isActive,
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

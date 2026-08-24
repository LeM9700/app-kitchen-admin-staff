import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_models.dart';
import 'package:app_admin_staff/features/haccp/data/haccp_repository.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_export_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_nc_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HaccpRepository non-conformities', () {
    test('listNonConformities envoie le filtre de statut et parse la liste',
        () async {
      late RequestOptions seen;
      final repository = HaccpRepository(
        _client((options) {
          seen = options;
          return _jsonResponse([_ncJson(id: 1, status: 'open')]);
        }),
      );

      final ncs = await repository.listNonConformities(status: 'open');

      expect(seen.path, ApiEndpoints.haccpNonConformities);
      expect(seen.queryParameters['status'], 'open');
      expect(ncs, hasLength(1));
      expect(ncs.first.id, 1);
      expect(ncs.first.isOpen, isTrue);
    });

    test(
        'updateNonConformity envoie action corrective + statut et parse la reponse',
        () async {
      late RequestOptions seen;
      final repository = HaccpRepository(
        _client((options) {
          seen = options;
          return _jsonResponse(_ncJson(
            id: 501,
            status: 'in_progress',
            correctiveAction: 'Ajustement thermostat',
          ));
        }),
      );

      final updated = await repository.updateNonConformity(
        501,
        correctiveAction: 'Ajustement thermostat',
        status: 'in_progress',
      );

      expect(seen.method, 'PATCH');
      expect(seen.path, ApiEndpoints.haccpNonConformity(501));
      expect(
        (seen.data as Map)['corrective_action'],
        'Ajustement thermostat',
      );
      expect((seen.data as Map)['status'], 'in_progress');
      expect(updated.status, 'in_progress');
      expect(updated.correctiveAction, 'Ajustement thermostat');
    });
  });

  group('HaccpNonConformityPage — flux non-conformite', () {
    testWidgets(
        'ajouter une action corrective puis cloturer met a jour le statut',
        (tester) async {
      var stage = 'open';
      final patchRequests = <RequestOptions>[];

      final api = _client((options) {
        if (options.method == 'GET' &&
            options.path == ApiEndpoints.haccpNonConformities) {
          switch (stage) {
            case 'in_progress':
              return _jsonResponse([
                _ncJson(
                  id: 501,
                  status: 'in_progress',
                  correctiveAction: 'Ajustement thermostat',
                ),
              ]);
            case 'closed':
              return _jsonResponse([
                _ncJson(
                  id: 501,
                  status: 'closed',
                  correctiveAction: 'Ajustement thermostat',
                  validatedAt: '2026-08-20T08:00:00Z',
                ),
              ]);
            default:
              return _jsonResponse([_ncJson(id: 501, status: 'open')]);
          }
        }
        if (options.method == 'PATCH' &&
            options.path == ApiEndpoints.haccpNonConformity(501)) {
          patchRequests.add(options);
          final data = options.data as Map;
          if (data['status'] == 'in_progress') {
            stage = 'in_progress';
            return _jsonResponse(_ncJson(
              id: 501,
              status: 'in_progress',
              correctiveAction: data['corrective_action'] as String,
            ));
          }
          stage = 'closed';
          return _jsonResponse(_ncJson(
            id: 501,
            status: 'closed',
            correctiveAction: 'Ajustement thermostat',
            validatedAt: '2026-08-20T08:00:00Z',
          ));
        }
        throw StateError(
          'requete inattendue ${options.method} ${options.path}',
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(api),
            sessionControllerProvider.overrideWith(_AdminSessionController.new),
          ],
          child: const MaterialApp(home: HaccpNonConformityPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.text('Frigo positif à 8°C, hors plage 0-4°C'), findsOneWidget);

      // Déplie la carte pour accéder aux actions admin.
      await tester.tap(find.text('Frigo positif à 8°C, hors plage 0-4°C'));
      await tester.pumpAndSettle();

      expect(find.text('Action corrective requise'), findsOneWidget);

      await tester.tap(find.text('Ajouter action'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField),
        'Ajustement thermostat',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(patchRequests, hasLength(1));
      expect(
        patchRequests[0].data['corrective_action'],
        'Ajustement thermostat',
      );
      expect(patchRequests[0].data['status'], 'in_progress');
      expect(find.text('Modifier action'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Clôturer').first);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Clôturer'),
        ),
      );
      await tester.pumpAndSettle();

      expect(patchRequests, hasLength(2));
      expect(patchRequests[1].data['status'], 'closed');
      expect(
        (patchRequests[1].data as Map).containsKey('corrective_action'),
        isFalse,
      );
      expect(find.text('Non-conformité clôturée ✓'), findsOneWidget);
    });
  });

  group('HaccpExportPage — flux export', () {
    testWidgets(
        'export PDF envoie une requete authentifiee sur la periode par defaut',
        (tester) async {
      // Corps vide : la page rejette explicitement une réponse vide avant
      // d'écrire un fichier ou d'appeler share_plus, ce qui nous laisse
      // vérifier la requête HTTP sans dépendre de plugins natifs (path_provider/
      // share_plus) non disponibles — et non mockés — dans ce test.
      RequestOptions? captured;
      final api = _client((options) {
        captured = options;
        return ResponseBody.fromString(
          '',
          200,
          headers: {
            Headers.contentTypeHeader: ['application/pdf'],
          },
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(home: HaccpExportPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Exporter en PDF'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.method, 'GET');
      expect(captured!.path, ApiEndpoints.haccpExportPdf);
      expect(captured!.headers['Authorization'], 'Bearer access');
      expect(captured!.queryParameters['from'], isNotNull);
      expect(captured!.queryParameters['to'], isNotNull);
    });

    testWidgets('export CSV envoie le type de donnees selectionne',
        (tester) async {
      RequestOptions? captured;
      final api = _client((options) {
        captured = options;
        return ResponseBody.fromString(
          '',
          200,
          headers: {
            Headers.contentTypeHeader: ['text/csv'],
          },
        );
      });

      // La page est une longue ListView : on agrandit la vue de test pour que
      // les tuiles CSV soient dans le viewport sans dépendre d'un scroll.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [apiClientProvider.overrideWithValue(api)],
          child: const MaterialApp(home: HaccpExportPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Non-conformités'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.method, 'GET');
      expect(captured!.path, ApiEndpoints.haccpExportCsv);
      expect(captured!.queryParameters['data_type'], 'nc');
      expect(captured!.headers['Authorization'], 'Bearer access');
    });
  });
}

// ─── Helpers ────────────────────────────────────────────────────────────────

Map<String, dynamic> _ncJson({
  required int id,
  required String status,
  String? correctiveAction,
  String? validatedAt,
}) {
  return {
    'id': id,
    'session_id': 10,
    'source_type': 'temperature',
    'source_id': 3,
    'description': 'Frigo positif à 8°C, hors plage 0-4°C',
    'corrective_action': correctiveAction,
    'validated_by': validatedAt != null ? 7 : null,
    'validated_at': validatedAt,
    'status': status,
    'created_at': '2026-08-20T07:15:00Z',
  };
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

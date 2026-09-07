// Prompt 05 — Isolation tenant et identité dans la file hors ligne.
//
// Ces tests prouvent qu'une action mise en file hors ligne pour le
// tenant A ne peut jamais être rejouée avec une session du tenant B (ou
// avec un autre utilisateur du même tenant), et que les files restent
// isolées par tenant/utilisateur sur l'appareil.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/offline/sync_worker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test_support.dart';

void main() {
  test('add() stamps the queued action with the current tenant/user/session',
      () {
    final container = ProviderContainer(
      overrides: [
        sessionControllerOverride(
          testAuthenticatedSession(
            tenantSlug: 'pizza-a',
            userId: 11,
            sessionId: 501,
          ),
        ),
        syncQueueProvider.overrideWith(_MemorySyncQueue.new),
      ],
    );
    addTearDown(container.dispose);

    container.read(syncQueueProvider.notifier).add(
          feature: 'kitchen',
          label: 'Commande #1',
          endpoint: '/orders/1/status',
          method: 'PATCH',
          payload: {'status': 'ready'},
        );

    final action = container.read(syncQueueProvider).single;
    expect(action.tenantSlug, 'pizza-a');
    expect(action.userId, 11);
    expect(action.sessionId, 501);
    expect(action.formatVersion, QueuedAction.currentFormatVersion);
  });

  test('add() refuses to queue an action without an authenticated session',
      () {
    final container = ProviderContainer(
      overrides: [
        sessionControllerOverride(null),
        syncQueueProvider.overrideWith(_MemorySyncQueue.new),
      ],
    );
    addTearDown(container.dispose);

    expect(
      () => container.read(syncQueueProvider.notifier).add(
            feature: 'kitchen',
            label: 'Commande #1',
            endpoint: '/orders/1/status',
            method: 'PATCH',
            payload: {'status': 'ready'},
          ),
      throwsStateError,
    );
    expect(container.read(syncQueueProvider), isEmpty);
  });

  test(
    'action offline tenant A -> deconnexion -> connexion tenant B -> sync : '
    'aucun appel API pour action A, action bloquee et non supprimee',
    () async {
      final requests = <RequestOptions>[];
      final apiClient = _apiClient(requests);
      final session = _MutableSessionController(
        testAuthenticatedSession(
          tenantSlug: 'pizza-a',
          userId: 11,
          sessionId: 501,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sessionControllerProvider.overrideWith(() => session),
          syncQueueProvider.overrideWith(_MemorySyncQueue.new),
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(container.dispose);

      // 1. Action hors ligne pendant que le tenant A est connecte.
      container.read(syncQueueProvider.notifier).add(
            feature: 'kitchen',
            label: 'Commande #1 -> PRETE',
            endpoint: '/orders/1/status',
            method: 'PATCH',
            payload: {'status': 'ready'},
          );
      final queuedForTenantA = container.read(syncQueueProvider).single;
      expect(queuedForTenantA.tenantSlug, 'pizza-a');

      // 2. Deconnexion puis connexion tenant B (autre etablissement).
      session.setSession(
        testAuthenticatedSession(
          tenantSlug: 'burger-b',
          userId: 22,
          sessionId: 902,
        ),
      );

      // 3. Tentative de synchronisation sous la session tenant B.
      await container
          .read(syncWorkerProvider)
          .flush(container.read(syncQueueProvider));

      // 4. Aucun appel API n'a ete emis pour l'action du tenant A.
      expect(requests, isEmpty);

      // L'action reste en file (jamais supprimee silencieusement) mais
      // marquee bloquee pour incompatibilite de tenant/utilisateur.
      final blocked = container.read(syncQueueProvider).single;
      expect(blocked.id, queuedForTenantA.id);
      expect(blocked.blockReason, 'tenant_or_user_mismatch');

      // Elle n'apparait plus dans la file "courante" (tenant B) mais bien
      // dans la file "etrangere" a isoler/nettoyer explicitement.
      expect(container.read(currentSessionQueuedActionsProvider), isEmpty);
      expect(
        container.read(foreignSessionQueuedActionsProvider).single.id,
        queuedForTenantA.id,
      );
    },
  );

  test('meme tenant mais utilisateur different : rejeu bloque aussi',
      () async {
    final requests = <RequestOptions>[];
    final apiClient = _apiClient(requests);
    final session = _MutableSessionController(
      testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 11),
    );
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(() => session),
        syncQueueProvider.overrideWith(_MemorySyncQueue.new),
        apiClientProvider.overrideWithValue(apiClient),
      ],
    );
    addTearDown(container.dispose);

    container.read(syncQueueProvider.notifier).add(
          feature: 'haccp',
          label: 'Releve T°',
          endpoint: '/haccp/sessions/1/temperatures',
          method: 'POST',
          payload: {'equipment_id': 1, 'measured_temp': 4.0},
        );

    // Meme tenant, mais un autre membre du staff se connecte sur l'appareil.
    session.setSession(
      testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 99),
    );

    await container
        .read(syncWorkerProvider)
        .flush(container.read(syncQueueProvider));

    expect(requests, isEmpty);
    expect(
      container.read(syncQueueProvider).single.blockReason,
      'tenant_or_user_mismatch',
    );
  });

  test('reconnexion du meme tenant/utilisateur laisse la sync repartir',
      () async {
    final requests = <RequestOptions>[];
    final apiClient = _apiClient(requests);
    final session = _MutableSessionController(
      testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 11),
    );
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(() => session),
        syncQueueProvider.overrideWith(_MemorySyncQueue.new),
        apiClientProvider.overrideWithValue(apiClient),
      ],
    );
    addTearDown(container.dispose);

    container.read(syncQueueProvider.notifier).add(
          feature: 'kitchen',
          label: 'Commande #1 -> PRETE',
          endpoint: '/orders/1/status',
          method: 'PATCH',
          payload: {'status': 'ready'},
        );

    await container
        .read(syncWorkerProvider)
        .flush(container.read(syncQueueProvider));

    expect(requests, hasLength(1));
    expect(requests.single.path, '/orders/1/status');
    expect(container.read(syncQueueProvider), isEmpty);
  });

  test(
    'removeForeignTo abandonne explicitement les actions d une autre '
    'session sans toucher a celles du tenant courant',
    () {
      final container = ProviderContainer(
        overrides: [
          sessionControllerOverride(
            testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 11),
          ),
          syncQueueProvider.overrideWith(
            () => _MemorySyncQueue.seeded([
              QueuedAction(
                id: 'own',
                feature: 'kitchen',
                label: 'own',
                endpoint: '/orders/1/status',
                method: 'PATCH',
                payload: const {},
                createdAt: DateTime.utc(2026, 9, 1),
                tenantSlug: 'pizza-a',
                userId: 11,
              ),
              QueuedAction(
                id: 'foreign',
                feature: 'kitchen',
                label: 'foreign',
                endpoint: '/orders/2/status',
                method: 'PATCH',
                payload: const {},
                createdAt: DateTime.utc(2026, 9, 1),
                tenantSlug: 'burger-b',
                userId: 22,
                blockReason: 'tenant_or_user_mismatch',
              ),
            ]),
          ),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(syncQueueProvider.notifier)
          .removeForeignTo(tenantSlug: 'pizza-a', userId: 11);

      final remaining = container.read(syncQueueProvider);
      expect(remaining.map((action) => action.id), ['own']);
    },
  );

  test('une action de format legacy (sans identite) est traitee comme '
      'etrangere et jamais rejouee', () async {
    final requests = <RequestOptions>[];
    final apiClient = _apiClient(requests);
    final container = ProviderContainer(
      overrides: [
        sessionControllerOverride(
          testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 11),
        ),
        syncQueueProvider.overrideWith(
          () => _MemorySyncQueue.seeded([
            QueuedAction(
              id: 'legacy',
              feature: 'kitchen',
              label: 'legacy',
              endpoint: '/orders/9/status',
              method: 'PATCH',
              payload: const {},
              createdAt: DateTime.utc(2026, 1, 1),
              formatVersion: 1,
            ),
          ]),
        ),
        apiClientProvider.overrideWithValue(apiClient),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(syncWorkerProvider)
        .flush(container.read(syncQueueProvider));

    expect(requests, isEmpty);
    expect(
      container.read(syncQueueProvider).single.blockReason,
      'unknown_origin',
    );
  });
}

ApiClient _apiClient(
  List<RequestOptions> requests, {
  ResponseBody? response,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test'));
  dio.httpClientAdapter = _RecordingAdapter(
    requests,
    response ?? _jsonResponse({'ok': true}),
  );
  return ApiClient(dio, _NoopTokenStore());
}

class _MemorySyncQueue extends SyncQueue {
  _MemorySyncQueue() : _seed = const [];
  _MemorySyncQueue.seeded(this._seed);

  final List<QueuedAction> _seed;

  // Seeds state directly instead of going through load()/secure storage,
  // matching the pattern used by other SyncQueue test doubles in this repo
  // — while still exercising the real add()/markBlocked()/remove() logic.
  @override
  List<QueuedAction> build() => _seed;

  @override
  Future<void> persist() async {}
}

class _MutableSessionController extends SessionController {
  _MutableSessionController(this._initial);

  final SessionState _initial;

  @override
  Future<SessionState> build() => SynchronousFuture(_initial);

  void setSession(SessionState session) {
    state = AsyncValue.data(session);
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.requests, this.response);

  final List<RequestOptions> requests;
  final ResponseBody response;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return response;
  }

  @override
  void close({bool force = false}) {}
}

class _NoopTokenStore extends TokenStore {
  _NoopTokenStore() : super(const FlutterSecureStorage());

  @override
  Future<StoredTokens?> read() async => null;

  @override
  Future<String?> readAccessToken() async => 'test-token';

  @override
  Future<String?> readRefreshToken() async => null;

  @override
  Future<String?> readTenantSlug() async => null;

  @override
  Future<void> write(StoredTokens tokens) async {}

  @override
  Future<void> clear() async {}
}

ResponseBody _jsonResponse(Map<String, dynamic> body, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

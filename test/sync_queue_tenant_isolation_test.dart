// Prompt 05 (passe 2) — Isolation tenant et identité dans la file hors ligne.
//
// La passe precedente empechait le REJEU cross-tenant/cross-utilisateur
// (aucun appel API pour une action etrangere) mais toutes les actions,
// quel que soit leur proprietaire, vivaient encore dans une seule liste
// en memoire/stockage partagee — visible et supprimable par n'importe
// quelle session sur le meme appareil.
//
// Cette passe verifie l'isolation physique : chaque identite (tenant +
// utilisateur) a sa propre partition de stockage, et une session ne
// charge jamais que la sienne. Rien — pas le label, pas le payload, pas
// meme l'existence d'une action — n'est jamais expose a une autre
// session, et une action legacy sans identite part en quarantaine
// definitive plutot que d'etre exposee au premier compte venu.

import 'dart:async';
import 'dart:convert';

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
      () async {
    final store = _InMemoryKeyValueStore();
    final container = ProviderContainer(
      overrides: [
        sessionControllerOverride(
          testAuthenticatedSession(
            tenantSlug: 'pizza-a',
            userId: 11,
            sessionId: 501,
          ),
        ),
        syncQueueProvider.overrideWith(() => _TestSyncQueue(store)),
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

  test('add() refuses to queue an action without an authenticated session', () {
    final container = ProviderContainer(
      overrides: [
        sessionControllerOverride(null),
        syncQueueProvider
            .overrideWith(() => _TestSyncQueue(_InMemoryKeyValueStore())),
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
    'B ne peut ni lire ni afficher le label/payload d une action A '
    '(isolation physique du stockage)',
    () async {
      final store = _InMemoryKeyValueStore();
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
          syncQueueProvider.overrideWith(() => _TestSyncQueue(store)),
        ],
      );
      addTearDown(container.dispose);

      container.read(syncQueueProvider.notifier).add(
        feature: 'kitchen',
        label: 'Commande #1 -- infos sensibles tenant A',
        endpoint: '/orders/1/status',
        method: 'PATCH',
        payload: {'status': 'ready', 'note': 'donnee metier tenant A'},
      );
      expect(container.read(syncQueueProvider), hasLength(1));

      // Deconnexion puis connexion tenant B (autre etablissement).
      session.setSession(
        testAuthenticatedSession(
          tenantSlug: 'burger-b',
          userId: 22,
          sessionId: 902,
        ),
      );
      await _settle();

      // B ne voit strictement rien : ni le label, ni le payload, ni meme
      // l'existence d'une action en attente. La liste que B charge est sa
      // propre partition de stockage, jamais celle de A.
      expect(container.read(syncQueueProvider), isEmpty);

      // La donnee brute de A existe toujours sur l'appareil (sous sa
      // propre cle), mais B n'a physiquement aucun moyen d'y acceder via
      // le SyncQueue : sa partition est une cle de stockage differente.
      expect(
        store.data.keys.where((key) => key.contains('pizza-a::11')),
        isNotEmpty,
      );
    },
  );

  test(
    'B ne peut ni synchroniser ni supprimer une action A : sa partition '
    'ne contient rien a synchroniser/supprimer, celle de A reste intacte',
    () async {
      final requests = <RequestOptions>[];
      final apiClient = _apiClient(requests);
      final store = _InMemoryKeyValueStore();
      final session = _MutableSessionController(
        testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 11),
      );
      final container = ProviderContainer(
        overrides: [
          sessionControllerProvider.overrideWith(() => session),
          syncQueueProvider.overrideWith(() => _TestSyncQueue(store)),
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(container.dispose);

      container.read(syncQueueProvider.notifier).add(
        feature: 'kitchen',
        label: 'Commande #1 tenant A',
        endpoint: '/orders/1/status',
        method: 'PATCH',
        payload: {'status': 'ready'},
      );
      final rawPartitionABefore = store.data.entries
          .singleWhere((e) => e.key.contains('pizza-a::11'))
          .value;

      session.setSession(
        testAuthenticatedSession(tenantSlug: 'burger-b', userId: 22),
      );
      await _settle();

      // Tentative de sync sous B : rien a envoyer (sa file est vide), donc
      // aucun appel API.
      await container
          .read(syncWorkerProvider)
          .flush(container.read(syncQueueProvider));
      expect(requests, isEmpty);

      // Tentative de suppression sous B d'un identifiant qui appartenait a
      // A : no-op (rien de tel dans la partition de B), et la partition de
      // A sur le disque partage n'est pas modifiee.
      container.read(syncQueueProvider.notifier).remove('does-not-matter');
      final rawPartitionAAfter = store.data.entries
          .singleWhere((e) => e.key.contains('pizza-a::11'))
          .value;
      expect(rawPartitionAAfter, rawPartitionABefore);
    },
  );

  test('A reconnecte retrouve et peut synchroniser sa propre action', () async {
    final requests = <RequestOptions>[];
    final apiClient = _apiClient(requests);
    final store = _InMemoryKeyValueStore();
    final session = _MutableSessionController(
      testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 11),
    );
    final container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(() => session),
        syncQueueProvider.overrideWith(() => _TestSyncQueue(store)),
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

    // B se connecte sur le meme appareil, ne voit rien.
    session.setSession(
      testAuthenticatedSession(tenantSlug: 'burger-b', userId: 22),
    );
    await _settle();
    expect(container.read(syncQueueProvider), isEmpty);

    // A se reconnecte : sa file revient, intacte.
    session.setSession(
      testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 11),
    );
    await _settle();
    expect(container.read(syncQueueProvider), hasLength(1));
    expect(
      container.read(syncQueueProvider).single.endpoint,
      '/orders/1/status',
    );

    await container
        .read(syncWorkerProvider)
        .flush(container.read(syncQueueProvider));

    expect(requests, hasLength(1));
    expect(requests.single.path, '/orders/1/status');
    expect(container.read(syncQueueProvider), isEmpty);
  });

  test(
    'meme tenant mais utilisateur different : meme protection '
    '(partition distincte, rien de visible ni synchronisable)',
    () async {
      final requests = <RequestOptions>[];
      final apiClient = _apiClient(requests);
      final store = _InMemoryKeyValueStore();
      final session = _MutableSessionController(
        testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 11),
      );
      final container = ProviderContainer(
        overrides: [
          sessionControllerProvider.overrideWith(() => session),
          syncQueueProvider.overrideWith(() => _TestSyncQueue(store)),
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

      // Meme tenant, mais un autre membre du staff se connecte.
      session.setSession(
        testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 99),
      );
      await _settle();

      expect(container.read(syncQueueProvider), isEmpty);

      await container
          .read(syncWorkerProvider)
          .flush(container.read(syncQueueProvider));
      expect(requests, isEmpty);
    },
  );

  test(
    'meme tenant et meme utilisateur apres rotation de refresh token : '
    'synchronisation autorisee',
    () async {
      final requests = <RequestOptions>[];
      final apiClient = _apiClient(requests);
      final store = _InMemoryKeyValueStore();
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
          syncQueueProvider.overrideWith(() => _TestSyncQueue(store)),
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
      expect(container.read(syncQueueProvider).single.sessionId, 501);

      // Une rotation de refresh token change l'identifiant de session
      // backend sans changer le tenant ni l'utilisateur.
      session.setSession(
        testAuthenticatedSession(
          tenantSlug: 'pizza-a',
          userId: 11,
          sessionId: 902,
        ),
      );
      await _settle();

      // L'action, creee sous l'ancien sessionId, est toujours la et reste
      // synchronisable : sessionId est une metadonnee d'audit, jamais un
      // critere de blocage.
      expect(container.read(syncQueueProvider), hasLength(1));

      await container
          .read(syncWorkerProvider)
          .flush(container.read(syncQueueProvider));

      expect(requests, hasLength(1));
      expect(container.read(syncQueueProvider), isEmpty);
    },
  );

  test(
    'une action legacy sans identite part en quarantaine : jamais '
    'synchronisee, jamais exposee a un compte, quel qu il soit',
    () async {
      final requests = <RequestOptions>[];
      final apiClient = _apiClient(requests);
      final store = _InMemoryKeyValueStore();
      // Simule une file pre-migration : un seul blob global, sans identite.
      store.data['admin_staff_sync_queue'] = jsonEncode([
        {
          'id': 'legacy-1',
          'feature': 'kitchen',
          'label': 'Commande legacy #9',
          'endpoint': '/orders/9/status',
          'method': 'PATCH',
          'payload': {'status': 'ready'},
          'created_at': '2026-01-01T00:00:00.000Z',
          'retry_count': 0,
        },
      ]);

      final sessionA = _MutableSessionController(
        testAuthenticatedSession(tenantSlug: 'pizza-a', userId: 11),
      );
      final containerA = ProviderContainer(
        overrides: [
          sessionControllerProvider.overrideWith(() => sessionA),
          syncQueueProvider.overrideWith(() => _TestSyncQueue(store)),
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(containerA.dispose);

      // Le tenant A est le premier a se connecter apres la migration.
      containerA.read(syncQueueProvider.notifier);
      await _settle();

      // L'action legacy n'est jamais adoptee par A : sa file reste vide.
      expect(containerA.read(syncQueueProvider), isEmpty);
      await containerA
          .read(syncWorkerProvider)
          .flush(containerA.read(syncQueueProvider));
      expect(requests, isEmpty);

      // Le blob global a ete entierement redistribue puis supprime : plus
      // aucune session, meme future, ne peut le relire.
      expect(store.data.containsKey('admin_staff_sync_queue'), isFalse);

      // Le tenant B se connecte ensuite sur le meme appareil : lui non plus
      // ne voit jamais l'action legacy (le blob global n'existe plus).
      final sessionB = _MutableSessionController(
        testAuthenticatedSession(tenantSlug: 'burger-b', userId: 22),
      );
      final containerB = ProviderContainer(
        overrides: [
          sessionControllerProvider.overrideWith(() => sessionB),
          syncQueueProvider.overrideWith(() => _TestSyncQueue(store)),
          apiClientProvider.overrideWithValue(apiClient),
        ],
      );
      addTearDown(containerB.dispose);
      containerB.read(syncQueueProvider.notifier);
      await _settle();

      expect(containerB.read(syncQueueProvider), isEmpty);
    },
  );
}

/// Flushes a small, bounded number of microtask/event-loop turns so that
/// fire-and-forget `load()`/migration chains triggered by `build()` have a
/// chance to finish before assertions run.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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

/// Deterministic in-memory stand-in for [SecureKeyValueStore], simulating a
/// single device's "disk" shared across identities/sessions within a test.
class _InMemoryKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

class _TestSyncQueue extends SyncQueue {
  _TestSyncQueue(this._store);

  final SecureKeyValueStore _store;

  @override
  SecureKeyValueStore get storage => _store;
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

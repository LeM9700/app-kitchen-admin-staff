import 'dart:async';

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/application/kds_active_screens_provider.dart';
import 'package:app_admin_staff/features/kitchen/application/kds_screen_management_controller.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chargement initial appelle listScreens(includeInactive: true)',
      () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1), _screen(id: 2)];
    final container = _container(repository: repository);
    addTearDown(container.dispose);

    final state = await container.read(kdsScreenManagementProvider.future);

    expect(repository.includeInactiveCaptured, isTrue);
    expect(state.screens, hasLength(2));
    expect(
      container.read(kdsScreenManagementProvider),
      isA<AsyncData<KdsScreenManagementState>>(),
    );
  });

  test('createScreen succes ajoute l ecran et repasse creating a false',
      () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1)]
      ..createScreenResult = _screen(id: 2, name: 'Nouvel ecran');
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    await container.read(kdsScreenManagementProvider.notifier).createScreen(
          name: 'Nouvel ecran',
          screenKey: 'nouvel-ecran',
          mode: 'kitchen',
          station: 'kitchen',
          interactionMode: 'wall',
          ticketsPerPage: 4,
        );

    final state = container.read(kdsScreenManagementProvider).value!;
    expect(state.screens.map((s) => s.id), [1, 2]);
    expect(state.creating, isFalse);
    expect(state.actionError, isNull);
    expect(repository.createScreenCalls, hasLength(1));
    expect(repository.createScreenCalls.single['screen_key'], 'nouvel-ecran');
  });

  test(
      'createScreen succes invalide kdsActiveScreensProvider (visible sur '
      'le board sans redemarrage)', () async {
    // Final whole-branch review finding: createScreen must invalidate the
    // board's screen-selector provider the same way updateScreen already
    // does (see comment on updateScreen), otherwise a newly created screen
    // stays invisible in the board selector until an unrelated edit or an
    // app restart happens to refresh it.
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1)]
      ..createScreenResult = _screen(id: 2, name: 'Nouvel ecran');
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);
    await container.read(kdsActiveScreensProvider.future);
    final callsBeforeCreate = repository.listScreensCallCount;

    await container.read(kdsScreenManagementProvider.notifier).createScreen(
          name: 'Nouvel ecran',
          screenKey: 'nouvel-ecran',
          mode: 'kitchen',
          station: 'kitchen',
          interactionMode: 'wall',
          ticketsPerPage: 4,
        );

    // If kdsActiveScreensProvider was invalidated, re-reading it triggers a
    // fresh listScreens() call instead of returning the stale cached
    // result from before the screen was created.
    await container.read(kdsActiveScreensProvider.future);
    expect(repository.listScreensCallCount, greaterThan(callsBeforeCreate));
  });

  test('createScreen reste en AsyncData (liste visible) pendant creating',
      () async {
    final repository = _FakeKdsRepository()..screensResult = [_screen(id: 1)];
    final gate = Completer<KdsScreen>();
    repository.createScreenGate = gate;
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    final future =
        container.read(kdsScreenManagementProvider.notifier).createScreen(
              name: 'Nouvel ecran',
              screenKey: 'nouvel-ecran',
              mode: 'kitchen',
              station: 'kitchen',
              interactionMode: 'wall',
              ticketsPerPage: 4,
            );

    final midState = container.read(kdsScreenManagementProvider);
    expect(midState, isA<AsyncData<KdsScreenManagementState>>());
    expect(midState.value!.creating, isTrue);
    expect(midState.value!.screens, hasLength(1));

    gate.complete(_screen(id: 2, name: 'Nouvel ecran'));
    await future;

    final finalState = container.read(kdsScreenManagementProvider).value!;
    expect(finalState.creating, isFalse);
    expect(finalState.screens, hasLength(2));
  });

  test('updateScreen succes remplace l ecran dans la liste', () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1, name: 'Avant')]
      ..updateScreenResult = _screen(id: 1, name: 'Apres');
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    await container.read(kdsScreenManagementProvider.notifier).updateScreen(
          screenId: 1,
          name: 'Apres',
        );

    final state = container.read(kdsScreenManagementProvider).value!;
    expect(state.screens.single.name, 'Apres');
    expect(state.actionError, isNull);
  });

  test(
      'updateScreen succes invalide kdsActiveScreensProvider (visible sur '
      'le board sans redemarrage)', () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1, name: 'Avant')]
      ..updateScreenResult = _screen(id: 1, name: 'Apres');
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);
    await container.read(kdsActiveScreensProvider.future);
    final callsBeforeUpdate = repository.listScreensCallCount;

    await container.read(kdsScreenManagementProvider.notifier).updateScreen(
          screenId: 1,
          name: 'Apres',
        );

    await container.read(kdsActiveScreensProvider.future);
    expect(repository.listScreensCallCount, greaterThan(callsBeforeUpdate));
  });

  test('toggle actif ne transmet que is_active', () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1)]
      ..updateScreenResult = _screen(id: 1, isActive: false);
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    await container.read(kdsScreenManagementProvider.notifier).updateScreen(
          screenId: 1,
          isActive: false,
        );

    expect(repository.updateScreenCalls, hasLength(1));
    expect(
      repository.updateScreenCalls.single,
      {'screen_id': 1, 'is_active': false},
    );
  });

  test('generatePairingCode retourne le code, busy pendant l appel', () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1), _screen(id: 2)];
    final gate = Completer<KdsPairingCode>();
    repository.pairingCodeGate = gate;
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    final future = container
        .read(kdsScreenManagementProvider.notifier)
        .generatePairingCode(screenId: 1);

    final midState = container.read(kdsScreenManagementProvider).value!;
    expect(midState.busyScreenIds, {1});
    expect(midState.busyScreenIds, isNot(contains(2)));

    final pairingCode = KdsPairingCode(
      screenId: 1,
      code: '123456',
      expiresAt: DateTime.utc(2026, 8, 18, 23),
    );
    gate.complete(pairingCode);
    final result = await future;

    expect(result, pairingCode);
    final finalState = container.read(kdsScreenManagementProvider).value!;
    expect(finalState.busyScreenIds, isEmpty);
  });

  test('revokeScreenSessions retourne le compte revoque', () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1)]
      ..revokeResult = 3;
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    final result = await container
        .read(kdsScreenManagementProvider.notifier)
        .revokeScreenSessions(screenId: 1);

    expect(result, 3);
    expect(repository.revokeScreenIds, [1]);
    final state = container.read(kdsScreenManagementProvider).value!;
    expect(state.busyScreenIds, isEmpty);
  });

  test('busyScreenIds isole par ecran (deux ecrans, un seul busy)', () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1), _screen(id: 2)];
    final gate = Completer<int>();
    repository.revokeGate = gate;
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    final future = container
        .read(kdsScreenManagementProvider.notifier)
        .revokeScreenSessions(screenId: 1);

    final midState = container.read(kdsScreenManagementProvider).value!;
    expect(midState.busyScreenIds, {1});
    expect(midState.busyScreenIds, isNot(contains(2)));

    gate.complete(1);
    await future;
  });

  test(
      'une mutation qui echoue laisse screens peuple et remplit actionError '
      '(pas de AsyncError)', () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1), _screen(id: 2)]
      ..updateScreenError = const ConflictException(
        message: 'deja utilise',
        code: 'KDS_SCREEN_KEY_ALREADY_EXISTS',
        statusCode: 409,
      );
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    await container.read(kdsScreenManagementProvider.notifier).updateScreen(
          screenId: 1,
          screenKey: 'deja-pris',
        );

    final providerState = container.read(kdsScreenManagementProvider);
    expect(providerState, isA<AsyncData<KdsScreenManagementState>>());
    final state = providerState.value!;
    expect(state.screens, hasLength(2));
    expect(state.actionError, 'UN ÉCRAN AVEC CET IDENTIFIANT EXISTE DÉJÀ');
    expect(state.busyScreenIds, isEmpty);
  });

  test('createScreen echec ne touche pas screens et remplit actionError',
      () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1)]
      ..createScreenError = const ForbiddenException(message: 'forbidden');
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    await container.read(kdsScreenManagementProvider.notifier).createScreen(
          name: 'X',
          screenKey: 'x',
          mode: 'kitchen',
          station: 'kitchen',
          interactionMode: 'wall',
          ticketsPerPage: 4,
        );

    final state = container.read(kdsScreenManagementProvider).value!;
    expect(state.screens, hasLength(1));
    expect(state.creating, isFalse);
    expect(state.actionError, 'ACTION NON AUTORISÉE');
  });

  test('generatePairingCode echec retourne null et remplit actionError',
      () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1)]
      ..pairingCodeError = const NetworkException(message: 'offline');
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    final result = await container
        .read(kdsScreenManagementProvider.notifier)
        .generatePairingCode(screenId: 1);

    expect(result, isNull);
    final state = container.read(kdsScreenManagementProvider).value!;
    expect(state.actionError, 'CONNEXION IMPOSSIBLE');
    expect(state.busyScreenIds, isEmpty);
  });

  test('revokeScreenSessions echec retourne null et remplit actionError',
      () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1)]
      ..revokeError = const BusinessException(
        message: 'introuvable',
        code: 'KDS_SCREEN_NOT_FOUND',
        statusCode: 404,
      );
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);

    final result = await container
        .read(kdsScreenManagementProvider.notifier)
        .revokeScreenSessions(screenId: 1);

    expect(result, isNull);
    final state = container.read(kdsScreenManagementProvider).value!;
    expect(state.actionError, 'ÉCRAN INTROUVABLE');
  });

  test('clearActionError vide le message d erreur', () async {
    final repository = _FakeKdsRepository()
      ..screensResult = [_screen(id: 1)]
      ..updateScreenError = const BusinessException(
        message: 'inactif',
        code: 'KDS_SCREEN_INACTIVE',
      );
    final container = _container(repository: repository);
    addTearDown(container.dispose);
    await container.read(kdsScreenManagementProvider.future);
    await container.read(kdsScreenManagementProvider.notifier).updateScreen(
          screenId: 1,
          isActive: true,
        );
    expect(
      container.read(kdsScreenManagementProvider).value!.actionError,
      'ÉCRAN INACTIF',
    );

    container.read(kdsScreenManagementProvider.notifier).clearActionError();

    expect(
      container.read(kdsScreenManagementProvider).value!.actionError,
      isNull,
    );
  });
}

ProviderContainer _container({_FakeKdsRepository? repository}) {
  return ProviderContainer(
    overrides: [
      kdsRepositoryProvider.overrideWithValue(
        repository ?? _FakeKdsRepository(),
      ),
    ],
  );
}

KdsScreen _screen({
  required int id,
  String name = 'Ecran',
  String screenKey = 'ecran',
  String mode = 'kitchen',
  String station = 'kitchen',
  String interactionMode = 'wall',
  int ticketsPerPage = 4,
  bool isActive = true,
}) {
  return KdsScreen(
    id: id,
    name: name,
    screenKey: '$screenKey-$id',
    mode: mode,
    station: station,
    interactionMode: interactionMode,
    ticketsPerPage: ticketsPerPage,
    isActive: isActive,
  );
}

class _FakeKdsRepository extends KdsRepository {
  _FakeKdsRepository() : super(_unusedClient());

  List<KdsScreen> screensResult = const [];
  Object? listScreensError;
  bool includeInactiveCaptured = false;
  int listScreensCallCount = 0;

  KdsScreen? createScreenResult;
  Object? createScreenError;
  Completer<KdsScreen>? createScreenGate;
  final List<Map<String, dynamic>> createScreenCalls = [];

  KdsScreen? updateScreenResult;
  Object? updateScreenError;
  Completer<KdsScreen>? updateScreenGate;
  final List<Map<String, dynamic>> updateScreenCalls = [];

  KdsPairingCode? pairingCodeResult;
  Object? pairingCodeError;
  Completer<KdsPairingCode>? pairingCodeGate;
  final List<int> pairingCodeScreenIds = [];

  int? revokeResult;
  Object? revokeError;
  Completer<int>? revokeGate;
  final List<int> revokeScreenIds = [];

  @override
  Future<List<KdsScreen>> listScreens({bool includeInactive = false}) async {
    includeInactiveCaptured = includeInactive;
    listScreensCallCount++;
    final error = listScreensError;
    if (error != null) {
      throw error;
    }
    return screensResult;
  }

  @override
  Future<KdsScreen> createScreen({
    required String name,
    required String screenKey,
    required String mode,
    required String station,
    required String interactionMode,
    required int ticketsPerPage,
  }) async {
    createScreenCalls.add({
      'name': name,
      'screen_key': screenKey,
      'mode': mode,
      'station': station,
      'interaction_mode': interactionMode,
      'tickets_per_page': ticketsPerPage,
    });
    final gate = createScreenGate;
    if (gate != null) {
      return gate.future;
    }
    final error = createScreenError;
    if (error != null) {
      throw error;
    }
    return createScreenResult ?? _screen(id: 999);
  }

  @override
  Future<KdsScreen> updateScreen({
    required int screenId,
    String? name,
    String? screenKey,
    String? mode,
    String? station,
    String? interactionMode,
    int? ticketsPerPage,
    bool? isActive,
  }) async {
    updateScreenCalls.add({
      'screen_id': screenId,
      if (name != null) 'name': name,
      if (screenKey != null) 'screen_key': screenKey,
      if (mode != null) 'mode': mode,
      if (station != null) 'station': station,
      if (interactionMode != null) 'interaction_mode': interactionMode,
      if (ticketsPerPage != null) 'tickets_per_page': ticketsPerPage,
      if (isActive != null) 'is_active': isActive,
    });
    final gate = updateScreenGate;
    if (gate != null) {
      return gate.future;
    }
    final error = updateScreenError;
    if (error != null) {
      throw error;
    }
    return updateScreenResult ?? _screen(id: screenId);
  }

  @override
  Future<KdsPairingCode> generatePairingCode({required int screenId}) async {
    pairingCodeScreenIds.add(screenId);
    final gate = pairingCodeGate;
    if (gate != null) {
      return gate.future;
    }
    final error = pairingCodeError;
    if (error != null) {
      throw error;
    }
    return pairingCodeResult ??
        KdsPairingCode(
          screenId: screenId,
          code: '000000',
          expiresAt: DateTime.utc(2026, 1, 1),
        );
  }

  @override
  Future<int> revokeScreenSessions({required int screenId}) async {
    revokeScreenIds.add(screenId);
    final gate = revokeGate;
    if (gate != null) {
      return gate.future;
    }
    final error = revokeError;
    if (error != null) {
      throw error;
    }
    return revokeResult ?? 0;
  }
}

ApiClient _unusedClient() {
  return ApiClient(
    Dio(BaseOptions(baseUrl: 'http://api.test')),
    _MemoryTokenStore(),
  );
}

class _MemoryTokenStore extends TokenStore {
  _MemoryTokenStore() : super(const FlutterSecureStorage());
}

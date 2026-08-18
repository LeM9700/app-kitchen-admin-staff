import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_remote_controller.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:app_admin_staff/features/kitchen/data/kitchen_remote_session_store.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

void main() {
  test('aucun token restaure disconnected', () async {
    final store = _MemoryRemoteSessionStore();
    final container = _container(store: store);
    addTearDown(container.dispose);

    final state = await container.read(kitchenRemoteSessionProvider.future);

    expect(state.phase, KitchenRemotePhase.disconnected);
    expect(state.session, isNull);
    expect(
      container.read(kitchenRemoteSessionProvider.notifier).isConnected,
      isFalse,
    );
    expect(
      container.read(kitchenRemoteSessionProvider.notifier).actionsAllowed,
      isFalse,
    );
  });

  test('token stocke valide restaure connected', () async {
    final store = _MemoryRemoteSessionStore('stored-token');
    final repository = _FakeKdsRepository()
      ..statusResult = _remoteStatus(screen: _screen(mode: 'counter'));
    final container = _container(store: store, repository: repository);
    addTearDown(container.dispose);

    final state = await container.read(kitchenRemoteSessionProvider.future);

    expect(repository.sessionTokens, ['stored-token']);
    expect(state.phase, KitchenRemotePhase.connected);
    expect(state.session?.sessionToken, 'stored-token');
    expect(state.session?.remoteSessionId, 44);
    expect(state.session?.screenId, 12);
    expect(state.session?.screenName, 'Cuisine principale');
    expect(state.session?.screenKey, 'kitchen-main');
    expect(state.session?.profile.mode, KitchenScreenMode.counter);
    expect(state.session?.profile.ticketsPerPage, 4);
    expect(
      container.read(kitchenRemoteSessionProvider.notifier).actionsAllowed,
      isTrue,
    );
  });

  test('token expire clear le store et revient disconnected', () async {
    final store = _MemoryRemoteSessionStore('expired-token');
    final repository = _FakeKdsRepository()
      ..statusError = const UnauthorizedException(
        message: 'expired',
        code: 'KDS_SESSION_EXPIRED',
        statusCode: 401,
      );
    final container = _container(store: store, repository: repository);
    addTearDown(container.dispose);

    final state = await container.read(kitchenRemoteSessionProvider.future);

    expect(state.phase, KitchenRemotePhase.disconnected);
    expect(state.message, 'SESSION EXPIRÉE');
    expect(store.token, isNull);
    expect(store.clearCalls, 1);
  });

  test('pair code valide sauvegarde le token et connecte', () async {
    final store = _MemoryRemoteSessionStore();
    final repository = _FakeKdsRepository()
      ..pairResult = KdsPairResult(
        sessionToken: 'new-token',
        expiresAt: DateTime.utc(2026, 8, 18, 22),
        screen: _screen(station: 'dessert', ticketsPerPage: 6),
      );
    final container = _container(store: store, repository: repository);
    addTearDown(container.dispose);
    await container.read(kitchenRemoteSessionProvider.future);

    await container
        .read(kitchenRemoteSessionProvider.notifier)
        .pairWithCode(code: '004281');

    final state = container.read(kitchenRemoteSessionProvider).valueOrNull!;
    expect(repository.pairCodes, ['004281']);
    expect(repository.deviceLabels, ['Kitchen Remote']);
    expect(store.token, 'new-token');
    expect(state.phase, KitchenRemotePhase.connected);
    expect(state.session?.profile.station, 'dessert');
    expect(state.session?.profile.ticketsPerPage, 6);
  });

  test('pair invalid affiche une erreur lisible sans sauvegarder', () async {
    final store = _MemoryRemoteSessionStore();
    final repository = _FakeKdsRepository()
      ..pairError = const BusinessException(
        message: 'invalid',
        code: 'PAIRING_CODE_INVALID',
        statusCode: 400,
      );
    final container = _container(store: store, repository: repository);
    addTearDown(container.dispose);
    await container.read(kitchenRemoteSessionProvider.future);

    await container
        .read(kitchenRemoteSessionProvider.notifier)
        .pairWithCode(code: '004281');

    final state = container.read(kitchenRemoteSessionProvider).valueOrNull!;
    expect(state.phase, KitchenRemotePhase.disconnected);
    expect(state.message, 'CODE INVALIDE');
    expect(store.token, isNull);
    expect(store.saveCalls, 0);
  });

  test('disconnect revoque cote serveur et supprime le token local', () async {
    final store = _MemoryRemoteSessionStore('stored-token');
    final repository = _FakeKdsRepository()
      ..statusResult = _remoteStatus()
      ..revokeResult = null;
    final container = _container(store: store, repository: repository);
    addTearDown(container.dispose);
    await container.read(kitchenRemoteSessionProvider.future);

    await container.read(kitchenRemoteSessionProvider.notifier).disconnect();

    final state = container.read(kitchenRemoteSessionProvider).valueOrNull!;
    expect(repository.revokedTokens, ['stored-token']);
    expect(store.token, isNull);
    expect(state.phase, KitchenRemotePhase.disconnected);
  });

  test('disconnect NetworkException supprime quand meme le token local',
      () async {
    final store = _MemoryRemoteSessionStore('stored-token');
    final repository = _FakeKdsRepository()
      ..statusResult = _remoteStatus()
      ..revokeError = const NetworkException(message: 'offline');
    final container = _container(store: store, repository: repository);
    addTearDown(container.dispose);
    await container.read(kitchenRemoteSessionProvider.future);

    await container.read(kitchenRemoteSessionProvider.notifier).disconnect();

    final state = container.read(kitchenRemoteSessionProvider).valueOrNull!;
    expect(repository.revokedTokens, ['stored-token']);
    expect(store.token, isNull);
    expect(state.phase, KitchenRemotePhase.disconnected);
    expect(state.message, contains('RÉVOCATION SERVEUR À VÉRIFIER'));
  });

  test('mappe les erreurs backend de pairing', () {
    expect(
      kdsPairingErrorMessage(
        const BusinessException(
          message: 'invalid',
          code: 'PAIRING_CODE_INVALID',
        ),
      ),
      'CODE INVALIDE',
    );
    expect(
      kdsPairingErrorMessage(
        const BusinessException(
          message: 'expired',
          code: 'PAIRING_CODE_EXPIRED',
        ),
      ),
      'CODE EXPIRÉ',
    );
    expect(
      kdsPairingErrorMessage(
        const ConflictException(
          message: 'used',
          code: 'PAIRING_CODE_ALREADY_USED',
        ),
      ),
      'CODE DÉJÀ UTILISÉ',
    );
    expect(
      kdsPairingErrorMessage(
        const ConflictException(
          message: 'inactive',
          code: 'KDS_SCREEN_INACTIVE',
        ),
      ),
      'ÉCRAN INDISPONIBLE',
    );
    expect(
      kdsPairingErrorMessage(
        const RateLimitException(message: 'rate limit', statusCode: 429),
      ),
      'TROP DE TENTATIVES, RÉESSAYEZ PLUS TARD',
    );
  });

  test('mappe les erreurs backend de session remote', () {
    expect(
      kdsRemoteSessionErrorMessage(
        const UnauthorizedException(
          message: 'invalid',
          code: 'KDS_SESSION_INVALID',
        ),
      ),
      'SESSION INVALIDE',
    );
    expect(
      kdsRemoteSessionErrorMessage(
        const UnauthorizedException(
          message: 'expired',
          code: 'KDS_SESSION_EXPIRED',
        ),
      ),
      'SESSION EXPIRÉE',
    );
    expect(
      kdsRemoteSessionErrorMessage(
        const UnauthorizedException(
          message: 'revoked',
          code: 'KDS_SESSION_REVOKED',
        ),
      ),
      'SESSION RÉVOQUÉE',
    );
  });
}

ProviderContainer _container({
  _MemoryRemoteSessionStore? store,
  _FakeKdsRepository? repository,
}) {
  return ProviderContainer(
    overrides: [
      kitchenRemoteSessionStoreProvider.overrideWithValue(
        store ?? _MemoryRemoteSessionStore(),
      ),
      kdsRepositoryProvider.overrideWithValue(
        repository ?? _FakeKdsRepository(),
      ),
    ],
  );
}

KdsScreen _screen({
  String mode = 'kitchen',
  String station = 'kitchen',
  int ticketsPerPage = 4,
}) {
  return KdsScreen(
    id: 12,
    name: 'Cuisine principale',
    screenKey: 'kitchen-main',
    mode: mode,
    station: station,
    interactionMode: 'wall',
    ticketsPerPage: ticketsPerPage,
    isActive: true,
  );
}

KdsRemoteSessionStatus _remoteStatus({KdsScreen? screen}) {
  return KdsRemoteSessionStatus(
    id: 44,
    screenId: 12,
    pairedByUserId: 7,
    deviceLabel: 'Kitchen Remote',
    createdAt: DateTime.utc(2026, 8, 18, 10),
    lastSeenAt: DateTime.utc(2026, 8, 18, 10, 5),
    expiresAt: DateTime.utc(2026, 8, 18, 22),
    screen: screen ?? _screen(),
  );
}

class _FakeKdsRepository extends KdsRepository {
  _FakeKdsRepository() : super(_unusedClient());

  KdsPairResult? pairResult;
  Object? pairError;
  KdsRemoteSessionStatus? statusResult;
  Object? statusError;
  Object? revokeResult;
  Object? revokeError;

  final List<String> pairCodes = [];
  final List<String?> deviceLabels = [];
  final List<String> sessionTokens = [];
  final List<String> revokedTokens = [];

  @override
  Future<List<KdsScreen>> listScreens({bool includeInactive = false}) async =>
      const [];

  @override
  Future<KdsPairResult> pair({
    required String code,
    String? deviceLabel,
  }) async {
    pairCodes.add(code);
    deviceLabels.add(deviceLabel);
    final error = pairError;
    if (error != null) {
      throw error;
    }
    return pairResult ??
        KdsPairResult(
          sessionToken: 'new-token',
          expiresAt: DateTime.utc(2026, 8, 18, 22),
          screen: _screen(),
        );
  }

  @override
  Future<KdsRemoteSessionStatus> getRemoteSession({
    required String sessionToken,
  }) async {
    sessionTokens.add(sessionToken);
    final error = statusError;
    if (error != null) {
      throw error;
    }
    return statusResult ?? _remoteStatus();
  }

  @override
  Future<void> revokeRemoteSession({required String sessionToken}) async {
    revokedTokens.add(sessionToken);
    final error = revokeError;
    if (error != null) {
      throw error;
    }
  }
}

class _MemoryRemoteSessionStore extends KitchenRemoteSessionStore {
  _MemoryRemoteSessionStore([this.token]) : super(const FlutterSecureStorage());

  String? token;
  int saveCalls = 0;
  int clearCalls = 0;

  @override
  Future<void> saveToken(String token) async {
    saveCalls++;
    this.token = token;
  }

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> clearToken() async {
    clearCalls++;
    token = null;
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

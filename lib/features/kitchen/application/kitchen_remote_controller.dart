import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:app_admin_staff/features/kitchen/data/kitchen_remote_session_store.dart';
import 'package:app_admin_staff/features/kitchen/domain/kds_screen_profile_mapper.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_remote_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final kitchenRemoteSessionProvider =
    AsyncNotifierProvider<KitchenRemoteController, KitchenRemoteState>(
  KitchenRemoteController.new,
);

enum KitchenRemotePhase {
  disconnected,
  pairing,
  connected,
  unavailable,
}

class KitchenRemoteState {
  const KitchenRemoteState._({
    required this.phase,
    this.session,
    this.message,
  });

  const KitchenRemoteState.disconnected({String? message})
      : this._(
          phase: KitchenRemotePhase.disconnected,
          message: message,
        );

  const KitchenRemoteState.pairing()
      : this._(phase: KitchenRemotePhase.pairing);

  const KitchenRemoteState.connected(KitchenRemoteSession session)
      : this._(
          phase: KitchenRemotePhase.connected,
          session: session,
        );

  const KitchenRemoteState.unavailable({
    KitchenRemoteSession? session,
    String? message,
  }) : this._(
          phase: KitchenRemotePhase.unavailable,
          session: session,
          message: message,
        );

  final KitchenRemotePhase phase;
  final KitchenRemoteSession? session;
  final String? message;

  bool get isConnected {
    return phase == KitchenRemotePhase.connected &&
        session?.status == KitchenRemoteSessionStatus.connected;
  }

  bool get isPairing => phase == KitchenRemotePhase.pairing;

  bool get hasSession => session != null;

  bool get actionsAllowed => isConnected;
}

class KitchenRemoteController extends AsyncNotifier<KitchenRemoteState> {
  static final _pairingCodePattern = RegExp(r'^\d{6}$');

  @override
  Future<KitchenRemoteState> build() {
    return _restoreFromStoredToken();
  }

  bool get isConnected => state.valueOrNull?.isConnected ?? false;

  bool get hasSession => state.valueOrNull?.hasSession ?? false;

  bool get actionsAllowed => state.valueOrNull?.actionsAllowed ?? false;

  Future<void> restoreSession() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_restoreFromStoredToken);
  }

  Future<void> pairWithCode({
    required String code,
    String? deviceLabel,
  }) async {
    final normalizedCode = code.trim();
    if (!_pairingCodePattern.hasMatch(normalizedCode)) {
      state = const AsyncValue.data(
        KitchenRemoteState.disconnected(message: 'CODE INVALIDE'),
      );
      return;
    }

    state = const AsyncValue.data(KitchenRemoteState.pairing());
    try {
      final result = await ref.read(kdsRepositoryProvider).pair(
            code: normalizedCode,
            deviceLabel: deviceLabel ?? 'Kitchen Remote',
          );
      await ref
          .read(kitchenRemoteSessionStoreProvider)
          .saveToken(result.sessionToken);
      state = AsyncValue.data(
        KitchenRemoteState.connected(_sessionFromPairResult(result)),
      );
    } on AppException catch (error) {
      state = AsyncValue.data(
        KitchenRemoteState.disconnected(
          message: kdsPairingErrorMessage(error),
        ),
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> disconnect() async {
    final currentSession = state.valueOrNull?.session;
    String? message;

    if (currentSession != null) {
      try {
        await ref.read(kdsRepositoryProvider).revokeRemoteSession(
              sessionToken: currentSession.sessionToken,
            );
      } on NetworkException {
        message = 'SESSION LOCALE DISSOCIÉE\nRÉVOCATION SERVEUR À VÉRIFIER';
      } on AppException catch (error) {
        if (!_isSessionTerminal(error.code)) {
          message = 'SESSION LOCALE DISSOCIÉE\nRÉVOCATION SERVEUR À VÉRIFIER';
        }
      }
    }

    await ref.read(kitchenRemoteSessionStoreProvider).clearToken();
    state = AsyncValue.data(KitchenRemoteState.disconnected(message: message));
  }

  Future<void> retry() {
    return restoreSession();
  }

  void markUnavailable() {
    final current = state.valueOrNull?.session;
    if (current == null) {
      return;
    }

    state = AsyncValue.data(
      KitchenRemoteState.unavailable(
        session:
            current.copyWith(status: KitchenRemoteSessionStatus.unavailable),
        message: 'SESSION INDISPONIBLE',
      ),
    );
  }

  Future<KitchenRemoteState> _restoreFromStoredToken() async {
    final store = ref.read(kitchenRemoteSessionStoreProvider);
    final token = await store.readToken();
    if (token == null) {
      return const KitchenRemoteState.disconnected();
    }

    try {
      final remote = await ref.read(kdsRepositoryProvider).getRemoteSession(
            sessionToken: token,
          );
      return KitchenRemoteState.connected(_sessionFromStatus(token, remote));
    } on NetworkException {
      return const KitchenRemoteState.unavailable(
        message: 'SESSION À VÉRIFIER\nHORS CONNEXION',
      );
    } on AppException catch (error) {
      final message = kdsRemoteSessionErrorMessage(error);
      if (_mustClearStoredToken(error.code)) {
        await store.clearToken();
        return KitchenRemoteState.disconnected(message: message);
      }
      return KitchenRemoteState.unavailable(
        message: message ?? 'SESSION À VÉRIFIER',
      );
    }
  }
}

KitchenRemoteSession _sessionFromPairResult(KdsPairResult result) {
  return KitchenRemoteSession(
    sessionToken: result.sessionToken,
    screenId: result.screen.id,
    screenName: result.screen.name,
    screenKey: result.screen.screenKey,
    profile: profileFromKdsScreen(result.screen),
    status: KitchenRemoteSessionStatus.connected,
    connectedAt: DateTime.now(),
    expiresAt: result.expiresAt,
  );
}

KitchenRemoteSession _sessionFromStatus(
  String sessionToken,
  KdsRemoteSessionStatus status,
) {
  return KitchenRemoteSession(
    sessionToken: sessionToken,
    remoteSessionId: status.id,
    screenId: status.screenId,
    screenName: status.screen.name,
    screenKey: status.screen.screenKey,
    profile: profileFromKdsScreen(status.screen),
    status: KitchenRemoteSessionStatus.connected,
    connectedAt: status.createdAt ?? DateTime.now(),
    expiresAt: status.expiresAt,
  );
}

String kdsPairingErrorMessage(AppException error) {
  if (error.statusCode == 429) {
    return 'TROP DE TENTATIVES, RÉESSAYEZ PLUS TARD';
  }

  return switch (error.code) {
    'PAIRING_CODE_INVALID' => 'CODE INVALIDE',
    'PAIRING_CODE_EXPIRED' => 'CODE EXPIRÉ',
    'PAIRING_CODE_ALREADY_USED' => 'CODE DÉJÀ UTILISÉ',
    'KDS_SCREEN_INACTIVE' => 'ÉCRAN INDISPONIBLE',
    _ when error is NetworkException => 'CONNEXION IMPOSSIBLE',
    _ => error.message,
  };
}

String? kdsRemoteSessionErrorMessage(AppException error) {
  return switch (error.code) {
    'KDS_SESSION_INVALID' => 'SESSION INVALIDE',
    'KDS_SESSION_EXPIRED' => 'SESSION EXPIRÉE',
    'KDS_SESSION_REVOKED' => 'SESSION RÉVOQUÉE',
    'KDS_SCREEN_INACTIVE' => 'ÉCRAN INDISPONIBLE',
    _ when error is NetworkException => 'SESSION À VÉRIFIER\nHORS CONNEXION',
    _ => error.message,
  };
}

bool _mustClearStoredToken(String? code) {
  return _isSessionTerminal(code) || code == 'KDS_SCREEN_INACTIVE';
}

bool _isSessionTerminal(String? code) {
  return code == 'KDS_SESSION_INVALID' ||
      code == 'KDS_SESSION_EXPIRED' ||
      code == 'KDS_SESSION_REVOKED';
}

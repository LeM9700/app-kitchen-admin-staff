import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/auth/session_events.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/features/auth/data/auth_repository.dart';
import 'package:app_admin_staff/features/kitchen/data/kitchen_remote_session_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() async {
    final invalidationCount = ref.watch(sessionInvalidationProvider);
    final stored = await ref.watch(tokenStoreProvider).read();
    if (stored == null) {
      if (invalidationCount > 0) {
        await ref.watch(kitchenRemoteSessionStoreProvider).clearToken();
      }
      return invalidationCount > 0
          ? const SessionState.sessionExpired()
          : const SessionState.unauthenticated();
    }
    return _hydrate(stored);
  }

  Future<void> login({
    required String tenantSlug,
    required String email,
    required String password,
    String? mfaCode,
  }) async {
    final previousChallenge = state.valueOrNull?.mfaChallenge;
    state = const AsyncValue.loading();
    try {
      final tokens = await ref.watch(authRepositoryProvider).login(
            tenantSlug: tenantSlug,
            email: email,
            password: password,
            mfaCode: mfaCode,
          );
      await ref.watch(kitchenRemoteSessionStoreProvider).clearToken();
      await _storeTokens(tokens, tenantSlug);
      state = AsyncValue.data(
        await _hydrate(
          StoredTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            tenantSlug: tenantSlug,
            sessionId: tokens.sessionId,
          ),
        ),
      );
    } on AppException catch (error, stackTrace) {
      if (error.code == 'MFA_REQUIRED') {
        // The backend requires a second login call with mfa_code, so the
        // password is kept only in memory for this short-lived challenge.
        state = AsyncValue.data(
          SessionState.mfaRequired(
            MfaChallenge(
              tenantSlug: tenantSlug,
              email: email,
              password: password,
              error: error.message,
            ),
          ),
        );
        return;
      }
      if (error.code == 'INVALID_MFA_CODE') {
        if (previousChallenge != null) {
          state = AsyncValue.data(
            SessionState.mfaRequired(
              previousChallenge.copyWith(
                error: error.message,
              ),
            ),
          );
          return;
        }
      }
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> submitMfa(String mfaCode) async {
    final challenge = state.valueOrNull?.mfaChallenge;
    if (challenge == null) {
      state = const AsyncValue.data(SessionState.unauthenticated());
      return;
    }
    await login(
      tenantSlug: challenge.tenantSlug,
      email: challenge.email,
      password: challenge.password,
      mfaCode: mfaCode,
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final current = state.valueOrNull;
    final sessionId = current?.sessionId;
    state = const AsyncValue.loading();
    try {
      await ref.watch(authRepositoryProvider).changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
            sessionId: sessionId,
          );
      final refreshed =
          await ref.watch(authRepositoryProvider).refreshSession();
      if (!refreshed) {
        await _clearStoredSession();
        state = const AsyncValue.data(SessionState.sessionExpired());
        return;
      }
      final stored = await ref.watch(tokenStoreProvider).read();
      if (stored == null) {
        await _clearStoredSession();
        state = const AsyncValue.data(SessionState.sessionExpired());
        return;
      }
      state = AsyncValue.data(await _hydrate(stored));
    } on AppException catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> logout() async {
    try {
      await ref.watch(authRepositoryProvider).logout();
    } catch (_) {
      // Local logout still wins if the server is unreachable.
    }
    await _clearStoredSession();
    state = const AsyncValue.data(SessionState.unauthenticated());
  }

  Future<void> acknowledgeSessionExpired() async {
    await _clearStoredSession();
    state = const AsyncValue.data(SessionState.unauthenticated());
  }

  Future<SessionState> _hydrate(StoredTokens stored) async {
    try {
      final user = await ref
          .watch(authRepositoryProvider)
          .me(tenantSlug: stored.tenantSlug);
      return _stateForUser(user, stored);
    } on ForbiddenException catch (error) {
      if (_isMustChangePassword(error.code)) {
        try {
          final jwtUser = StaffUser.fromJwt(stored.accessToken);
          return SessionState.mustChangePassword(
            user: jwtUser,
            tenantSlug: stored.tenantSlug,
            sessionId: stored.sessionId,
            error: error.message,
          );
        } on FormatException {
          await _clearStoredSession();
          return const SessionState.sessionExpired();
        }
      }
      rethrow;
    } on UnauthorizedException {
      await _clearStoredSession();
      return const SessionState.sessionExpired();
    } on FormatException {
      await _clearStoredSession();
      return const SessionState.unauthenticated();
    }
  }

  SessionState _stateForUser(StaffUser user, StoredTokens stored) {
    _logDev(
      'auth transition user=${user.id} status=${user.mustChangePassword}',
    );
    if (user.mustChangePassword) {
      return SessionState.mustChangePassword(
        user: user,
        tenantSlug: stored.tenantSlug,
        sessionId: stored.sessionId,
      );
    }
    return SessionState.authenticated(
      user: user,
      tenantSlug: stored.tenantSlug,
      sessionId: stored.sessionId,
    );
  }

  Future<void> _storeTokens(AuthTokens tokens, String tenantSlug) {
    return ref.watch(tokenStoreProvider).write(
          StoredTokens(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            tenantSlug: tenantSlug,
            sessionId: tokens.sessionId,
          ),
        );
  }

  Future<void> _clearStoredSession() async {
    await ref.watch(tokenStoreProvider).clear();
    await ref.watch(kitchenRemoteSessionStoreProvider).clearToken();
  }

  bool _isMustChangePassword(String? code) {
    return code == 'PASSWORD_CHANGE_REQUIRED' || code == 'MUST_CHANGE_PASSWORD';
  }

  void _logDev(String message) {
    if (kDebugMode) {
      debugPrint('[auth] $message');
    }
  }
}

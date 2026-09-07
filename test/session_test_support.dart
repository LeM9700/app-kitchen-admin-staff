import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Builds an authenticated [SessionState] for tests that need
/// [sessionControllerProvider] to resolve to a known tenant/user without
/// exercising the real login/token flow.
SessionState testAuthenticatedSession({
  required String tenantSlug,
  int userId = 1,
  String email = 'staff@test.com',
  String role = 'staff',
  int sessionId = 1,
}) {
  return SessionState.authenticated(
    user: StaffUser(
      id: userId,
      email: email,
      role: role,
      tenantSlug: tenantSlug,
      permissions: const {},
      mustChangePassword: false,
    ),
    tenantSlug: tenantSlug,
    sessionId: sessionId,
  );
}

/// Overrides [sessionControllerProvider] to resolve immediately to [session]
/// (or to unauthenticated if omitted), bypassing the real token/API bootstrap.
Override sessionControllerOverride(SessionState? session) {
  return sessionControllerProvider.overrideWith(
    () => _FixedSessionController(
      session ?? const SessionState.unauthenticated(),
    ),
  );
}

class _FixedSessionController extends SessionController {
  _FixedSessionController(this._session);

  final SessionState _session;

  @override
  Future<SessionState> build() => SynchronousFuture(_session);
}

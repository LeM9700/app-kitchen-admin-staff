import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/router/app_router.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loading session stays on bootstrap instead of flashing login', () {
    const loading = AsyncLoading<SessionState>();

    expect(redirectForSession(loading, '/dashboard'), '/bootstrap');
    expect(redirectForSession(loading, '/bootstrap'), isNull);
  });

  test('unauthenticated users are redirected to login', () {
    expect(
      redirectForSession(
        const AsyncData(SessionState.unauthenticated()),
        '/dashboard',
      ),
      '/login',
    );
    expect(
      redirectForSession(
        const AsyncData(SessionState.unauthenticated()),
        '/bootstrap',
      ),
      '/login',
    );
  });

  test('admin can access admin routes', () {
    expect(
      redirectForSession(
        AsyncData(
          SessionState.authenticated(
            user: _user(role: 'admin'),
            tenantSlug: 'pizza',
            sessionId: 1,
          ),
        ),
        '/payments',
      ),
      isNull,
    );
  });

  test('staff can access routes allowed by permissions', () {
    expect(
      redirectForSession(
        AsyncData(
          SessionState.authenticated(
            user: _user(
              role: 'staff',
              permissions: {AppPermission.ordersRead},
            ),
            tenantSlug: 'pizza',
            sessionId: 1,
          ),
        ),
        '/orders',
      ),
      isNull,
    );
  });

  test('authenticated users land on role-appropriate first route', () {
    final staffSession = AsyncData(
      SessionState.authenticated(
        user: _user(role: 'staff', permissions: {AppPermission.ordersRead}),
        tenantSlug: 'pizza',
        sessionId: 1,
      ),
    );
    final adminSession = AsyncData(
      SessionState.authenticated(
        user: _user(role: 'admin'),
        tenantSlug: 'pizza',
        sessionId: 1,
      ),
    );

    expect(redirectForSession(staffSession, '/bootstrap'), '/orders');
    expect(redirectForSession(adminSession, '/bootstrap'), '/dashboard');
  });

  test('must change password is forced to dedicated route', () {
    expect(
      redirectForSession(
        AsyncData(
          SessionState.mustChangePassword(
            user: _user(mustChangePassword: true),
            tenantSlug: 'pizza',
            sessionId: 1,
          ),
        ),
        '/dashboard',
      ),
      '/change-password',
    );
  });

  test('mfa state is forced to mfa route', () {
    expect(
      redirectForSession(
        AsyncData(
          SessionState.mfaRequired(
            const MfaChallenge(
              tenantSlug: 'pizza',
              email: 'admin@test.com',
              password: 'Secret1!',
            ),
          ),
        ),
        '/login',
      ),
      '/mfa',
    );
  });

  test('session expired is forced to session expired route', () {
    expect(
      redirectForSession(
        const AsyncData(SessionState.sessionExpired()),
        '/dashboard',
      ),
      '/session-expired',
    );
  });

  test('permission denied redirects to forbidden', () {
    expect(
      redirectForSession(
        AsyncData(
          SessionState.authenticated(
            user: _user(
              role: 'staff',
              permissions: {AppPermission.ordersRead},
            ),
            tenantSlug: 'pizza',
            sessionId: 1,
          ),
        ),
        '/payments',
      ),
      '/forbidden',
    );
  });

  test('dashboard, admin users and admin HR routes require admin role', () {
    final staffSession = AsyncData(
      SessionState.authenticated(
        user: _user(role: 'staff', permissions: {AppPermission.ordersRead}),
        tenantSlug: 'pizza',
        sessionId: 1,
      ),
    );

    expect(redirectForSession(staffSession, '/dashboard'), '/forbidden');
    expect(redirectForSession(staffSession, '/team'), '/forbidden');
    expect(redirectForSession(staffSession, '/hr/admin'), '/forbidden');
  });

  test('staff can access self HR route', () {
    expect(
      redirectForSession(
        AsyncData(
          SessionState.authenticated(
            user: _user(role: 'staff', permissions: {AppPermission.ordersRead}),
            tenantSlug: 'pizza',
            sessionId: 1,
          ),
        ),
        '/hr',
      ),
      isNull,
    );
  });
}

StaffUser _user({
  String role = 'admin',
  Set<String>? permissions,
  bool mustChangePassword = false,
}) {
  return StaffUser(
    id: 1,
    email: 'user@test.com',
    role: role,
    tenantSlug: 'pizza',
    permissions: permissions,
    mustChangePassword: mustChangePassword,
  );
}

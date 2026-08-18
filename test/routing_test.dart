import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/router/app_router.dart';
import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/widgets/admin_shell.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_connection.dart';
import 'package:app_admin_staff/features/kitchen/data/kitchen_remote_session_store.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  test('staff preparation permission donne acces au remote KDS', () {
    expect(
      redirectForSession(
        AsyncData(
          SessionState.authenticated(
            user: _user(
              role: 'staff',
              permissions: {AppPermission.ordersPreparation},
            ),
            tenantSlug: 'pizza',
            sessionId: 1,
          ),
        ),
        '/kitchen/remote',
      ),
      isNull,
    );
  });

  test('remote KDS conserve la permission preparation par prefixe kitchen', () {
    expect(routePermission('/kitchen'), AppPermission.ordersPreparation);
    expect(routePermission('/kitchen/remote'), AppPermission.ordersPreparation);
  });

  test('remote KDS redirige les sessions non autorisees', () {
    expect(
      redirectForSession(
        const AsyncData(SessionState.unauthenticated()),
        '/kitchen/remote',
      ),
      '/login',
    );
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
        '/kitchen/remote',
      ),
      '/forbidden',
    );
  });

  testWidgets('remote KDS existe et s ouvre hors AdminShell', (tester) async {
    await _pumpRouterAt(tester, '/kitchen/remote');

    expect(find.text('AUCUN ÉCRAN ASSOCIÉ'), findsOneWidget);
    expect(find.byType(AdminShell), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('API KITCHEN'), findsNothing);
  });

  testWidgets('kitchen classique reste dans AdminShell', (tester) async {
    await _pumpRouterAt(tester, '/kitchen');

    expect(find.byType(AdminShell), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('AUCUNE COMMANDE EN COURS'), findsOneWidget);
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

Future<void> _pumpRouterAt(
  WidgetTester tester,
  String location,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      sessionControllerProvider.overrideWith(
        _PreparationStaffSessionController.new,
      ),
      activeOrdersProvider.overrideWith((ref) async => const []),
      tenantConfigProvider.overrideWith((ref) async => _tenantConfig()),
      kitchenRemoteSessionStoreProvider.overrideWithValue(
        _EmptyKitchenRemoteSessionStore(),
      ),
      kitchenConnectionStateProvider.overrideWithValue(
        const KitchenConnectionState(
          status: KitchenConnectionStatus.online,
          pendingActions: 0,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(appRouterProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  router.go(location);
  await tester.pumpAndSettle();
}

class _EmptyKitchenRemoteSessionStore extends KitchenRemoteSessionStore {
  _EmptyKitchenRemoteSessionStore() : super(const FlutterSecureStorage());

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> clearToken() async {}
}

class _PreparationStaffSessionController extends SessionController {
  @override
  Future<SessionState> build() async {
    return SessionState.authenticated(
      user: _user(
        role: 'staff',
        permissions: {AppPermission.ordersPreparation},
      ),
      tenantSlug: 'pizza',
      sessionId: 1,
    );
  }
}

TenantConfig _tenantConfig() {
  return const TenantConfig(
    id: 1,
    isTemporarilyClosed: false,
    defaultClosureMessage: '',
    prepTimeNormalMinutes: 15,
    prepTimePeakMinutes: 20,
    peakOrdersThreshold: 8,
    autoCalcPrepTime: true,
    overheadPerOrderMinutes: 2,
    timezone: 'Europe/Paris',
    largeStockAdjustmentThreshold: 10,
    printEnabled: false,
    printConfig: {},
  );
}

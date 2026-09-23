import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/app/navigation/navigation_capabilities.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/widgets/admin_shell.dart';
import 'package:app_admin_staff/features/auth/presentation/auth_flow_pages.dart';
import 'package:app_admin_staff/features/auth/presentation/login_page.dart';
import 'package:app_admin_staff/features/admin_users/presentation/admin_users_page.dart';
import 'package:app_admin_staff/features/catalog/presentation/catalog_page.dart';
import 'package:app_admin_staff/features/checkout/presentation/checkout_page.dart';
import 'package:app_admin_staff/features/customers/presentation/customers_page.dart';
import 'package:app_admin_staff/features/dashboard/presentation/dashboard_page.dart';
import 'package:app_admin_staff/features/delivery/presentation/delivery_page.dart';
import 'package:app_admin_staff/features/hr/presentation/hr_page.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_page.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_remote_page.dart';
import 'package:app_admin_staff/features/loyalty/presentation/loyalty_page.dart';
import 'package:app_admin_staff/features/orders/presentation/orders_board_page.dart';
import 'package:app_admin_staff/features/payments/presentation/payments_page.dart';
import 'package:app_admin_staff/features/promotions/presentation/promotions_page.dart';
import 'package:app_admin_staff/features/settings/presentation/settings_page.dart';
import 'package:app_admin_staff/features/stock/presentation/stock_dlc_page.dart';
import 'package:app_admin_staff/features/stock/presentation/stock_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_check_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_cleaning_tasks_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_cooling_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_equipment_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_export_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_nc_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_reception_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_stats_page.dart';
import 'package:app_admin_staff/features/haccp/presentation/haccp_training_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier();
  ref
    ..onDispose(refresh.dispose)
    ..listen(sessionControllerProvider, (previous, next) {
      refresh.notify();
    });

  return GoRouter(
    initialLocation: _bootstrapPath,
    refreshListenable: refresh,
    redirect: (context, state) {
      return redirectForSession(
        ref.read(sessionControllerProvider),
        state.uri.path,
      );
    },
    routes: [
      GoRoute(
        path: _bootstrapPath,
        builder: (context, state) => const BootstrapPage(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/mfa',
        builder: (context, state) => const MfaChallengePage(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const MustChangePasswordPage(),
      ),
      GoRoute(
        path: '/session-expired',
        builder: (context, state) => const SessionExpiredPage(),
      ),
      GoRoute(
        path: '/forbidden',
        builder: (context, state) => const ForbiddenPage(),
      ),
      GoRoute(
        path: '/kitchen/remote',
        builder: (context, state) => const KitchenRemotePage(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return AdminShell(
            location: state.uri.path,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrdersBoardPage(),
          ),
          GoRoute(
            path: '/kitchen',
            builder: (context, state) => const KitchenPage(),
          ),
          GoRoute(
            path: '/checkout',
            builder: (context, state) => const CheckoutPage(),
          ),
          GoRoute(
            path: '/catalog',
            builder: (context, state) => const CatalogPage(),
          ),
          GoRoute(
            path: '/stock',
            builder: (context, state) => const StockPage(),
            routes: [
              GoRoute(
                path: 'dlc',
                builder: (context, state) => const StockDlcPage(),
              ),
            ],
          ),
          GoRoute(
            path: '/team',
            builder: (context, state) => const AdminUsersPage(),
          ),
          GoRoute(
            path: '/customers',
            builder: (context, state) => const CustomersPage(),
            routes: [
              GoRoute(
                path: ':customerId',
                builder: (context, state) {
                  final customerId =
                      int.tryParse(state.pathParameters['customerId'] ?? '');
                  return CustomersPage(initialCustomerId: customerId);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/hr/admin',
            builder: (context, state) => const HrAdminPage(),
          ),
          GoRoute(
            path: '/hr',
            builder: (context, state) => const StaffHrPage(),
          ),
          GoRoute(
            path: '/payments',
            builder: (context, state) => const PaymentsPage(),
          ),
          GoRoute(
            path: '/delivery',
            builder: (context, state) => const DeliveryPage(),
          ),
          GoRoute(
            path: '/loyalty',
            builder: (context, state) => const LoyaltyPage(),
          ),
          GoRoute(
            path: '/promotions',
            builder: (context, state) => const PromotionsPage(),
          ),
          GoRoute(
            path: '/haccp',
            builder: (context, state) => const HaccpCheckPage(),
            routes: [
              GoRoute(
                path: 'nc',
                builder: (context, state) => const HaccpNonConformityPage(),
              ),
              GoRoute(
                path: 'reception',
                builder: (context, state) => const HaccpReceptionPage(),
              ),
              GoRoute(
                path: 'cooling',
                builder: (context, state) => const HaccpCoolingPage(),
              ),
              GoRoute(
                path: 'training',
                builder: (context, state) => const HaccpTrainingPage(),
              ),
              GoRoute(
                path: 'export',
                builder: (context, state) => const HaccpExportPage(),
              ),
              GoRoute(
                path: 'stats',
                builder: (context, state) => const HaccpStatsPage(),
              ),
              GoRoute(
                path: 'equipment',
                builder: (context, state) => const HaccpEquipmentPage(),
              ),
              GoRoute(
                path: 'cleaning-tasks',
                builder: (context, state) => const HaccpCleaningTasksPage(),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});

String? redirectForSession(
  AsyncValue<SessionState> session,
  String location,
) {
  final status = session.valueOrNull?.status;
  final isBootstrap = location == _bootstrapPath;
  final isAuthPath = _authPaths.contains(location);

  if (session.isLoading || status == null || status == SessionStatus.unknown) {
    return isBootstrap ? null : _bootstrapPath;
  }

  switch (status) {
    case SessionStatus.unauthenticated:
      return isAuthPath ? null : '/login';
    case SessionStatus.mfaRequired:
      return location == '/mfa' ? null : '/mfa';
    case SessionStatus.mustChangePassword:
      return location == '/change-password' ? null : '/change-password';
    case SessionStatus.sessionExpired:
      return location == '/session-expired' ? null : '/session-expired';
    case SessionStatus.authenticated:
      if (isAuthPath || isBootstrap) {
        return _landingFor(session.valueOrNull?.user);
      }
      final permission = routePermission(location);
      final role = routeRequiredRole(location);
      final user = session.valueOrNull?.user;
      final permissions = PermissionSet(
        role: user?.role ?? 'staff',
        permissions: user?.permissions,
      );
      if (role != null && !permissions.hasRole(role)) {
        return '/forbidden';
      }
      if (permission != null) {
        if (!permissions.can(permission)) {
          return '/forbidden';
        }
      }
      return null;
    case SessionStatus.unknown:
      return isBootstrap ? null : _bootstrapPath;
  }
}

String? routePermission(String location) {
  return navigationForLocation(location)?.permission;
}

String? routeRequiredRole(String location) {
  return navigationForLocation(location)?.requiredRole;
}

String _landingFor(StaffUser? user) {
  final permissions = PermissionSet(
    role: user?.role ?? 'staff',
    permissions: user?.permissions,
  );
  const routes = _defaultRoutes;
  for (final route in routes) {
    final role = routeRequiredRole(route);
    if (role != null && !permissions.hasRole(role)) {
      continue;
    }
    final permission = routePermission(route);
    if (permission == null || permissions.can(permission)) {
      return route;
    }
  }
  return '/settings';
}

const _authPaths = {
  '/login',
  '/mfa',
  '/change-password',
  '/session-expired',
};

const _bootstrapPath = '/bootstrap';

const _adminDefaultRoutes = [
  '/home',
  '/orders',
  '/kitchen',
  '/checkout',
  '/catalog',
  '/stock',
  '/team',
  '/customers',
  '/haccp',
  '/hr',
  '/hr/admin',
  '/payments',
  '/delivery',
  '/loyalty',
  '/promotions',
  '/settings',
];

const _defaultRoutes = _adminDefaultRoutes;

class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() {
    notifyListeners();
  }
}

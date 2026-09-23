import 'package:app_admin_staff/app/theme/app_theme.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/features/dashboard/data/dashboard_repository.dart';
import 'package:app_admin_staff/features/dashboard/presentation/dashboard_page.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/hr/data/hr_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [390.0, 768.0, 1024.0, 1440.0]) {
    testWidgets('home renders without overflow at ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: DashboardPage()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('A traiter maintenant'), findsOneWidget);
      expect(find.text('Vue groupe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

List<Override> _overrides() {
  return [
    sessionControllerProvider.overrideWith(_AdminSessionController.new),
    onlineStatusProvider.overrideWith((ref) => Stream.value(true)),
    availableEstablishmentsProvider.overrideWith(
      (ref) async => [
        const Establishment(
          id: 1,
          name: 'Restaurant Montpellier',
          timezone: 'Europe/Paris',
          isActive: true,
        ),
        const Establishment(
          id: 2,
          name: 'Restaurant Nimes',
          timezone: 'Europe/Paris',
          isActive: true,
        ),
      ],
    ),
    activeOrdersProvider.overrideWith(
      (ref) async => [
        OrderSummary(
          id: 184,
          orderType: 'dine_in',
          status: 'preparing',
          paymentStatus: 'paid',
          source: 'manual',
          total: 24,
          deliveryFee: 0,
          createdAt: DateTime.now().subtract(const Duration(minutes: 42)),
        ),
      ],
    ),
    stockAlertsProvider.overrideWith(
      (ref) async => const [
        Ingredient(
          id: 1,
          name: 'Mozzarella',
          unit: 'kg',
          currentQty: 1,
          alertThreshold: 2,
          isBelowThreshold: true,
        ),
      ],
    ),
    paymentsSummaryProvider.overrideWith(
      (ref) async => const PaymentSummary(
        collectedAmountCents: 12000,
        refundedAmountCents: 0,
        netAmountCents: 12000,
        paymentCount: 4,
        refundCount: 0,
        countsByStatus: {'succeeded': 4},
      ),
    ),
    tenantStatusProvider.overrideWith(
      (ref) async => const TenantStatus(
        isOpen: true,
        estimatedPrepTimeMinutes: 14,
        activeOrdersCount: 1,
      ),
    ),
    tenantPrintConfigProvider.overrideWith(
      (ref) async => const TenantPrintConfig(
        enabled: true,
        config: {
          'kitchen_printer': 'Cuisine',
          'counter_printer': 'Comptoir',
          'kitchen_host_confirmed': true,
          'counter_host_confirmed': true,
        },
      ),
    ),
    terminalReadersProvider.overrideWith(
      (ref) async => const [
        TerminalReader(
          id: 'tmr_1',
          label: 'TPE comptoir',
          status: 'online',
          raw: {},
        ),
      ],
    ),
    statsSummaryProvider.overrideWith(
      (ref) async => const StatsSummary(
        live: LiveStats(
          ordersLast24h: 8,
          revenueLast24h: 240,
          avgOrderValue24h: 30,
          pendingOrders: 1,
        ),
      ),
    ),
    topProductsProvider.overrideWith(
      (ref) async => const [
        TopProductStats(
          productId: 1,
          productName: 'Margherita',
          quantity: 12,
          revenue: 132,
        ),
      ],
    ),
    groupOverviewProvider.overrideWith(
      (ref) async => const GroupOverview(
        establishmentCount: 2,
        okCount: 1,
        warningCount: 1,
        criticalCount: 0,
        items: [
          GroupOverviewItem(
            establishmentId: 1,
            establishmentName: 'Restaurant Montpellier',
            status: 'ok',
            activeOrders: 1,
            pendingOrders: 0,
            lateOrders: 0,
            revenueToday: 120,
            staffPresent: 2,
            staffExpected: 2,
          ),
          GroupOverviewItem(
            establishmentId: 2,
            establishmentName: 'Restaurant Nimes',
            status: 'warning',
            activeOrders: 4,
            pendingOrders: 3,
            lateOrders: 0,
            revenueToday: 90,
            staffPresent: 1,
            staffExpected: 2,
          ),
        ],
      ),
    ),
    myShiftsProvider.overrideWith(
      (ref, query) async => [
        HrShift(
          id: 1,
          employeeId: 1,
          establishmentId: 1,
          startsAt: DateTime.now().add(const Duration(hours: 2)),
          endsAt: DateTime.now().add(const Duration(hours: 7)),
          breakMinutes: 30,
          status: 'scheduled',
        ),
      ],
    ),
    myTimeClockEntriesProvider.overrideWith((ref, query) async => const []),
  ];
}

class _AdminSessionController extends SessionController {
  @override
  Future<SessionState> build() {
    return SynchronousFuture(
      const SessionState.authenticated(
        user: StaffUser(
          id: 1,
          email: 'admin@test.com',
          role: 'admin',
          tenantSlug: 'pizza',
          permissions: {},
          mustChangePassword: false,
        ),
        tenantSlug: 'pizza',
        sessionId: 1,
      ),
    );
  }
}

import 'package:app_admin_staff/features/dashboard/application/home_models.dart';
import 'package:app_admin_staff/features/dashboard/data/dashboard_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home alerts prioritize operational issues and limit to five', () {
    final now = DateTime(2026, 9, 17, 12);
    final alerts = buildHomeAlerts(
      orders: [
        _order(
          184,
          status: 'preparing',
          createdAt: now.subtract(const Duration(minutes: 50)),
        ),
        _order(
          185,
          status: 'preparing',
          createdAt: now.subtract(const Duration(minutes: 35)),
        ),
        _order(
          186,
          status: 'pending',
          createdAt: now.subtract(const Duration(minutes: 4)),
        ),
        _order(
          187,
          status: 'pending',
          createdAt: now.subtract(const Duration(minutes: 3)),
        ),
        _order(
          188,
          status: 'pending',
          createdAt: now.subtract(const Duration(minutes: 2)),
        ),
        _order(
          189,
          status: 'pending',
          createdAt: now.subtract(const Duration(minutes: 1)),
        ),
        _order(190, status: 'pending', createdAt: now),
        _order(191, status: 'pending', createdAt: now),
      ],
      stockAlerts: [_ingredient('Mozzarella'), _ingredient('Pate')],
      payments: const PaymentSummary(
        collectedAmountCents: 1000,
        refundedAmountCents: 0,
        netAmountCents: 1000,
        paymentCount: 1,
        refundCount: 0,
        countsByStatus: {'failed': 2},
      ),
      tenant: const TenantStatus(
        isOpen: true,
        estimatedPrepTimeMinutes: 18,
        activeOrdersCount: 8,
      ),
      online: false,
      queuedActions: 3,
      establishmentLabel: 'Restaurant Montpellier',
      now: now,
    );

    expect(alerts, hasLength(5));
    expect(alerts.first.severity, HomeAlertSeverity.critical);
    expect(alerts.any((alert) => alert.title == 'Application offline'), isTrue);
    expect(alerts.any((alert) => alert.type == 'Commande en retard'), isTrue);
    expect(alerts.any((alert) => alert.title.contains('action(s)')), isTrue);
  });

  test('home alerts do not invent alerts when providers are clean', () {
    final alerts = buildHomeAlerts(
      orders: const [],
      stockAlerts: const [],
      payments: const PaymentSummary(
        collectedAmountCents: 0,
        refundedAmountCents: 0,
        netAmountCents: 0,
        paymentCount: 0,
        refundCount: 0,
        countsByStatus: {},
      ),
      tenant: const TenantStatus(
        isOpen: true,
        estimatedPrepTimeMinutes: 12,
        activeOrdersCount: 0,
      ),
      online: true,
      queuedActions: 0,
      establishmentLabel: 'Restaurant Montpellier',
    );

    expect(alerts, isEmpty);
  });

  test('group overview parses establishment health payload', () {
    final overview = GroupOverview.fromJson({
      'establishment_count': 2,
      'ok_count': 1,
      'warning_count': 1,
      'critical_count': 0,
      'items': [
        {
          'establishment_id': 7,
          'establishment_name': 'Restaurant Nimes',
          'status': 'warning',
          'active_orders': 6,
          'pending_orders': 4,
          'late_orders': 1,
          'revenue_today': 425.75,
          'staff_present': 2,
          'staff_expected': 3,
        }
      ],
    });

    expect(overview.establishmentCount, 2);
    expect(overview.items.single.establishmentId, 7);
    expect(overview.items.single.revenueToday, 425.75);
  });
}

OrderSummary _order(
  int id, {
  required String status,
  required DateTime createdAt,
}) {
  return OrderSummary(
    id: id,
    orderType: 'dine_in',
    status: status,
    paymentStatus: 'paid',
    source: 'customer',
    total: 12,
    deliveryFee: 0,
    createdAt: createdAt,
  );
}

Ingredient _ingredient(String name) {
  return Ingredient(
    id: name.hashCode,
    name: name,
    unit: 'kg',
    currentQty: 1,
    alertThreshold: 2,
    isBelowThreshold: true,
  );
}

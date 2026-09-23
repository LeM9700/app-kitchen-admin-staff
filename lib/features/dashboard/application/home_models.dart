import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';

enum HomeAlertSeverity { critical, urgent, watch }

class HomeAlert {
  const HomeAlert({
    required this.type,
    required this.title,
    required this.body,
    required this.route,
    required this.icon,
    required this.severity,
    required this.establishmentLabel,
    this.ageLabel,
  });

  final String type;
  final String title;
  final String body;
  final String route;
  final IconData icon;
  final HomeAlertSeverity severity;
  final String establishmentLabel;
  final String? ageLabel;
}

List<HomeAlert> buildHomeAlerts({
  required List<OrderSummary> orders,
  required List<Ingredient> stockAlerts,
  required PaymentSummary? payments,
  required TenantStatus? tenant,
  required bool online,
  required int queuedActions,
  required String establishmentLabel,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final alerts = <HomeAlert>[];

  if (!online) {
    alerts.add(
      HomeAlert(
        type: 'Systeme',
        title: 'Application offline',
        body: 'Les actions seront conservees localement.',
        route: '/settings',
        icon: Icons.wifi_off_outlined,
        severity: HomeAlertSeverity.critical,
        establishmentLabel: establishmentLabel,
      ),
    );
  }

  if (queuedActions > 0) {
    alerts.add(
      HomeAlert(
        type: 'Synchronisation',
        title: '$queuedActions action(s) en attente',
        body: 'La file locale doit etre synchronisee.',
        route: '/settings',
        icon: Icons.cloud_sync_outlined,
        severity: HomeAlertSeverity.urgent,
        establishmentLabel: establishmentLabel,
      ),
    );
  }

  final lateOrders = [
    for (final order in orders)
      if (_lateMinutes(order, clock) >= 30) order,
  ]..sort((a, b) => _lateMinutes(b, clock).compareTo(_lateMinutes(a, clock)));
  for (final order in lateOrders.take(2)) {
    final minutes = _lateMinutes(order, clock);
    alerts.add(
      HomeAlert(
        type: 'Commande en retard',
        title: '#${order.id}',
        body:
            '${_humanOrderType(order.orderType)} - ${_humanStatus(order.status)}',
        route: '/orders',
        icon: Icons.receipt_long_outlined,
        severity: minutes >= 45
            ? HomeAlertSeverity.critical
            : HomeAlertSeverity.urgent,
        establishmentLabel: establishmentLabel,
        ageLabel: '+$minutes min',
      ),
    );
  }

  final pendingOrders =
      orders.where((order) => order.status == 'pending').length;
  if (pendingOrders >= 6) {
    alerts.add(
      HomeAlert(
        type: 'Service',
        title: '$pendingOrders commandes en attente',
        body: 'Le flux de prise en charge ralentit.',
        route: '/orders',
        icon: Icons.pending_actions_outlined,
        severity: HomeAlertSeverity.urgent,
        establishmentLabel: establishmentLabel,
      ),
    );
  }

  for (final ingredient in stockAlerts.take(2)) {
    alerts.add(
      HomeAlert(
        type: 'Stock critique',
        title: ingredient.name,
        body: '${ingredient.currentQty} ${ingredient.unit} restants',
        route: '/stock',
        icon: Icons.inventory_2_outlined,
        severity: HomeAlertSeverity.watch,
        establishmentLabel: establishmentLabel,
      ),
    );
  }

  final failedPayments = payments?.countsByStatus['failed'] ?? 0;
  if (failedPayments > 0) {
    alerts.add(
      HomeAlert(
        type: 'Paiement',
        title: '$failedPayments paiement(s) echoue(s)',
        body: 'Controle requis cote caisse.',
        route: '/payments',
        icon: Icons.credit_card_off_outlined,
        severity: HomeAlertSeverity.urgent,
        establishmentLabel: establishmentLabel,
      ),
    );
  }

  if (tenant != null && !tenant.isOpen) {
    alerts.add(
      HomeAlert(
        type: 'Restaurant',
        title: 'Etablissement ferme',
        body: 'Le service est actuellement bloque.',
        route: '/settings',
        icon: Icons.storefront_outlined,
        severity: HomeAlertSeverity.watch,
        establishmentLabel: establishmentLabel,
      ),
    );
  }

  alerts.sort((a, b) {
    final severity = _severityWeight(b.severity).compareTo(
      _severityWeight(a.severity),
    );
    if (severity != 0) {
      return severity;
    }
    return (b.ageLabel ?? '').compareTo(a.ageLabel ?? '');
  });
  return alerts.take(5).toList();
}

int _lateMinutes(OrderSummary order, DateTime now) {
  final createdAt = order.createdAt;
  if (createdAt == null ||
      {'ready', 'delivered', 'cancelled'}.contains(order.status)) {
    return 0;
  }
  return now.difference(createdAt.toLocal()).inMinutes;
}

int _severityWeight(HomeAlertSeverity severity) {
  return switch (severity) {
    HomeAlertSeverity.critical => 3,
    HomeAlertSeverity.urgent => 2,
    HomeAlertSeverity.watch => 1,
  };
}

String _humanOrderType(String value) {
  return switch (value) {
    'dine_in' => 'Sur place',
    'takeaway' => 'A emporter',
    'delivery' => 'Livraison',
    _ => value,
  };
}

String _humanStatus(String value) {
  return switch (value) {
    'pending' => 'A preparer',
    'queued' => 'En attente',
    'confirmed' => 'Confirmee',
    'preparing' => 'En cuisine',
    'ready' => 'Prete',
    'out_for_delivery' => 'En livraison',
    _ => value,
  };
}

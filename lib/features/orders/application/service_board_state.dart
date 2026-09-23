import 'package:app_admin_staff/features/orders/data/orders_repository.dart';

const serviceReadyStatus = 'ready';
const serviceDeliveryStatus = 'out_for_delivery';
const serviceDeliveredStatus = 'delivered';
const serviceLateThreshold = Duration(minutes: 30);

enum ServiceFilter {
  all,
  dineIn,
  pickup,
  delivery,
  late,
}

enum ServiceActionKind {
  handoff,
  startDelivery,
  markDelivered,
}

class ServiceOrderViewModel {
  const ServiceOrderViewModel({
    required this.order,
    required this.isLate,
    required this.elapsedSince,
    required this.actionKind,
    required this.nextStatus,
  });

  final OrderSummary order;
  final bool isLate;
  final DateTime? elapsedSince;
  final ServiceActionKind? actionKind;
  final String? nextStatus;

  String get actionLabel {
    return switch (actionKind) {
      ServiceActionKind.handoff => 'Remise au client',
      ServiceActionKind.startDelivery => 'Depart livraison',
      ServiceActionKind.markDelivered => 'Marquer livree',
      null => '',
    };
  }
}

class ServiceBoardState {
  const ServiceBoardState({
    required this.ready,
    required this.outForDelivery,
    required this.counts,
    required this.total,
    required this.lateCount,
  });

  final List<ServiceOrderViewModel> ready;
  final List<ServiceOrderViewModel> outForDelivery;
  final Map<ServiceFilter, int> counts;
  final int total;
  final int lateCount;

  List<ServiceOrderViewModel> get all => [...ready, ...outForDelivery];

  static ServiceBoardState build({
    required Iterable<OrderSummary> orders,
    ServiceFilter filter = ServiceFilter.all,
    String query = '',
    int? establishmentId,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final serviceOrders = orders
        .where((order) {
          if (!isServiceStatus(order.status)) {
            return false;
          }
          if (establishmentId != null &&
              order.establishmentId != null &&
              order.establishmentId != establishmentId) {
            return false;
          }
          return true;
        })
        .map((order) => toViewModel(order, now: clock))
        .toList();

    final counts = <ServiceFilter, int>{
      ServiceFilter.all: serviceOrders.length,
      ServiceFilter.dineIn: serviceOrders
          .where((order) => order.order.orderType == 'dine_in')
          .length,
      ServiceFilter.pickup: serviceOrders
          .where((order) => order.order.orderType == 'pickup')
          .length,
      ServiceFilter.delivery: serviceOrders
          .where((order) => order.order.orderType == 'delivery')
          .length,
      ServiceFilter.late: serviceOrders.where((order) => order.isLate).length,
    };

    final normalizedQuery = query.trim().toLowerCase();
    final filtered = serviceOrders.where((order) {
      if (!_matchesFilter(order, filter)) {
        return false;
      }
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return _matchesQuery(order.order, normalizedQuery);
    }).toList()
      ..sort(_compareAttention);

    return ServiceBoardState(
      ready: filtered
          .where((order) => order.order.status == serviceReadyStatus)
          .toList(),
      outForDelivery: filtered
          .where((order) => order.order.status == serviceDeliveryStatus)
          .toList(),
      counts: counts,
      total: serviceOrders.length,
      lateCount: counts[ServiceFilter.late] ?? 0,
    );
  }
}

bool isServiceStatus(String status) {
  return status == serviceReadyStatus || status == serviceDeliveryStatus;
}

ServiceOrderViewModel toViewModel(
  OrderSummary order, {
  DateTime? now,
}) {
  return ServiceOrderViewModel(
    order: order,
    isLate: isLateForService(order, now: now),
    elapsedSince: order.createdAt,
    actionKind: resolveServiceAction(order),
    nextStatus: resolveServiceNextStatus(order),
  );
}

ServiceActionKind? resolveServiceAction(OrderSummary order) {
  return switch (order.status) {
    serviceReadyStatus when order.orderType == 'delivery' =>
      ServiceActionKind.startDelivery,
    serviceReadyStatus => ServiceActionKind.handoff,
    serviceDeliveryStatus => ServiceActionKind.markDelivered,
    _ => null,
  };
}

String? resolveServiceNextStatus(OrderSummary order) {
  return switch (resolveServiceAction(order)) {
    ServiceActionKind.startDelivery => serviceDeliveryStatus,
    ServiceActionKind.handoff => serviceDeliveredStatus,
    ServiceActionKind.markDelivered => serviceDeliveredStatus,
    null => null,
  };
}

bool isLateForService(
  OrderSummary order, {
  DateTime? now,
}) {
  final createdAt = order.createdAt;
  if (createdAt == null || !isServiceStatus(order.status)) {
    return false;
  }

  // The list endpoint does not expose ready_at. Keep the existing 30 minute
  // threshold, using created_at as the only available safe timestamp.
  final clock = now ?? DateTime.now();
  if (clock.isBefore(createdAt)) {
    return false;
  }
  return clock.difference(createdAt.toLocal()) >= serviceLateThreshold;
}

bool _matchesFilter(ServiceOrderViewModel order, ServiceFilter filter) {
  return switch (filter) {
    ServiceFilter.all => true,
    ServiceFilter.dineIn => order.order.orderType == 'dine_in',
    ServiceFilter.pickup => order.order.orderType == 'pickup',
    ServiceFilter.delivery => order.order.orderType == 'delivery',
    ServiceFilter.late => order.isLate,
  };
}

bool _matchesQuery(OrderSummary order, String query) {
  final haystack = [
    '#${order.id}',
    order.id.toString(),
    order.customerName,
    order.customerEmail,
    order.customerPhone,
    order.tableNumber == null ? null : 'table ${order.tableNumber}',
    order.tableNumber,
    order.deliveryAddress,
  ].whereType<String>().join(' ').toLowerCase();
  return haystack.contains(query);
}

int _compareAttention(ServiceOrderViewModel left, ServiceOrderViewModel right) {
  if (left.isLate != right.isLate) {
    return left.isLate ? -1 : 1;
  }

  final leftCreatedAt = left.order.createdAt;
  final rightCreatedAt = right.order.createdAt;
  if (leftCreatedAt == null && rightCreatedAt == null) {
    return left.order.id.compareTo(right.order.id);
  }
  if (leftCreatedAt == null) {
    return 1;
  }
  if (rightCreatedAt == null) {
    return -1;
  }

  final dateComparison = leftCreatedAt.compareTo(rightCreatedAt);
  if (dateComparison != 0) {
    return dateComparison;
  }
  return left.order.id.compareTo(right.order.id);
}

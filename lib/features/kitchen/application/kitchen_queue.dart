import 'package:app_admin_staff/features/orders/data/orders_repository.dart';

const _kdsStatuses = {
  'pending',
  'queued',
  'confirmed',
  'preparing',
  'ready',
};

List<OrderSummary> sortKitchenOrdersFifo(
  Iterable<OrderSummary> orders,
) {
  final sorted = List<OrderSummary>.of(orders);

  sorted.sort((left, right) {
    final leftCreatedAt = left.createdAt;
    final rightCreatedAt = right.createdAt;

    if (leftCreatedAt == null && rightCreatedAt == null) {
      return left.id.compareTo(right.id);
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

    return left.id.compareTo(right.id);
  });

  return sorted;
}

List<OrderSummary> filterOrdersForKds(
  Iterable<OrderSummary> orders,
) {
  return orders.where((order) => _kdsStatuses.contains(order.status)).toList();
}

List<OrderSummary> buildKitchenQueue(
  Iterable<OrderSummary> orders,
) {
  return sortKitchenOrdersFifo(filterOrdersForKds(orders));
}

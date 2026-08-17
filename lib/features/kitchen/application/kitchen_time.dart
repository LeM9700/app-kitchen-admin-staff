import 'package:app_admin_staff/features/orders/data/orders_repository.dart';

DateTime? resolveConfirmedAt(OrderDetail order) {
  DateTime? confirmedAt;

  for (final history in order.statusHistory) {
    if (history.status != 'confirmed' || history.createdAt == null) {
      continue;
    }

    final candidate = history.createdAt!;
    if (confirmedAt == null || candidate.isBefore(confirmedAt)) {
      confirmedAt = candidate;
    }
  }

  return confirmedAt;
}

Duration preparationElapsed({
  required OrderDetail order,
  required DateTime now,
}) {
  final confirmedAt = resolveConfirmedAt(order);
  if (confirmedAt == null || now.isBefore(confirmedAt)) {
    return Duration.zero;
  }

  return now.difference(confirmedAt);
}

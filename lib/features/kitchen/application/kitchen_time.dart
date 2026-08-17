import 'package:app_admin_staff/features/orders/data/orders_repository.dart';

const defaultKitchenPrepTimeNormalMinutes = 15;

enum KitchenUrgency {
  normal,
  late,
}

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

KitchenUrgency resolveKitchenUrgency({
  required DateTime? confirmedAt,
  required DateTime now,
  required int prepTimeNormalMinutes,
}) {
  final threshold = prepTimeNormalMinutes <= 0
      ? defaultKitchenPrepTimeNormalMinutes
      : prepTimeNormalMinutes;
  if (confirmedAt == null || now.isBefore(confirmedAt)) {
    return KitchenUrgency.normal;
  }

  final elapsed = now.difference(confirmedAt);
  if (elapsed.inSeconds >= threshold * 60) {
    return KitchenUrgency.late;
  }

  return KitchenUrgency.normal;
}

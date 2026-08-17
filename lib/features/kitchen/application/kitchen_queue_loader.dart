import 'package:app_admin_staff/features/kitchen/application/kitchen_queue.dart';
import 'package:app_admin_staff/features/kitchen/application/kitchen_ticket_mapper.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_models.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';

Future<List<KitchenTicketViewModel>> loadKitchenTickets({
  required List<OrderSummary> summaries,
  required Future<OrderDetail> Function(int orderId) loadDetail,
  required KitchenScreenProfile profile,
}) async {
  final queue = buildKitchenQueue(summaries);
  final loadedTickets = await Future.wait(
    queue.map((summary) async {
      final detail = await loadDetail(summary.id);
      if (!isKdsOrderStatus(detail.status)) {
        return null;
      }

      return mapOrderToKitchenTicket(
        order: detail,
        profile: profile,
      );
    }),
  );

  return loadedTickets.whereType<KitchenTicketViewModel>().toList();
}

import 'package:app_admin_staff/core/printing/print_job.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';

class ReceiptBuilder {
  const ReceiptBuilder._();

  static PrintJob customerReceipt(OrderDetail order) {
    final lines = [
      "O'Pizza",
      'Commande #${order.id}',
      humanOrderType(order.orderType),
      if (order.tableNumber != null) 'Table ${order.tableNumber}',
      '',
      ...order.items.expand(
        (item) => [
          '${item.quantity}x ${item.productName ?? 'Produit #${item.productId}'} ${formatMoney(item.total)}',
          ...item.extras.map(
            (extra) => '  + ${extra.quantity}x ${extra.name}',
          ),
        ],
      ),
      '',
      'Total ${formatMoney(order.total)}',
    ];
    return PrintJob(
      id: 'receipt-${order.id}-${DateTime.now().microsecondsSinceEpoch}',
      kind: 'customer_receipt',
      title: 'Recu commande #${order.id}',
      content: lines.join('\n'),
      createdAt: DateTime.now(),
    );
  }

  static List<PrintJob> kitchenTickets(OrderDetail order) {
    final grouped = <String, List<OrderItem>>{};
    for (final item in order.items) {
      grouped.putIfAbsent(item.preparationStation, () => []).add(item);
    }
    return grouped.entries.map((entry) {
      final lines = [
        'Station ${entry.key}',
        'Commande #${order.id}',
        if (order.tableNumber != null) 'Table ${order.tableNumber}',
        '',
        ...entry.value.expand(
          (item) => [
            '${item.quantity}x ${item.productName ?? 'Produit #${item.productId}'}',
            ...item.extras
                .map((extra) => '  + ${extra.quantity}x ${extra.name}'),
          ],
        ),
      ];
      return PrintJob(
        id: 'kitchen-${order.id}-${entry.key}-${DateTime.now().microsecondsSinceEpoch}',
        kind: 'kitchen_ticket',
        title: 'Ticket ${entry.key} #${order.id}',
        content: lines.join('\n'),
        station: entry.key,
        createdAt: DateTime.now(),
      );
    }).toList();
  }
}

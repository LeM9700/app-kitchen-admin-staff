import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/config/env.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/printing/printer_registry.dart';
import 'package:app_admin_staff/core/printing/receipt_builder.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/core/widgets/live_elapsed.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/states/order_status_ui.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _lateOnlyProvider = StateProvider<bool>((ref) => false);
final _orderActionBusyProvider =
    StateProvider<Set<String>>((ref) => const <String>{});

class OrdersBoardPage extends ConsumerWidget {
  const OrdersBoardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(activeOrdersProvider);
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';
    final lateOnly = ref.watch(_lateOnlyProvider);

    return orders.when(
      data: (items) {
        if (items.isEmpty) {
          return const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Aucune commande active',
          );
        }
        final visibleItems = lateOnly ? items.where(_isLate).toList() : items;
        final grouped = <String, List<OrderSummary>>{};
        for (final order in visibleItems) {
          grouped.putIfAbsent(order.status, () => []).add(order);
        }
        final statuses = [
          'pending',
          'queued',
          'confirmed',
          'preparing',
          'ready',
          'out_for_delivery',
        ];

        final isMobile = Breakpoints.isMobile(context);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Commandes actives',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  FilterChip(
                    selected: lateOnly,
                    avatar: const Icon(Icons.timer_outlined),
                    label: const Text('Retards'),
                    onSelected: (value) {
                      ref.read(_lateOnlyProvider.notifier).state = value;
                    },
                  ),
                  if (isAdmin)
                    IconButton.filledTonal(
                      tooltip: 'Export CSV',
                      onPressed: () => _exportCsv(context, ref),
                      icon: const Icon(Icons.download_outlined),
                    ),
                  IconButton.filledTonal(
                    tooltip: 'Rafraichir',
                    onPressed: () => _refresh(context, ref),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: isMobile
                  ? _MobileOrdersBoard(statuses: statuses, grouped: grouped)
                  : _DesktopOrdersBoard(statuses: statuses, grouped: grouped),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => EmptyState(
        icon: Icons.error_outline,
        title: 'Chargement impossible',
        subtitle: error.toString(),
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final csv = await ref.read(ordersRepositoryProvider).exportCsv();
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export commandes CSV'),
          content: SizedBox(width: 720, child: SelectableText(csv)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    try {
      ref.invalidate(activeOrdersProvider);
      await ref.read(activeOrdersProvider.future);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Commandes rafraichies')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nextStatuses = _nextStatuses(order);
    final isLate = _isLate(order);
    final busyActions = ref.watch(_orderActionBusyProvider);
    final showLocalTestPayment = _supportsLocalTestPayment &&
        order.status == 'pending' &&
        order.paymentStatus != 'paid';
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showDetail(context, order.id),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 42),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '#${order.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Imprimer',
                        onPressed: () => _printOrder(context, ref),
                        icon: const Icon(Icons.print_outlined),
                      ),
                      Flexible(
                        child: Text(
                          formatMoney(order.total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _customerLine(order),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Chip(label: Text(humanOrderType(order.orderType))),
                      _OrderStatusBadge(status: order.paymentStatus),
                      if (order.source == 'manual')
                        const Chip(label: Text('Staff')),
                      if (isLate)
                        Chip(
                          avatar: const Icon(Icons.warning_amber_outlined),
                          label: const Text('Retard'),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                  if (order.tableNumber != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.table_restaurant_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text('Table ${order.tableNumber}'),
                      ],
                    ),
                  ],
                  if (order.deliveryAddress != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      order.deliveryAddress!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...nextStatuses
                          .where((status) => status != 'cancelled')
                          .map((status) {
                        final paymentRequired = status == 'confirmed' &&
                            order.paymentStatus != 'paid';
                        return Tooltip(
                          message: paymentRequired
                              ? 'Paiement requis avant confirmation'
                              : humanStatus(status),
                          child: FilledButton.tonal(
                            onPressed: paymentRequired ||
                                    _isActionBusy(busyActions, status)
                                ? null
                                : () => _runAction(
                                      ref,
                                      status,
                                      () => _updateStatus(
                                        context,
                                        ref,
                                        status,
                                      ),
                                    ),
                            child: Text(humanStatus(status)),
                          ),
                        );
                      }),
                      if (nextStatuses.contains('cancelled'))
                        OutlinedButton.icon(
                          onPressed: _isActionBusy(busyActions, 'cancelled')
                              ? null
                              : () => _cancel(context, ref),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Annuler'),
                        ),
                      if (showLocalTestPayment)
                        FilledButton.tonalIcon(
                          onPressed: _isActionBusy(
                            busyActions,
                            'local-test-payment',
                          )
                              ? null
                              : () => _runAction(
                                    ref,
                                    'local-test-payment',
                                    () => _confirmLocalTestPayment(
                                      context,
                                      ref,
                                    ),
                                  ),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Paiement test'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (order.createdAt != null)
              Positioned(
                right: 12,
                bottom: 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: LiveElapsed(
                      since: order.createdAt!,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _nextStatuses(OrderSummary order) {
    return switch (order.status) {
      'pending' => const ['confirmed', 'cancelled'],
      'queued' => const ['confirmed', 'cancelled'],
      'confirmed' => const ['preparing', 'cancelled'],
      'preparing' => const ['ready'],
      'ready' => order.orderType == 'delivery'
          ? const ['out_for_delivery', 'delivered']
          : const ['delivered'],
      'out_for_delivery' => const ['delivered'],
      _ => const [],
    };
  }

  bool get _supportsLocalTestPayment {
    final environment = Env.appEnvironment.trim().toLowerCase();
    return environment != 'production' && environment != 'prod';
  }

  bool _isActionBusy(Set<String> busyActions, String action) {
    return busyActions.contains(_actionKey(action));
  }

  String _actionKey(String action) => '${order.id}:$action';

  Future<void> _runAction(
    WidgetRef ref,
    String action,
    Future<void> Function() callback,
  ) async {
    final key = _actionKey(action);
    final current = ref.read(_orderActionBusyProvider);
    if (current.contains(key)) {
      return;
    }
    ref.read(_orderActionBusyProvider.notifier).state = {...current, key};
    try {
      await callback();
    } finally {
      ref.read(_orderActionBusyProvider.notifier).state = {
        ...ref.read(_orderActionBusyProvider),
      }..remove(key);
    }
  }

  Future<void> _confirmLocalTestPayment(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await ref
          .read(ordersRepositoryProvider)
          .confirmLocalTestPayment(order.id);
      ref.invalidate(activeOrdersProvider);
      await ref.read(activeOrdersProvider.future);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paiement test valide')),
        );
      }
    } catch (error) {
      final message = error is ApiError ? error.message : error.toString();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    String status, {
    String? note,
  }) async {
    try {
      await ref.read(ordersRepositoryProvider).updateStatus(
            order.id,
            status,
            note: note,
          );
      ref.invalidate(activeOrdersProvider);
      await ref.read(activeOrdersProvider.future);
    } catch (error) {
      if (error is ApiError && error.statusCode != null) {
        final message = error.code == 'PAYMENT_REQUIRED'
            ? 'La commande doit etre payee avant confirmation.'
            : error.message;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
        return;
      }

      ref.read(syncQueueProvider.notifier).add(
            feature: 'orders',
            label: 'Commande #${order.id} -> ${humanStatus(status)}',
            endpoint: ApiEndpoints.orderStatus(order.id),
            method: 'PATCH',
            payload: {
              'status': status,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            },
            lastError: error.toString(),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action mise en file offline')),
        );
      }
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Annuler commande #${order.id}'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(
            labelText: 'Raison obligatoire',
            prefixIcon: Icon(Icons.notes_outlined),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    if (reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Raison obligatoire')),
      );
      return;
    }
    await _runAction(
      ref,
      'cancelled',
      () => _updateStatus(context, ref, 'cancelled', note: reason.text),
    );
  }

  Future<void> _printOrder(BuildContext context, WidgetRef ref) async {
    try {
      final detail =
          await ref.read(ordersRepositoryProvider).getOrder(order.id);
      ref.read(printJobsProvider.notifier).enqueue(
            ReceiptBuilder.customerReceipt(detail),
          );
      for (final ticket in ReceiptBuilder.kitchenTickets(detail)) {
        ref.read(printJobsProvider.notifier).enqueue(ticket);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tickets ajoutes a la file')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  void _showDetail(BuildContext context, int orderId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _OrderDetailSheet(orderId: orderId),
    );
  }
}

class _OrderDetailSheet extends ConsumerWidget {
  const _OrderDetailSheet({required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(orderDetailProvider(orderId));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return detail.when(
          data: (order) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Commande #${order.id}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text(humanOrderType(order.orderType))),
                  _OrderStatusBadge(status: order.status),
                  _OrderStatusBadge(status: order.paymentStatus),
                  if (order.createdAt != null)
                    Chip(label: LiveElapsed(since: order.createdAt!)),
                ],
              ),
              if (order.stationSummary.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: order.stationSummary.map((station) {
                    return Chip(
                      avatar: Icon(
                        station.allReady
                            ? Icons.check_circle_outline
                            : Icons.restaurant_outlined,
                      ),
                      label: Text(
                        '${station.station} ${station.readyItems}/${station.totalItems}',
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _print(context, ref, order),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimer'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _markAllReady(context, ref, order),
                    icon: const Icon(Icons.done_all_outlined),
                    label: const Text('Commande preparee'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...order.items.map((item) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.productName ?? 'Produit #${item.productId}'),
                  subtitle: Text(
                    [
                      '${item.quantity} x ${formatMoney(item.unitPrice)}',
                      item.preparationStation,
                      if (item.extras.isNotEmpty)
                        item.extras
                            .map((extra) => '+${extra.quantity} ${extra.name}')
                            .join(', '),
                    ].join(' - '),
                  ),
                  trailing: _OrderStatusBadge(
                    status: item.preparationStatus,
                    compact: true,
                  ),
                );
              }),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.toString()),
          ),
        );
      },
    );
  }

  void _print(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
  ) async {
    ref.read(printJobsProvider.notifier).enqueue(
          ReceiptBuilder.customerReceipt(order),
        );
    for (final ticket in ReceiptBuilder.kitchenTickets(order)) {
      ref.read(printJobsProvider.notifier).enqueue(ticket);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tickets ajoutes a la file')),
    );
  }

  Future<void> _markAllReady(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
  ) async {
    try {
      for (final item in order.items) {
        if (item.preparationStatus != 'ready') {
          await ref.read(ordersRepositoryProvider).updateItemPreparation(
                orderId: order.id,
                itemId: item.id,
                status: 'ready',
              );
        }
      }
      ref.invalidate(orderDetailProvider(order.id));
      ref.invalidate(activeOrdersProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }
}

bool _isLate(OrderSummary order) {
  final createdAt = order.createdAt;
  if (createdAt == null ||
      {'ready', 'delivered', 'cancelled'}.contains(order.status)) {
    return false;
  }
  return DateTime.now().difference(createdAt.toLocal()).inMinutes >= 30;
}

String _customerLine(OrderSummary order) {
  return order.customerName ??
      order.customerEmail ??
      order.customerPhone ??
      'Client comptoir';
}

class _DesktopOrdersBoard extends StatelessWidget {
  const _DesktopOrdersBoard({
    required this.statuses,
    required this.grouped,
  });

  final List<String> statuses;
  final Map<String, List<OrderSummary>> grouped;

  @override
  Widget build(BuildContext context) {
    if (Breakpoints.isTablet(context)) {
      return ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(16),
        children: statuses.map((status) {
          return SizedBox(
            width: 260,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _OrdersColumn(
                status: status,
                orders: grouped[status] ?? const <OrderSummary>[],
              ),
            ),
          );
        }).toList(),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < statuses.length; index++) ...[
            Expanded(
              child: _OrdersColumn(
                status: statuses[index],
                orders: grouped[statuses[index]] ?? const <OrderSummary>[],
              ),
            ),
            if (index != statuses.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

class _OrdersColumn extends StatelessWidget {
  const _OrdersColumn({
    required this.status,
    required this.orders,
  });

  final String status;
  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  OrderStatusUi.from(status).label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 6),
              Badge(label: Text(orders.length.toString())),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: orders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              return _OrderCard(order: orders[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  const _OrderStatusBadge({
    required this.status,
    this.compact = true,
  });

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ui = OrderStatusUi.from(status);
    return StatusBadge(
      label: ui.label,
      tone: ui.tone,
      icon: ui.icon,
      compact: compact,
    );
  }
}

class _MobileOrdersBoard extends StatefulWidget {
  const _MobileOrdersBoard({required this.statuses, required this.grouped});

  final List<String> statuses;
  final Map<String, List<OrderSummary>> grouped;

  @override
  State<_MobileOrdersBoard> createState() => _MobileOrdersBoardState();
}

class _MobileOrdersBoardState extends State<_MobileOrdersBoard> {
  late String _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = _firstNonEmptyStatus();
  }

  @override
  void didUpdateWidget(covariant _MobileOrdersBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.statuses.contains(_selectedStatus) ||
        (widget.grouped[_selectedStatus]?.isEmpty ?? true)) {
      _selectedStatus = _firstNonEmptyStatus();
    }
  }

  String _firstNonEmptyStatus() {
    for (final status in widget.statuses) {
      if (widget.grouped[status]?.isNotEmpty == true) {
        return status;
      }
    }
    return widget.statuses.first;
  }

  @override
  Widget build(BuildContext context) {
    final columnOrders =
        widget.grouped[_selectedStatus] ?? const <OrderSummary>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedStatus,
            decoration: const InputDecoration(labelText: 'Statut'),
            items: widget.statuses.map((status) {
              final count = widget.grouped[status]?.length ?? 0;
              return DropdownMenuItem(
                value: status,
                child: Text('${humanStatus(status)} ($count)'),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedStatus = value);
              }
            },
          ),
        ),
        Expanded(
          child: columnOrders.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'Aucune commande pour ce statut',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: columnOrders.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    return _OrderCard(order: columnOrders[index]);
                  },
                ),
        ),
      ],
    );
  }
}

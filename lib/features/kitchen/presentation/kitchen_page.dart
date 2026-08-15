import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/states/order_status_ui.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/widgets/live_elapsed.dart';

final _kitchenStationProvider = StateProvider<String>((ref) => 'kitchen');
final _selectedKitchenOrderProvider = StateProvider<int?>((ref) => null);
final _kitchenActionBusyProvider =
    StateProvider<Set<String>>((ref) => const <String>{});

class KitchenPage extends ConsumerWidget {
  const KitchenPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(activeOrdersProvider);
    final selectedOrderId = ref.watch(_selectedKitchenOrderProvider);
    final isMobile = Breakpoints.isMobile(context);

    return orders.when(
      data: (items) {
        final kitchenOrders = items
            .where(
              (order) => {'confirmed', 'preparing', 'ready'}.contains(
                order.status,
              ),
            )
            .toList();
        if (kitchenOrders.isEmpty) {
          return const EmptyState(
            icon: Icons.restaurant_outlined,
            title: 'Rien en preparation',
          );
        }

        if (isMobile) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: kitchenOrders.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final order = kitchenOrders[index];
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                title: Text('#${order.id}'),
                subtitle: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        '${humanOrderType(order.orderType)} - ${humanStatus(order.status)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (order.createdAt != null) ...[
                      const SizedBox(width: 6),
                      LiveElapsed(since: order.createdAt!),
                    ],
                  ],
                ),
                trailing: order.tableNumber == null
                    ? null
                    : Text('T${order.tableNumber}'),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => Scaffold(
                        appBar: AppBar(title: Text('Commande #${order.id}')),
                        body: _KitchenOrderDetail(orderId: order.id),
                      ),
                    ),
                  );
                },
              );
            },
          );
        }

        final effectiveSelected = selectedOrderId ?? kitchenOrders.first.id;
        if (selectedOrderId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(_selectedKitchenOrderProvider.notifier).state =
                effectiveSelected;
          });
        }

        return Row(
          children: [
            SizedBox(
              width: 300,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final order = kitchenOrders[index];
                  return ListTile(
                    selected: order.id == effectiveSelected,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    title: Text('#${order.id}'),
                    subtitle: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '${humanOrderType(order.orderType)} - ${humanStatus(order.status)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (order.createdAt != null) ...[
                          const SizedBox(width: 6),
                          LiveElapsed(since: order.createdAt!),
                        ],
                      ],
                    ),
                    trailing: order.tableNumber == null
                        ? null
                        : Text('T${order.tableNumber}'),
                    onTap: () {
                      ref.read(_selectedKitchenOrderProvider.notifier).state =
                          order.id;
                    },
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemCount: kitchenOrders.length,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _KitchenOrderDetail(orderId: effectiveSelected)),
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
}

class _KitchenOrderDetail extends ConsumerWidget {
  const _KitchenOrderDetail({required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(_kitchenStationProvider);
    final busyActions = ref.watch(_kitchenActionBusyProvider);
    final detail = ref.watch(orderDetailProvider(orderId));
    final hasOrderActionBusy = busyActions.any(
      (key) => key.startsWith('$orderId:'),
    );

    return detail.when(
      data: (order) {
        final items = order.items
            .where(
              (item) => station == 'all' || item.preparationStation == station,
            )
            .toList();
        final isMobile = Breakpoints.isMobile(context);
        final segmentedButton = SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'kitchen',
              icon: const Icon(Icons.restaurant_outlined),
              label: isMobile ? null : const Text('Cuisine'),
            ),
            ButtonSegment(
              value: 'counter',
              icon: const Icon(Icons.local_drink_outlined),
              label: isMobile ? null : const Text('Comptoir'),
            ),
            ButtonSegment(
              value: 'all',
              icon: const Icon(Icons.all_inclusive),
              label: isMobile ? null : const Text('Tout'),
            ),
          ],
          selected: {station},
          onSelectionChanged: (value) {
            ref.read(_kitchenStationProvider.notifier).state = value.first;
          },
        );
        final readyButton = FilledButton.tonalIcon(
          onPressed: items.isEmpty || hasOrderActionBusy
              ? null
              : () => _setAllReady(context, ref, order, items),
          icon: const Icon(Icons.done_all_outlined),
          label: const Text('Tout pret'),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compactHeader = isMobile || constraints.maxWidth < 980;
                  if (compactHeader) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Commande #${order.id}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            segmentedButton,
                            readyButton,
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Commande #${order.id}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: 8),
                      segmentedButton,
                      const SizedBox(width: 8),
                      readyButton,
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'Aucun item pour cette station',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          leading: CircleAvatar(
                            child: Text(item.quantity.toString()),
                          ),
                          title: Text(
                            item.productName ?? 'Produit #${item.productId}',
                          ),
                          subtitle: Text(item.preparationStation),
                          trailing: Wrap(
                            spacing: 8,
                            children: [
                              if (item.preparationStatus == 'pending')
                                FilledButton.tonal(
                                  onPressed: hasOrderActionBusy
                                      ? null
                                      : () => _setStatus(
                                            context,
                                            ref,
                                            item.id,
                                            'preparing',
                                          ),
                                  child: const Text('En prep'),
                                ),
                              if (item.preparationStatus != 'ready')
                                FilledButton(
                                  onPressed: hasOrderActionBusy
                                      ? null
                                      : () => _setStatus(
                                            context,
                                            ref,
                                            item.id,
                                            'ready',
                                          ),
                                  child: const Text('Pret'),
                                ),
                              if (item.preparationStatus == 'ready')
                                _KitchenStatusBadge(
                                  status: item.preparationStatus,
                                ),
                            ],
                          ),
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemCount: items.length,
                    ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => EmptyState(
        icon: Icons.error_outline,
        title: 'Detail indisponible',
        subtitle: error.toString(),
      ),
    );
  }

  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    int itemId,
    String status,
  ) async {
    await _runAction(
      ref,
      'item:$itemId:$status',
      () => _setStatusUnlocked(context, ref, itemId, status),
    );
  }

  Future<void> _setStatusUnlocked(
    BuildContext context,
    WidgetRef ref,
    int itemId,
    String status,
  ) async {
    try {
      final previousOrder = await ref.read(orderDetailProvider(orderId).future);
      await ref.read(ordersRepositoryProvider).updateItemPreparation(
            orderId: orderId,
            itemId: itemId,
            status: status,
          );
      await _syncOrderStatusAfterItemUpdate(ref, previousOrder, status);
      ref.invalidate(orderDetailProvider(orderId));
      ref.invalidate(activeOrdersProvider);
      await ref.read(activeOrdersProvider.future);
    } catch (error) {
      if (error is AppException && error.statusCode != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
        return;
      }

      ref.read(syncQueueProvider.notifier).add(
            feature: 'kitchen',
            label: 'Item #$itemId -> $status',
            endpoint: ApiEndpoints.orderItemPreparation(orderId, itemId),
            method: 'PATCH',
            payload: {'status': status},
            lastError: error.toString(),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action mise en file offline')),
        );
      }
    }
  }

  Future<void> _setAllReady(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
    List<OrderItem> items,
  ) async {
    await _runAction(
      ref,
      'all-ready',
      () => _setAllReadyUnlocked(context, ref, order, items),
    );
  }

  Future<void> _setAllReadyUnlocked(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
    List<OrderItem> items,
  ) async {
    for (final item in items) {
      if (item.preparationStatus != 'ready') {
        await _setStatusUnlocked(context, ref, item.id, 'ready');
      }
    }
    ref.invalidate(orderDetailProvider(order.id));
    final refreshedOrder = await ref.read(orderDetailProvider(order.id).future);
    if (refreshedOrder.items.every(
      (item) => item.preparationStatus == 'ready',
    )) {
      await _syncOrderStatus(ref, refreshedOrder, 'ready');
      ref.invalidate(orderDetailProvider(order.id));
      ref.invalidate(activeOrdersProvider);
      await ref.read(activeOrdersProvider.future);
    }
  }

  Future<void> _syncOrderStatusAfterItemUpdate(
    WidgetRef ref,
    OrderDetail previousOrder,
    String itemStatus,
  ) async {
    if ((itemStatus == 'preparing' || itemStatus == 'ready') &&
        previousOrder.status == 'confirmed') {
      await _syncOrderStatus(ref, previousOrder, 'preparing');
    }

    if (itemStatus != 'ready') {
      return;
    }

    ref.invalidate(orderDetailProvider(orderId));
    final refreshedOrder = await ref.read(orderDetailProvider(orderId).future);
    final effectiveStatus = previousOrder.status == 'confirmed'
        ? 'preparing'
        : refreshedOrder.status;
    if (effectiveStatus == 'preparing' &&
        refreshedOrder.items.every(
          (item) => item.preparationStatus == 'ready',
        )) {
      await _syncOrderStatus(ref, refreshedOrder, 'ready');
    }
  }

  Future<void> _syncOrderStatus(
    WidgetRef ref,
    OrderDetail order,
    String status,
  ) async {
    if (order.status == status) {
      return;
    }
    await ref.read(ordersRepositoryProvider).updateStatus(order.id, status);
  }

  Future<void> _runAction(
    WidgetRef ref,
    String action,
    Future<void> Function() callback,
  ) async {
    final key = '$orderId:$action';
    final current = ref.read(_kitchenActionBusyProvider);
    if (current.contains(key)) {
      return;
    }
    ref.read(_kitchenActionBusyProvider.notifier).state = {...current, key};
    try {
      await callback();
    } finally {
      ref.read(_kitchenActionBusyProvider.notifier).state = {
        ...ref.read(_kitchenActionBusyProvider),
      }..remove(key);
    }
  }
}

class _KitchenStatusBadge extends StatelessWidget {
  const _KitchenStatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final ui = OrderStatusUi.from(status);
    return StatusBadge(
      label: ui.label,
      tone: ui.tone,
      icon: ui.icon,
      compact: true,
    );
  }
}

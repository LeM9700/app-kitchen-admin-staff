import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/printing/printer_registry.dart';
import 'package:app_admin_staff/core/printing/receipt_builder.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/widgets/empty_state.dart';
import 'package:app_admin_staff/core/widgets/live_elapsed.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/states/order_status_ui.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/orders/application/service_board_state.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _serviceFilterProvider =
    StateProvider<ServiceFilter>((ref) => ServiceFilter.all);
final _serviceSearchProvider = StateProvider<String>((ref) => '');
final _serviceMobileTabProvider =
    StateProvider<_ServiceMobileTab>((ref) => _ServiceMobileTab.ready);
final _orderActionBusyProvider =
    StateProvider<Set<String>>((ref) => const <String>{});

enum _ServiceMobileTab { ready, outForDelivery }

class OrdersBoardPage extends ConsumerWidget {
  const OrdersBoardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(activeOrdersProvider);
    final currentEstablishment = ref.watch(currentEstablishmentProvider);
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';
    final filter = ref.watch(_serviceFilterProvider);
    final query = ref.watch(_serviceSearchProvider);

    return NeumorphicIntensityScope(
      intensity: NeumorphicIntensity.subtle,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFF1F0EC)),
        child: orders.when(
          data: (items) {
            final establishment = currentEstablishment.valueOrNull;
            final state = ServiceBoardState.build(
              orders: items,
              filter: filter,
              query: query,
              establishmentId: establishment?.id,
            );

            return _ServiceScaffold(
              state: state,
              filter: filter,
              isAdmin: isAdmin,
              onFilterSelected: (value) {
                ref.read(_serviceFilterProvider.notifier).state = value;
              },
              onSearchChanged: (value) {
                ref.read(_serviceSearchProvider.notifier).state = value;
              },
              onRefresh: () => _refresh(context, ref),
              onExportCsv: isAdmin ? () => _exportCsv(context, ref) : null,
            );
          },
          loading: () => const _ServiceBoardSkeleton(),
          error: (error, stackTrace) => _ServiceErrorState(
            message: _friendlyError(error),
            onRetry: () => _refresh(context, ref, silent: true),
          ),
        ),
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    try {
      final csv = await ref.read(ordersRepositoryProvider).exportCsv(
            status: 'ready,out_for_delivery',
          );
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export service CSV'),
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
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }

  Future<void> _refresh(
    BuildContext context,
    WidgetRef ref, {
    bool silent = false,
  }) async {
    try {
      ref.invalidate(activeOrdersProvider);
      await ref.read(activeOrdersProvider.future);
      if (context.mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Service rafraichi')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }
}

class _ServiceScaffold extends StatelessWidget {
  const _ServiceScaffold({
    required this.state,
    required this.filter,
    required this.isAdmin,
    required this.onFilterSelected,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.onExportCsv,
  });

  final ServiceBoardState state;
  final ServiceFilter filter;
  final bool isAdmin;
  final ValueChanged<ServiceFilter> onFilterSelected;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final VoidCallback? onExportCsv;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ServiceHeader(
          state: state,
          isAdmin: isAdmin,
          onRefresh: onRefresh,
          onExportCsv: onExportCsv,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ServiceSearchField(onChanged: onSearchChanged),
              const SizedBox(height: 10),
              _ServiceFilterBar(
                selected: filter,
                counts: state.counts,
                onSelected: onFilterSelected,
              ),
            ],
          ),
        ),
        Expanded(child: _ServiceResponsiveBoard(state: state)),
      ],
    );
  }
}

class _ServiceHeader extends StatelessWidget {
  const _ServiceHeader({
    required this.state,
    required this.isAdmin,
    required this.onRefresh,
    required this.onExportCsv,
  });

  final ServiceBoardState state;
  final bool isAdmin;
  final VoidCallback onRefresh;
  final VoidCallback? onExportCsv;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: Breakpoints.isMobile(context) ? double.infinity : 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Service',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${state.ready.length} pretes - '
                  '${state.outForDelivery.length} en livraison - '
                  '${state.lateCount} en retard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _ServiceCountPill(
            icon: Icons.receipt_long_outlined,
            label: '${state.total} concernees',
          ),
          _ServiceCountPill(
            icon: Icons.task_alt_outlined,
            label: '${state.ready.length} pretes',
          ),
          _ServiceCountPill(
            icon: Icons.delivery_dining_outlined,
            label: '${state.outForDelivery.length} livraison',
          ),
          if (state.lateCount > 0)
            _ServiceCountPill(
              icon: Icons.warning_amber_outlined,
              label: '${state.lateCount} retard',
              danger: true,
            ),
          if (isAdmin && onExportCsv != null)
            IconButton.filledTonal(
              tooltip: 'Export CSV',
              onPressed: onExportCsv,
              icon: const Icon(Icons.download_outlined),
            ),
          IconButton.filledTonal(
            tooltip: 'Rafraichir',
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}

class _ServiceCountPill extends StatelessWidget {
  const _ServiceCountPill({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.dangerAlt : AppColors.textSecondary;
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: danger ? AppColors.dangerBg : const Color(0xFFE6E4DE),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: const Color(0xFFD9D4CA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceSearchField extends StatefulWidget {
  const _ServiceSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_ServiceSearchField> createState() => _ServiceSearchFieldState();
}

class _ServiceSearchFieldState extends State<_ServiceSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (value) {
        widget.onChanged(value);
        setState(() {});
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF9F7F2),
        hintText: 'Rechercher #commande, client, table',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer',
                onPressed: () {
                  _controller.clear();
                  widget.onChanged('');
                  setState(() {});
                },
                icon: const Icon(Icons.close, size: 18),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8D2C7)),
        ),
      ),
    );
  }
}

class _ServiceFilterBar extends StatelessWidget {
  const _ServiceFilterBar({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final ServiceFilter selected;
  final Map<ServiceFilter, int> counts;
  final ValueChanged<ServiceFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterButton(
            label: 'Toutes',
            count: counts[ServiceFilter.all] ?? 0,
            icon: Icons.view_agenda_outlined,
            selected: selected == ServiceFilter.all,
            onTap: () => onSelected(ServiceFilter.all),
          ),
          _FilterButton(
            label: 'Sur place',
            count: counts[ServiceFilter.dineIn] ?? 0,
            icon: Icons.table_restaurant_outlined,
            selected: selected == ServiceFilter.dineIn,
            onTap: () => onSelected(ServiceFilter.dineIn),
          ),
          _FilterButton(
            label: 'A emporter',
            count: counts[ServiceFilter.pickup] ?? 0,
            icon: Icons.shopping_bag_outlined,
            selected: selected == ServiceFilter.pickup,
            onTap: () => onSelected(ServiceFilter.pickup),
          ),
          _FilterButton(
            label: 'Livraison',
            count: counts[ServiceFilter.delivery] ?? 0,
            icon: Icons.delivery_dining_outlined,
            selected: selected == ServiceFilter.delivery,
            onTap: () => onSelected(ServiceFilter.delivery),
          ),
          _FilterButton(
            label: 'Retards',
            count: counts[ServiceFilter.late] ?? 0,
            icon: Icons.warning_amber_outlined,
            selected: selected == ServiceFilter.late,
            onTap: () => onSelected(ServiceFilter.late),
          ),
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = selected ? AppColors.adminSidebar : const Color(0xFFE6E4DE);
    final foreground = selected ? Colors.white : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: selected
              ? AppElevation.pressed(AppColors.adminSidebar, intensity: 0.55)
              : AppElevation.flat,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 38),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: foreground),
                    const SizedBox(width: 7),
                    Text(
                      '$label $count',
                      style: TextStyle(
                        color: foreground,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceResponsiveBoard extends StatelessWidget {
  const _ServiceResponsiveBoard({required this.state});

  final ServiceBoardState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useMobile = Breakpoints.isMobile(context) ||
            constraints.maxWidth < Breakpoints.tablet;
        if (useMobile) {
          return _MobileServiceBoard(state: state);
        }
        return _DesktopServiceBoard(state: state);
      },
    );
  }
}

class _DesktopServiceBoard extends StatelessWidget {
  const _DesktopServiceBoard({required this.state});

  final ServiceBoardState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ServiceBoardColumn(
              title: 'Pretes',
              status: serviceReadyStatus,
              orders: state.ready,
              emptyTitle: 'Aucune commande prete',
              emptySubtitle:
                  'Les commandes apparaissent ici des que la cuisine a termine.',
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _ServiceBoardColumn(
              title: 'En livraison',
              status: serviceDeliveryStatus,
              orders: state.outForDelivery,
              emptyTitle: 'Aucune livraison en cours',
              emptySubtitle:
                  'Les departs livraison seront visibles dans cette colonne.',
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileServiceBoard extends ConsumerWidget {
  const _MobileServiceBoard({required this.state});

  final ServiceBoardState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(_serviceMobileTabProvider);
    final orders = selected == _ServiceMobileTab.ready
        ? state.ready
        : state.outForDelivery;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: SegmentedButton<_ServiceMobileTab>(
            segments: [
              ButtonSegment(
                value: _ServiceMobileTab.ready,
                label: Text('Pretes ${state.ready.length}'),
                icon: const Icon(Icons.task_alt_outlined),
              ),
              ButtonSegment(
                value: _ServiceMobileTab.outForDelivery,
                label: Text('Livraison ${state.outForDelivery.length}'),
                icon: const Icon(Icons.delivery_dining_outlined),
              ),
            ],
            selected: {selected},
            onSelectionChanged: (values) {
              ref.read(_serviceMobileTabProvider.notifier).state = values.first;
            },
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? EmptyState(
                  icon: selected == _ServiceMobileTab.ready
                      ? Icons.receipt_long_outlined
                      : Icons.delivery_dining_outlined,
                  title: selected == _ServiceMobileTab.ready
                      ? 'Aucune commande prete'
                      : 'Aucune livraison en cours',
                  subtitle: selected == _ServiceMobileTab.ready
                      ? 'La cuisine fera apparaitre les commandes ici.'
                      : 'Les commandes parties seront listees ici.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: orders.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _ServiceOrderCard(viewModel: orders[index]);
                  },
                ),
        ),
      ],
    );
  }
}

class _ServiceBoardColumn extends StatelessWidget {
  const _ServiceBoardColumn({
    required this.title,
    required this.status,
    required this.orders,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final String title;
  final String status;
  final List<ServiceOrderViewModel> orders;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: EdgeInsets.zero,
      backgroundColor: const Color(0xFFF7F5F0),
      borderColor: const Color(0xFFD8D2C7),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Icon(OrderStatusUi.from(status).icon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                  ),
                ),
                Badge(label: Text(orders.length.toString())),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2DDD4)),
          Expanded(
            child: orders.isEmpty
                ? EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: emptyTitle,
                    subtitle: emptySubtitle,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: orders.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _ServiceOrderCard(viewModel: orders[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ServiceOrderCard extends ConsumerWidget {
  const _ServiceOrderCard({required this.viewModel});

  final ServiceOrderViewModel viewModel;

  OrderSummary get order => viewModel.order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busyActions = ref.watch(_orderActionBusyProvider);
    final nextStatus = viewModel.nextStatus;
    final actionKey = nextStatus == null ? null : _actionKey(nextStatus);
    final isBusy = actionKey != null && busyActions.contains(actionKey);

    return Semantics(
      button: true,
      label: 'Commande ${order.id}, ${humanOrderType(order.orderType)}',
      child: DsCard(
        padding: EdgeInsets.zero,
        backgroundColor: const Color(0xFFFFFCF4),
        borderColor:
            viewModel.isLate ? AppColors.dangerAlt : const Color(0xFFE1D8C9),
        borderRadius: 14,
        onTap: () => _showDetail(context, order.id),
        child: Stack(
          children: [
            Positioned.fill(
              left: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: viewModel.isLate
                        ? AppColors.dangerAlt
                        : _statusAccent(order.status),
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 13, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Commande #${order.id}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            _ServiceLocationLine(order: order),
                          ],
                        ),
                      ),
                      _ServiceTimer(viewModel: viewModel),
                      _ServiceCardMenu(
                        onPrint: () => _printOrder(context, ref),
                        onDetail: () => _showDetail(context, order.id),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ServiceTypeBadge(orderType: order.orderType),
                      _OrderStatusBadge(status: order.paymentStatus),
                      if (viewModel.isLate)
                        const StatusBadge(
                          label: 'Retard',
                          tone: StatusTone.danger,
                          icon: Icons.warning_amber_outlined,
                          compact: true,
                        ),
                    ],
                  ),
                  if (order.deliveryAddress != null &&
                      order.orderType == 'delivery') ...[
                    const SizedBox(height: 8),
                    Text(
                      order.deliveryAddress!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          formatMoney(order.total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: nextStatus == null || isBusy
                            ? null
                            : () => _runAction(
                                  ref,
                                  nextStatus,
                                  () => _updateStatus(
                                    context,
                                    ref,
                                    nextStatus,
                                  ),
                                ),
                        child: Text(viewModel.actionLabel.toUpperCase()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    String status,
  ) async {
    try {
      await ref.read(ordersRepositoryProvider).updateStatus(order.id, status);
      ref
        ..invalidate(orderDetailProvider(order.id))
        ..invalidate(activeOrdersProvider);
      await ref.read(activeOrdersProvider.future);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Commande #${order.id} mise a jour')),
        );
      }
    } catch (error) {
      if (error is ApiError && error.statusCode != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
        return;
      }

      ref.read(syncQueueProvider.notifier).add(
            feature: 'orders',
            label: 'Commande #${order.id} -> ${humanStatus(status)}',
            endpoint: ApiEndpoints.orderStatus(order.id),
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

  Future<void> _printOrder(BuildContext context, WidgetRef ref) async {
    try {
      final detail =
          await ref.read(ordersRepositoryProvider).getOrder(order.id);
      _enqueuePrint(ref, detail);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tickets ajoutes a la file')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }

  void _showDetail(BuildContext context, int orderId) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ServiceOrderDetailSheet(orderId: orderId),
    );
  }
}

class _ServiceLocationLine extends StatelessWidget {
  const _ServiceLocationLine({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final icon = switch (order.orderType) {
      'dine_in' => Icons.table_restaurant_outlined,
      'pickup' => Icons.shopping_bag_outlined,
      'delivery' => Icons.delivery_dining_outlined,
      _ => Icons.receipt_long_outlined,
    };
    final label = switch (order.orderType) {
      'dine_in' when order.tableNumber != null => 'Table ${order.tableNumber}',
      'pickup' => _customerLine(order),
      'delivery' => _customerLine(order),
      _ => _customerLine(order),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ],
    );
  }
}

class _ServiceTimer extends StatelessWidget {
  const _ServiceTimer({required this.viewModel});

  final ServiceOrderViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final since = viewModel.elapsedSince;
    if (since == null) {
      return const SizedBox.shrink();
    }
    final color =
        viewModel.isLate ? AppColors.dangerAlt : AppColors.textPrimary;
    return Semantics(
      label: viewModel.isLate ? 'Commande en retard' : 'Temps ecoule',
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color:
              viewModel.isLate ? AppColors.dangerBg : const Color(0xFFEFE9DD),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: viewModel.isLate
                ? AppColors.dangerAlt.withValues(alpha: 0.5)
                : const Color(0xFFD9D0BF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (viewModel.isLate) ...[
              Icon(Icons.warning_amber_outlined, size: 15, color: color),
              const SizedBox(width: 4),
            ],
            LiveElapsed(
              since: since,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceCardMenu extends StatelessWidget {
  const _ServiceCardMenu({
    required this.onPrint,
    required this.onDetail,
  });

  final VoidCallback onPrint;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Actions secondaires',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'print') {
          onPrint();
        }
        if (value == 'detail') {
          onDetail();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'detail',
          child: ListTile(
            leading: Icon(Icons.open_in_new_outlined),
            title: Text('Ouvrir detail'),
          ),
        ),
        PopupMenuItem(
          value: 'print',
          child: ListTile(
            leading: Icon(Icons.print_outlined),
            title: Text('Imprimer'),
          ),
        ),
      ],
    );
  }
}

class _ServiceTypeBadge extends StatelessWidget {
  const _ServiceTypeBadge({required this.orderType});

  final String orderType;

  @override
  Widget build(BuildContext context) {
    return StatusBadge(
      label: humanOrderType(orderType),
      tone: orderType == 'delivery' ? StatusTone.info : StatusTone.neutral,
      icon: switch (orderType) {
        'dine_in' => Icons.table_restaurant_outlined,
        'pickup' => Icons.shopping_bag_outlined,
        'delivery' => Icons.delivery_dining_outlined,
        _ => Icons.receipt_long_outlined,
      },
      compact: true,
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  const _OrderStatusBadge({
    required this.status,
  });

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

class _ServiceOrderDetailSheet extends ConsumerWidget {
  const _ServiceOrderDetailSheet({required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(orderDetailProvider(orderId));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return detail.when(
          data: (order) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Commande #${order.id}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _ServiceTypeBadge(orderType: order.orderType),
                            _OrderStatusBadge(status: order.status),
                            _OrderStatusBadge(status: order.paymentStatus),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Imprimer',
                    onPressed: () => _print(context, ref, order),
                    icon: const Icon(Icons.print_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DetailGrid(order: order),
              if (order.stationSummary.isNotEmpty) ...[
                const SizedBox(height: 18),
                _PreparationSummary(order: order),
              ],
              const SizedBox(height: 20),
              Text(
                'Articles',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              ...order.items.map((item) => _DetailItemTile(item: item)),
              if (order.statusHistory.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Historique',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                ...order.statusHistory.map(_HistoryTile.new),
              ],
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Padding(
            padding: const EdgeInsets.all(24),
            child: _ServiceErrorState(
              message: _friendlyError(error),
              onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
            ),
          ),
        );
      },
    );
  }

  void _print(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
  ) {
    _enqueuePrint(ref, order);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tickets ajoutes a la file')),
    );
  }
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Client', _customerLine(order)),
      if (order.tableNumber != null) ('Table', order.tableNumber!),
      ('Heure commande', formatTime(order.createdAt)),
      ('Paiement', humanStatus(order.paymentStatus)),
      ('Total', formatMoney(order.total)),
      if (order.deliveryAddress != null) ('Adresse', order.deliveryAddress!),
    ];

    return DsCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: const Color(0xFFFFFCF4),
      borderRadius: 14,
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        children: rows.map((row) {
          return SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.$1,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  row.$2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PreparationSummary extends StatelessWidget {
  const _PreparationSummary({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final allReady = order.stationSummary.every((station) => station.allReady);
    return DsCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: allReady ? AppColors.successBg : AppColors.warningBg,
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allReady
                    ? Icons.check_circle_outline
                    : Icons.restaurant_outlined,
                color: allReady ? AppColors.success : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  allReady ? 'Preparation terminee' : 'Preparation a verifier',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: order.stationSummary.map((station) {
              return StatusBadge(
                label:
                    '${station.station} ${station.readyItems}/${station.totalItems}',
                tone:
                    station.allReady ? StatusTone.success : StatusTone.warning,
                icon: station.allReady
                    ? Icons.task_alt_outlined
                    : Icons.timelapse_outlined,
                compact: true,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DetailItemTile extends StatelessWidget {
  const _DetailItemTile({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(item.productName ?? 'Produit #${item.productId}'),
      subtitle: Text(
        [
          '${item.quantity} x ${formatMoney(item.unitPrice)}',
          if (item.variantName != null) item.variantName,
          if (item.extras.isNotEmpty)
            item.extras
                .map((extra) => '+${extra.quantity} ${extra.name}')
                .join(', '),
        ].whereType<String>().join(' - '),
      ),
      trailing: Text(
        formatMoney(item.total),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile(this.history);

  final OrderStatusHistory history;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.history, size: 18),
      title: Text(humanStatus(history.status)),
      subtitle: history.note == null ? null : Text(history.note!),
      trailing: Text(formatTime(history.createdAt)),
    );
  }
}

class _ServiceBoardSkeleton extends StatelessWidget {
  const _ServiceBoardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SkeletonLine(width: 180, height: 28),
          const SizedBox(height: 10),
          const _SkeletonLine(width: 320, height: 18),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              children: [
                const Expanded(child: _SkeletonColumn()),
                if (!Breakpoints.isMobile(context)) ...[
                  const SizedBox(width: 14),
                  const Expanded(child: _SkeletonColumn()),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonColumn extends StatelessWidget {
  const _SkeletonColumn();

  @override
  Widget build(BuildContext context) {
    return const DsCard(
      padding: EdgeInsets.all(12),
      backgroundColor: Color(0xFFF7F5F0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SkeletonLine(width: 120, height: 20),
          SizedBox(height: 16),
          _SkeletonTicket(),
          SizedBox(height: 10),
          _SkeletonTicket(),
          SizedBox(height: 10),
          _SkeletonTicket(),
        ],
      ),
    );
  }
}

class _SkeletonTicket extends StatelessWidget {
  const _SkeletonTicket();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 128,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1D8C9)),
      ),
      padding: const EdgeInsets.all(14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonLine(width: 140, height: 18),
          SizedBox(height: 12),
          _SkeletonLine(width: 220, height: 14),
          Spacer(),
          _SkeletonLine(width: double.infinity, height: 36),
        ],
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFE2DDD4),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _ServiceErrorState extends StatelessWidget {
  const _ServiceErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DsCard(
          padding: const EdgeInsets.all(18),
          backgroundColor: const Color(0xFFFFFCF4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 34),
              const SizedBox(height: 10),
              Text(
                'Chargement du service impossible',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _statusAccent(String status) {
  return status == serviceReadyStatus ? AppColors.success : AppColors.infoAlt;
}

String _customerLine(OrderSummary order) {
  return order.customerName ??
      order.customerEmail ??
      order.customerPhone ??
      'Client comptoir';
}

String _friendlyError(Object error) {
  if (error is AppException && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return 'Une erreur est survenue. Reessayez dans un instant.';
}

void _enqueuePrint(WidgetRef ref, OrderDetail order) {
  ref.read(printJobsProvider.notifier).enqueue(
        ReceiptBuilder.customerReceipt(order),
      );
  for (final ticket in ReceiptBuilder.kitchenTickets(order)) {
    ref.read(printJobsProvider.notifier).enqueue(ticket);
  }
}

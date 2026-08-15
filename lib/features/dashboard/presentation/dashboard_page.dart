import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/features/dashboard/data/dashboard_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final _dashboardPeriodProvider = StateProvider<String>((ref) => 'today');

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(activeOrdersProvider);
    final alerts = ref.watch(stockAlertsProvider);
    final summary = ref.watch(paymentsSummaryProvider);
    final tenant = ref.watch(tenantStatusProvider);
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';
    final stats = isAdmin ? ref.watch(statsSummaryProvider) : null;
    final daily = isAdmin ? ref.watch(dailyStatsProvider) : null;
    final monthly = isAdmin ? ref.watch(monthlyStatsProvider) : null;
    final topProducts = isAdmin ? ref.watch(topProductsProvider) : null;
    final period = ref.watch(_dashboardPeriodProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeOrdersProvider);
        ref.invalidate(stockAlertsProvider);
        ref.invalidate(paymentsSummaryProvider);
        ref.invalidate(tenantStatusProvider);
        ref.invalidate(statsSummaryProvider);
        ref.invalidate(dailyStatsProvider);
        ref.invalidate(monthlyStatsProvider);
        ref.invalidate(topProductsProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricTile(
                icon: Icons.receipt_long_outlined,
                label: 'Commandes actives',
                value: orders.maybeWhen(
                  data: (value) => value.length.toString(),
                  orElse: () => '-',
                ),
                onTap: () => context.go('/orders'),
              ),
              _MetricTile(
                icon: Icons.timer_outlined,
                label: 'Preparation',
                value: tenant.maybeWhen(
                  data: (value) => '${value.estimatedPrepTimeMinutes} min',
                  orElse: () => '-',
                ),
              ),
              _MetricTile(
                icon: Icons.warning_amber_outlined,
                label: 'Alertes stock',
                value: alerts.maybeWhen(
                  data: (value) => value.length.toString(),
                  orElse: () => '-',
                ),
                onTap: () => context.go('/stock'),
              ),
              _MetricTile(
                icon: Icons.payments_outlined,
                label: 'Net encaisse',
                value: summary.maybeWhen(
                  data: (value) => formatCents(value.netAmountCents),
                  orElse: () => '-',
                ),
                onTap: () => context.go('/payments'),
              ),
              if (isAdmin)
                _MetricTile(
                  icon: Icons.trending_up_outlined,
                  label: 'CA 24h',
                  value: stats?.maybeWhen(
                        data: (value) => formatMoney(value.live.revenueLast24h),
                        orElse: () => '-',
                      ) ??
                      '-',
                ),
              if (isAdmin)
                _MetricTile(
                  icon: Icons.shopping_cart_checkout_outlined,
                  label: 'Panier moyen',
                  value: stats?.maybeWhen(
                        data: (value) =>
                            formatMoney(value.live.avgOrderValue24h),
                        orElse: () => '-',
                      ) ??
                      '-',
                ),
              if (isAdmin)
                _MetricTile(
                  icon: Icons.pending_actions_outlined,
                  label: 'En attente',
                  value: stats?.maybeWhen(
                        data: (value) => value.live.pendingOrders.toString(),
                        orElse: () => '-',
                      ) ??
                      '-',
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'A traiter maintenant',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          orders.when(
            data: (items) {
              final pending =
                  items.where((order) => order.status == 'pending').length;
              final late = items.where(_isLate).length;
              final delivery = items
                  .where((order) => order.status == 'out_for_delivery')
                  .length;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricTile(
                    icon: Icons.pending_actions_outlined,
                    label: 'En attente',
                    value: pending.toString(),
                    onTap: () => context.go('/orders'),
                  ),
                  _MetricTile(
                    icon: Icons.timer_outlined,
                    label: 'Retards',
                    value: late.toString(),
                    onTap: () => context.go('/orders'),
                  ),
                  _MetricTile(
                    icon: Icons.delivery_dining_outlined,
                    label: 'Livraisons',
                    value: delivery.toString(),
                    onTap: () => context.go('/orders'),
                  ),
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => _PanelMessage(
              icon: Icons.error_outline,
              text: error.toString(),
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text('Periodes', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'today', label: Text("Aujourd'hui")),
                    ButtonSegment(value: '7d', label: Text('7 jours')),
                    ButtonSegment(value: '30d', label: Text('30 jours')),
                  ],
                  selected: {period},
                  onSelectionChanged: (value) {
                    ref.read(_dashboardPeriodProvider.notifier).state =
                        value.first;
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            _periodStats(period, daily, monthly),
            const SizedBox(height: 24),
            Text('Top produits', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            topProducts?.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return const _PanelMessage(
                        icon: Icons.local_pizza_outlined,
                        text: 'Aucune vente produit sur la periode',
                      );
                    }
                    return Column(
                      children: items.take(8).map((item) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                            ),
                            leading: const Icon(Icons.leaderboard_outlined),
                            title: Text(item.productName),
                            subtitle: Text('${item.quantity} vendu(s)'),
                            trailing: Text(formatMoney(item.revenue)),
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stackTrace) => Text(error.toString()),
                ) ??
                const SizedBox.shrink(),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Service en cours',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.go('/checkout'),
                icon: const Icon(Icons.point_of_sale_outlined),
                label: const Text('Caisse'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          orders.when(
            data: (items) {
              if (items.isEmpty) {
                return const _PanelMessage(
                  icon: Icons.check_circle_outline,
                  text: 'Aucune commande active',
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items.take(8).map((order) {
                  return SizedBox(
                    width: 280,
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      title: Text(
                        '#${order.id} - ${humanOrderType(order.orderType)}',
                      ),
                      subtitle: Text(humanStatus(order.status)),
                      trailing: Text(formatMoney(order.total)),
                      onTap: () => context.go('/orders'),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => _PanelMessage(
              icon: Icons.error_outline,
              text: error.toString(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodStats(
    String period,
    AsyncValue<List<DailyStats>>? daily,
    AsyncValue<List<MonthlyStats>>? monthly,
  ) {
    if (period == '30d') {
      return monthly?.when(
            data: (items) => _periodWrap(
              items.take(1).map((item) {
                return _MetricTile(
                  icon: Icons.calendar_month_outlined,
                  label: '${item.month}/${item.year}',
                  value: formatMoney(item.totalRevenue),
                );
              }).toList(),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => Text(error.toString()),
          ) ??
          const SizedBox.shrink();
    }

    final take = period == '7d' ? 7 : 1;
    return daily?.when(
          data: (items) {
            final selected = items.take(take).toList();
            final revenue = selected.fold<double>(
              0,
              (sum, item) => sum + item.revenue,
            );
            final orders = selected.fold<int>(
              0,
              (sum, item) => sum + item.orderCount,
            );
            final avgBasket = orders == 0 ? 0.0 : revenue / orders;
            return _periodWrap(
              [
                _MetricTile(
                  icon: Icons.euro_outlined,
                  label: 'CA',
                  value: formatMoney(revenue),
                ),
                _MetricTile(
                  icon: Icons.receipt_long_outlined,
                  label: 'Commandes',
                  value: orders.toString(),
                ),
                _MetricTile(
                  icon: Icons.shopping_cart_checkout_outlined,
                  label: 'Panier moyen',
                  value: formatMoney(avgBasket),
                ),
              ],
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (error, stackTrace) => Text(error.toString()),
        ) ??
        const SizedBox.shrink();
  }

  Widget _periodWrap(List<Widget> children) {
    if (children.isEmpty) {
      return const _PanelMessage(
        icon: Icons.insights_outlined,
        text: 'Aucune statistique disponible',
      );
    }
    return Wrap(spacing: 12, runSpacing: 12, children: children);
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

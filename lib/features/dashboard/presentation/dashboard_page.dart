import 'package:app_admin_staff/app/permissions/permissions.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/connectivity/connectivity_status.dart';
import 'package:app_admin_staff/core/offline/sync_queue.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_elevation.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/dashboard/application/home_models.dart';
import 'package:app_admin_staff/features/dashboard/data/dashboard_repository.dart';
import 'package:app_admin_staff/features/establishments/application/establishment_invalidation.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:app_admin_staff/features/hr/data/hr_repository.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:app_admin_staff/features/payments/data/payments_repository.dart';
import 'package:app_admin_staff/features/stock/data/stock_repository.dart';
import 'package:app_admin_staff/features/tenant_config/data/tenant_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = ref.watch(currentPermissionSetProvider);
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final orders = ref.watch(activeOrdersProvider);
    final stockAlerts = permissions.can(AppPermission.stockRead)
        ? ref.watch(stockAlertsProvider)
        : const AsyncData(<Ingredient>[]);
    final AsyncValue<PaymentSummary?> payments =
        permissions.can(AppPermission.paymentsRead)
            ? ref.watch(paymentsSummaryProvider).whenData((value) => value)
            : const AsyncData(null);
    final AsyncValue<TenantPrintConfig?> printConfig =
        permissions.can(AppPermission.printRead)
            ? ref.watch(tenantPrintConfigProvider).whenData((value) => value)
            : const AsyncData(null);
    final terminalReaders = permissions.can(AppPermission.paymentsTerminal)
        ? ref.watch(terminalReadersProvider)
        : const AsyncData(<TerminalReader>[]);
    final tenant = ref.watch(tenantStatusProvider);
    final currentEstablishment = ref.watch(currentEstablishmentProvider);
    final online = ref.watch(onlineStatusProvider).valueOrNull ?? true;
    final queuedActions = ref.watch(syncQueueProvider).length;
    final AsyncValue<StatsSummary?> stats = permissions.hasRole('admin')
        ? ref.watch(statsSummaryProvider).whenData((value) => value)
        : const AsyncData(null);
    final topProducts = permissions.hasRole('admin')
        ? ref.watch(topProductsProvider)
        : const AsyncData(<TopProductStats>[]);
    final AsyncValue<GroupOverview?> groupOverview =
        permissions.hasRole('admin')
            ? ref.watch(groupOverviewProvider).whenData((value) => value)
            : const AsyncData(null);
    final today = _today();
    final shifts = ref.watch(
      myShiftsProvider(
        HrShiftQuery(
          dateFrom: today,
          dateTo: today.add(const Duration(days: 14)),
        ),
      ),
    );
    final openTimeEntries = ref.watch(
      myTimeClockEntriesProvider(
        TimeClockEntryQuery(
          status: 'open',
          dateFrom: today.subtract(const Duration(days: 1)),
          dateTo: today.add(const Duration(days: 1)),
        ),
      ),
    );

    final establishmentLabel = currentEstablishment.maybeWhen(
      data: (value) => value?.name ?? user?.tenantSlug ?? 'Etablissement',
      orElse: () => user?.tenantSlug ?? 'Etablissement',
    );
    final alertItems = buildHomeAlerts(
      orders: orders.valueOrNull ?? const [],
      stockAlerts: stockAlerts.valueOrNull ?? const [],
      payments: payments.valueOrNull,
      tenant: tenant.valueOrNull,
      online: online,
      queuedActions: queuedActions,
      establishmentLabel: establishmentLabel,
    );

    return NeumorphicIntensityScope(
      intensity: NeumorphicIntensity.subtle,
      child: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(activeOrdersProvider)
            ..invalidate(stockAlertsProvider)
            ..invalidate(paymentsSummaryProvider)
            ..invalidate(tenantPrintConfigProvider)
            ..invalidate(terminalReadersProvider)
            ..invalidate(tenantStatusProvider)
            ..invalidate(statsSummaryProvider)
            ..invalidate(topProductsProvider)
            ..invalidate(groupOverviewProvider)
            ..invalidate(myShiftsProvider)
            ..invalidate(myTimeClockEntriesProvider);
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isMobile = width < 760;
            final isTablet = width >= 760 && width < 1100;
            final padding = isMobile
                ? const EdgeInsets.all(AppSpacing.md)
                : const EdgeInsets.all(AppSpacing.xl);
            return ListView(
              padding: padding,
              children: [
                _HomeHeader(
                  userName: _displayName(user?.fullName, user?.email),
                  establishment: establishmentLabel,
                ),
                const SizedBox(height: AppSpacing.lg),
                _HomeAlertSection(
                  alerts: alertItems,
                  loading: orders.isLoading || stockAlerts.isLoading,
                  error: orders.hasError ? orders.error : null,
                ),
                _GroupOverviewSection(
                  overview: groupOverview,
                  selectedEstablishmentId: currentEstablishment.valueOrNull?.id,
                  permissions: permissions,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (isMobile) ...[
                  _MyServicePanel(
                    shifts: shifts,
                    openEntries: openTimeEntries,
                    currentEstablishment: currentEstablishment.valueOrNull,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _RealtimeSection(orders: orders, tenant: tenant),
                  const SizedBox(height: AppSpacing.md),
                  _RestaurantHealthSection(
                    tenant: tenant,
                    stockAlerts: stockAlerts,
                    payments: payments,
                    online: online,
                    queuedActions: queuedActions,
                    permissions: permissions,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _DeviceHealthSection(
                    printConfig: printConfig,
                    terminalReaders: terminalReaders,
                    permissions: permissions,
                    online: online,
                    queuedActions: queuedActions,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _UpcomingShiftsPanel(
                    shifts: shifts,
                    currentEstablishment: currentEstablishment.valueOrNull,
                  ),
                ] else ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: isTablet ? 1 : 7,
                        child: Column(
                          children: [
                            _RealtimeSection(orders: orders, tenant: tenant),
                            const SizedBox(height: AppSpacing.md),
                            _RestaurantHealthSection(
                              tenant: tenant,
                              stockAlerts: stockAlerts,
                              payments: payments,
                              online: online,
                              queuedActions: queuedActions,
                              permissions: permissions,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _DeviceHealthSection(
                              printConfig: printConfig,
                              terminalReaders: terminalReaders,
                              permissions: permissions,
                              online: online,
                              queuedActions: queuedActions,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        flex: isTablet ? 1 : 3,
                        child: Column(
                          children: [
                            _MyServicePanel(
                              shifts: shifts,
                              openEntries: openTimeEntries,
                              currentEstablishment:
                                  currentEstablishment.valueOrNull,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _UpcomingShiftsPanel(
                              shifts: shifts,
                              currentEstablishment:
                                  currentEstablishment.valueOrNull,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _PerformanceSection(
                  stats: stats,
                  topProducts: topProducts,
                  permissions: permissions,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.userName,
    required this.establishment,
  });

  final String userName;
  final String establishment;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bonjour $userName',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                establishment,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        const _ServicePulse(),
      ],
    );
  }
}

class _ServicePulse extends StatelessWidget {
  const _ServicePulse();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.success.withValues(alpha: .24)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.radio_button_checked, size: 15, color: AppColors.success),
          SizedBox(width: AppSpacing.xs),
          Text(
            'Service live',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeAlertSection extends StatelessWidget {
  const _HomeAlertSection({
    required this.alerts,
    required this.loading,
    required this.error,
  });

  final List<HomeAlert> alerts;
  final bool loading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return _HomePanel(
      title: 'A traiter maintenant',
      trailing: Text(
        '${alerts.length}/5',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      child: Builder(
        builder: (context) {
          if (loading && alerts.isEmpty) {
            return const _SkeletonRows(rows: 3);
          }
          if (error != null) {
            return _PanelMessage(
              icon: Icons.error_outline,
              title: 'Alertes indisponibles',
              body: error.toString(),
            );
          }
          if (alerts.isEmpty) {
            return const _PanelMessage(
              icon: Icons.check_circle_outline,
              title: 'Rien a traiter maintenant',
              body: 'Aucune alerte operationnelle detectee.',
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  for (final alert in alerts)
                    SizedBox(
                      width: compact ? double.infinity : 300,
                      child: _AlertCard(alert: alert),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final HomeAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.severity) {
      HomeAlertSeverity.critical => AppColors.danger,
      HomeAlertSeverity.urgent => AppColors.warning,
      HomeAlertSeverity.watch => AppColors.infoAlt,
    };
    final label = switch (alert.severity) {
      HomeAlertSeverity.critical => 'Critique',
      HomeAlertSeverity.urgent => 'Urgent',
      HomeAlertSeverity.watch => 'A surveiller',
    };
    return DsCard(
      onTap: () => context.go(alert.route),
      backgroundColor: AppColors.adminSurface,
      borderColor: color.withValues(alpha: .32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RaisedIcon(icon: alert.icon, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  alert.type.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              _StatusPill(label: label, color: color),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            alert.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            alert.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  alert.establishmentLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (alert.ageLabel != null)
                Text(
                  alert.ageLabel!,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

class _GroupOverviewSection extends ConsumerWidget {
  const _GroupOverviewSection({
    required this.overview,
    required this.selectedEstablishmentId,
    required this.permissions,
  });

  final AsyncValue<GroupOverview?> overview;
  final int? selectedEstablishmentId;
  final PermissionSet permissions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!permissions.hasRole('admin')) {
      return const SizedBox.shrink();
    }
    return overview.when(
      data: (value) {
        if (value == null || value.items.length <= 1) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.lg),
          child: _HomePanel(
            title: 'Vue groupe',
            trailing: _StatusPill(
              label: '${value.establishmentCount} sites',
              color: value.criticalCount > 0
                  ? AppColors.danger
                  : value.warningCount > 0
                      ? AppColors.warning
                      : AppColors.success,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _MetricChip(
                      label: 'OK',
                      value: value.okCount.toString(),
                      icon: Icons.check_circle_outline,
                    ),
                    _MetricChip(
                      label: 'A surveiller',
                      value: value.warningCount.toString(),
                      icon: Icons.error_outline,
                    ),
                    _MetricChip(
                      label: 'Critique',
                      value: value.criticalCount.toString(),
                      icon: Icons.warning_amber_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                for (final item in value.items)
                  _GroupOverviewLine(
                    item: item,
                    selected: item.establishmentId == selectedEstablishmentId,
                    onTap: () {
                      ref.read(selectedEstablishmentIdProvider.notifier).state =
                          item.establishmentId;
                      invalidateEstablishmentScopedProviders(ref);
                    },
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.only(top: AppSpacing.lg),
        child: _HomePanel(
          title: 'Vue groupe',
          child: _SkeletonRows(rows: 2),
        ),
      ),
      error: (error, stackTrace) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: _HomePanel(
          title: 'Vue groupe',
          child: _PanelMessage(
            icon: Icons.error_outline,
            title: 'Vue groupe indisponible',
            body: error.toString(),
          ),
        ),
      ),
    );
  }
}

class _GroupOverviewLine extends StatelessWidget {
  const _GroupOverviewLine({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final GroupOverviewItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.status) {
      'critical' => AppColors.danger,
      'warning' => AppColors.warning,
      _ => AppColors.success,
    };
    final statusLabel = switch (item.status) {
      'critical' => 'Critique',
      'warning' => 'A surveiller',
      _ => 'OK',
    };
    final staffValue = '${item.staffPresent}/${item.staffExpected}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .08) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? color.withValues(alpha: .28) : Colors.transparent,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _RaisedIcon(
                        icon: Icons.storefront_outlined,
                        color: color,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          item.establishmentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      _StatusPill(label: statusLabel, color: color),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Text('${item.activeOrders} actives'),
                      Text('${item.lateOrders} retard'),
                      Text('Equipe $staffValue'),
                      Text(formatMoney(item.revenueToday)),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                _RaisedIcon(icon: Icons.storefront_outlined, color: color),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.establishmentName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                _GroupMetric(
                  value: item.activeOrders.toString(),
                  label: 'actives',
                ),
                _GroupMetric(
                  value: item.lateOrders.toString(),
                  label: 'retard',
                ),
                _GroupMetric(value: staffValue, label: 'equipe'),
                SizedBox(
                  width: 94,
                  child: Text(
                    formatMoney(item.revenueToday),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _StatusPill(label: statusLabel, color: color),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GroupMetric extends StatelessWidget {
  const _GroupMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RealtimeSection extends StatelessWidget {
  const _RealtimeSection({
    required this.orders,
    required this.tenant,
  });

  final AsyncValue<List<OrderSummary>> orders;
  final AsyncValue<TenantStatus> tenant;

  @override
  Widget build(BuildContext context) {
    final items = orders.valueOrNull ?? const <OrderSummary>[];
    final late = items.where(_isLate).length;
    final pending = items.where((order) => order.status == 'pending').length;
    return _HomePanel(
      title: 'Activite en temps reel',
      child: orders.when(
        data: (items) {
          if (items.isEmpty) {
            return const _PanelMessage(
              icon: Icons.check_circle_outline,
              title: 'Aucune commande active',
              body: 'Le service est calme pour le moment.',
            );
          }
          return Column(
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _MetricChip(
                    label: 'Commandes',
                    value: items.length.toString(),
                    icon: Icons.receipt_long_outlined,
                  ),
                  _MetricChip(
                    label: 'Prep. moy.',
                    value: tenant.maybeWhen(
                      data: (value) => '${value.estimatedPrepTimeMinutes} min',
                      orElse: () => '-',
                    ),
                    icon: Icons.timer_outlined,
                  ),
                  _MetricChip(
                    label: 'Attente',
                    value: pending.toString(),
                    icon: Icons.pending_actions_outlined,
                  ),
                  _MetricChip(
                    label: 'Retard',
                    value: late.toString(),
                    icon: Icons.warning_amber_outlined,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final order in items.take(8))
                _OrderLine(order: order, late: _isLate(order)),
            ],
          );
        },
        loading: () => const _SkeletonRows(rows: 4),
        error: (error, stackTrace) => _PanelMessage(
          icon: Icons.error_outline,
          title: 'Activite indisponible',
          body: error.toString(),
        ),
      ),
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine({
    required this.order,
    required this.late,
  });

  final OrderSummary order;
  final bool late;

  @override
  Widget build(BuildContext context) {
    final age = order.createdAt == null
        ? '-'
        : '${DateTime.now().difference(order.createdAt!.toLocal()).inMinutes} min';
    return InkWell(
      onTap: () => context.go('/orders'),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                '#${order.id}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Expanded(child: Text(humanOrderType(order.orderType))),
            SizedBox(width: 72, child: Text(age)),
            _StatusPill(
              label: humanStatus(order.status),
              color: late ? AppColors.danger : AppColors.neutral,
            ),
          ],
        ),
      ),
    );
  }
}

class _MyServicePanel extends ConsumerWidget {
  const _MyServicePanel({
    required this.shifts,
    required this.openEntries,
    required this.currentEstablishment,
  });

  final AsyncValue<List<HrShift>> shifts;
  final AsyncValue<List<TimeClockEntry>> openEntries;
  final Establishment? currentEstablishment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final openEntriesList = openEntries.valueOrNull ?? const <TimeClockEntry>[];
    final openCandidates = [
      for (final entry in openEntriesList)
        if (entry.isActive) entry,
    ];
    final openEntry = openCandidates.isEmpty ? null : openCandidates.first;
    final onBreak = openEntry?.isOnBreak ?? false;
    final nextShifts = [
      for (final shift in shifts.valueOrNull ?? const <HrShift>[])
        if (!shift.isCancelled && shift.endsAt.isAfter(DateTime.now())) shift,
    ];
    final nextShift = nextShifts.isEmpty ? null : nextShifts.first;
    return _HomePanel(
      title: 'Mon service',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricChip(
            label: 'Pointage',
            value: openEntry == null
                ? 'Hors service'
                : onBreak
                    ? 'En pause'
                    : 'En service',
            icon: openEntry == null
                ? Icons.punch_clock_outlined
                : onBreak
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
          ),
          const SizedBox(height: AppSpacing.md),
          if (shifts.isLoading)
            const _SkeletonRows(rows: 1)
          else if (nextShift == null)
            const _PanelMessage(
              icon: Icons.event_available_outlined,
              title: 'Aucun shift a venir',
              body: 'Les prochains services apparaitront ici.',
            )
          else
            Text(
              '${formatDateTime(nextShift.startsAt)} - ${formatTime(nextShift.endsAt)}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: openEntry == null && currentEstablishment != null
                    ? () => _clockIn(ref, currentEstablishment!.id)
                    : null,
                icon: const Icon(Icons.login),
                label: const Text('Entree'),
              ),
              OutlinedButton.icon(
                onPressed: openEntry != null ? () => _clockOut(ref) : null,
                icon: const Icon(Icons.logout),
                label: const Text('Sortie'),
              ),
              OutlinedButton.icon(
                onPressed: openEntry == null
                    ? null
                    : () => onBreak ? _endBreak(ref) : _startBreak(ref),
                icon: Icon(onBreak ? Icons.play_arrow : Icons.pause),
                label: Text(onBreak ? 'Reprendre' : 'Pause'),
              ),
              OutlinedButton.icon(
                onPressed: currentEstablishment == null
                    ? null
                    : () => _reportLate(context, ref, nextShift?.id),
                icon: const Icon(Icons.schedule_send_outlined),
                label: const Text('Retard'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _clockIn(WidgetRef ref, int establishmentId) async {
    await ref.read(hrRepositoryProvider).clockIn(
          ClockInDraft(method: 'web', establishmentId: establishmentId),
        );
    ref
      ..invalidate(myTimeClockEntriesProvider)
      ..invalidate(myShiftsProvider)
      ..invalidate(groupOverviewProvider);
  }

  Future<void> _clockOut(WidgetRef ref) async {
    await ref.read(hrRepositoryProvider).clockOut();
    ref
      ..invalidate(myTimeClockEntriesProvider)
      ..invalidate(groupOverviewProvider);
  }

  Future<void> _startBreak(WidgetRef ref) async {
    await ref.read(hrRepositoryProvider).startBreak();
    ref
      ..invalidate(myTimeClockEntriesProvider)
      ..invalidate(groupOverviewProvider);
  }

  Future<void> _endBreak(WidgetRef ref) async {
    await ref.read(hrRepositoryProvider).endBreak();
    ref
      ..invalidate(myTimeClockEntriesProvider)
      ..invalidate(groupOverviewProvider);
  }

  Future<void> _reportLate(
    BuildContext context,
    WidgetRef ref,
    int? shiftId,
  ) async {
    await ref.read(hrRepositoryProvider).reportLate(
          shiftId: shiftId,
          reason: 'Signalement depuis accueil',
        );
    ref
      ..invalidate(hrAlertsProvider)
      ..invalidate(groupOverviewProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Retard signale')),
      );
    }
  }
}

class _UpcomingShiftsPanel extends StatelessWidget {
  const _UpcomingShiftsPanel({
    required this.shifts,
    required this.currentEstablishment,
  });

  final AsyncValue<List<HrShift>> shifts;
  final Establishment? currentEstablishment;

  @override
  Widget build(BuildContext context) {
    return _HomePanel(
      title: 'Prochains shifts',
      child: shifts.when(
        data: (items) {
          final upcoming = items
              .where(
                (shift) =>
                    !shift.isCancelled && shift.endsAt.isAfter(DateTime.now()),
              )
              .take(5)
              .toList();
          if (upcoming.isEmpty) {
            return const _PanelMessage(
              icon: Icons.event_note_outlined,
              title: 'Planning vide',
              body: 'Aucun service programme sur la periode.',
            );
          }
          return Column(
            children: [
              for (final shift in upcoming)
                _ShiftLine(
                  shift: shift,
                  currentEstablishmentId: currentEstablishment?.id,
                ),
            ],
          );
        },
        loading: () => const _SkeletonRows(rows: 3),
        error: (error, stackTrace) => _PanelMessage(
          icon: Icons.error_outline,
          title: 'Shifts indisponibles',
          body: error.toString(),
        ),
      ),
    );
  }
}

class _ShiftLine extends StatelessWidget {
  const _ShiftLine({
    required this.shift,
    required this.currentEstablishmentId,
  });

  final HrShift shift;
  final int? currentEstablishmentId;

  @override
  Widget build(BuildContext context) {
    final otherEstablishment = currentEstablishmentId != null &&
        shift.establishmentId != currentEstablishmentId;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          const _RaisedIcon(
            icon: Icons.event_outlined,
            color: AppColors.infoAlt,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatDateTime(shift.startsAt)} - ${formatTime(shift.endsAt)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  otherEstablishment
                      ? 'Service dans un autre etablissement'
                      : 'Etablissement actif',
                  style: TextStyle(
                    color: otherEstablishment
                        ? AppColors.warning
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.go('/hr'),
            child: const Text('Voir'),
          ),
        ],
      ),
    );
  }
}

class _RestaurantHealthSection extends StatelessWidget {
  const _RestaurantHealthSection({
    required this.tenant,
    required this.stockAlerts,
    required this.payments,
    required this.online,
    required this.queuedActions,
    required this.permissions,
  });

  final AsyncValue<TenantStatus> tenant;
  final AsyncValue<List<Ingredient>> stockAlerts;
  final AsyncValue<PaymentSummary?> payments;
  final bool online;
  final int queuedActions;
  final PermissionSet permissions;

  @override
  Widget build(BuildContext context) {
    final rows = [
      _HealthRow(
        icon: Icons.storefront_outlined,
        label: 'Service',
        value: tenant.maybeWhen(
          data: (value) => value.isOpen ? 'Ouvert' : 'Ferme',
          orElse: () => '-',
        ),
        route: '/settings',
      ),
      if (permissions.can(AppPermission.stockRead))
        _HealthRow(
          icon: Icons.inventory_2_outlined,
          label: 'Stock',
          value: stockAlerts.maybeWhen(
            data: (value) => value.isEmpty ? 'OK' : '${value.length} alerte(s)',
            orElse: () => '-',
          ),
          route: '/stock',
        ),
      if (permissions.can(AppPermission.haccpRead))
        const _HealthRow(
          icon: Icons.thermostat_outlined,
          label: 'HACCP',
          value: 'A controler',
          route: '/haccp',
        ),
      if (permissions.can(AppPermission.paymentsRead))
        _HealthRow(
          icon: Icons.payments_outlined,
          label: 'Paiements',
          value: payments.maybeWhen(
            data: (value) {
              final failed = value?.countsByStatus['failed'] ?? 0;
              return failed == 0 ? 'OK' : '$failed echec(s)';
            },
            orElse: () => '-',
          ),
          route: '/payments',
        ),
      _HealthRow(
        icon: Icons.wifi_outlined,
        label: 'Internet',
        value: online ? 'Stable' : 'Offline',
        route: '/settings',
      ),
      _HealthRow(
        icon: Icons.cloud_sync_outlined,
        label: 'Synchronisation',
        value: queuedActions == 0 ? 'A jour' : '$queuedActions en queue',
        route: '/settings',
      ),
    ];
    return _HomePanel(
      title: 'Etat du restaurant',
      child: Column(children: rows),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String value;
  final String route;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(route),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(icon, size: 19, color: AppColors.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceHealthSection extends StatelessWidget {
  const _DeviceHealthSection({
    required this.printConfig,
    required this.terminalReaders,
    required this.permissions,
    required this.online,
    required this.queuedActions,
  });

  final AsyncValue<TenantPrintConfig?> printConfig;
  final AsyncValue<List<TerminalReader>> terminalReaders;
  final PermissionSet permissions;
  final bool online;
  final int queuedActions;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _HealthRow(
        icon: online ? Icons.router_outlined : Icons.wifi_off_outlined,
        label: 'Reseau',
        value: online ? 'Connecte' : 'Offline',
        route: '/settings',
      ),
      _HealthRow(
        icon: Icons.cloud_sync_outlined,
        label: 'File locale',
        value: queuedActions == 0 ? 'Vide' : '$queuedActions action(s)',
        route: '/settings',
      ),
      if (permissions.can(AppPermission.printRead))
        _DevicePrinterRows(printConfig: printConfig),
      if (permissions.can(AppPermission.paymentsTerminal))
        _DeviceTerminalRows(terminalReaders: terminalReaders),
    ];

    return _HomePanel(
      title: 'Sante peripheriques',
      child: Column(children: rows),
    );
  }
}

class _DevicePrinterRows extends StatelessWidget {
  const _DevicePrinterRows({required this.printConfig});

  final AsyncValue<TenantPrintConfig?> printConfig;

  @override
  Widget build(BuildContext context) {
    return printConfig.when(
      data: (config) {
        if (config == null) {
          return const _HealthRow(
            icon: Icons.print_disabled_outlined,
            label: 'Impression',
            value: 'Non autorisee',
            route: '/settings',
          );
        }
        if (!config.enabled) {
          return const _HealthRow(
            icon: Icons.print_disabled_outlined,
            label: 'Impression',
            value: 'Desactivee',
            route: '/settings',
          );
        }
        final kitchen = _printerConfigured(config.config, 'kitchen');
        final counter = _printerConfigured(config.config, 'counter');
        final ready = [kitchen, counter].where((value) => value).length;
        return _HealthRow(
          icon: Icons.print_outlined,
          label: 'Impression',
          value: '$ready / 2 confirmees',
          route: '/settings',
        );
      },
      loading: () => const _HealthRow(
        icon: Icons.print_outlined,
        label: 'Impression',
        value: 'Chargement',
        route: '/settings',
      ),
      error: (error, stackTrace) => const _HealthRow(
        icon: Icons.print_disabled_outlined,
        label: 'Impression',
        value: 'Indisponible',
        route: '/settings',
      ),
    );
  }

  bool _printerConfigured(Map<String, dynamic> config, String prefix) {
    final host = config['${prefix}_printer']?.toString().trim() ?? '';
    final confirmed = config['${prefix}_host_confirmed'] == true;
    return host.isNotEmpty && confirmed;
  }
}

class _DeviceTerminalRows extends StatelessWidget {
  const _DeviceTerminalRows({required this.terminalReaders});

  final AsyncValue<List<TerminalReader>> terminalReaders;

  @override
  Widget build(BuildContext context) {
    return terminalReaders.when(
      data: (readers) {
        if (readers.isEmpty) {
          return const _HealthRow(
            icon: Icons.credit_card_off_outlined,
            label: 'TPE',
            value: 'Aucun lecteur',
            route: '/payments',
          );
        }
        final online = readers.where(_readerOnline).length;
        return _HealthRow(
          icon: Icons.point_of_sale_outlined,
          label: 'TPE',
          value: '$online / ${readers.length} connecte(s)',
          route: '/payments',
        );
      },
      loading: () => const _HealthRow(
        icon: Icons.point_of_sale_outlined,
        label: 'TPE',
        value: 'Chargement',
        route: '/payments',
      ),
      error: (error, stackTrace) => const _HealthRow(
        icon: Icons.credit_card_off_outlined,
        label: 'TPE',
        value: 'Indisponible',
        route: '/payments',
      ),
    );
  }

  bool _readerOnline(TerminalReader reader) {
    final status = reader.status.toLowerCase();
    return status == 'online' || status == 'available' || status == 'ready';
  }
}

class _PerformanceSection extends StatelessWidget {
  const _PerformanceSection({
    required this.stats,
    required this.topProducts,
    required this.permissions,
  });

  final AsyncValue<StatsSummary?> stats;
  final AsyncValue<List<TopProductStats>> topProducts;
  final PermissionSet permissions;

  @override
  Widget build(BuildContext context) {
    if (!permissions.hasRole('admin')) {
      return const SizedBox.shrink();
    }
    return _HomePanel(
      title: 'Performance / tendances',
      child: stats.when(
        data: (summary) {
          if (summary == null) {
            return const _PanelMessage(
              icon: Icons.insights_outlined,
              title: 'Statistiques indisponibles',
              body: 'Les performances necessitent un acces admin.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _MetricChip(
                    label: 'CA 24h',
                    value: formatMoney(summary.live.revenueLast24h),
                    icon: Icons.euro_outlined,
                  ),
                  _MetricChip(
                    label: 'Panier moyen',
                    value: formatMoney(summary.live.avgOrderValue24h),
                    icon: Icons.shopping_cart_checkout_outlined,
                  ),
                  _MetricChip(
                    label: 'Commandes',
                    value: summary.live.ordersLast24h.toString(),
                    icon: Icons.receipt_long_outlined,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              topProducts.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const _PanelMessage(
                      icon: Icons.local_pizza_outlined,
                      title: 'Aucun top produit',
                      body: 'Les ventes apparaitront apres le service.',
                    );
                  }
                  return Column(
                    children: [
                      for (final item in items.take(5))
                        _TopProductLine(item: item),
                    ],
                  );
                },
                loading: () => const _SkeletonRows(rows: 3),
                error: (error, stackTrace) => _PanelMessage(
                  icon: Icons.error_outline,
                  title: 'Top produits indisponible',
                  body: error.toString(),
                ),
              ),
            ],
          );
        },
        loading: () => const _SkeletonRows(rows: 3),
        error: (error, stackTrace) => _PanelMessage(
          icon: Icons.error_outline,
          title: 'Performance indisponible',
          body: error.toString(),
        ),
      ),
    );
  }
}

class _TopProductLine extends StatelessWidget {
  const _TopProductLine({required this.item});

  final TopProductStats item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text('${item.quantity}'),
          const SizedBox(width: AppSpacing.md),
          Text(formatMoney(item.revenue)),
        ],
      ),
    );
  }
}

class _HomePanel extends StatelessWidget {
  const _HomePanel({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      backgroundColor: AppColors.adminSurface,
      borderColor: AppColors.adminBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.adminSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.adminBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _RaisedIcon extends StatelessWidget {
  const _RaisedIcon({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.adminSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: .28)),
        boxShadow: AppElevation.raisedSm(AppColors.adminSurface, intensity: .5),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < rows; index++) ...[
          Container(
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.adminSurfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          if (index != rows - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
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

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _displayName(String? fullName, String? email) {
  final name = fullName?.trim();
  if (name != null && name.isNotEmpty) {
    return name.split(' ').first;
  }
  final rawEmail = email?.trim();
  if (rawEmail != null && rawEmail.isNotEmpty) {
    return rawEmail.split('@').first;
  }
  return 'Kitchen';
}

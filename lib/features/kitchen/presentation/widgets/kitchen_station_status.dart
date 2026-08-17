import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_radius.dart';
import 'package:app_admin_staff/features/kitchen/domain/kitchen_screen_presets.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kitchen_typography.dart';
import 'package:app_admin_staff/features/orders/data/orders_repository.dart';
import 'package:flutter/material.dart';

class KitchenStationStatus extends StatelessWidget {
  const KitchenStationStatus({
    required this.order,
    this.compact = false,
    super.key,
  });

  final OrderDetail order;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final statuses = kitchenStationStatusesForOrder(order);
    if (statuses.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 16,
          compact ? 8 : 10,
          compact ? 12 : 16,
          compact ? 4 : 6,
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final status in statuses)
              _KitchenStationStatusChip(status: status, compact: compact),
          ],
        ),
      ),
    );
  }
}

class KitchenStationStatusViewModel {
  const KitchenStationStatusViewModel({
    required this.station,
    required this.totalItems,
    required this.readyItems,
    required this.allReady,
  });

  final String station;
  final int totalItems;
  final int readyItems;
  final bool allReady;
}

List<KitchenStationStatusViewModel> kitchenStationStatusesForOrder(
  OrderDetail order,
) {
  if (order.stationSummary.isNotEmpty) {
    return [
      for (final summary in order.stationSummary)
        KitchenStationStatusViewModel(
          station: summary.station,
          totalItems: summary.totalItems,
          readyItems: summary.readyItems,
          allReady: summary.allReady,
        ),
    ];
  }

  final counters = <String, _StationCounter>{};
  for (final item in order.items) {
    final station = item.preparationStation.trim().isEmpty
        ? 'kitchen'
        : item.preparationStation;
    final counter = counters.putIfAbsent(station, _StationCounter.new);
    counter.totalItems += 1;
    if (item.preparationStatus == 'ready') {
      counter.readyItems += 1;
    }
  }

  return [
    for (final entry in counters.entries)
      KitchenStationStatusViewModel(
        station: entry.key,
        totalItems: entry.value.totalItems,
        readyItems: entry.value.readyItems,
        allReady: entry.value.totalItems > 0 &&
            entry.value.readyItems == entry.value.totalItems,
      ),
  ];
}

class _KitchenStationStatusChip extends StatelessWidget {
  const _KitchenStationStatusChip({
    required this.status,
    required this.compact,
  });

  final KitchenStationStatusViewModel status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isReady = status.allReady;
    final background = isReady ? AppColors.successBg : AppColors.warningSoftBg;
    final border = isReady ? AppColors.success : AppColors.warning;
    final stateLabel = isReady ? '✓ PRÊT' : 'EN COURS';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 5 : 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isReady ? Icons.check_circle_outline : Icons.sync_outlined,
              size: compact ? 14 : 16,
              color: AppColors.textPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              '${kitchenStationLabel(status.station)} $stateLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: KitchenTypography.meta(
                context,
              ).copyWith(fontSize: compact ? 11 : 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationCounter {
  int totalItems = 0;
  int readyItems = 0;
}

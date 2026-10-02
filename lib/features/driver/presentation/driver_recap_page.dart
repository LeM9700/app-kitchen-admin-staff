import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/driver/presentation/driver_deliveries_page.dart'
    show driverErrorMessage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recapitulatif de la journee du livreur : livraisons, tournees, especes a remettre.
class DriverRecapPage extends ConsumerWidget {
  const DriverRecapPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(driverRecapProvider);
    return recap.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(driverErrorMessage(error), textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              FilledButton(
                onPressed: () => ref.invalidate(driverRecapProvider),
                child: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      ),
      data: (data) => RefreshIndicator(
        onRefresh: () async => ref.refresh(driverRecapProvider.future),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Livrees',
                    value: '${data.deliveredCount}',
                    icon: Icons.done_all_outlined,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _Stat(
                    label: 'Departs',
                    value: '${data.runsCount}',
                    icon: Icons.route_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _Stat(
              key: const ValueKey('recap-cash'),
              label: 'Especes encaissees (a remettre au restaurant)',
              value: formatMoney(data.cashCollected),
              icon: Icons.payments_outlined,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Livraisons du jour',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (data.deliveries.isEmpty)
              Text(
                'Aucune livraison terminee aujourd\'hui.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            for (final item in data.deliveries)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: DsCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Commande #${item.orderId}',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            if (item.deliveryAddress != null)
                              Text(
                                item.deliveryAddress!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatMoney(item.total)),
                          if (item.finishedAt != null)
                            Text(
                              formatTime(item.finishedAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

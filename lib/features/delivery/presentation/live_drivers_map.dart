import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/dispatch_repository.dart';
import 'package:app_admin_staff/features/delivery/presentation/delivery_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Etat d'un livreur sur la carte, en une phrase.
String liveDriverStatusLabel(LiveDriver driver) {
  if (driver.isEnRoute) {
    if (driver.signalLost) {
      final age = driver.ageSeconds;
      return age == null
          ? 'En route : aucune position recue'
          : 'En route : signal perdu depuis ${(age / 60).ceil()} min';
    }
    if (driver.stale) return 'En route : position ancienne';
    return 'En route';
  }
  if (driver.state == 'assigned') return 'Livraison attribuee';
  if (!driver.clockedIn) return 'Non pointe';
  return 'Disponible';
}

/// Couleur du repere : bleu normal, orange position ancienne, rouge signal perdu.
Color liveDriverColor(LiveDriver driver) {
  if (driver.signalLost) return AppColors.dangerAlt;
  if (driver.stale) return AppColors.warning;
  return AppColors.infoAlt;
}

/// Carte des livreurs actifs (comptoir). Seuls les livreurs en route ont une position : en dehors
/// d'une livraison, aucune position n'est montree.
class LiveDriversSection extends ConsumerWidget {
  const LiveDriversSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveDriversProvider);
    final drivers = live.valueOrNull ?? const <LiveDriver>[];
    final onRoad = drivers.where((d) => d.isEnRoute).toList();
    if (onRoad.isEmpty) return const SizedBox.shrink();
    final alerts = onRoad.where((d) => d.signalLost).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Livreurs en route (${onRoad.length})',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (alerts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: StatusBadge(
                key: const ValueKey('live-signal-alert'),
                label: alerts.length == 1
                    ? 'Signal perdu : ${alerts.first.label}'
                    : '${alerts.length} livreurs sans signal',
                tone: StatusTone.danger,
                icon: Icons.wifi_off_outlined,
              ),
            ),
          if (onRoad.any((d) => d.hasPosition))
            _LiveMap(drivers: onRoad)
          else
            const Text('Aucune position recue pour le moment.'),
          const SizedBox(height: AppSpacing.xs),
          for (final driver in onRoad) _LiveDriverRow(driver: driver),
        ],
      ),
    );
  }
}

class _LiveMap extends ConsumerWidget {
  const _LiveMap({required this.drivers});

  final List<LiveDriver> drivers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = [
      for (final d in drivers)
        if (d.hasPosition) LatLng(d.lat!, d.lng!),
    ];
    final destinations = [
      for (final d in drivers)
        for (final delivery in d.deliveries)
          if (delivery.lat != null && delivery.lng != null)
            LatLng(delivery.lat!, delivery.lng!),
    ];
    final center = boundsCenter(points) ?? fallbackDeliveryCenter;
    return SizedBox(
      height: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: FlutterMap(
          key: const ValueKey('live-map'),
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
            initialCameraFit: points.length + destinations.length > 1
                ? CameraFit.coordinates(
                    coordinates: [...points, ...destinations],
                    padding: const EdgeInsets.all(40),
                    maxZoom: 16,
                  )
                : null,
          ),
          children: [
            ref.watch(deliveryTileLayerProvider),
            MarkerLayer(
              markers: [
                for (final point in destinations)
                  Marker(
                    point: point,
                    width: 28,
                    height: 28,
                    child: const Icon(
                      Icons.flag_rounded,
                      color: AppColors.neutral,
                      size: 24,
                    ),
                  ),
                for (final d in drivers)
                  if (d.hasPosition)
                    Marker(
                      point: LatLng(d.lat!, d.lng!),
                      width: 120,
                      height: 56,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.delivery_dining,
                            key: ValueKey('live-driver-${d.driverId}'),
                            color: liveDriverColor(d),
                            size: 30,
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            color: Colors.white70,
                            child: Text(
                              d.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveDriverRow extends StatelessWidget {
  const _LiveDriverRow({required this.driver});

  final LiveDriver driver;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: DsCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.two_wheeler_outlined, color: liveDriverColor(driver)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    driver.label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    liveDriverStatusLabel(driver),
                    key: ValueKey('live-status-${driver.driverId}'),
                  ),
                  if (!driver.sharingConsent)
                    const Text(
                      'N\'a pas accepte le partage de position',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
            Text('${driver.deliveries.length} cmd'),
          ],
        ),
      ),
    );
  }
}

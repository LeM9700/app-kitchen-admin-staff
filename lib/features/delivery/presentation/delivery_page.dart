import 'dart:convert';
import 'dart:math' as math;

import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/auth/session_controller.dart';
import 'package:app_admin_staff/core/utils/formatters.dart';
import 'package:app_admin_staff/design_system/components/badges/status_badge.dart';
import 'package:app_admin_staff/design_system/components/cards/ds_card.dart';
import 'package:app_admin_staff/design_system/components/cards/stat_card.dart';
import 'package:app_admin_staff/design_system/components/feedback/app_feedback.dart';
import 'package:app_admin_staff/design_system/components/forms/pill_filter_bar.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeliveryPage extends ConsumerWidget {
  const DeliveryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(deliveryZonesProvider);
    final filter = ref.watch(deliveryZoneStatusFilterProvider);
    final user = ref.watch(sessionControllerProvider).valueOrNull?.user;
    final isAdmin = user?.role == 'admin' || user?.role == 'super-admin';

    return Padding(
      padding: EdgeInsets.all(
        Breakpoints.isMobile(context) ? AppSpacing.md : AppSpacing.xxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zones de livraison',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Couverture, frais et delais estimes',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Tester coordonnees',
                child: IconButton.filledTonal(
                  onPressed: () => _checkAddress(context, ref),
                  icon: const Icon(Icons.my_location_outlined),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Tooltip(
                message: 'Rafraichir',
                child: IconButton.filledTonal(
                  onPressed: () => ref.invalidate(deliveryZonesProvider),
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: AppSpacing.xs),
                FilledButton.icon(
                  onPressed: () => _zoneDialog(context, ref),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Nouvelle zone'),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          zones.when(
            data: (items) => _DeliveryStats(zones: items),
            loading: () => const LinearProgressIndicator(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.md),
          _DeliveryFilters(selected: filter),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: zones.when(
              data: (items) {
                final visible = _filteredZones(items, filter);
                if (visible.isEmpty) {
                  return const AppFeedback(
                    kind: AppFeedbackKind.noResults,
                    title: 'Aucune zone',
                    message: 'Aucune zone ne correspond au filtre.',
                  );
                }
                if (Breakpoints.isCompactDesktop(context) ||
                    Breakpoints.isMobile(context)) {
                  return ListView.separated(
                    itemCount: visible.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _ZonesMapPanel(zones: visible);
                      }
                      return _ZoneCard(
                        zone: visible[index - 1],
                        isAdmin: isAdmin,
                      );
                    },
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 480, child: _ZonesMapPanel(zones: visible)),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      child: ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) => _ZoneCard(
                          zone: visible[index],
                          isAdmin: isAdmin,
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const AppFeedback(
                kind: AppFeedbackKind.loading,
                title: 'Chargement des zones',
              ),
              error: (error, stackTrace) => AppFeedback(
                kind: AppFeedbackKind.error,
                title: 'Zones indisponibles',
                message: _errorMessage(error),
                onRetry: () => ref.invalidate(deliveryZonesProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<DeliveryZone> _filteredZones(
    List<DeliveryZone> zones,
    DeliveryZoneStatusFilter filter,
  ) {
    return zones.where((zone) {
      return switch (filter) {
        DeliveryZoneStatusFilter.all => true,
        DeliveryZoneStatusFilter.active => zone.isActive,
        DeliveryZoneStatusFilter.inactive => !zone.isActive,
      };
    }).toList();
  }

  Future<void> _zoneDialog(
    BuildContext context,
    WidgetRef ref, {
    DeliveryZone? zone,
  }) async {
    final name = TextEditingController(text: zone?.name ?? '');
    final fee = TextEditingController(text: zone?.fee.toString() ?? '0');
    final min =
        TextEditingController(text: zone?.minOrderAmount.toString() ?? '0');
    final minutes =
        TextEditingController(text: zone?.estimatedMinutes.toString() ?? '30');
    final polygon = TextEditingController(
      text: zone?.polygon == null
          ? ''
          : const JsonEncoder.withIndent('  ').convert(zone!.polygon),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(zone == null ? 'Nouvelle zone' : 'Modifier ${zone.name}'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fee,
                        decoration: const InputDecoration(labelText: 'Frais'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: min,
                        decoration: const InputDecoration(
                          labelText: 'Minimum commande',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: TextField(
                        controller: minutes,
                        decoration: const InputDecoration(
                          labelText: 'Minutes estimees',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: polygon,
                  decoration:
                      const InputDecoration(labelText: 'Polygone GeoJSON'),
                  minLines: 6,
                  maxLines: 10,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Valider'),
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
    final draft = _zoneDraft(
      context,
      name: name.text,
      fee: fee.text,
      min: min.text,
      minutes: minutes.text,
      polygon: polygon.text,
    );
    if (draft == null) {
      return;
    }
    try {
      final repository = ref.read(deliveryRepositoryProvider);
      if (zone == null) {
        await repository.createZone(draft);
      } else {
        await repository.updateZone(zone.id, draft);
      }
      ref.invalidate(deliveryZonesProvider);
      if (!context.mounted) {
        return;
      }
      _showSnack(context, zone == null ? 'Zone creee' : 'Zone mise a jour');
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }

  Future<void> _checkAddress(BuildContext context, WidgetRef ref) async {
    final lat = TextEditingController();
    final lng = TextEditingController();
    final address = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tester livraison'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'Adresse'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: lat,
                      decoration: const InputDecoration(labelText: 'Latitude'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: lng,
                      decoration: const InputDecoration(labelText: 'Longitude'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tester'),
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
    try {
      final result = await ref.read(deliveryRepositoryProvider).checkAddress(
            lat: _double(lat.text),
            lng: _double(lng.text),
            address: address.text,
          );
      if (!context.mounted) {
        return;
      }
      _showSnack(context, '${result.name} - ${formatMoney(result.fee)}');
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, _errorMessage(error));
      }
    }
  }
}

class _DeliveryStats extends StatelessWidget {
  const _DeliveryStats({required this.zones});

  final List<DeliveryZone> zones;

  @override
  Widget build(BuildContext context) {
    final active = zones.where((zone) => zone.isActive).length;
    final averageFee = zones.isEmpty
        ? 0.0
        : zones.fold<double>(0, (sum, zone) => sum + zone.fee) / zones.length;
    final averageMin = zones.isEmpty
        ? 0.0
        : zones.fold<double>(0, (sum, zone) => sum + zone.minOrderAmount) /
            zones.length;
    final averageEta = zones.isEmpty
        ? 0
        : (zones.fold<int>(0, (sum, zone) => sum + zone.estimatedMinutes) /
                zones.length)
            .round();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppStatCard(
          label: 'Zones actives',
          value: active.toString(),
          icon: Icons.map_outlined,
          accentColor: AppColors.success,
          subtitle: '${zones.length} zones',
        ),
        AppStatCard(
          label: 'Frais moyen',
          value: formatMoney(averageFee),
          icon: Icons.payments_outlined,
          accentColor: AppColors.accent,
        ),
        AppStatCard(
          label: 'Minimum moyen',
          value: formatMoney(averageMin),
          icon: Icons.shopping_basket_outlined,
          accentColor: AppColors.infoAlt,
        ),
        AppStatCard(
          label: 'ETA moyenne',
          value: '$averageEta min',
          icon: Icons.timer_outlined,
          accentColor: AppColors.warning,
        ),
      ],
    );
  }
}

class _DeliveryFilters extends ConsumerWidget {
  const _DeliveryFilters({required this.selected});

  final DeliveryZoneStatusFilter selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: PillFilterBar<DeliveryZoneStatusFilter>(
        selected: selected,
        onSelected: (value) {
          ref.read(deliveryZoneStatusFilterProvider.notifier).state = value;
        },
        options: const [
          PillFilterOption(
            value: DeliveryZoneStatusFilter.all,
            label: 'Toutes',
            icon: Icons.all_inclusive,
          ),
          PillFilterOption(
            value: DeliveryZoneStatusFilter.active,
            label: 'Actives',
            icon: Icons.play_circle_outline,
          ),
          PillFilterOption(
            value: DeliveryZoneStatusFilter.inactive,
            label: 'Inactives',
            icon: Icons.pause_circle_outline,
          ),
        ],
      ),
    );
  }
}

class _ZonesMapPanel extends StatelessWidget {
  const _ZonesMapPanel({required this.zones});

  final List<DeliveryZone> zones;

  @override
  Widget build(BuildContext context) {
    return DsCard(
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Carte des zones',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const StatusBadge(
                label: 'GeoJSON',
                tone: StatusTone.info,
                icon: Icons.polyline_outlined,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: Semantics(
              label: 'Representation abstraite des zones de livraison',
              child: CustomPaint(
                painter: _ZonesPainter(zones),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZoneCard extends ConsumerWidget {
  const _ZoneCard({
    required this.zone,
    required this.isAdmin,
  });

  final DeliveryZone zone;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: zone.isActive ? AppColors.successBg : AppColors.neutralBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.location_on_outlined,
              color: zone.isActive ? AppColors.success : AppColors.neutral,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        zone.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    StatusBadge(
                      label: zone.isActive ? 'Active' : 'Inactive',
                      tone: zone.isActive
                          ? StatusTone.success
                          : StatusTone.neutral,
                      icon: zone.isActive
                          ? Icons.play_circle_outline
                          : Icons.pause_circle_outline,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _ZoneMetric(label: 'Frais', value: formatMoney(zone.fee)),
                    _ZoneMetric(
                      label: 'Minimum',
                      value: formatMoney(zone.minOrderAmount),
                    ),
                    _ZoneMetric(
                      label: 'ETA',
                      value: '${zone.estimatedMinutes} min',
                    ),
                    _ZoneMetric(
                      label: 'Polygone',
                      value: zone.hasGeoJson ? 'Expose' : 'Non expose',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              tooltip: 'Modifier',
              onPressed: () => const DeliveryPage()._zoneDialog(
                context,
                ref,
                zone: zone,
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

class _ZoneMetric extends StatelessWidget {
  const _ZoneMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}

class _ZonesPainter extends CustomPainter {
  const _ZonesPainter(this.zones);

  final List<DeliveryZone> zones;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.adminBorder
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final center = Offset(size.width / 2, size.height / 2);
    final restaurant = Paint()..color = AppColors.accent;
    canvas.drawCircle(center, 7, restaurant);

    for (var index = 0; index < zones.length; index++) {
      final zone = zones[index];
      final paint = Paint()
        ..color = (zone.isActive ? AppColors.infoAlt : AppColors.neutral)
            .withValues(alpha: zone.isActive ? 0.18 : 0.12)
        ..style = PaintingStyle.fill;
      final stroke = Paint()
        ..color = zone.isActive ? AppColors.infoAlt : AppColors.neutral
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final radius = math.min(size.width, size.height) *
          (0.18 + math.min(index, 4) * 0.055);
      final sides = 5 + (index % 3);
      final path = Path();
      for (var point = 0; point < sides; point++) {
        final angle = (math.pi * 2 * point / sides) + index * 0.28;
        final offset = Offset(
          center.dx + math.cos(angle) * radius * (1.2 + index * 0.04),
          center.dy + math.sin(angle) * radius * (0.75 + index * 0.03),
        );
        if (point == 0) {
          path.moveTo(offset.dx, offset.dy);
        } else {
          path.lineTo(offset.dx, offset.dy);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _ZonesPainter oldDelegate) {
    return oldDelegate.zones != zones;
  }
}

DeliveryZoneDraft? _zoneDraft(
  BuildContext context, {
  required String name,
  required String fee,
  required String min,
  required String minutes,
  required String polygon,
}) {
  final trimmedName = name.trim();
  final parsedFee = _double(fee);
  final parsedMin = _double(min);
  final parsedMinutes = int.tryParse(minutes.trim()) ?? 0;
  final decodedPolygon = _decodePolygon(polygon);
  if (trimmedName.isEmpty) {
    _showSnack(context, 'Nom obligatoire');
    return null;
  }
  if (parsedFee < 0 || parsedMin < 0) {
    _showSnack(context, 'Montants invalides');
    return null;
  }
  if (parsedMinutes <= 0) {
    _showSnack(context, 'Delai invalide');
    return null;
  }
  if (decodedPolygon == null) {
    _showSnack(context, 'Polygone GeoJSON obligatoire');
    return null;
  }
  return DeliveryZoneDraft(
    name: trimmedName,
    fee: parsedFee,
    minOrderAmount: parsedMin,
    estimatedMinutes: parsedMinutes,
    polygon: decodedPolygon,
  );
}

Map<String, dynamic>? _decodePolygon(String value) {
  try {
    final decoded = json.decode(value);
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      if (map['type'] != null && map['coordinates'] != null) {
        return map;
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

double _double(String value) {
  return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
}

void _showSnack(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _errorMessage(Object error) {
  return error.toString().replaceFirst('Exception: ', '');
}

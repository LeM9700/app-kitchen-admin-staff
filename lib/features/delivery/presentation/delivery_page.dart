import 'dart:async';

import 'package:app_admin_staff/app/responsive/breakpoints.dart';
import 'package:app_admin_staff/core/api/api_error.dart';
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
import 'package:app_admin_staff/features/delivery/presentation/delivery_map.dart';
import 'package:app_admin_staff/features/delivery/presentation/delivery_zone_editor_page.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Zone mise en avant sur la carte (touchee dans la liste).
final selectedZoneIdProvider = StateProvider.autoDispose<int?>((ref) => null);

/// Point teste via « Tester une adresse » : affiche un repere sur la carte.
final coverageTestPointProvider = StateProvider.autoDispose<LatLng?>((ref) => null);

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
                      'Couverture, frais, regles de tarification et delais estimes',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Tester une adresse',
                child: IconButton.filledTonal(
                  key: const ValueKey('delivery-test-address'),
                  onPressed: () => _testAddress(context, ref),
                  icon: const Icon(Icons.my_location_outlined),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Tooltip(
                message: 'Rafraichir',
                child: IconButton.filledTonal(
                  onPressed: () {
                    ref
                      ..invalidate(deliveryZonesProvider)
                      ..invalidate(deliverySettingsProvider);
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (isAdmin) ...[
                const SizedBox(width: AppSpacing.xs),
                FilledButton.icon(
                  key: const ValueKey('delivery-new-zone'),
                  onPressed: () => _openEditor(context, ref),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('Nouvelle zone'),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _DeliverySwitchCard(isAdmin: isAdmin),
          const SizedBox(height: AppSpacing.md),
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
                final list = visible.isEmpty
                    ? const AppFeedback(
                        kind: AppFeedbackKind.noResults,
                        title: 'Aucune zone',
                        message: 'Aucune zone ne correspond au filtre.',
                      )
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) => _ZoneCard(
                          zone: visible[index],
                          isAdmin: isAdmin,
                        ),
                      );
                if (Breakpoints.isCompactDesktop(context) ||
                    Breakpoints.isMobile(context)) {
                  return ListView(
                    children: [
                      SizedBox(
                        height: 340,
                        child: _ZonesMapPanel(zones: items, visible: visible),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (visible.isEmpty)
                        list
                      else
                        for (final zone in visible) ...[
                          _ZoneCard(zone: zone, isAdmin: isAdmin),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 520,
                      child: _ZonesMapPanel(zones: items, visible: visible),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(child: list),
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

  Future<void> _testAddress(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (context) => const _CoverageTestDialog(),
    );
  }
}

/// Ouvre l'editeur plein ecran ; rafraichit la liste si la zone a ete enregistree.
Future<void> _openEditor(
  BuildContext context,
  WidgetRef ref, {
  DeliveryZone? zone,
}) async {
  final establishments = await ref.read(availableEstablishmentsProvider.future);
  if (!context.mounted) return;
  final saved = await Navigator.of(context).push<DeliveryZone>(
    MaterialPageRoute(
      builder: (context) => DeliveryZoneEditorPage(
        zone: zone,
        establishments: establishments,
      ),
    ),
  );
  if (saved == null) return;
  ref.invalidate(deliveryZonesProvider);
  if (context.mounted) {
    _showSnack(context, zone == null ? 'Zone creee' : 'Zone mise a jour');
  }
}

// --------------------------------------------------------------------------- interrupteur general

class _DeliverySwitchCard extends ConsumerWidget {
  const _DeliverySwitchCard({required this.isAdmin});

  final bool isAdmin;

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    DeliverySettings current,
    bool enabled,
  ) async {
    if (!enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Couper la livraison ?'),
          content: const Text(
            'Les clients ne pourront plus commander en livraison (le retrait reste '
            'possible). Les commandes deja passees ne sont pas affectees.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('delivery-switch-confirm-off'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Couper la livraison'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await ref.read(deliveryRepositoryProvider).setDeliveryEnabled(
            enabled: enabled,
            expectedVersion: current.version,
          );
    } catch (error) {
      if (context.mounted) _showSnack(context, _errorMessage(error));
    } finally {
      ref.invalidate(deliverySettingsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(deliverySettingsProvider);
    return DsCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: settings.when(
        data: (value) => SwitchListTile(
          key: const ValueKey('delivery-enabled-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Livraison activee'),
          subtitle: Text(
            value.internalEnabled
                ? 'Les clients peuvent commander en livraison dans les zones actives.'
                : 'La livraison est coupee : seul le retrait est propose aux clients.',
          ),
          value: value.internalEnabled,
          onChanged: isAdmin
              ? (enabled) => _toggle(context, ref, value, enabled)
              : null,
        ),
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: LinearProgressIndicator(),
        ),
        error: (error, stackTrace) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.error_outline),
          title: const Text('Reglage de livraison indisponible'),
          subtitle: Text(_errorMessage(error)),
          trailing: TextButton(
            onPressed: () => ref.invalidate(deliverySettingsProvider),
            child: const Text('Reessayer'),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- statistiques / filtres

class _DeliveryStats extends StatelessWidget {
  const _DeliveryStats({required this.zones});

  final List<DeliveryZone> zones;

  @override
  Widget build(BuildContext context) {
    final active = zones.where((zone) => zone.isActive).toList();
    final averageFee = active.isEmpty
        ? 0.0
        : active.fold<double>(0, (sum, zone) => sum + zone.fee) / active.length;
    final averageMin = active.isEmpty
        ? 0.0
        : active.fold<double>(0, (sum, zone) => sum + zone.minOrderAmount) /
            active.length;
    final averageEta = active.isEmpty
        ? 0
        : (active.fold<int>(0, (sum, zone) => sum + zone.estimatedMinutes) /
                active.length)
            .round();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppStatCard(
          label: 'Zones actives',
          value: active.length.toString(),
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

// --------------------------------------------------------------------------- carte

class _ZonesMapPanel extends ConsumerStatefulWidget {
  const _ZonesMapPanel({required this.zones, required this.visible});

  /// Toutes les zones (pour centrer la carte) ; [visible] : celles que le filtre affiche.
  final List<DeliveryZone> zones;
  final List<DeliveryZone> visible;

  @override
  ConsumerState<_ZonesMapPanel> createState() => _ZonesMapPanelState();
}

class _ZonesMapPanelState extends ConsumerState<_ZonesMapPanel> {
  final _controller = MapController();
  bool _ready = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _focus(LatLng? point, {double zoom = 13}) {
    if (point == null || !_ready) return;
    _controller.move(point, zoom);
  }

  @override
  Widget build(BuildContext context) {
    final establishments =
        ref.watch(availableEstablishmentsProvider).valueOrNull ?? const [];
    final selectedId = ref.watch(selectedZoneIdProvider);
    final testPoint = ref.watch(coverageTestPointProvider);

    ref.listen<int?>(selectedZoneIdProvider, (_, id) {
      if (id == null) return;
      for (final zone in widget.zones) {
        if (zone.id == id) _focus(boundsCenter(zone.ring));
      }
    });
    ref.listen<LatLng?>(coverageTestPointProvider, (_, point) => _focus(point, zoom: 14));

    final center = deliveryMapCenter(
      establishment: establishments.isEmpty ? null : establishments.first,
      zones: widget.zones,
    );

    return DsCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Carte des zones',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const StatusBadge(
                  label: 'Couverture reelle',
                  tone: StatusTone.info,
                  icon: Icons.layers_outlined,
                  compact: true,
                ),
              ],
            ),
          ),
          Expanded(
            child: Semantics(
              label: 'Carte des zones de livraison',
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
                child: FlutterMap(
                  key: const ValueKey('delivery-zones-map'),
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 12,
                    onMapReady: () => _ready = true,
                  ),
                  children: [
                    ref.watch(deliveryTileLayerProvider),
                    PolygonLayer(
                      polygons: zonePolygons(widget.visible, highlightId: selectedId),
                    ),
                    MarkerLayer(
                      markers: [
                        for (final e in establishments)
                          if (e.latitude != null && e.longitude != null)
                            restaurantMarker(LatLng(e.latitude!, e.longitude!)),
                        if (testPoint != null)
                          Marker(
                            point: testPoint,
                            width: 36,
                            height: 36,
                            child: const Icon(
                              Icons.location_pin,
                              color: AppColors.danger,
                              size: 34,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------- liste

class _ZoneCard extends ConsumerWidget {
  const _ZoneCard({required this.zone, required this.isAdmin});

  final DeliveryZone zone;
  final bool isAdmin;

  static String _shapeLabel(String kind) => switch (kind) {
        'circle' => 'Rayon',
        'isochrone' => 'Temps de trajet',
        _ => 'Dessin',
      };

  Future<void> _toggleActive(BuildContext context, WidgetRef ref) async {
    if (zone.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Desactiver ${zone.name} ?'),
          content: const Text(
            'Les clients ne pourront plus se faire livrer dans cette zone. Vous pourrez '
            'la reactiver a tout moment.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              key: const ValueKey('zone-deactivate-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Desactiver'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await ref.read(deliveryRepositoryProvider).setZoneActive(zone.id, !zone.isActive);
      ref.invalidate(deliveryZonesProvider);
      if (context.mounted) {
        _showSnack(context, zone.isActive ? 'Zone desactivee' : 'Zone reactivee');
      }
    } catch (error) {
      if (context.mounted) _showSnack(context, _errorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedZoneIdProvider) == zone.id;
    return DsCard(
      onTap: () => ref.read(selectedZoneIdProvider.notifier).state = zone.id,
      borderColor: selected ? AppColors.infoAlt : null,
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
                      tone: zone.isActive ? StatusTone.success : StatusTone.neutral,
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
                    _ZoneMetric(label: 'Minimum', value: formatMoney(zone.minOrderAmount)),
                    _ZoneMetric(label: 'ETA', value: '${zone.estimatedMinutes} min'),
                    _ZoneMetric(
                      label: 'Forme',
                      value: '${_shapeLabel(zone.shapeKind)}'
                          '${zone.areaKm2 > 0 ? ' · ${zone.areaKm2.toStringAsFixed(1)} km²' : ''}',
                    ),
                  ],
                ),
                if (zone.rules.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  for (final rule in zone.rules.take(3))
                    Text(
                      '• ${rule.label} : ${rule.describe(formatMoney)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (zone.rules.length > 3)
                    Text(
                      '+ ${zone.rules.length - 3} autre(s) regle(s)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ],
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(width: AppSpacing.sm),
            Column(
              children: [
                IconButton(
                  key: ValueKey('zone-edit-${zone.id}'),
                  tooltip: 'Modifier',
                  onPressed: () => _openEditor(context, ref, zone: zone),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  key: ValueKey('zone-toggle-${zone.id}'),
                  tooltip: zone.isActive ? 'Desactiver' : 'Reactiver',
                  onPressed: () => _toggleActive(context, ref),
                  icon: Icon(
                    zone.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline,
                  ),
                ),
              ],
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
      width: 130,
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

// --------------------------------------------------------------------------- test d'adresse

/// Saisit une adresse (suggestions via le geocodage serveur) et indique quelle zone la couvre,
/// avec les frais appliques ; place un repere sur la carte.
class _CoverageTestDialog extends ConsumerStatefulWidget {
  const _CoverageTestDialog();

  @override
  ConsumerState<_CoverageTestDialog> createState() => _CoverageTestDialogState();
}

class _CoverageTestDialogState extends ConsumerState<_CoverageTestDialog> {
  final _query = TextEditingController();
  final _subtotal = TextEditingController();
  List<AddressSuggestion> _suggestions = const [];
  bool _busy = false;
  String? _error;
  _CoverageOutcome? _outcome;

  @override
  void dispose() {
    _query.dispose();
    _subtotal.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final text = _query.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'Saisissez au moins 3 caracteres');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _outcome = null;
    });
    try {
      final results = await ref.read(deliveryRepositoryProvider).geocode(text);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        if (results.isEmpty) _error = 'Aucune adresse trouvee';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check(AddressSuggestion suggestion) async {
    final subtotal = double.tryParse(_subtotal.text.trim().replaceAll(',', '.'));
    setState(() {
      _busy = true;
      _error = null;
      _suggestions = const [];
      _query.text = suggestion.label;
    });
    ref.read(coverageTestPointProvider.notifier).state = suggestion.point;
    try {
      final result = await ref.read(deliveryRepositoryProvider).checkAddress(
            lat: suggestion.point.latitude,
            lng: suggestion.point.longitude,
            address: suggestion.label,
            subtotal: subtotal,
          );
      if (mounted) setState(() => _outcome = _CoverageOutcome.covered(result));
    } catch (error) {
      if (!mounted) return;
      if (error is AppException && error.code == 'DELIVERY_ZONE_UNREACHABLE') {
        setState(() => _outcome = const _CoverageOutcome.outside());
      } else {
        setState(() => _error = _errorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outcome = _outcome;
    return AlertDialog(
      title: const Text('Tester une adresse'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('coverage-address'),
                controller: _query,
                decoration: InputDecoration(
                  labelText: 'Adresse',
                  suffixIcon: IconButton(
                    key: const ValueKey('coverage-search'),
                    tooltip: 'Rechercher',
                    icon: const Icon(Icons.search),
                    onPressed: _busy ? null : _search,
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey('coverage-subtotal'),
                controller: _subtotal,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Panier (optionnel, pour calculer les frais reels)',
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm),
                  child: LinearProgressIndicator(),
                ),
              for (final suggestion in _suggestions)
                ListTile(
                  key: ValueKey('coverage-suggestion-${suggestion.label}'),
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(suggestion.label),
                  onTap: () => _check(suggestion),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _error!,
                    key: const ValueKey('coverage-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (outcome != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: outcome.result == null
                      ? const Text(
                          'Hors zone : aucune zone active ne couvre cette adresse.',
                          key: ValueKey('coverage-outside'),
                          style: TextStyle(fontWeight: FontWeight.w700),
                        )
                      : _CoverageResultView(result: outcome.result!),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _CoverageOutcome {
  const _CoverageOutcome.outside() : result = null;
  const _CoverageOutcome.covered(DeliveryCheckResult this.result);

  final DeliveryCheckResult? result;
}

class _CoverageResultView extends StatelessWidget {
  const _CoverageResultView({required this.result});

  final DeliveryCheckResult result;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      'Zone : ${result.name}',
      if (result.freeDelivery)
        'Livraison offerte${result.appliedLabel == null ? '' : ' (${result.appliedLabel})'}'
      else
        'Frais : ${formatMoney(result.fee)}'
            '${result.baseFee != null && result.baseFee != result.fee ? ' (tarif de base ${formatMoney(result.baseFee!)})' : ''}',
      'Delai estime : ${result.estimatedMinutes} min',
      if (result.minOrderAmount > 0)
        'Minimum de commande : ${formatMoney(result.minOrderAmount)}'
            '${result.minOrderMet == false ? ' (non atteint)' : ''}',
      if (!result.freeDelivery && (result.remainingForFree ?? 0) > 0)
        'Plus que ${formatMoney(result.remainingForFree!)} pour la livraison offerte',
    ];
    return Column(
      key: const ValueKey('coverage-result'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Text(line),
          ),
      ],
    );
  }
}

void _showSnack(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _errorMessage(Object error) {
  if (error is AppException) return error.message;
  return error.toString().replaceFirst('Exception: ', '');
}

import 'dart:math' as math;

import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/design_system/tokens/app_spacing.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/delivery/presentation/delivery_map.dart';
import 'package:app_admin_staff/features/delivery/presentation/delivery_rules_editor.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

enum ZoneEditMode { draw, circle, isochrone }

/// Creation / modification d'une zone de livraison, sur une vraie carte. L'administrateur ne
/// saisit jamais de coordonnees : il dessine le contour, choisit un rayon autour du restaurant
/// ou un temps de trajet. Le serveur calcule et valide le contour ; l'apercu affiche son
/// resultat avant l'enregistrement.
class DeliveryZoneEditorPage extends ConsumerStatefulWidget {
  const DeliveryZoneEditorPage({
    required this.establishments,
    this.zone,
    super.key,
  });

  final DeliveryZone? zone;
  final List<Establishment> establishments;

  @override
  ConsumerState<DeliveryZoneEditorPage> createState() =>
      _DeliveryZoneEditorPageState();
}

class _DeliveryZoneEditorPageState
    extends ConsumerState<DeliveryZoneEditorPage> {
  static const _minRadiusKm = 0.3;
  static const _maxRadiusKm = 20.0;
  static const _minIsoMinutes = 3.0;
  static const _maxIsoMinutes = 45.0;

  final _mapController = MapController();
  late final TextEditingController _name;
  late final TextEditingController _fee;
  late final TextEditingController _minOrder;
  late final TextEditingController _minutes;

  ZoneEditMode _mode = ZoneEditMode.circle;
  int? _establishmentId;
  bool _isActive = true;
  List<DeliveryZoneRule> _rules = const [];

  LatLng? _center;
  double _radiusKm = 3;
  double _isoMinutes = 15;
  List<LatLng> _drawn = const [];

  /// Contour calcule par le serveur pour le cercle / temps de trajet courant.
  List<LatLng> _preview = const [];
  double? _previewAreaKm2;
  bool _busy = false;
  bool _mapReady = false;
  String? _message;
  bool _messageIsError = false;

  bool get _editing => widget.zone != null;

  Establishment? get _establishment {
    for (final e in widget.establishments) {
      if (e.id == _establishmentId) return e;
    }
    return null;
  }

  LatLng? get _establishmentPoint {
    final e = _establishment;
    return e?.latitude != null && e?.longitude != null
        ? LatLng(e!.latitude!, e.longitude!)
        : null;
  }

  @override
  void initState() {
    super.initState();
    final zone = widget.zone;
    _name = TextEditingController(text: zone?.name ?? '');
    _fee = TextEditingController(text: zone == null ? '3' : _plain(zone.fee));
    _minOrder = TextEditingController(
      text: zone == null ? '0' : _plain(zone.minOrderAmount),
    );
    _minutes = TextEditingController(
      text: (zone?.estimatedMinutes ?? 30).toString(),
    );
    _isActive = zone?.isActive ?? true;
    _rules = [...?zone?.rules];

    final activeEstablishments = widget.establishments
        .where((e) => e.isActive)
        .toList();
    _establishmentId =
        zone?.establishmentId ??
        (activeEstablishments.isNotEmpty
            ? activeEstablishments.first.id
            : null);

    if (zone != null) {
      final shape = ZoneShape.fromZone(zone);
      switch (shape) {
        case CircleZoneShape():
          _mode = ZoneEditMode.circle;
          _center = shape.center;
          _radiusKm = (shape.radiusMeters / 1000).clamp(
            _minRadiusKm,
            _maxRadiusKm,
          );
        case IsochroneZoneShape():
          _mode = ZoneEditMode.isochrone;
          _center = shape.center;
          _isoMinutes = shape.minutes.toDouble().clamp(
            _minIsoMinutes,
            _maxIsoMinutes,
          );
        case PolygonZoneShape():
          _mode = ZoneEditMode.draw;
          _drawn = [...shape.points];
        case null:
          break;
      }
      _preview = zone.ring;
      _previewAreaKm2 = zone.areaKm2;
    } else {
      _center = _establishmentPoint;
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _name.dispose();
    _fee.dispose();
    _minOrder.dispose();
    _minutes.dispose();
    super.dispose();
  }

  static String _plain(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  LatLng get _initialCenter {
    final zones = ref.read(deliveryZonesProvider).valueOrNull ?? const [];
    return _center ??
        boundsCenter(_drawn) ??
        boundsCenter(_preview) ??
        deliveryMapCenter(establishment: _establishment, zones: zones);
  }

  void _moveMap(LatLng point, {double? zoom}) {
    if (!_mapReady) return;
    _mapController.move(point, zoom ?? _mapController.camera.zoom);
  }

  void _setMessage(String? text, {bool error = false}) {
    setState(() {
      _message = text;
      _messageIsError = error;
    });
  }

  String _errorText(Object error) => error is AppException
      ? error.message
      : 'Operation impossible, reessayez.';

  // ------------------------------------------------------------------ interactions carte

  void _onMapTap(LatLng point) {
    switch (_mode) {
      case ZoneEditMode.draw:
        setState(() {
          _drawn = [..._drawn, point];
          _message = null;
        });
      case ZoneEditMode.circle:
      case ZoneEditMode.isochrone:
        setState(() {
          _center = point;
          _preview = const [];
          _previewAreaKm2 = null;
          _message = null;
        });
        _requestPreview();
    }
  }

  void _movePoint(int index, Offset screenDelta) {
    final camera = _mapController.camera;
    final projected = camera.project(_drawn[index]);
    final moved = camera.unproject(
      math.Point(projected.x + screenDelta.dx, projected.y + screenDelta.dy),
    );
    setState(() {
      _drawn = [..._drawn]..[index] = moved;
    });
  }

  void _changeMode(ZoneEditMode mode) {
    setState(() {
      _mode = mode;
      _message = null;
      _preview = mode == ZoneEditMode.draw ? const [] : _preview;
      if (mode != ZoneEditMode.draw && _center == null) {
        _center = _establishmentPoint;
      }
    });
    if (mode != ZoneEditMode.draw && _center != null) _requestPreview();
  }

  void _onEstablishmentChanged(int? id) {
    final previousPoint = _establishmentPoint;
    setState(() => _establishmentId = id);
    final point = _establishmentPoint;
    if (point != null && (_center == null || _center == previousPoint)) {
      setState(() {
        _center = point;
        _preview = const [];
      });
      _moveMap(point, zoom: 13);
      if (_mode != ZoneEditMode.draw) _requestPreview();
    }
  }

  // ------------------------------------------------------------------ apercu / enregistrement

  ZoneShape? _currentShape() {
    switch (_mode) {
      case ZoneEditMode.draw:
        return _drawn.length >= 3 ? PolygonZoneShape(_drawn) : null;
      case ZoneEditMode.circle:
        final center = _center;
        return center == null
            ? null
            : CircleZoneShape(center, _radiusKm * 1000);
      case ZoneEditMode.isochrone:
        final center = _center;
        return center == null
            ? null
            : IsochroneZoneShape(center, _isoMinutes.round());
    }
  }

  Future<void> _requestPreview() async {
    final shape = _currentShape();
    if (shape == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final preview = await ref
          .read(deliveryRepositoryProvider)
          .previewShape(shape);
      if (!mounted) return;
      setState(() {
        _preview = preview.points;
        _previewAreaKm2 = preview.areaKm2;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _preview = const [];
        _previewAreaKm2 = null;
      });
      _setMessage(_errorText(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setRestaurantLocation() async {
    final id = _establishmentId;
    final point = _center ?? (_drawn.isNotEmpty ? _drawn.first : null);
    if (id == null || point == null) return;
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .setEstablishmentLocation(id, point);
      ref.invalidate(availableEstablishmentsProvider);
      if (!mounted) return;
      _setMessage('Position du restaurant enregistree');
    } catch (error) {
      if (mounted) _setMessage(_errorText(error), error: true);
    }
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Nom obligatoire';
    final fee = _number(_fee.text);
    final minOrder = _number(_minOrder.text);
    if (fee == null || fee < 0 || minOrder == null || minOrder < 0) {
      return 'Montants invalides';
    }
    final minutes = int.tryParse(_minutes.text.trim());
    if (minutes == null || minutes < 1 || minutes > 240) {
      return 'Delai invalide (1 a 240 minutes)';
    }
    if (_currentShape() == null) {
      return switch (_mode) {
        ZoneEditMode.draw => 'Placez au moins 3 points sur la carte',
        _ => 'Touchez la carte pour choisir le centre de la zone',
      };
    }
    return null;
  }

  double? _number(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      _setMessage(problem, error: true);
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final draft = DeliveryZoneDraft(
        name: _name.text.trim(),
        fee: _number(_fee.text)!,
        minOrderAmount: _number(_minOrder.text)!,
        estimatedMinutes: int.parse(_minutes.text.trim()),
        isActive: _isActive,
        establishmentId: _establishmentId,
        shape: _currentShape()!,
        rules: _rules,
      );
      final repository = ref.read(deliveryRepositoryProvider);
      final saved = widget.zone == null
          ? await repository.createZone(draft)
          : await repository.updateZone(widget.zone!.id, draft);
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _setMessage(_errorText(error), error: true);
      }
    }
  }

  // ------------------------------------------------------------------ affichage

  List<LatLng> get _shownPolygon =>
      _mode == ZoneEditMode.draw ? _drawn : _preview;

  Widget _buildMap(List<DeliveryZone> otherZones) {
    final restaurant = _establishmentPoint;
    final polygon = _shownPolygon;
    return FlutterMap(
      key: const ValueKey('zone-map'),
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: 13,
        onTap: (_, point) => _onMapTap(point),
        onMapReady: () => _mapReady = true,
      ),
      children: [
        ref.watch(deliveryTileLayerProvider),
        // Les autres zones, en retrait, pour voir comment la nouvelle s'y articule.
        PolygonLayer(polygons: zonePolygons(otherZones)),
        if (polygon.length >= 3)
          PolygonLayer(
            polygons: [
              Polygon(
                points: polygon,
                color: AppColors.accent.withValues(alpha: 0.28),
                borderColor: AppColors.accent,
                borderStrokeWidth: 3,
              ),
            ],
          )
        else if (_mode == ZoneEditMode.draw && polygon.length == 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: polygon,
                color: AppColors.accent,
                strokeWidth: 3,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (restaurant != null) restaurantMarker(restaurant),
            if (_mode != ZoneEditMode.draw && _center != null)
              Marker(
                point: _center!,
                width: 36,
                height: 36,
                child: const Icon(
                  Icons.my_location,
                  color: AppColors.accent,
                  size: 30,
                ),
              ),
            if (_mode == ZoneEditMode.draw)
              for (var i = 0; i < _drawn.length; i++)
                Marker(
                  point: _drawn[i],
                  width: 36,
                  height: 36,
                  child: GestureDetector(
                    key: ValueKey('zone-point-$i'),
                    onPanUpdate: (details) => _movePoint(i, details.delta),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accent, width: 3),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    final establishments = widget.establishments
        .where((e) => e.isActive)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        TextField(
          key: const ValueKey('zone-name-field'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nom de la zone'),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (establishments.length > 1)
          DropdownButtonFormField<int>(
            key: const ValueKey('zone-establishment'),
            initialValue: _establishmentId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Etablissement qui livre',
            ),
            items: [
              for (final e in establishments)
                DropdownMenuItem(value: e.id, child: Text(e.name)),
            ],
            onChanged: _onEstablishmentChanged,
          ),
        if (establishments.length > 1) const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('zone-fee-field'),
                controller: _fee,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Frais de livraison',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                key: const ValueKey('zone-min-field'),
                controller: _minOrder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minimum de commande',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                key: const ValueKey('zone-minutes-field'),
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Minutes estimees',
                ),
              ),
            ),
          ],
        ),
        SwitchListTile(
          key: const ValueKey('zone-active-switch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Zone active'),
          subtitle: const Text(
            'Une zone inactive n\'est plus proposee aux clients.',
          ),
          value: _isActive,
          onChanged: (value) => setState(() => _isActive = value),
        ),
        const Divider(),
        Text('Forme de la zone', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<ZoneEditMode>(
          key: const ValueKey('zone-mode'),
          segments: const [
            ButtonSegment(
              value: ZoneEditMode.circle,
              label: Text('Rayon'),
              icon: Icon(Icons.radio_button_unchecked),
            ),
            ButtonSegment(
              value: ZoneEditMode.isochrone,
              label: Text('Temps de trajet'),
              icon: Icon(Icons.timer_outlined),
            ),
            ButtonSegment(
              value: ZoneEditMode.draw,
              label: Text('Dessiner'),
              icon: Icon(Icons.edit_location_alt_outlined),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: (value) => _changeMode(value.first),
        ),
        const SizedBox(height: AppSpacing.sm),
        ..._buildModeControls(context),
        if (_previewAreaKm2 != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Surface couverte : ${_previewAreaKm2!.toStringAsFixed(1)} km²',
              key: const ValueKey('zone-area'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _message!,
              key: const ValueKey('zone-message'),
              style: TextStyle(
                color: _messageIsError
                    ? Theme.of(context).colorScheme.error
                    : AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const Divider(),
        DeliveryRulesEditor(
          rules: _rules,
          onChanged: (next) => setState(() => _rules = next),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const ValueKey('zone-save-button'),
          onPressed: _busy ? null : _save,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_editing ? 'Enregistrer' : 'Creer la zone'),
        ),
      ],
    );
  }

  List<Widget> _buildModeControls(BuildContext context) {
    final hint = Theme.of(context).textTheme.bodySmall;
    switch (_mode) {
      case ZoneEditMode.draw:
        return [
          Text(
            'Touchez la carte pour poser les points du contour (3 minimum). '
            'Faites glisser un point pour le deplacer.',
            style: hint,
          ),
          Wrap(
            spacing: AppSpacing.xs,
            children: [
              TextButton.icon(
                key: const ValueKey('zone-undo-point'),
                onPressed: _drawn.isEmpty
                    ? null
                    : () => setState(
                        () => _drawn = _drawn.sublist(0, _drawn.length - 1),
                      ),
                icon: const Icon(Icons.undo),
                label: const Text('Annuler le dernier point'),
              ),
              TextButton.icon(
                key: const ValueKey('zone-clear-points'),
                onPressed: _drawn.isEmpty
                    ? null
                    : () => setState(() => _drawn = const []),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Effacer'),
              ),
              Text('${_drawn.length} point(s)', style: hint),
            ],
          ),
        ];
      case ZoneEditMode.circle:
        return [
          Text(
            'Touchez la carte pour placer le centre (par defaut : le restaurant), '
            'puis reglez le rayon.',
            style: hint,
          ),
          Slider(
            key: const ValueKey('zone-radius'),
            value: _radiusKm,
            min: _minRadiusKm,
            max: _maxRadiusKm,
            divisions: 98,
            label: '${_radiusKm.toStringAsFixed(1)} km',
            onChanged: (value) => setState(() => _radiusKm = value),
            onChangeEnd: (_) => _requestPreview(),
          ),
          Text('Rayon : ${_radiusKm.toStringAsFixed(1)} km', style: hint),
        ];
      case ZoneEditMode.isochrone:
        return [
          Text(
            'La zone couvre tout ce qui est atteignable en voiture en ce temps depuis '
            'le centre (calcul via Mapbox).',
            style: hint,
          ),
          Slider(
            key: const ValueKey('zone-isochrone-minutes'),
            value: _isoMinutes,
            min: _minIsoMinutes,
            max: _maxIsoMinutes,
            divisions: (_maxIsoMinutes - _minIsoMinutes).round(),
            label: '${_isoMinutes.round()} min',
            onChanged: (value) => setState(() => _isoMinutes = value),
            onChangeEnd: (_) => _requestPreview(),
          ),
          Text('Temps de trajet : ${_isoMinutes.round()} min', style: hint),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final otherZones =
        (ref.watch(deliveryZonesProvider).valueOrNull ?? const [])
            .where((z) => z.id != widget.zone?.id)
            .toList();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final map = Stack(
      children: [
        _buildMap(otherZones),
        if (_busy)
          const Positioned(
            top: 8,
            right: 8,
            child: CircularProgressIndicator(),
          ),
        if (_establishmentPoint == null && _establishmentId != null)
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Material(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Position du restaurant inconnue : touchez la carte puis '
                        'definissez-la.',
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('zone-set-restaurant-location'),
                      onPressed: _center == null && _drawn.isEmpty
                          ? null
                          : _setRestaurantLocation,
                      child: const Text('Definir ici'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? 'Modifier ${widget.zone!.name}' : 'Nouvelle zone',
        ),
      ),
      body: wide
          ? Row(
              children: [
                SizedBox(width: 460, child: _buildForm(context)),
                Expanded(child: map),
              ],
            )
          : Column(
              children: [
                SizedBox(height: 280, child: map),
                Expanded(child: _buildForm(context)),
              ],
            ),
    );
  }
}

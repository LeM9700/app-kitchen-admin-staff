import 'package:app_admin_staff/core/config/env.dart';
import 'package:app_admin_staff/design_system/tokens/app_colors.dart';
import 'package:app_admin_staff/features/delivery/data/delivery_repository.dart';
import 'package:app_admin_staff/features/establishments/data/establishment_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

/// Centre de repli quand ni l'etablissement ni aucune zone n'ont de position connue.
const fallbackDeliveryCenter = LatLng(48.8566, 2.3522);

/// Tuiles : Mapbox si un jeton public est fourni (`--dart-define=MAPBOX_PUBLIC_TOKEN=pk...`),
/// OpenStreetMap sinon (developpement). Surchargeable dans les tests.
final deliveryTileLayerProvider = Provider<Widget>((ref) {
  const token = Env.mapboxPublicToken;
  return TileLayer(
    urlTemplate: token.isEmpty
        ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
        : 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x'
              '?access_token=$token',
    userAgentPackageName: 'com.opizza.app_admin_staff',
  );
});

/// Centre de la boite englobante d'un ensemble de points, ou `null`.
LatLng? boundsCenter(Iterable<LatLng> points) {
  if (points.isEmpty) return null;
  var minLat = 90.0;
  var maxLat = -90.0;
  var minLng = 180.0;
  var maxLng = -180.0;
  for (final p in points) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }
  return LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
}

/// Position de l'etablissement, sinon centre de ses zones, sinon centre de toutes les zones,
/// sinon [fallbackDeliveryCenter].
LatLng deliveryMapCenter({
  Establishment? establishment,
  required List<DeliveryZone> zones,
}) {
  if (establishment?.latitude != null && establishment?.longitude != null) {
    return LatLng(establishment!.latitude!, establishment.longitude!);
  }
  final own = zones.where(
    (z) => establishment == null || z.establishmentId == establishment.id,
  );
  return boundsCenter(own.expand((z) => z.ring)) ??
      boundsCenter(zones.expand((z) => z.ring)) ??
      fallbackDeliveryCenter;
}

Color zoneColor(DeliveryZone zone) =>
    zone.isActive ? AppColors.infoAlt : AppColors.neutral;

/// Polygones des zones pour une `PolygonLayer`. La zone [highlightId] est mise en avant.
List<Polygon> zonePolygons(List<DeliveryZone> zones, {int? highlightId}) {
  return [
    for (final zone in zones)
      if (zone.ring.length >= 3)
        Polygon(
          points: zone.ring,
          color: zoneColor(zone).withValues(
            alpha: highlightId == zone.id
                ? 0.35
                : (zone.isActive ? 0.18 : 0.08),
          ),
          borderColor: zoneColor(zone),
          borderStrokeWidth: highlightId == zone.id ? 3 : 1.5,
        ),
  ];
}

/// Marqueur du restaurant.
Marker restaurantMarker(LatLng point) {
  return Marker(
    point: point,
    width: 40,
    height: 40,
    child: const Icon(Icons.storefront, color: AppColors.accent, size: 32),
  );
}

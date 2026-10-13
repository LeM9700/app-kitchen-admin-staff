import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

final deliveryRepositoryProvider = Provider<DeliveryRepository>((ref) {
  return DeliveryRepository(ref.watch(apiClientProvider));
});

/// Toutes les zones (actives ou non) avec contour et regles : lecture reservee au personnel.
final deliveryZonesProvider = FutureProvider.autoDispose<List<DeliveryZone>>((
  ref,
) {
  return ref.watch(deliveryRepositoryProvider).listZones();
});

final deliverySettingsProvider = FutureProvider.autoDispose<DeliverySettings>((
  ref,
) {
  return ref.watch(deliveryRepositoryProvider).getSettings();
});

enum DeliveryZoneStatusFilter { all, active, inactive }

final deliveryZoneStatusFilterProvider =
    StateProvider<DeliveryZoneStatusFilter>((ref) {
      return DeliveryZoneStatusFilter.all;
    });

class DeliveryRepository {
  const DeliveryRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<DeliveryZone>> listZones() async {
    final response = await _apiClient.get(ApiEndpoints.deliveryZonesManage);
    return _zonesFromData(response.data);
  }

  Future<DeliveryZone> createZone(DeliveryZoneDraft draft) async {
    final response = await _apiClient.post(
      ApiEndpoints.deliveryZones,
      data: draft.toJson(),
    );
    return DeliveryZone.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DeliveryZone> updateZone(int zoneId, DeliveryZoneDraft draft) async {
    final response = await _apiClient.put(
      ApiEndpoints.deliveryZone(zoneId),
      data: draft.toJson(),
    );
    return DeliveryZone.fromJson(response.data as Map<String, dynamic>);
  }

  /// Une zone n'est jamais supprimee (des commandes passees y font reference) : on la
  /// desactive, et on peut la reactiver.
  Future<DeliveryZone> setZoneActive(int zoneId, bool isActive) async {
    final response = await _apiClient.patch(
      ApiEndpoints.deliveryZone(zoneId),
      data: {'is_active': isActive},
    );
    return DeliveryZone.fromJson(response.data as Map<String, dynamic>);
  }

  /// Contour calcule par le serveur pour une forme (cercle, temps de trajet, dessin), sans
  /// rien enregistrer.
  Future<ZonePreview> previewShape(ZoneShape shape) async {
    final response = await _apiClient.post(
      ApiEndpoints.deliveryZonePreview,
      data: {'shape': shape.toJson()},
    );
    return ZonePreview.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DeliveryCheckResult> checkAddress({
    required double lat,
    required double lng,
    String? address,
    double? subtotal,
    int? establishmentId,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.deliveryCheck,
      data: {
        'lat': lat,
        'lng': lng,
        if (address != null && address.trim().isNotEmpty)
          'address': address.trim(),
        if (subtotal != null) 'subtotal': subtotal,
        if (establishmentId != null) 'establishment_id': establishmentId,
      },
    );
    return DeliveryCheckResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<AddressSuggestion>> geocode(String query, {LatLng? near}) async {
    final response = await _apiClient.get(
      ApiEndpoints.deliveryGeocode,
      queryParameters: {
        'q': query,
        if (near != null) ...{'lat': near.latitude, 'lng': near.longitude},
        'language': 'fr',
        'limit': 5,
      },
    );
    return (response.data as List? ?? const [])
        .map(AddressSuggestion.tryParse)
        .whereType<AddressSuggestion>()
        .toList();
  }

  Future<AddressSuggestion?> reverseGeocode(LatLng point) async {
    final response = await _apiClient.get(
      ApiEndpoints.deliveryReverseGeocode,
      queryParameters: {'lat': point.latitude, 'lng': point.longitude},
    );
    return AddressSuggestion.tryParse(response.data);
  }

  Future<DeliverySettings> getSettings() async {
    final response = await _apiClient.get(ApiEndpoints.deliverySettings);
    return DeliverySettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<DeliverySettings> setDeliveryEnabled({
    required bool enabled,
    required int expectedVersion,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.deliverySettings,
      data: {'internal_enabled': enabled, 'expected_version': expectedVersion},
    );
    return DeliverySettings.fromJson(response.data as Map<String, dynamic>);
  }

  /// Preuve de remise par code et regles d'echec (administrateur). Les champs `null` ne sont pas
  /// envoyes : le serveur les laisse inchanges.
  Future<DeliverySettings> updateProofSettings({
    required bool internalEnabled,
    required int expectedVersion,
    bool? proofRequired,
    int? failureMinWaitMinutes,
    int? failureMinCallAttempts,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.deliverySettings,
      data: {
        'internal_enabled': internalEnabled,
        'expected_version': expectedVersion,
        if (proofRequired != null) 'delivery_proof_required': proofRequired,
        if (failureMinWaitMinutes != null)
          'failure_min_wait_minutes': failureMinWaitMinutes,
        if (failureMinCallAttempts != null)
          'failure_min_call_attempts': failureMinCallAttempts,
      },
    );
    return DeliverySettings.fromJson(response.data as Map<String, dynamic>);
  }

  /// Active ou coupe le dispatch par livreurs. L'API exige `internal_enabled` avec chaque
  /// ecriture : on renvoie sa valeur courante pour ne pas la modifier.
  Future<DeliverySettings> setDriverDispatch({
    required bool enabled,
    required bool internalEnabled,
    required int expectedVersion,
  }) async {
    final response = await _apiClient.put(
      ApiEndpoints.deliverySettings,
      data: {
        'internal_enabled': internalEnabled,
        'driver_dispatch_enabled': enabled,
        'expected_version': expectedVersion,
      },
    );
    return DeliverySettings.fromJson(response.data as Map<String, dynamic>);
  }

  /// Position de l'etablissement : centre des cartes et point de depart des zones.
  Future<void> setEstablishmentLocation(
    int establishmentId,
    LatLng point,
  ) async {
    await _apiClient.put(
      ApiEndpoints.deliveryEstablishmentLocation(establishmentId),
      data: {'latitude': point.latitude, 'longitude': point.longitude},
    );
  }

  List<DeliveryZone> _zonesFromData(Object? data) {
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((value) => DeliveryZone.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }
}

// --------------------------------------------------------------------------- reglages

class DeliverySettings {
  const DeliverySettings({
    required this.internalEnabled,
    required this.version,
    this.driverDispatchEnabled = false,
    this.deliveryProofRequired = false,
    this.failureMinWaitMinutes = 5,
    this.failureMinCallAttempts = 1,
  });

  /// Le livreur doit saisir le code a 4 chiffres du client pour livrer.
  final bool deliveryProofRequired;

  /// « Client absent / injoignable » : attente depuis l'arrivee et appels minimaux.
  final int failureMinWaitMinutes;
  final int failureMinCallAttempts;

  /// Dispatch par livreurs : `ready -> out_for_delivery` exige un livreur assigne.
  final bool driverDispatchEnabled;

  /// Interrupteur general de la livraison (coupe aussi la proposition cote client).
  final bool internalEnabled;

  /// Version pour la concurrence optimiste : une ecriture sur une version perimee est refusee.
  final int version;

  factory DeliverySettings.fromJson(Map<String, dynamic> json) {
    return DeliverySettings(
      internalEnabled: readBool(json['internal_enabled'], fallback: true),
      driverDispatchEnabled: readBool(json['driver_dispatch_enabled']),
      deliveryProofRequired: readBool(json['delivery_proof_required']),
      failureMinWaitMinutes: readInt(
        json['failure_min_wait_minutes'],
        fallback: 5,
      ),
      failureMinCallAttempts: readInt(
        json['failure_min_call_attempts'],
        fallback: 1,
      ),
      version: readInt(json['version']),
    );
  }
}

// --------------------------------------------------------------------------- regles

/// Regle de tarification d'une zone : tarif different (`fee`) ou livraison offerte (`free`),
/// limitee a certains jours, horaires, dates ou a partir d'un montant de panier.
class DeliveryZoneRule {
  const DeliveryZoneRule({
    required this.label,
    required this.kind,
    this.id,
    this.fee,
    this.minSubtotal,
    this.daysOfWeek = const [],
    this.startTime,
    this.endTime,
    this.startsOn,
    this.endsOn,
    this.priority = 0,
    this.isActive = true,
  });

  static const kindFee = 'fee';
  static const kindFree = 'free';

  final int? id;
  final String label;
  final String kind;
  final double? fee;
  final double? minSubtotal;

  /// 0 = lundi ... 6 = dimanche. Vide = tous les jours.
  final List<int> daysOfWeek;

  /// `HH:mm` (heure locale de l'etablissement). Les deux ou aucun.
  final String? startTime;
  final String? endTime;

  /// `yyyy-MM-dd`.
  final String? startsOn;
  final String? endsOn;
  final int priority;
  final bool isActive;

  bool get isFree => kind == kindFree;

  DeliveryZoneRule copyWith({
    String? label,
    String? kind,
    double? fee,
    bool clearFee = false,
    double? minSubtotal,
    bool clearMinSubtotal = false,
    List<int>? daysOfWeek,
    String? startTime,
    String? endTime,
    bool clearTimes = false,
    String? startsOn,
    String? endsOn,
    bool clearDates = false,
    int? priority,
    bool? isActive,
  }) {
    return DeliveryZoneRule(
      id: id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      fee: clearFee ? null : (fee ?? this.fee),
      minSubtotal: clearMinSubtotal ? null : (minSubtotal ?? this.minSubtotal),
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      startTime: clearTimes ? null : (startTime ?? this.startTime),
      endTime: clearTimes ? null : (endTime ?? this.endTime),
      startsOn: clearDates ? null : (startsOn ?? this.startsOn),
      endsOn: clearDates ? null : (endsOn ?? this.endsOn),
      priority: priority ?? this.priority,
      isActive: isActive ?? this.isActive,
    );
  }

  factory DeliveryZoneRule.fromJson(Map<String, dynamic> json) {
    return DeliveryZoneRule(
      id: readNullableInt(json['id']),
      label: json['label']?.toString() ?? '',
      kind: json['kind']?.toString() ?? kindFree,
      fee: json['fee'] == null ? null : readDouble(json['fee']),
      minSubtotal: json['min_subtotal'] == null
          ? null
          : readDouble(json['min_subtotal']),
      daysOfWeek: (json['days_of_week'] as List? ?? const [])
          .map(readInt)
          .toList(),
      startTime: _hhmm(json['start_time']),
      endTime: _hhmm(json['end_time']),
      startsOn: json['starts_on']?.toString(),
      endsOn: json['ends_on']?.toString(),
      priority: readInt(json['priority']),
      isActive: readBool(json['is_active'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label.trim(),
      'kind': kind,
      if (kind == kindFee) 'fee': fee,
      if (minSubtotal != null) 'min_subtotal': minSubtotal,
      if (daysOfWeek.isNotEmpty) 'days_of_week': daysOfWeek,
      if (startTime != null && endTime != null) ...{
        'start_time': startTime,
        'end_time': endTime,
      },
      if (startsOn != null) 'starts_on': startsOn,
      if (endsOn != null) 'ends_on': endsOn,
      'priority': priority,
      'is_active': isActive,
    };
  }

  /// Libelle lisible : « Offerte des 25 EUR, vendredi, 19:00-23:00 ».
  String describe(String Function(double) money) {
    const dayNames = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    final parts = <String>[
      if (isFree) 'Livraison offerte' else 'Tarif ${money(fee ?? 0)}',
      if (minSubtotal != null) 'des ${money(minSubtotal!)}',
      if (daysOfWeek.isNotEmpty && daysOfWeek.length < 7)
        daysOfWeek.map((d) => dayNames[d.clamp(0, 6)]).join(' '),
      if (startTime != null && endTime != null) '$startTime-$endTime',
      if (startsOn != null || endsOn != null)
        '${startsOn ?? '...'} → ${endsOn ?? '...'}',
    ];
    return parts.join(' · ');
  }
}

String? _hhmm(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return text.length >= 5 ? text.substring(0, 5) : text;
}

// --------------------------------------------------------------------------- formes

/// Mode de saisie d'une zone. Le serveur construit et valide le contour : l'admin ne tape
/// jamais de GeoJSON.
sealed class ZoneShape {
  const ZoneShape();

  String get kind;

  Map<String, dynamic> toJson();

  static ZoneShape? fromZone(DeliveryZone zone) {
    final params = zone.shapeParams ?? const <String, dynamic>{};
    final lat = params['center_lat'];
    final lng = params['center_lng'];
    switch (zone.shapeKind) {
      case 'circle':
        if (lat is num && lng is num && params['radius_m'] is num) {
          return CircleZoneShape(
            LatLng(lat.toDouble(), lng.toDouble()),
            (params['radius_m'] as num).toDouble(),
          );
        }
      case 'isochrone':
        if (lat is num && lng is num && params['minutes'] is num) {
          return IsochroneZoneShape(
            LatLng(lat.toDouble(), lng.toDouble()),
            (params['minutes'] as num).toInt(),
          );
        }
    }
    final ring = zone.ring;
    return ring.length >= 3 ? PolygonZoneShape(ring) : null;
  }
}

class PolygonZoneShape extends ZoneShape {
  const PolygonZoneShape(this.points);

  /// Sommets (sans repeter le premier a la fin ; le serveur ferme l'anneau).
  final List<LatLng> points;

  @override
  String get kind => 'polygon';

  @override
  Map<String, dynamic> toJson() {
    return {
      'kind': 'polygon',
      'polygon': {
        'type': 'Polygon',
        'coordinates': [
          [
            for (final p in points) [p.longitude, p.latitude],
          ],
        ],
      },
    };
  }
}

class CircleZoneShape extends ZoneShape {
  const CircleZoneShape(this.center, this.radiusMeters);

  final LatLng center;
  final double radiusMeters;

  @override
  String get kind => 'circle';

  @override
  Map<String, dynamic> toJson() {
    return {
      'kind': 'circle',
      'center_lat': center.latitude,
      'center_lng': center.longitude,
      'radius_m': radiusMeters,
    };
  }
}

class IsochroneZoneShape extends ZoneShape {
  const IsochroneZoneShape(this.center, this.minutes);

  final LatLng center;
  final int minutes;

  @override
  String get kind => 'isochrone';

  @override
  Map<String, dynamic> toJson() {
    return {
      'kind': 'isochrone',
      'center_lat': center.latitude,
      'center_lng': center.longitude,
      'minutes': minutes,
    };
  }
}

class ZonePreview {
  const ZonePreview({required this.points, required this.areaKm2});

  final List<LatLng> points;
  final double areaKm2;

  factory ZonePreview.fromJson(Map<String, dynamic> json) {
    return ZonePreview(
      points: _ringFromPolygon(json['polygon']),
      areaKm2: readDouble(json['area_km2']),
    );
  }
}

List<LatLng> _ringFromPolygon(Object? polygon) {
  if (polygon is! Map) return const [];
  final rings = polygon['coordinates'];
  if (rings is! List || rings.isEmpty || rings.first is! List) return const [];
  final ring = <LatLng>[];
  for (final point in rings.first as List) {
    if (point is List &&
        point.length >= 2 &&
        point[0] is num &&
        point[1] is num) {
      ring.add(
        LatLng((point[1] as num).toDouble(), (point[0] as num).toDouble()),
      );
    }
  }
  // Retire le point de fermeture : l'affichage et l'edition travaillent sur les sommets.
  if (ring.length > 1 && ring.first == ring.last) ring.removeLast();
  return ring;
}

// --------------------------------------------------------------------------- zones

class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.name,
    required this.fee,
    required this.minOrderAmount,
    required this.estimatedMinutes,
    required this.isActive,
    this.establishmentId,
    this.polygon,
    this.shapeKind = 'polygon',
    this.shapeParams,
    this.areaKm2 = 0,
    this.rules = const [],
  });

  final int id;
  final String name;
  final int? establishmentId;
  final double fee;
  final double minOrderAmount;
  final int estimatedMinutes;
  final bool isActive;
  final Map<String, dynamic>? polygon;
  final String shapeKind;
  final Map<String, dynamic>? shapeParams;
  final double areaKm2;
  final List<DeliveryZoneRule> rules;

  bool get hasGeoJson => polygon != null && polygon!.isNotEmpty;

  /// Sommets du contour (sans point de fermeture).
  List<LatLng> get ring => _ringFromPolygon(polygon);

  factory DeliveryZone.fromJson(Map<String, dynamic> json) {
    return DeliveryZone(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      establishmentId: readNullableInt(json['establishment_id']),
      fee: readDouble(json['fee']),
      minOrderAmount: readDouble(json['min_order_amount']),
      estimatedMinutes: readInt(json['estimated_minutes']),
      isActive: readBool(json['is_active'], fallback: true),
      polygon: json['polygon'] is Map
          ? Map<String, dynamic>.from(json['polygon'] as Map)
          : null,
      shapeKind: json['shape_kind']?.toString() ?? 'polygon',
      shapeParams: json['shape_params'] is Map
          ? Map<String, dynamic>.from(json['shape_params'] as Map)
          : null,
      areaKm2: json['area_km2'] == null ? 0 : readDouble(json['area_km2']),
      rules: (json['rules'] as List? ?? const [])
          .whereType<Map>()
          .map((r) => DeliveryZoneRule.fromJson(Map<String, dynamic>.from(r)))
          .toList(),
    );
  }
}

class DeliveryZoneDraft {
  const DeliveryZoneDraft({
    required this.name,
    required this.fee,
    required this.minOrderAmount,
    required this.estimatedMinutes,
    required this.shape,
    this.establishmentId,
    this.isActive = true,
    this.rules,
  });

  final String name;
  final double fee;
  final double minOrderAmount;
  final int estimatedMinutes;
  final ZoneShape shape;
  final int? establishmentId;
  final bool isActive;

  /// Liste complete des regles ; `null` = ne pas toucher aux regles existantes.
  final List<DeliveryZoneRule>? rules;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'fee': fee,
      'min_order_amount': minOrderAmount,
      'estimated_minutes': estimatedMinutes,
      'is_active': isActive,
      if (establishmentId != null) 'establishment_id': establishmentId,
      'shape': shape.toJson(),
      if (rules != null) 'rules': rules!.map((r) => r.toJson()).toList(),
    };
  }
}

// --------------------------------------------------------------------------- verification / adresses

class DeliveryCheckResult {
  const DeliveryCheckResult({
    required this.zoneId,
    required this.name,
    required this.fee,
    required this.estimatedMinutes,
    this.establishmentId,
    this.baseFee,
    this.freeDelivery = false,
    this.appliedLabel,
    this.remainingForFree,
    this.minOrderAmount = 0,
    this.minOrderMet,
  });

  final int zoneId;
  final String name;

  /// Frais appliques au sous-total envoye (regles de zone comprises).
  final double fee;
  final int estimatedMinutes;
  final int? establishmentId;
  final double? baseFee;
  final bool freeDelivery;
  final String? appliedLabel;
  final double? remainingForFree;
  final double minOrderAmount;

  /// `null` si aucun sous-total n'a ete envoye.
  final bool? minOrderMet;

  factory DeliveryCheckResult.fromJson(Map<String, dynamic> json) {
    return DeliveryCheckResult(
      zoneId: readInt(json['zone_id']),
      name: json['name']?.toString() ?? '',
      fee: readDouble(json['fee']),
      estimatedMinutes: readInt(json['estimated_minutes']),
      establishmentId: readNullableInt(json['establishment_id']),
      baseFee: json['base_fee'] == null ? null : readDouble(json['base_fee']),
      freeDelivery: readBool(json['free_delivery']),
      appliedLabel: json['applied_label']?.toString(),
      remainingForFree: json['remaining_for_free'] == null
          ? null
          : readDouble(json['remaining_for_free']),
      minOrderAmount: readDouble(json['min_order_amount']),
      minOrderMet: json['min_order_met'] is bool
          ? json['min_order_met'] as bool
          : null,
    );
  }
}

class AddressSuggestion {
  const AddressSuggestion({required this.label, required this.point});

  final String label;
  final LatLng point;

  static AddressSuggestion? tryParse(Object? json) {
    if (json is! Map) return null;
    final lat = json['lat'];
    final lng = json['lng'];
    final label = json['label'];
    if (lat is! num || lng is! num || label is! String || label.isEmpty) {
      return null;
    }
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
    return AddressSuggestion(
      label: label,
      point: LatLng(lat.toDouble(), lng.toDouble()),
    );
  }
}

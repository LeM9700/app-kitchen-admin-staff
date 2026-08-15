import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/token_store.dart';
import 'package:app_admin_staff/core/config/env.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final deliveryRepositoryProvider = Provider<DeliveryRepository>((ref) {
  return DeliveryRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  );
});

final deliveryZonesProvider =
    FutureProvider.autoDispose<List<DeliveryZone>>((ref) {
  return ref.watch(deliveryRepositoryProvider).listZones();
});

enum DeliveryZoneStatusFilter { all, active, inactive }

final deliveryZoneStatusFilterProvider =
    StateProvider<DeliveryZoneStatusFilter>((ref) {
  return DeliveryZoneStatusFilter.all;
});

class DeliveryRepository {
  const DeliveryRepository(this._apiClient, this._tokenStore);

  final ApiClient _apiClient;
  final TokenStore _tokenStore;

  Future<List<DeliveryZone>> listZones() async {
    final tenantSlug =
        await _tokenStore.readTenantSlug() ?? Env.defaultTenantSlug;
    final response = await _apiClient.get(
      ApiEndpoints.deliveryZones,
      authenticated: false,
      headers: {'X-Tenant-Slug': tenantSlug},
    );
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

  Future<DeliveryCheckResult> checkAddress({
    required double lat,
    required double lng,
    String? address,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.deliveryCheck,
      data: {
        'lat': lat,
        'lng': lng,
        if (address != null && address.trim().isNotEmpty)
          'address': address.trim(),
      },
    );
    return DeliveryCheckResult.fromJson(response.data as Map<String, dynamic>);
  }

  List<DeliveryZone> _zonesFromData(Object? data) {
    return (data as List? ?? const [])
        .whereType<Map>()
        .map((value) => DeliveryZone.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }
}

class DeliveryZone {
  const DeliveryZone({
    required this.id,
    required this.name,
    required this.fee,
    required this.minOrderAmount,
    required this.estimatedMinutes,
    required this.isActive,
    this.polygon,
  });

  final int id;
  final String name;
  final double fee;
  final double minOrderAmount;
  final int estimatedMinutes;
  final bool isActive;
  final Map<String, dynamic>? polygon;

  bool get hasGeoJson => polygon != null && polygon!.isNotEmpty;

  factory DeliveryZone.fromJson(Map<String, dynamic> json) {
    return DeliveryZone(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      fee: readDouble(json['fee']),
      minOrderAmount: readDouble(json['min_order_amount']),
      estimatedMinutes: readInt(json['estimated_minutes']),
      isActive: readBool(json['is_active'], fallback: true),
      polygon: json['polygon'] is Map
          ? Map<String, dynamic>.from(json['polygon'] as Map)
          : null,
    );
  }
}

class DeliveryZoneDraft {
  const DeliveryZoneDraft({
    required this.name,
    required this.fee,
    required this.minOrderAmount,
    required this.estimatedMinutes,
    required this.polygon,
  });

  final String name;
  final double fee;
  final double minOrderAmount;
  final int estimatedMinutes;
  final Map<String, dynamic> polygon;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'fee': fee,
      'min_order_amount': minOrderAmount,
      'estimated_minutes': estimatedMinutes,
      'polygon': polygon,
    };
  }
}

class DeliveryCheckResult {
  const DeliveryCheckResult({
    required this.zoneId,
    required this.name,
    required this.fee,
    required this.estimatedMinutes,
  });

  final int zoneId;
  final String name;
  final double fee;
  final int estimatedMinutes;

  factory DeliveryCheckResult.fromJson(Map<String, dynamic> json) {
    return DeliveryCheckResult(
      zoneId: readInt(json['zone_id']),
      name: json['name']?.toString() ?? '',
      fee: readDouble(json['fee']),
      estimatedMinutes: readInt(json['estimated_minutes']),
    );
  }
}

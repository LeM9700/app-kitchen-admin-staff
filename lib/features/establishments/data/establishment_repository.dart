import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/utils/json.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final establishmentRepositoryProvider =
    Provider<EstablishmentRepository>((ref) {
  return EstablishmentRepository(ref.watch(apiClientProvider));
});

final availableEstablishmentsProvider =
    FutureProvider.autoDispose<List<Establishment>>((ref) {
  return ref.watch(establishmentRepositoryProvider).listEstablishments();
});

final selectedEstablishmentIdProvider = StateProvider<int?>((ref) => null);

final currentEstablishmentProvider =
    FutureProvider.autoDispose<Establishment?>((ref) async {
  final establishments =
      await ref.watch(availableEstablishmentsProvider.future);
  if (establishments.isEmpty) {
    return null;
  }

  final selectedId = ref.watch(selectedEstablishmentIdProvider);
  if (selectedId == null) {
    return establishments.first;
  }

  for (final establishment in establishments) {
    if (establishment.id == selectedId) {
      return establishment;
    }
  }
  return establishments.first;
});

class EstablishmentRepository {
  const EstablishmentRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Establishment>> listEstablishments() async {
    final response = await _apiClient.get(ApiEndpoints.tenantEstablishments);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map(
          (value) => Establishment.fromJson(Map<String, dynamic>.from(value)),
        )
        .toList();
  }
}

class Establishment {
  const Establishment({
    required this.id,
    required this.name,
    required this.timezone,
    required this.isActive,
  });

  final int id;
  final String name;
  final String timezone;
  final bool isActive;

  factory Establishment.fromJson(Map<String, dynamic> json) {
    return Establishment(
      id: readInt(json['id']),
      name: json['name']?.toString() ?? '',
      timezone: json['timezone']?.toString() ?? 'Europe/Paris',
      isActive: readBool(json['is_active'], fallback: true),
    );
  }
}

import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final kdsRepositoryProvider = Provider<KdsRepository>((ref) {
  return KdsRepository(ref.watch(apiClientProvider));
});

class KdsRepository {
  const KdsRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<KdsScreen>> listScreens({bool includeInactive = false}) async {
    final response = await _apiClient.get(
      ApiEndpoints.kdsScreens,
      queryParameters: includeInactive ? {'include_inactive': true} : null,
    );
    final data = response.data;
    if (data is! List) {
      throw const FormatException('KDS screens response must be a list');
    }
    return [
      for (final item in data)
        if (item is Map)
          KdsScreen.fromJson(Map<String, dynamic>.from(item))
        else
          throw const FormatException('KDS screen item must be an object'),
    ];
  }

  Future<KdsPairResult> pair({
    required String code,
    String? deviceLabel,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.kdsPair,
      data: {
        'code': code,
        if (deviceLabel != null && deviceLabel.trim().isNotEmpty)
          'device_label': deviceLabel.trim(),
      },
    );
    return KdsPairResult.fromJson(
      _responseMap(response.data, 'KDS pair'),
    );
  }

  Future<KdsRemoteSessionStatus> getRemoteSession({
    required String sessionToken,
  }) async {
    final response = await _apiClient.get(
      ApiEndpoints.kdsRemoteSession,
      headers: _sessionHeaders(sessionToken),
    );
    return KdsRemoteSessionStatus.fromJson(
      _responseMap(response.data, 'KDS remote session'),
    );
  }

  Future<void> revokeRemoteSession({
    required String sessionToken,
  }) async {
    await _apiClient.post(
      ApiEndpoints.kdsRemoteSessionRevoke,
      headers: _sessionHeaders(sessionToken),
    );
  }

  Future<KdsScreen> createScreen({
    required String name,
    required String screenKey,
    required String mode,
    required String station,
    required String interactionMode,
    required int ticketsPerPage,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.kdsScreens,
      data: {
        'name': name,
        'screen_key': screenKey,
        'mode': mode,
        'station': station,
        'interaction_mode': interactionMode,
        'tickets_per_page': ticketsPerPage,
      },
    );
    return KdsScreen.fromJson(_responseMap(response.data, 'KDS create screen'));
  }

  Future<KdsScreen> updateScreen({
    required int screenId,
    String? name,
    String? screenKey,
    String? mode,
    String? station,
    String? interactionMode,
    int? ticketsPerPage,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (screenKey != null) 'screen_key': screenKey,
      if (mode != null) 'mode': mode,
      if (station != null) 'station': station,
      if (interactionMode != null) 'interaction_mode': interactionMode,
      if (ticketsPerPage != null) 'tickets_per_page': ticketsPerPage,
      if (isActive != null) 'is_active': isActive,
    };
    final response = await _apiClient.patch(
      ApiEndpoints.kdsScreen(screenId),
      data: body,
    );
    return KdsScreen.fromJson(_responseMap(response.data, 'KDS update screen'));
  }

  Future<KdsPairingCode> generatePairingCode({required int screenId}) async {
    final response = await _apiClient.post(
      ApiEndpoints.kdsScreenPairingCode(screenId),
    );
    return KdsPairingCode.fromJson(
      _responseMap(response.data, 'KDS pairing code'),
    );
  }

  Future<int> revokeScreenSessions({required int screenId}) async {
    final response = await _apiClient.post(
      ApiEndpoints.kdsScreenRevokeSessions(screenId),
    );
    final data = _responseMap(response.data, 'KDS revoke sessions');
    final value = data['revoked_count'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw const FormatException(
        'KDS revoke sessions response must contain "revoked_count"');
  }

  Map<String, dynamic> _sessionHeaders(String sessionToken) {
    return {'X-KDS-Session': sessionToken};
  }

  Map<String, dynamic> _responseMap(Object? data, String label) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    throw FormatException('$label response must be an object');
  }
}

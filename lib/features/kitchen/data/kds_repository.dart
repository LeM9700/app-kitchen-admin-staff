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

  Future<List<KdsScreen>> listScreens() async {
    final response = await _apiClient.get(ApiEndpoints.kdsScreens);
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

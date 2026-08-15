import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/auth/session_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

final authSessionsProvider =
    FutureProvider.autoDispose<List<AuthSession>>((ref) {
  return ref.watch(authRepositoryProvider).sessions();
});

class AuthRepository {
  const AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<AuthTokens> login({
    required String tenantSlug,
    required String email,
    required String password,
    String? mfaCode,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.authLogin,
      data: {
        'tenant_slug': tenantSlug,
        'email': email,
        'password': password,
        if (mfaCode != null && mfaCode.trim().isNotEmpty) 'mfa_code': mfaCode,
      },
      authenticated: false,
    );
    return AuthTokens.fromJson(response.data as Map<String, dynamic>);
  }

  Future<StaffUser> me({required String tenantSlug}) async {
    final response = await _apiClient.get(ApiEndpoints.authMe);
    return StaffUser.fromJson(
      response.data as Map<String, dynamic>,
      tenantSlug: tenantSlug,
    );
  }

  Future<void> logout() async {
    await _apiClient.post(ApiEndpoints.authLogout);
  }

  Future<bool> refreshSession() {
    return _apiClient.refreshSession();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    int? sessionId,
  }) async {
    await _apiClient.post(
      ApiEndpoints.authChangePassword,
      queryParameters: {
        if (sessionId != null) 'session_id': sessionId,
      },
      data: {
        if (currentPassword.trim().isNotEmpty)
          'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  Future<List<AuthSession>> sessions() async {
    final response = await _apiClient.get(ApiEndpoints.authSessions);
    return (response.data as List? ?? const [])
        .whereType<Map>()
        .map((value) => AuthSession.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<void> revokeSession(int sessionId) async {
    await _apiClient.delete(ApiEndpoints.authSession(sessionId));
  }
}

class AuthSession {
  const AuthSession({
    required this.id,
    required this.createdAt,
    required this.expiresAt,
    required this.isCurrent,
    this.userAgent,
    this.ipAddress,
  });

  final int id;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool isCurrent;
  final String? userAgent;
  final String? ipAddress;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isCurrent: json['is_current'] == true,
      userAgent: json['user_agent']?.toString(),
      ipAddress: json['ip_address']?.toString(),
    );
  }
}

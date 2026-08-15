import 'package:app_admin_staff/core/api/api_client.dart';
import 'package:app_admin_staff/core/api/api_endpoints.dart';
import 'package:app_admin_staff/core/api/paginated.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final adminUsersRepositoryProvider = Provider<AdminUsersRepository>((ref) {
  return AdminUsersRepository(ref.watch(apiClientProvider));
});

final adminUsersProvider = FutureProvider.autoDispose
    .family<PaginatedResult<AdminUser>, AdminUsersQuery>((ref, query) {
  return ref.watch(adminUsersRepositoryProvider).listUsers(query);
});

class AdminUsersRepository {
  const AdminUsersRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<PaginatedResult<AdminUser>> listUsers(AdminUsersQuery query) async {
    final response = await _apiClient.get(
      ApiEndpoints.adminUsers,
      queryParameters: query.toQueryParameters(),
    );
    return PaginatedResult<AdminUser>.fromJson(
      Map<String, dynamic>.from(response.data as Map),
      AdminUser.fromJson,
    );
  }

  Future<AdminUserCreateResult> createUser(AdminUserCreateDraft draft) async {
    final response = await _apiClient.post(
      ApiEndpoints.adminUsers,
      data: draft.toJson(),
    );
    return AdminUserCreateResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<AdminUser> updatePermissions(
    int userId,
    List<String> permissions,
  ) async {
    final response = await _apiClient.patch(
      ApiEndpoints.adminUserPermissions(userId),
      data: {'permissions': permissions},
    );
    return AdminUser.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<void> deactivateUser(int userId) async {
    await _apiClient.patch(ApiEndpoints.adminUserDeactivate(userId));
  }

  Future<void> reactivateUser(int userId) async {
    await _apiClient.patch(ApiEndpoints.adminUserReactivate(userId));
  }

  Future<String> resetPassword(int userId) async {
    final response = await _apiClient.post(
      ApiEndpoints.adminUserResetPassword(userId),
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    return data['temporary_password']?.toString() ?? '';
  }
}

class AdminUsersQuery {
  const AdminUsersQuery({
    this.role,
    this.isActive,
    this.emailVerified,
    this.page = 1,
    this.pageSize = 50,
  });

  final String? role;
  final bool? isActive;
  final bool? emailVerified;
  final int page;
  final int pageSize;

  Map<String, dynamic> toQueryParameters() {
    return {
      if (role != null && role!.isNotEmpty) 'role': role,
      if (isActive != null) 'is_active': isActive,
      if (emailVerified != null) 'email_verified': emailVerified,
      'page': page,
      'page_size': pageSize,
    };
  }

  AdminUsersQuery copyWith({
    String? role,
    bool clearRole = false,
    bool? isActive,
    bool clearIsActive = false,
    bool? emailVerified,
    bool clearEmailVerified = false,
    int? page,
    int? pageSize,
  }) {
    return AdminUsersQuery(
      role: clearRole ? null : role ?? this.role,
      isActive: clearIsActive ? null : isActive ?? this.isActive,
      emailVerified:
          clearEmailVerified ? null : emailVerified ?? this.emailVerified,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AdminUsersQuery &&
        other.role == role &&
        other.isActive == isActive &&
        other.emailVerified == emailVerified &&
        other.page == page &&
        other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(role, isActive, emailVerified, page, pageSize);
  }
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.role,
    required this.isActive,
    required this.emailVerified,
    required this.createdAt,
    required this.mustChangePassword,
    this.fullName,
    this.permissions,
  });

  final int id;
  final String email;
  final String? fullName;
  final String role;
  final List<String>? permissions;
  final bool isActive;
  final bool emailVerified;
  final DateTime createdAt;
  final bool mustChangePassword;

  String get displayName {
    final name = fullName?.trim();
    return name == null || name.isEmpty ? email : name;
  }

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: _intValue(json['id']),
      email: json['email']?.toString() ?? '',
      fullName: json['full_name']?.toString(),
      role: json['role']?.toString() ?? 'staff',
      permissions: _stringListOrNull(json['permissions']),
      isActive: json['is_active'] == true,
      emailVerified: json['email_verified'] == true,
      createdAt: DateTime.parse(json['created_at'].toString()).toLocal(),
      mustChangePassword: json['must_change_password'] == true,
    );
  }
}

class AdminUserCreateDraft {
  const AdminUserCreateDraft({
    required this.email,
    required this.role,
    this.fullName,
    this.permissions,
  });

  final String email;
  final String? fullName;
  final String role;
  final List<String>? permissions;

  Map<String, dynamic> toJson() {
    return {
      'email': email.trim(),
      'full_name': fullName?.trim().isEmpty ?? true ? null : fullName!.trim(),
      'role': role,
      if (permissions != null) 'permissions': permissions,
    };
  }
}

class AdminUserCreateResult {
  const AdminUserCreateResult({
    required this.id,
    required this.email,
    required this.role,
    required this.temporaryPassword,
  });

  final int id;
  final String email;
  final String role;
  final String temporaryPassword;

  factory AdminUserCreateResult.fromJson(Map<String, dynamic> json) {
    return AdminUserCreateResult(
      id: _intValue(json['id']),
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'staff',
      temporaryPassword: json['temporary_password']?.toString() ?? '',
    );
  }
}

List<String>? _stringListOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return const [];
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

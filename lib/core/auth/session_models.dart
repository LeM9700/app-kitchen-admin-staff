import 'dart:convert';

class StaffUser {
  const StaffUser({
    required this.id,
    required this.email,
    required this.role,
    required this.tenantSlug,
    required this.permissions,
    required this.mustChangePassword,
    this.fullName,
    this.phone,
    this.isActive = true,
    this.emailVerified = false,
  });

  final int id;
  final String email;
  final String role;
  final String tenantSlug;
  final Set<String>? permissions;
  final bool mustChangePassword;
  final String? fullName;
  final String? phone;
  final bool isActive;
  final bool emailVerified;

  factory StaffUser.fromJwt(String token) {
    final payload = jwtPayload(token);
    return StaffUser(
      id: int.parse(payload['sub'].toString()),
      email: payload['email']?.toString() ?? '',
      role: payload['role']?.toString() ?? 'staff',
      tenantSlug: payload['tenant_slug']?.toString() ?? '',
      permissions: _permissionsFrom(payload['permissions']),
      mustChangePassword: payload['must_change_password'] == true,
    );
  }

  factory StaffUser.fromJson(
    Map<String, dynamic> json, {
    required String tenantSlug,
  }) {
    return StaffUser(
      id: int.parse(json['id'].toString()),
      email: json['email']?.toString() ?? '',
      fullName: json['full_name']?.toString(),
      phone: json['phone']?.toString(),
      role: json['role']?.toString() ?? 'staff',
      tenantSlug: tenantSlug,
      permissions: _permissionsFrom(json['permissions']),
      isActive: json['is_active'] != false,
      emailVerified: json['email_verified'] == true,
      mustChangePassword: json['must_change_password'] == true,
    );
  }
}

Map<String, dynamic> jwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length < 2) {
    throw const FormatException('Invalid JWT');
  }
  return json.decode(
    utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
  ) as Map<String, dynamic>;
}

Set<String>? _permissionsFrom(Object? rawPermissions) {
  return rawPermissions is List
      ? rawPermissions.map((value) => value.toString()).toSet()
      : null;
}

class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.sessionId,
  });

  final String accessToken;
  final String refreshToken;
  final int sessionId;

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'].toString(),
      refreshToken: json['refresh_token'].toString(),
      sessionId: int.parse(json['session_id'].toString()),
    );
  }
}

class MfaChallenge {
  const MfaChallenge({
    required this.tenantSlug,
    required this.email,
    required this.password,
    this.error,
  });

  final String tenantSlug;
  final String email;
  final String password;
  final String? error;

  MfaChallenge copyWith({String? error}) {
    return MfaChallenge(
      tenantSlug: tenantSlug,
      email: email,
      password: password,
      error: error ?? this.error,
    );
  }
}

enum SessionStatus {
  unknown,
  unauthenticated,
  authenticated,
  mustChangePassword,
  mfaRequired,
  sessionExpired,
}

class SessionState {
  const SessionState._({
    required this.status,
    this.user,
    this.tenantSlug,
    this.sessionId,
    this.mfaChallenge,
    this.error,
  });

  const SessionState.unknown() : this._(status: SessionStatus.unknown);

  const SessionState.unauthenticated({String? error})
      : this._(status: SessionStatus.unauthenticated, error: error);

  const SessionState.sessionExpired({String? error})
      : this._(status: SessionStatus.sessionExpired, error: error);

  SessionState.mfaRequired(MfaChallenge challenge)
      : this._(
          status: SessionStatus.mfaRequired,
          tenantSlug: challenge.tenantSlug,
          mfaChallenge: challenge,
          error: challenge.error,
        );

  const SessionState.mustChangePassword({
    required StaffUser user,
    required String tenantSlug,
    required int sessionId,
    String? error,
  }) : this._(
          status: SessionStatus.mustChangePassword,
          user: user,
          tenantSlug: tenantSlug,
          sessionId: sessionId,
          error: error,
        );

  const SessionState.authenticated({
    required StaffUser user,
    required String tenantSlug,
    required int sessionId,
  }) : this._(
          status: SessionStatus.authenticated,
          user: user,
          tenantSlug: tenantSlug,
          sessionId: sessionId,
        );

  final SessionStatus status;
  final StaffUser? user;
  final String? tenantSlug;
  final int? sessionId;
  final MfaChallenge? mfaChallenge;
  final String? error;

  bool get isAuthenticated => status == SessionStatus.authenticated;

  bool get needsPasswordChange => status == SessionStatus.mustChangePassword;

  bool get needsMfa => status == SessionStatus.mfaRequired;
}

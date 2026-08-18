class KdsScreen {
  const KdsScreen({
    required this.id,
    required this.name,
    required this.screenKey,
    required this.mode,
    required this.station,
    required this.interactionMode,
    required this.ticketsPerPage,
    required this.isActive,
  });

  final int id;
  final String name;
  final String screenKey;
  final String mode;
  final String station;
  final String interactionMode;
  final int ticketsPerPage;
  final bool isActive;

  factory KdsScreen.fromJson(Map<String, dynamic> json) {
    return KdsScreen(
      id: _readRequiredInt(json, 'id'),
      name: _readRequiredString(json, 'name'),
      screenKey: _readRequiredString(json, 'screen_key'),
      mode: _readRequiredString(json, 'mode'),
      station: _readRequiredString(json, 'station'),
      interactionMode: _readRequiredString(json, 'interaction_mode'),
      ticketsPerPage: _readRequiredInt(json, 'tickets_per_page'),
      isActive: _readRequiredBool(json, 'is_active'),
    );
  }
}

class KdsPairResult {
  const KdsPairResult({
    required this.sessionToken,
    required this.expiresAt,
    required this.screen,
  });

  final String sessionToken;
  final DateTime expiresAt;
  final KdsScreen screen;

  factory KdsPairResult.fromJson(Map<String, dynamic> json) {
    return KdsPairResult(
      sessionToken: _readRequiredString(json, 'session_token'),
      expiresAt: _readRequiredDateTime(json, 'expires_at'),
      screen: KdsScreen.fromJson(_readRequiredMap(json, 'screen')),
    );
  }
}

class KdsPairingCode {
  const KdsPairingCode({
    required this.screenId,
    required this.code,
    required this.expiresAt,
  });

  final int screenId;
  final String code;
  final DateTime expiresAt;

  factory KdsPairingCode.fromJson(Map<String, dynamic> json) {
    return KdsPairingCode(
      screenId: _readRequiredInt(json, 'screen_id'),
      code: _readRequiredString(json, 'code'),
      expiresAt: _readRequiredDateTime(json, 'expires_at'),
    );
  }
}

class KdsRemoteSessionStatus {
  const KdsRemoteSessionStatus({
    required this.id,
    required this.screenId,
    required this.expiresAt,
    required this.screen,
    this.pairedByUserId,
    this.deviceLabel,
    this.createdAt,
    this.lastSeenAt,
  });

  final int id;
  final int screenId;
  final int? pairedByUserId;
  final String? deviceLabel;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime expiresAt;
  final KdsScreen screen;

  factory KdsRemoteSessionStatus.fromJson(Map<String, dynamic> json) {
    return KdsRemoteSessionStatus(
      id: _readRequiredInt(json, 'id'),
      screenId: _readRequiredInt(json, 'screen_id'),
      pairedByUserId: _readOptionalInt(json, 'paired_by_user_id'),
      deviceLabel: _readOptionalString(json, 'device_label'),
      createdAt: _readOptionalDateTime(json, 'created_at'),
      lastSeenAt: _readOptionalDateTime(json, 'last_seen_at'),
      expiresAt: _readRequiredDateTime(json, 'expires_at'),
      screen: KdsScreen.fromJson(_readRequiredMap(json, 'screen')),
    );
  }
}

Map<String, dynamic> _readRequiredMap(
  Map<String, dynamic> json,
  String field,
) {
  final value = json[field];
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw FormatException('KDS field "$field" must be an object');
}

String _readRequiredString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('KDS field "$field" must be a non-empty string');
}

String? _readOptionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('KDS field "$field" must be a string');
}

int _readRequiredInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('KDS field "$field" must be an integer');
}

int? _readOptionalInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('KDS field "$field" must be an integer');
}

bool _readRequiredBool(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is bool) {
    return value;
  }
  throw FormatException('KDS field "$field" must be a boolean');
}

DateTime _readRequiredDateTime(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('KDS field "$field" must be an ISO date');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('KDS field "$field" must be an ISO date');
  }
  return parsed;
}

DateTime? _readOptionalDateTime(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! String || value.isEmpty) {
    throw FormatException('KDS field "$field" must be an ISO date');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('KDS field "$field" must be an ISO date');
  }
  return parsed;
}

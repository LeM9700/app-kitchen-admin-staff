import 'dart:convert';

import 'package:app_admin_staff/core/config/env.dart';

enum KdsRemoteQrPayloadKind { pairingPayload, pairingCode }

class KdsRemoteQrPayload {
  const KdsRemoteQrPayload._({
    required this.kind,
    required this.value,
  });

  const KdsRemoteQrPayload.pairingPayload(String value)
      : this._(
          kind: KdsRemoteQrPayloadKind.pairingPayload,
          value: value,
        );

  const KdsRemoteQrPayload.pairingCode(String value)
      : this._(
          kind: KdsRemoteQrPayloadKind.pairingCode,
          value: value,
        );

  final KdsRemoteQrPayloadKind kind;
  final String value;
}

KdsRemoteQrPayload? parseKdsRemoteQrPayload(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty) {
    return null;
  }

  final jsonPayload = _parseJsonPayload(value);
  if (jsonPayload != null) {
    return jsonPayload;
  }

  final uriPayload = _parseUriPayload(value);
  if (uriPayload != null) {
    return uriPayload;
  }

  if (_isPairingCode(value)) {
    return KdsRemoteQrPayload.pairingCode(value);
  }

  if (_looksLikeProtectedPayload(value)) {
    return KdsRemoteQrPayload.pairingPayload(value);
  }

  return null;
}

String buildKdsRemotePairingQrData(String pairingPayload) {
  final payload = pairingPayload.trim();
  if (payload.isEmpty) {
    return payload;
  }

  final publicUrl = Env.appPublicUrl.trim();
  final query = {'pair': payload};
  if (publicUrl.isEmpty) {
    return Uri(path: '/kitchen/remote', queryParameters: query).toString();
  }

  final base = Uri.tryParse(publicUrl);
  if (base == null || !base.hasScheme || base.host.isEmpty) {
    return Uri(path: '/kitchen/remote', queryParameters: query).toString();
  }

  return base.replace(path: '/kitchen/remote', queryParameters: query).toString();
}

KdsRemoteQrPayload? _parseJsonPayload(String value) {
  if (!value.startsWith('{')) {
    return null;
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is! Map) {
      return null;
    }
    final pair = decoded['pair'] ?? decoded['pairing_payload'];
    if (pair is String && pair.trim().isNotEmpty) {
      return KdsRemoteQrPayload.pairingPayload(pair.trim());
    }
    final code = decoded['code'];
    if (code is String && _isPairingCode(code.trim())) {
      return KdsRemoteQrPayload.pairingCode(code.trim());
    }
  } on FormatException {
    return null;
  }
  return null;
}

KdsRemoteQrPayload? _parseUriPayload(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) {
    return null;
  }

  final pair = uri.queryParameters['pair'] ??
      uri.queryParameters['pairing_payload'] ??
      uri.queryParameters['payload'];
  if (pair != null && pair.trim().isNotEmpty) {
    return KdsRemoteQrPayload.pairingPayload(pair.trim());
  }

  final code = uri.queryParameters['code'];
  if (code != null && _isPairingCode(code.trim())) {
    return KdsRemoteQrPayload.pairingCode(code.trim());
  }

  return null;
}

bool _isPairingCode(String value) {
  return RegExp(r'^\d{6}$').hasMatch(value);
}

bool _looksLikeProtectedPayload(String value) {
  if (value.length < 20 || value.contains(RegExp(r'\s'))) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9._~+/=-]+$').hasMatch(value);
}

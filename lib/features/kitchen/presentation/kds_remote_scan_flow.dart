import 'package:app_admin_staff/core/api/api_error.dart';
import 'package:app_admin_staff/features/kitchen/application/kds_remote_qr_parser.dart';
import 'package:app_admin_staff/features/kitchen/data/kds_repository.dart';
import 'package:app_admin_staff/features/kitchen/presentation/kds_remote_qr_scanner_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

typedef KdsRemoteQrScanReader = Future<String?> Function(BuildContext context);

Future<void> scanAndOpenKdsRemote(
  BuildContext context,
  WidgetRef ref,
  {
  KdsRemoteQrScanReader scanReader = _openKdsRemoteQrScanner,
}) async {
  final rawValue = await scanReader(context);
  if (rawValue == null || !context.mounted) {
    return;
  }

  final payload = parseKdsRemoteQrPayload(rawValue);
  if (payload == null) {
    _showScanMessage(context, 'QR REMOTE INVALIDE');
    return;
  }

  try {
    final code = switch (payload.kind) {
      KdsRemoteQrPayloadKind.pairingCode => payload.value,
      KdsRemoteQrPayloadKind.pairingPayload => (await ref
              .read(kdsRepositoryProvider)
              .resolvePairingPayload(pairingPayload: payload.value))
          .code,
    };
    if (!context.mounted) {
      return;
    }
    context.go('/kitchen/remote?code=${Uri.encodeQueryComponent(code)}');
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    _showScanMessage(context, _scanErrorMessage(error));
  }
}

Future<String?> _openKdsRemoteQrScanner(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (context) => const KdsRemoteQrScannerPage(),
      fullscreenDialog: true,
    ),
  );
}

String _scanErrorMessage(Object error) {
  if (error is UnauthorizedException) {
    return 'CONNEXION REQUISE';
  }
  if (error is ForbiddenException) {
    return 'PERMISSION INSUFFISANTE';
  }
  if (error is BusinessException) {
    return switch (error.code) {
      'KDS_PAIRING_PAYLOAD_EXPIRED' => 'CODE EXPIRÉ',
      'KDS_PAIRING_PAYLOAD_INVALID' => 'QR REMOTE INVALIDE',
      'KDS_SCREEN_REMOTE_DISABLED' => 'REMOTE DÉSACTIVÉ POUR CET ÉCRAN',
      _ => error.message.trim().isEmpty ? 'QR REMOTE INVALIDE' : error.message,
    };
  }
  return 'QR REMOTE INVALIDE';
}

void _showScanMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

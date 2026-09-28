import 'package:app_admin_staff/features/kitchen/application/kds_remote_qr_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse une URL remote avec payload protege', () {
    final payload = parseKdsRemoteQrPayload(
      'https://staff.example.test/kitchen/remote?pair=encrypted_payload_1234567890',
    );

    expect(payload?.kind, KdsRemoteQrPayloadKind.pairingPayload);
    expect(payload?.value, 'encrypted_payload_1234567890');
  });

  test('parse un payload protege brut', () {
    final payload = parseKdsRemoteQrPayload(
      'gAAAAABremoteEncryptedPayloadWithEnoughLength',
    );

    expect(payload?.kind, KdsRemoteQrPayloadKind.pairingPayload);
    expect(payload?.value, 'gAAAAABremoteEncryptedPayloadWithEnoughLength');
  });

  test('parse un payload JSON simple', () {
    final payload = parseKdsRemoteQrPayload(
      '{"pairing_payload":"encrypted_json_payload_123456"}',
    );

    expect(payload?.kind, KdsRemoteQrPayloadKind.pairingPayload);
    expect(payload?.value, 'encrypted_json_payload_123456');
  });

  test('parse un code 6 chiffres comme fallback', () {
    final payload = parseKdsRemoteQrPayload(' 482731 ');

    expect(payload?.kind, KdsRemoteQrPayloadKind.pairingCode);
    expect(payload?.value, '482731');
  });

  test('refuse un QR sans information remote', () {
    expect(parseKdsRemoteQrPayload('bonjour service'), isNull);
    expect(parseKdsRemoteQrPayload('/kitchen/remote'), isNull);
  });

  test('construit une URL remote relative quand APP_PUBLIC_URL est absent', () {
    expect(
      buildKdsRemotePairingQrData('encrypted payload+/='),
      '/kitchen/remote?pair=encrypted+payload%2B%2F%3D',
    );
  });
}

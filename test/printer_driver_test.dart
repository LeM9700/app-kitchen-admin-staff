import 'dart:io';

import 'package:app_admin_staff/core/printing/print_job.dart';
import 'package:app_admin_staff/core/printing/printer_driver.dart';
import 'package:flutter_test/flutter_test.dart';

PrintJob _job() => PrintJob(
      id: 'job-1',
      kind: 'kitchen_ticket',
      title: 'Ticket',
      content: 'contenu sensible du ticket',
      createdAt: DateTime(2026, 1, 1),
    );

PrinterTarget _target({
  required String host,
  int port = 9100,
  bool confirmed = true,
}) =>
    PrinterTarget(
      name: 'Cuisine',
      transport: PrinterTransport.network,
      host: host,
      port: port,
      confirmed: confirmed,
    );

void main() {
  group('PrinterNetworkPolicy.resolveIfAllowed', () {
    test('accepte une IP privee sur un port imprimante autorise', () async {
      const policy = PrinterNetworkPolicy();
      final result =
          await policy.resolveIfAllowed('192.168.1.50', 9100);
      expect(result, isNotNull);
      expect(result!.address, '192.168.1.50');
    });

    test('refuse localhost', () async {
      const policy = PrinterNetworkPolicy();
      expect(await policy.resolveIfAllowed('localhost', 9100), isNull);
      expect(await policy.resolveIfAllowed('127.0.0.1', 9100), isNull);
      expect(await policy.resolveIfAllowed('::1', 9100), isNull);
    });

    test('refuse le lien local, dont les metadonnees cloud', () async {
      const policy = PrinterNetworkPolicy();
      expect(
        await policy.resolveIfAllowed('169.254.169.254', 9100),
        isNull,
      );
    });

    test('refuse une adresse IP publique', () async {
      const policy = PrinterNetworkPolicy();
      expect(await policy.resolveIfAllowed('8.8.8.8', 9100), isNull);
    });

    test('refuse un port non autorise', () async {
      const policy = PrinterNetworkPolicy();
      expect(await policy.resolveIfAllowed('192.168.1.50', 22), isNull);
      expect(await policy.resolveIfAllowed('192.168.1.50', 80), isNull);
    });

    test('refuse une valeur host en forme d\'URL', () async {
      const policy = PrinterNetworkPolicy();
      expect(
        await policy.resolveIfAllowed('http://192.168.1.50/', 9100),
        isNull,
      );
      expect(
        await policy.resolveIfAllowed('192.168.1.50/../evil', 9100),
        isNull,
      );
      expect(
        await policy.resolveIfAllowed('user@192.168.1.50', 9100),
        isNull,
      );
    });

    test('refuse une resolution DNS vers une adresse interdite', () async {
      final policy = PrinterNetworkPolicy(
        resolveHost: (host) async => [InternetAddress('1.1.1.1')],
      );
      expect(await policy.resolveIfAllowed('printer.local', 9100), isNull);
    });

    test('autorise une plage CGNAT explicitement ajoutee par restaurant',
        () async {
      const policy = PrinterNetworkPolicy(
        extraAllowedCidrs: ['100.64.0.0/10'],
      );
      final result = await policy.resolveIfAllowed('100.64.0.5', 9100);
      expect(result, isNotNull);
    });

    test('autorise un sous-reseau precis d\'une plage privee par defaut',
        () async {
      const policy = PrinterNetworkPolicy(
        extraAllowedCidrs: ['172.16.5.0/24'],
      );
      final result = await policy.resolveIfAllowed('172.16.5.10', 9100);
      expect(result, isNotNull);
    });

    test('la plage CGNAT n\'est jamais autorisee par defaut', () async {
      const policy = PrinterNetworkPolicy();
      expect(await policy.resolveIfAllowed('100.64.0.5', 9100), isNull);
    });

    test('refuse 0.0.0.0/0 comme plage supplementaire', () async {
      const policy = PrinterNetworkPolicy(
        extraAllowedCidrs: ['0.0.0.0/0'],
      );
      expect(await policy.resolveIfAllowed('8.8.8.8', 9100), isNull);
      expect(await policy.resolveIfAllowed('1.2.3.4', 9100), isNull);
    });

    test('refuse ::/0 comme plage supplementaire', () async {
      const policy = PrinterNetworkPolicy(
        extraAllowedCidrs: ['::/0'],
      );
      expect(
        await policy.resolveIfAllowed('2001:4860:4860::8888', 9100),
        isNull,
      );
    });

    test('refuse un CIDR public comme plage supplementaire', () async {
      const policy = PrinterNetworkPolicy(
        extraAllowedCidrs: ['8.0.0.0/8'],
      );
      expect(await policy.resolveIfAllowed('8.8.8.8', 9100), isNull);
    });

    test('refuse un CIDR plus large que la plage CGNAT reconnue', () async {
      // /9 est plus large que la plage CGNAT reconnue (/10) : l'entree
      // entiere doit etre ignoree, y compris pour les adresses qui seraient
      // couvertes par un /10 legitime.
      const policy = PrinterNetworkPolicy(
        extraAllowedCidrs: ['100.64.0.0/9'],
      );
      expect(await policy.resolveIfAllowed('100.64.0.5', 9100), isNull);
      expect(await policy.resolveIfAllowed('100.32.0.5', 9100), isNull);
    });

    test('refuse loopback/link-local/multicast comme plage supplementaire',
        () async {
      const policy = PrinterNetworkPolicy(
        extraAllowedCidrs: [
          '127.0.0.0/8',
          '169.254.0.0/16',
          '224.0.0.0/4',
        ],
      );
      expect(await policy.resolveIfAllowed('127.0.0.5', 9100), isNull);
      expect(await policy.resolveIfAllowed('169.254.1.1', 9100), isNull);
      expect(await policy.resolveIfAllowed('224.0.0.5', 9100), isNull);
    });

    test('ignore un CIDR malforme sans planter', () async {
      const policy = PrinterNetworkPolicy(
        extraAllowedCidrs: ['not-a-cidr', '192.168.1.0/999', '192.168.1.0'],
      );
      // Les plages par defaut restent actives malgre les entrees invalides.
      final result = await policy.resolveIfAllowed('192.168.1.50', 9100);
      expect(result, isNotNull);
    });

    test('une erreur de resolution DNS est traitee comme un refus',
        () async {
      final policy = PrinterNetworkPolicy(
        resolveHost: (host) async => throw const SocketException('nope'),
      );
      expect(await policy.resolveIfAllowed('printer.local', 9100), isNull);
    });
  });

  group('NetworkTextPrinterDriver', () {
    test('refuse d\'envoyer sans confirmation explicite de la cible',
        () async {
      const driver = NetworkTextPrinterDriver();
      final result = await driver.send(
        _job(),
        _target(host: '192.168.1.50', confirmed: false),
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('Confirmez'));
    });

    test('refuse une destination non autorisee sans tenter de connexion',
        () async {
      const driver = NetworkTextPrinterDriver();
      final result = await driver.send(
        _job(),
        _target(host: '8.8.8.8'),
      );
      expect(result.ok, isFalse);
      expect(result.message, isNot(contains('8.8.8.8')));
    });

    test('refuse un host vide', () async {
      const driver = NetworkTextPrinterDriver();
      final result = await driver.send(
        _job(),
        _target(host: ''),
      );
      expect(result.ok, isFalse);
    });

    test('journalise les tentatives sans jamais inclure le contenu du ticket',
        () async {
      final events = <String>[];
      final driver = NetworkTextPrinterDriver(
        logger: _RecordingLogger(events),
      );
      await driver.send(_job(), _target(host: '8.8.8.8'));
      expect(events, isNotEmpty);
      for (final event in events) {
        expect(event, isNot(contains('contenu sensible du ticket')));
      }
    });
  });

  group('PrinterDriverRegistry', () {
    test('construit un NetworkTextPrinterDriver pour le transport reseau',
        () {
      const registry = PrinterDriverRegistry();
      final driver = registry.driverFor(PrinterTransport.network);
      expect(driver, isA<NetworkTextPrinterDriver>());
    });

    test('construit un NativePrinterDriver pour les autres transports', () {
      const registry = PrinterDriverRegistry();
      final driver = registry.driverFor(PrinterTransport.pdf);
      expect(driver, isA<NativePrinterDriver>());
    });
  });
}

class _RecordingLogger implements PrinterAuditLogger {
  _RecordingLogger(this.events);

  final List<String> events;

  @override
  void log({
    required String printerName,
    required bool success,
    required String reason,
  }) {
    events.add('$printerName:$success:$reason');
  }
}

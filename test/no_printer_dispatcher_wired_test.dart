import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard test: printer_driver.dart is a hardened foundation
/// (host/port validation, timeouts, confirmation, minimal audit log) that
/// nothing in the app currently calls. Screens only enqueue [PrintJob]s
/// into `printJobsProvider`; the settings screen lets staff mark them done
/// by hand. No dispatcher opens a network printer connection today.
///
/// This test fails the day someone wires a real dispatcher, which is the
/// point: update this test (and docs/printer_network_security.md) together
/// with that change instead of discovering the doc is stale later.
void main() {
  test(
    'no code outside lib/core/printing/ references the network printer '
    'driver (see docs/printer_network_security.md)',
    () {
      final libDir = Directory('lib');
      expect(libDir.existsSync(), isTrue, reason: 'run tests from repo root');

      const guardedSymbols = [
        'PrinterDriverRegistry',
        'NetworkTextPrinterDriver',
        '.driverFor(',
      ];

      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final segments = entity.path
            .replaceAll(r'\', '/')
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .toList();
        final libIndex = segments.indexOf('lib');
        final relativeSegments = segments.sublist(libIndex + 1);
        if (relativeSegments.length >= 2 &&
            relativeSegments[0] == 'core' &&
            relativeSegments[1] == 'printing') {
          continue;
        }
        final relativePath = relativeSegments.join('/');
        final content = entity.readAsStringSync();
        if (guardedSymbols.any(content.contains)) {
          offenders.add(relativePath);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Found references to the network printer driver outside '
            'lib/core/printing/: $offenders. This means a real dispatcher '
            'now exists - update docs/printer_network_security.md to '
            'describe the real flow and relax/replace this guard test '
            'instead of leaving both stale.',
      );
    },
  );
}

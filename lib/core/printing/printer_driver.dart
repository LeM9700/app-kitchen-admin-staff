import 'dart:convert';
import 'dart:io';

import 'package:app_admin_staff/core/printing/print_job.dart';

enum PrinterTransport {
  pdf,
  windows,
  network,
  bluetooth,
  usbSunmi,
}

class PrinterTarget {
  const PrinterTarget({
    required this.name,
    required this.transport,
    this.host,
    this.port = 9100,
  });

  final String name;
  final PrinterTransport transport;
  final String? host;
  final int port;
}

class PrinterDispatchResult {
  const PrinterDispatchResult({
    required this.ok,
    required this.message,
  });

  final bool ok;
  final String message;
}

abstract class PrinterDriver {
  const PrinterDriver();

  Future<PrinterDispatchResult> send(PrintJob job, PrinterTarget target);
}

class NetworkTextPrinterDriver extends PrinterDriver {
  const NetworkTextPrinterDriver();

  @override
  Future<PrinterDispatchResult> send(PrintJob job, PrinterTarget target) async {
    final host = target.host?.trim();
    if (host == null || host.isEmpty) {
      return const PrinterDispatchResult(
        ok: false,
        message: 'Host imprimante reseau manquant',
      );
    }
    final socket = await Socket.connect(
      host,
      target.port,
      timeout: const Duration(seconds: 5),
    );
    try {
      socket.add(utf8.encode('${job.content}\n\n\n'));
      await socket.flush();
      return PrinterDispatchResult(
        ok: true,
        message: 'Ticket envoye a ${target.name}',
      );
    } finally {
      await socket.close();
    }
  }
}

class NativePrinterDriver extends PrinterDriver {
  const NativePrinterDriver(this.transport);

  final PrinterTransport transport;

  @override
  Future<PrinterDispatchResult> send(PrintJob job, PrinterTarget target) async {
    return PrinterDispatchResult(
      ok: false,
      message: '${transport.name} requiert le plugin natif de plateforme',
    );
  }
}

class PrinterDriverRegistry {
  const PrinterDriverRegistry();

  PrinterDriver driverFor(PrinterTransport transport) {
    return switch (transport) {
      PrinterTransport.network => const NetworkTextPrinterDriver(),
      PrinterTransport.pdf ||
      PrinterTransport.windows ||
      PrinterTransport.bluetooth ||
      PrinterTransport.usbSunmi =>
        NativePrinterDriver(transport),
    };
  }

  static PrinterTransport transportFromKey(String? key) {
    return switch (key) {
      'windows' => PrinterTransport.windows,
      'network' => PrinterTransport.network,
      'bluetooth' => PrinterTransport.bluetooth,
      'usb_sunmi' => PrinterTransport.usbSunmi,
      _ => PrinterTransport.pdf,
    };
  }
}

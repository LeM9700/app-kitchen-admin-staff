/// This file is a hardened *foundation* for network printer dispatch: host,
/// port and network-range validation, timeouts, generic error messages and a
/// content-free audit log. As of now nothing in `lib/` outside this file
/// (and its tests) calls [PrinterDriverRegistry.driverFor] or constructs a
/// [NetworkTextPrinterDriver] - screens only enqueue [PrintJob]s into
/// `printJobsProvider`, and the settings screen lets staff mark them done by
/// hand. No TCP connection is opened by the app today. See
/// `docs/printer_network_security.md` for the full picture, and update both
/// that doc and `test/no_printer_dispatcher_wired_test.dart` if a real
/// dispatcher is wired up later.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:app_admin_staff/core/printing/print_job.dart';

enum PrinterTransport {
  pdf,
  windows,
  network,
  bluetooth,
  usbSunmi,
}

/// A configured printer destination.
///
/// [confirmed] must be explicitly set to `true` by whoever saved the printer
/// configuration (see the printer settings dialog). It is the human
/// attestation that [host] really points at the intended physical printer on
/// the restaurant's local network, and it is required before any network
/// dispatch is attempted — the driver never sends a ticket to a host nobody
/// confirmed.
class PrinterTarget {
  const PrinterTarget({
    required this.name,
    required this.transport,
    this.host,
    this.port = 9100,
    this.confirmed = false,
  });

  final String name;
  final PrinterTransport transport;
  final String? host;
  final int port;
  final bool confirmed;
}

class PrinterDispatchResult {
  const PrinterDispatchResult({
    required this.ok,
    required this.message,
  });

  final bool ok;
  final String message;
}

/// Resolves a hostname/IP literal to the addresses it points at.
///
/// Overridable so tests can simulate DNS resolution without touching the
/// network or relying on environment-specific lookups.
typedef PrinterHostResolver = Future<List<InternetAddress>> Function(
  String host,
);

Future<List<InternetAddress>> _defaultResolveHost(String host) async {
  final literal = InternetAddress.tryParse(host);
  if (literal != null) {
    return [literal];
  }
  return InternetAddress.lookup(host);
}

/// Restricts which network destinations a [PrinterTarget] is allowed to
/// resolve to, so the app cannot be turned into a generic TCP client.
///
/// By default only RFC 1918 / ULA private ranges are allowed (the ranges a
/// restaurant's kitchen printers actually live on). Loopback, link-local
/// (including the 169.254.169.254 cloud metadata address), multicast and
/// public internet destinations are always rejected regardless of
/// [extraAllowedCidrs].
///
/// [extraAllowedCidrs] lets a restaurant with a non-default LAN layout (e.g.
/// a shared CGNAT range across sites) opt in to more ranges, but every entry
/// is validated against [_recognizedExtraCidrBases]: only a range that is a
/// subnet of one of those bases is accepted, so a value such as `0.0.0.0/0`,
/// a public CIDR, or an overly broad prefix can never widen the policy to
/// public destinations. Invalid or disallowed entries are silently dropped
/// rather than crashing the app on a corrupted config value.
class PrinterNetworkPolicy {
  const PrinterNetworkPolicy({
    this.extraAllowedCidrs = const [],
    this.allowedPorts = const {9100, 9101, 9102, 515, 631},
    PrinterHostResolver? resolveHost,
  }) : _resolveHost = resolveHost ?? _defaultResolveHost;

  /// Additional private network ranges (CIDR notation) authorised for this
  /// restaurant, on top of the default private ranges below. Entries that
  /// are not a subnet of [_recognizedExtraCidrBases] are ignored - see the
  /// class doc.
  final List<String> extraAllowedCidrs;

  /// Ports a network printer is allowed to listen on.
  final Set<int> allowedPorts;

  final PrinterHostResolver _resolveHost;

  static const List<String> _defaultPrivateCidrs = [
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    'fc00::/7',
  ];

  /// Ranges an [extraAllowedCidrs] entry is allowed to be a subnet of. Same
  /// as [_defaultPrivateCidrs] plus the shared CGNAT range (RFC 6598),
  /// which is intentionally *not* allowed by default: a restaurant must opt
  /// in to it explicitly (e.g. `extraAllowedCidrs: ['100.64.0.0/10']`) since
  /// it is sometimes used by carrier-grade NAT on the public internet side
  /// too, not exclusively for private LANs.
  static const List<String> _recognizedExtraCidrBases = [
    ..._defaultPrivateCidrs,
    '100.64.0.0/10',
  ];

  /// A bare hostname or IP literal: no scheme, path, credentials or
  /// whitespace. Rejects anything shaped like a URL so a printer "host"
  /// field can never be abused to reach an arbitrary endpoint.
  static final RegExp _bareHostPattern = RegExp(r'^[A-Za-z0-9.\-:%\[\]]+$');

  bool _looksLikeBareHost(String host) {
    if (host.isEmpty) return false;
    if (host.contains('://') || host.contains('/') || host.contains('@')) {
      return false;
    }
    return _bareHostPattern.hasMatch(host);
  }

  bool _isDisallowedHostname(String host) {
    final lower = host.toLowerCase();
    return lower == 'localhost' ||
        lower.endsWith('.localhost') ||
        lower == 'metadata.google.internal';
  }

  bool isAddressAllowed(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return false;
    }
    if (address.address == '0.0.0.0' || address.address == '::') {
      return false;
    }
    final cidrs = [
      ..._defaultPrivateCidrs,
      ...extraAllowedCidrs.where(_isRecognizedExtraCidr),
    ];
    return cidrs.any((cidr) => _matchesCidr(address, cidr));
  }

  /// Whether [cidr] is well-formed and entirely contained within one of the
  /// [_recognizedExtraCidrBases] - i.e. it cannot describe anything broader
  /// than, or outside of, the private/CGNAT ranges this app ever allows.
  static bool _isRecognizedExtraCidr(String cidr) {
    final parsed = _parseCidr(cidr);
    if (parsed == null) return false;
    final (network, prefixLength) = parsed;
    if (network.isLoopback || network.isLinkLocal || network.isMulticast) {
      return false;
    }
    for (final base in _recognizedExtraCidrBases) {
      final baseParsed = _parseCidr(base);
      if (baseParsed == null) continue;
      final (baseNetwork, basePrefixLength) = baseParsed;
      if (baseNetwork.type != network.type) continue;
      if (prefixLength < basePrefixLength) continue;
      if (_rawAddressMatchesPrefix(
        network.rawAddress,
        baseNetwork.rawAddress,
        basePrefixLength,
      )) {
        return true;
      }
    }
    return false;
  }

  static (InternetAddress, int)? _parseCidr(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final network = InternetAddress.tryParse(parts[0]);
    final prefixLength = int.tryParse(parts[1]);
    if (network == null || prefixLength == null) return null;
    if (prefixLength < 0 || prefixLength > network.rawAddress.length * 8) {
      return null;
    }
    return (network, prefixLength);
  }

  static bool _matchesCidr(InternetAddress address, String cidr) {
    final parsed = _parseCidr(cidr);
    if (parsed == null) return false;
    final (network, prefixLength) = parsed;
    if (network.type != address.type) return false;
    return _rawAddressMatchesPrefix(
      address.rawAddress,
      network.rawAddress,
      prefixLength,
    );
  }

  static bool _rawAddressMatchesPrefix(
    List<int> address,
    List<int> network,
    int prefixLength,
  ) {
    if (address.length != network.length) return false;
    var remainingBits = prefixLength;
    for (var i = 0; i < address.length; i++) {
      if (remainingBits <= 0) break;
      final bitsInByte = remainingBits >= 8 ? 8 : remainingBits;
      final mask = bitsInByte == 8 ? 0xFF : (0xFF << (8 - bitsInByte)) & 0xFF;
      if ((address[i] & mask) != (network[i] & mask)) {
        return false;
      }
      remainingBits -= bitsInByte;
    }
    return true;
  }

  /// Validates [host]/[port] against this policy and, if allowed, returns
  /// the resolved [InternetAddress] to connect to. Resolution happens once
  /// here and the caller must connect to the returned address directly
  /// (never re-resolve the hostname) to avoid a DNS-rebinding
  /// time-of-check/time-of-use gap.
  Future<InternetAddress?> resolveIfAllowed(String host, int port) async {
    if (!allowedPorts.contains(port)) {
      return null;
    }
    if (!_looksLikeBareHost(host) || _isDisallowedHostname(host)) {
      return null;
    }
    List<InternetAddress> addresses;
    try {
      addresses = await _resolveHost(host);
    } catch (_) {
      return null;
    }
    if (addresses.isEmpty) {
      return null;
    }
    for (final address in addresses) {
      if (!isAddressAllowed(address)) {
        return null;
      }
    }
    return addresses.first;
  }
}

/// Minimal local audit trail for printer dispatch attempts. Never receives
/// ticket content — only enough metadata to diagnose connectivity issues.
abstract class PrinterAuditLogger {
  void log({
    required String printerName,
    required bool success,
    required String reason,
  });
}

class DeveloperPrinterAuditLogger implements PrinterAuditLogger {
  const DeveloperPrinterAuditLogger();

  @override
  void log({
    required String printerName,
    required bool success,
    required String reason,
  }) {
    developer.log(
      '${success ? 'OK' : 'FAIL'} printer="$printerName" reason=$reason',
      name: 'printer_driver',
    );
  }
}

abstract class PrinterDriver {
  const PrinterDriver();

  Future<PrinterDispatchResult> send(PrintJob job, PrinterTarget target);
}

class NetworkTextPrinterDriver extends PrinterDriver {
  const NetworkTextPrinterDriver({
    this.policy = const PrinterNetworkPolicy(),
    this.logger = const DeveloperPrinterAuditLogger(),
    this.connectTimeout = const Duration(seconds: 5),
  });

  final PrinterNetworkPolicy policy;
  final PrinterAuditLogger logger;
  final Duration connectTimeout;

  static const _genericConnectionError =
      'Impossible de contacter cette imprimante. Verifiez qu\'elle est '
      'allumee et accessible sur le reseau local.';

  @override
  Future<PrinterDispatchResult> send(PrintJob job, PrinterTarget target) async {
    final host = target.host?.trim();
    if (host == null || host.isEmpty) {
      logger.log(
        printerName: target.name,
        success: false,
        reason: 'missing_host',
      );
      return const PrinterDispatchResult(
        ok: false,
        message: 'Host imprimante reseau manquant',
      );
    }

    if (!target.confirmed) {
      logger.log(
        printerName: target.name,
        success: false,
        reason: 'not_confirmed',
      );
      return const PrinterDispatchResult(
        ok: false,
        message: 'Confirmez cette imprimante dans la configuration avant '
            'de lancer une impression reseau.',
      );
    }

    final resolvedAddress = await policy.resolveIfAllowed(host, target.port);
    if (resolvedAddress == null) {
      logger.log(
        printerName: target.name,
        success: false,
        reason: 'destination_not_allowed',
      );
      return const PrinterDispatchResult(
        ok: false,
        message: 'Cette destination n\'est pas autorisee pour l\'impression '
            'reseau.',
      );
    }

    Socket socket;
    try {
      socket = await Socket.connect(
        resolvedAddress,
        target.port,
        timeout: connectTimeout,
      );
    } on TimeoutException {
      logger.log(printerName: target.name, success: false, reason: 'timeout');
      return const PrinterDispatchResult(
        ok: false,
        message: _genericConnectionError,
      );
    } on SocketException {
      logger.log(
        printerName: target.name,
        success: false,
        reason: 'connect_failed',
      );
      return const PrinterDispatchResult(
        ok: false,
        message: _genericConnectionError,
      );
    }

    try {
      socket.add(utf8.encode('${job.content}\n\n\n'));
      await socket.flush().timeout(connectTimeout);
      logger.log(printerName: target.name, success: true, reason: 'sent');
      return PrinterDispatchResult(
        ok: true,
        message: 'Ticket envoye a ${target.name}',
      );
    } on TimeoutException {
      logger.log(printerName: target.name, success: false, reason: 'timeout');
      return const PrinterDispatchResult(
        ok: false,
        message: _genericConnectionError,
      );
    } on SocketException {
      logger.log(
        printerName: target.name,
        success: false,
        reason: 'send_failed',
      );
      return const PrinterDispatchResult(
        ok: false,
        message: _genericConnectionError,
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
  const PrinterDriverRegistry({
    this.networkPolicy = const PrinterNetworkPolicy(),
  });

  final PrinterNetworkPolicy networkPolicy;

  PrinterDriver driverFor(PrinterTransport transport) {
    return switch (transport) {
      PrinterTransport.network =>
        NetworkTextPrinterDriver(policy: networkPolicy),
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
